# Codex Session Cleaner

[English README](README.md)

这是一个用于按会话 ID 安全物理清理本地 Codex 会话的 skill，支持 Windows 和 macOS，核心实现基于 Python，并且默认把文件移动到 `trash`，而不是直接永久删除。

## 这个 Skill 能做什么

- 先预览、再执行，降低误操作风险
- 清理 `session_index.jsonl` 和 `.codex-global-state.json` 里的精确会话引用
- 把命中的会话文件移动到 `trash`，保留恢复路径
- 为索引和全局状态生成备份，并输出清理清单
- 不修改高风险 SQLite 文件
- 只支持显式调用，不走隐式触发

## 适合什么场景

- 按 session ID 清理某个本地会话
- 从本地历史中移走某个会话，但先保留恢复能力
- 清理会话索引和 UI 全局状态里的精确引用
- 需要一个同时适用于 Windows 和 macOS 的 Python 版方案

## 仓库结构说明

这个仓库按“仓库根目录就是 skill 根目录”的方式发布。

关键内容包括：

- `SKILL.md`
  skill 指令和行为规范
- `scripts/remove-session-by-id.py`
  Windows / macOS 通用的 Python 主实现
- `references/`
  更详细的使用说明、trash 结构说明、恢复指南和风险说明

## 环境要求

- Codex，并且本地存在可访问的 Codex 根目录
- Python `3.9+`
- 执行 `--apply` 时，对目标 `$CODEX_HOME` 具备读写权限

## 安装方式

### 方法 A：通过 `skill-installer` 从 GitHub 安装

因为这个仓库是独立 skill 仓库，所以安装时固定从仓库根目录取 skill，使用 `--path "."`，并显式指定安装名。

Windows：

```powershell
python "$CODEX_HOME\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo "<owner>/<repo>" `
  --path "." `
  --name "codex-session-cleaner"
```

macOS：

```bash
python3 "$CODEX_HOME/skills/.system/skill-installer/scripts/install-skill-from-github.py" \
  --repo "<owner>/<repo>" \
  --path "." \
  --name "codex-session-cleaner"
```

如果环境里没有设置 `CODEX_HOME`，请把它替换为你的本机 Codex 根目录。

### 方法 B：手动安装

1. clone 或下载这个仓库
2. 把仓库根目录复制到 `$CODEX_HOME/skills/codex-session-cleaner`
3. 重启 Codex，让新 skill 被重新发现

## 快速开始

推荐提示词：

```text
请使用 $codex-session-cleaner 预览清理会话 <session-id>
```

或者：

```text
请使用 $codex-session-cleaner 物理清理会话 <session-id>
```

直接运行 CLI：

Windows 预览：

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>"
```

Windows 执行：

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

macOS 预览：

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>"
```

macOS 执行：

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

如果需要显式指定 Codex 根目录：

```text
--codex-home "<codex-home>"
```

## 安全提示

- 不要在当前活跃会话里直接清理当前会话自己
- 应先跑预览，再根据命中结果决定是否执行 `--apply`
- 这个 skill 默认把会话文件移动到 `trash`，不直接永久删除
- 这个 skill 不会修改 `state_*.sqlite`、`logs_*.sqlite` 等 SQLite 文件
- 只清理精确等于目标会话 ID 的引用，不模糊替换普通文本

## 延伸文档

- [English README](README.md)
- [详细英文使用说明](references/usage-en.md)
- [中文使用说明](references/usage-zh.md)
- [会话布局、trash 结构与恢复说明](references/codex-session-layout.md)
