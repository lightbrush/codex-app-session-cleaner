#!/usr/bin/env python3
"""
按会话 ID 安全清理本地 Codex 会话。

整体架构说明：
1. 先构建一份“计划对象”用于预览，明确本次会改哪些文件、会移动哪些会话记录。
2. 计划对象包含三类核心数据：
   - 会话文件命中结果：扫描 sessions/ 与 archived_sessions/ 下包含目标 session ID 的 jsonl 文件。
   - session_index.jsonl 清理结果：仅移除 id 精确匹配目标 session ID 的记录。
   - .codex-global-state.json 清理结果：仅移除键等于 session ID 或值精确等于 session ID 的引用。
3. 默认只输出预览 JSON；只有传入 --apply 才会真正改写索引、备份全局状态、移动会话文件到 trash。
4. 所有核心逻辑仅依赖 Python 标准库，确保 Windows 与 macOS 都可运行。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


# 这个唯一哨兵对象用于在递归清理 JSON 时表示“当前节点应被删除”。
REMOVED_SENTINEL = object()

# 会话 ID 校验沿用原 PowerShell 版本的宽松 UUID 风格校验。
SESSION_ID_PATTERN = re.compile(r"^[0-9a-fA-F-]{36}$")


@dataclass(frozen=True)
class SessionFileMatch:
    """描述一个命中的会话文件。"""

    scope: str
    full_path: Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    """解析命令行参数。"""

    parser = argparse.ArgumentParser(
        description="Safely preview or clean a local Codex session by session ID."
    )
    parser.add_argument(
        "--session-id",
        required=True,
        help="Target Codex session ID.",
    )
    parser.add_argument(
        "--codex-home",
        default=os.environ.get("CODEX_HOME") or str(Path.home() / ".codex"),
        help="Codex home directory. Defaults to CODEX_HOME or ~/.codex.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply changes. Without this flag the script only previews the cleanup plan.",
    )
    args = parser.parse_args(argv)

    if not SESSION_ID_PATTERN.fullmatch(args.session_id):
        parser.error("session-id must be a 36-character UUID-like value")

    return args


def configure_stdio() -> None:
    """
    显式把标准输出/错误输出切到 UTF-8。

    背景：
    - Windows 控制台或宿主进程经常不是 UTF-8，中文 JSON 在预览输出里容易出现乱码。
    - 这里仅影响终端输出，不影响文件读写编码。
    """

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")


def assert_codex_home(codex_home: Path) -> None:
    """确认 Codex 根目录存在。"""

    if not codex_home.is_dir():
        raise RuntimeError(f"Codex home not found: {codex_home}")


def scan_session_files(codex_home: Path, session_id: str) -> list[SessionFileMatch]:
    """
    扫描目标会话文件。

    参数：
    - codex_home: Codex 根目录
    - session_id: 目标会话 ID

    返回：
    - 所有命中的 SessionFileMatch 列表

    说明：
    - 只查 sessions/ 与 archived_sessions/ 两个目录。
    - 只匹配文件名中包含 session_id 且扩展名为 .jsonl 的文件。
    """

    results: list[SessionFileMatch] = []
    for scope in ("sessions", "archived_sessions"):
        search_root = codex_home / scope
        if not search_root.is_dir():
            continue

        for path in search_root.rglob("*.jsonl"):
            if session_id in path.name:
                results.append(SessionFileMatch(scope=scope, full_path=path.resolve()))

    return results


def detect_newline_style(text: str) -> str:
    """
    推断文本原有换行风格。

    目的：
    - 改写 session_index.jsonl 时尽量保留原文件换行习惯，减少无关 diff。
    """

    if "\r\n" in text:
        return "\r\n"
    if "\n" in text:
        return "\n"
    return os.linesep


def build_session_index_plan(index_path: Path, session_id: str) -> dict[str, Any]:
    """
    构建 session_index.jsonl 的清理计划。

    行为要求：
    - 只删除 id 精确匹配目标 session ID 的记录
    - 无法解析的 JSON 行保持原样
    - 保留非匹配行的原始文本内容
    """

    if not index_path.is_file():
        return {
            "Exists": False,
            "RemovedCount": 0,
            "MatchingRecords": [],
            "OutputLines": [],
            "OutputText": "",
        }

    original_text = index_path.read_text(encoding="utf-8")
    newline_style = detect_newline_style(original_text)
    original_lines = original_text.splitlines()

    output_lines: list[str] = []
    matching_records: list[dict[str, Any]] = []

    for line in original_lines:
        if not line.strip():
            output_lines.append(line)
            continue

        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            # 保持未知格式的原始行，避免破坏手工写入或未来版本格式。
            output_lines.append(line)
            continue

        if isinstance(parsed, dict) and parsed.get("id") == session_id:
            matching_records.append(parsed)
            continue

        output_lines.append(line)

    output_text = newline_style.join(output_lines)
    if original_text.endswith(("\r\n", "\n")) and output_lines:
        output_text += newline_style

    return {
        "Exists": True,
        "RemovedCount": len(matching_records),
        "MatchingRecords": matching_records,
        "OutputLines": output_lines,
        "OutputText": output_text,
    }


def join_json_path(parent: str, child: str) -> str:
    """构造对象属性路径。"""

    return child if not parent else f"{parent}.{child}"


def remove_exact_session_references(
    value: Any,
    path: str,
    session_id: str,
    removed_paths: list[str],
) -> Any:
    """
    递归清理 JSON 结构中的精确 session 引用。

    参数：
    - value: 当前待处理节点
    - path: 当前节点路径，用于审计输出
    - session_id: 目标会话 ID
    - removed_paths: 所有被删路径的收集器

    返回：
    - 清理后的新值
    - 若当前节点本身需要删除，则返回 REMOVED_SENTINEL

    关键规则：
    - 仅删除“字符串值完全等于 session_id”的节点
    - 仅删除“对象键完全等于 session_id”的属性
    - 普通文本里只要不是完全等于 session_id，就必须原样保留
    """

    if value is None:
        return None

    if isinstance(value, str):
        if value == session_id:
            removed_paths.append(path)
            return REMOVED_SENTINEL
        return value

    if isinstance(value, dict):
        cleaned: dict[str, Any] = {}
        for key, child in value.items():
            child_path = join_json_path(path, str(key))
            if str(key) == session_id:
                removed_paths.append(child_path)
                continue

            cleaned_child = remove_exact_session_references(
                child,
                child_path,
                session_id,
                removed_paths,
            )
            if cleaned_child is REMOVED_SENTINEL:
                continue
            cleaned[key] = cleaned_child
        return cleaned

    if isinstance(value, list):
        cleaned_items: list[Any] = []
        for index, item in enumerate(value):
            child_path = f"[{index}]" if not path else f"{path}[{index}]"
            cleaned_item = remove_exact_session_references(
                item,
                child_path,
                session_id,
                removed_paths,
            )
            if cleaned_item is REMOVED_SENTINEL:
                continue
            cleaned_items.append(cleaned_item)
        return cleaned_items

    # 数字、布尔等标量无需特殊处理。
    return value


def build_global_state_plan(global_state_path: Path, session_id: str) -> dict[str, Any]:
    """构建 .codex-global-state.json 的清理计划。"""

    if not global_state_path.is_file():
        return {
            "Exists": False,
            "RemovedReferenceCount": 0,
            "RemovedReferencePaths": [],
            "OutputText": None,
        }

    original_text = global_state_path.read_text(encoding="utf-8")
    parsed = json.loads(original_text)
    removed_paths: list[str] = []
    cleaned = remove_exact_session_references(parsed, "", session_id, removed_paths)
    output_text = json.dumps(cleaned, ensure_ascii=False, indent=2) + "\n"

    return {
        "Exists": True,
        "RemovedReferenceCount": len(removed_paths),
        "RemovedReferencePaths": removed_paths,
        "OutputText": output_text,
    }


def build_trash_plan(codex_home: Path, session_id: str) -> dict[str, str]:
    """构建 trash 目录布局。"""

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    trash_root = (codex_home / "trash" / "session-cleaner" / f"{timestamp}-{session_id}").resolve()
    return {
        "TrashRoot": str(trash_root),
        "BackupDirectory": str(trash_root / "backups"),
        "SessionFileRoot": str(trash_root / "session-files"),
        "ManifestPath": str(trash_root / "cleanup-manifest.json"),
    }


def build_plan(codex_home: Path, session_id: str, apply: bool) -> dict[str, Any]:
    """汇总预览/执行计划对象。"""

    paths = {
        "SessionIndexPath": str((codex_home / "session_index.jsonl").resolve()),
        "GlobalStatePath": str((codex_home / ".codex-global-state.json").resolve()),
    }

    session_files = scan_session_files(codex_home, session_id)
    session_index = build_session_index_plan(Path(paths["SessionIndexPath"]), session_id)
    global_state = build_global_state_plan(Path(paths["GlobalStatePath"]), session_id)
    trash = build_trash_plan(codex_home, session_id)

    plan = {
        "Mode": "apply" if apply else "preview",
        "SessionId": session_id,
        "CodexHome": str(codex_home.resolve()),
        "Paths": paths,
        "SessionFiles": [
            {
                "Scope": item.scope,
                "FullPath": str(item.full_path),
            }
            for item in session_files
        ],
        "SessionIndex": {
            "Exists": session_index["Exists"],
            "RemovedCount": session_index["RemovedCount"],
            "MatchingRecords": session_index["MatchingRecords"],
        },
        "GlobalState": {
            "Exists": global_state["Exists"],
            "RemovedReferenceCount": global_state["RemovedReferenceCount"],
            "RemovedReferencePaths": global_state["RemovedReferencePaths"],
        },
        "Trash": trash,
        "Summary": {
            "SessionFileCount": len(session_files),
            "SessionIndexRemovedCount": session_index["RemovedCount"],
            "GlobalStateReferenceCount": global_state["RemovedReferenceCount"],
        },
    }

    # 执行阶段会复用这些内部字段；输出 JSON 时会过滤掉，避免暴露实现细节。
    plan["_internal"] = {
        "SessionFiles": session_files,
        "SessionIndex": session_index,
        "GlobalState": global_state,
    }
    return plan


def build_public_plan(plan: dict[str, Any]) -> dict[str, Any]:
    """移除内部执行字段，生成对外 JSON 结构。"""

    return {
        key: value
        for key, value in plan.items()
        if key != "_internal"
    }


def ensure_apply_has_work(plan: dict[str, Any]) -> None:
    """执行前校验至少命中一个有效改动点。"""

    summary = plan["Summary"]
    if (
        summary["SessionFileCount"] == 0
        and summary["SessionIndexRemovedCount"] == 0
        and summary["GlobalStateReferenceCount"] == 0
    ):
        raise RuntimeError(
            f"No matching session files or exact references found for session ID: {plan['SessionId']}"
        )


def apply_plan(plan: dict[str, Any]) -> None:
    """
    执行清理计划。

    执行顺序：
    1. 创建 trash 目录
    2. 备份关键文件
    3. 改写 session_index.jsonl
    4. 改写 .codex-global-state.json
    5. 移动命中的会话文件
    6. 写入 cleanup-manifest.json
    """

    internal = plan["_internal"]
    trash_root = Path(plan["Trash"]["TrashRoot"])
    backup_dir = Path(plan["Trash"]["BackupDirectory"])
    session_file_root = Path(plan["Trash"]["SessionFileRoot"])
    manifest_path = Path(plan["Trash"]["ManifestPath"])

    backup_dir.mkdir(parents=True, exist_ok=True)
    session_file_root.mkdir(parents=True, exist_ok=True)

    session_index_path = Path(plan["Paths"]["SessionIndexPath"])
    session_index_plan = internal["SessionIndex"]
    if session_index_plan["Exists"]:
        shutil.copy2(session_index_path, backup_dir / "session_index.jsonl.bak")
        session_index_path.write_text(session_index_plan["OutputText"], encoding="utf-8")

    global_state_path = Path(plan["Paths"]["GlobalStatePath"])
    global_state_plan = internal["GlobalState"]
    if global_state_plan["Exists"]:
        shutil.copy2(global_state_path, backup_dir / ".codex-global-state.json.bak")
        global_state_path.write_text(global_state_plan["OutputText"], encoding="utf-8")

    for session_file in internal["SessionFiles"]:
        scope_dir = session_file_root / session_file.scope
        scope_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(session_file.full_path), str(scope_dir / session_file.full_path.name))

    manifest_path.write_text(
        json.dumps(build_public_plan(plan), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str]) -> int:
    """脚本入口。"""

    try:
        configure_stdio()
        args = parse_args(argv)
        codex_home = Path(args.codex_home).expanduser().resolve()
        assert_codex_home(codex_home)
        plan = build_plan(codex_home, args.session_id, args.apply)

        if args.apply:
            ensure_apply_has_work(plan)
            apply_plan(plan)

        print(json.dumps(build_public_plan(plan), ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:  # noqa: BLE001
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
