---
name: codex-session-cleaner
description: Safely physically clean a local Codex session by session/thread ID with a Python-based workflow for Windows and macOS. Use when Codex needs to delete, purge, hard-remove, or clean up a conversation from `~/.codex` or `$CODEX_HOME`, update `session_index.jsonl`, scrub exact session references from `.codex-global-state.json`, and move session files into a `trash` folder instead of destructive deletion. Also use for Chinese requests such as “按会话ID删除会话”, “物理清理会话”, “清掉 session”, or “根据 session id 清理会话”.
---

# Codex Session Cleaner

使用这个 skill 时，优先走“先预览、再执行”的两阶段流程。这个 skill 默认使用 Python 主实现，面向 Windows 与 macOS，目标是按会话 ID 安全清理本地 Codex 会话文件，并避免直接删除。

运行前假定环境可用 `Python 3.9+`。

## 快速流程

1. 确认用户给了明确的会话 ID。
2. 判断目标是否可能是当前正在进行的会话。
3. 先运行 `scripts/remove-session-by-id.py` 预览计划，不带 `--apply`。
4. 检查预览输出里的命中文件、索引变更数量、全局状态引用清理数量。
5. 只有在用户确认执行，且目标不是当前活跃会话时，才带 `--apply` 再执行一次。
6. 汇报被移动到 `trash` 的文件路径，并提醒用户重启 Codex 刷新 UI 状态。

## 安全规则

- 不要在当前活跃会话里直接物理清理当前会话本身。
- 如果用户给出的 ID 看起来就是当前线程，停止执行，并让用户切到另一个线程再操作。
- 不要使用 `Remove-Item` 删除会话文件。
- 不要改动 SQLite 数据库，例如 `state_*.sqlite`、`logs_*.sqlite`。
- 只清理“精确等于该会话 ID”的索引或全局状态引用；不要尝试模糊替换普通文本。
- 如果沙箱阻止写入 `$CODEX_HOME` 或 `~/.codex`，按平台要求申请提权，不要绕过。

## 运行方式

Windows 预览：

```powershell
python "<skill-dir>\scripts\remove-session-by-id.py" --session-id "<session-id>"
```

Windows 执行：

```powershell
python "<skill-dir>\scripts\remove-session-by-id.py" --session-id "<session-id>" --apply
```

macOS 预览：

```bash
python3 "<skill-dir>/scripts/remove-session-by-id.py" --session-id "<session-id>"
```

macOS 执行：

```bash
python3 "<skill-dir>/scripts/remove-session-by-id.py" --session-id "<session-id>" --apply
```

如果需要显式指定 Codex 根目录：

```text
--codex-home "<codex-home>"
```

## 预期效果

执行脚本后会做这些事情：

- 在 `sessions/` 和 `archived_sessions/` 下查找包含该会话 ID 的 JSONL 会话文件
- 从 `session_index.jsonl` 中移除所有匹配该 ID 的记录
- 从 `.codex-global-state.json` 中移除所有“键等于该 ID”或“值精确等于该 ID”的引用
- 把命中的会话文件移动到 `$CODEX_HOME\trash\session-cleaner\<timestamp>-<session-id>\session-files\`
- 把被改写前的 `session_index.jsonl` 和 `.codex-global-state.json` 备份到同一个 trash 目录
- 输出一份 JSON 摘要，便于审计和回滚

## 何时读取参考资料

只有在下面情况才读取 [references/codex-session-layout.md](references/codex-session-layout.md)：

- 需要解释为什么只改 `session_index.jsonl` 和 `.codex-global-state.json`
- 需要向用户说明哪些文件会改、哪些不会改
- 需要判断预览输出是否符合预期

如果用户需要中文操作手册、示例命令、风险说明或回滚思路，读取 [references/usage-zh.md](references/usage-zh.md)。

如果用户需要英文操作手册、英文命令示例或英文风险说明，读取 [references/usage-en.md](references/usage-en.md)。

如果用户需要理解 `trash` 目录结构、各文件用途、或恢复时应该按什么顺序操作，读取 [references/codex-session-layout.md](references/codex-session-layout.md)。

## 结果汇报要求

- 预览模式：
  - 明确说明是“仅预览”
  - 列出命中的会话文件数
  - 列出从 `session_index.jsonl` 将删除的记录数
  - 列出从 `.codex-global-state.json` 将清掉的精确引用数
  - 给出目标 `trash` 目录路径
  - 所有动态值统一使用反引号包裹的 raw 文本格式
  - 不要把路径、会话 ID、会话名称或其他字段值渲染成 `[]()` Markdown 链接
- 执行成功后：
  - 必须输出一份结构化、简明的完成清理报告
  - 不要直接粘贴整段 JSON
  - 不要默认展开完整文件列表，除非用户追问
  - 所有动态值统一使用反引号包裹的 raw 文本格式
  - 不要把路径、会话 ID、会话名称或其他字段值渲染成 `[]()` Markdown 链接
- 执行失败后：
  - 不要输出成功报告模板
  - 改为短失败总结，说明失败原因与是否发生写入
  - 所有动态值统一使用反引号包裹的 raw 文本格式
  - 不要把路径、会话 ID、会话名称或其他字段值渲染成 `[]()` Markdown 链接

## 预览结果模板

中文用户使用：

```text
预览结果
状态: `仅预览`
会话 ID: `<session-id>`
会话名称: `<thread-name>`
原始对话位置: `<original-session-path>`
将移动的会话文件: `<count>`
将删除的索引记录: `<count>`
将清理的全局状态引用: `<count>`
目标 Trash 目录: `<path>`
后续: `如确认无误，再执行正式清理`
```

说明：

- `会话名称` 只有在 `SessionIndex.MatchingRecords` 可取到时才输出。
- `原始对话位置` 只有在 `SessionFiles` 可取到时才输出。
- 如果命中多个会话文件，默认展示第一条原始路径，并补一句“另有 N 个关联文件命中”。
- 字段值保持 raw 文本展示，不要转成 Markdown 链接。
- 保持 6-8 行内完成，优先简明。

英文用户使用：

```text
Preview Result
Status: `Preview Only`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Session Files To Move: `<count>`
Session Index Records To Remove: `<count>`
Global State References To Remove: `<count>`
Target Trash Directory: `<path>`
Next Step: `If everything looks correct, run the actual cleanup`
```

说明：

- `Thread Name` only appears when available in `SessionIndex.MatchingRecords`.
- `Original Conversation Location` only appears when available in `SessionFiles`.
- If multiple session files are matched, show the first original path and note that additional matched files also exist.
- Keep dynamic values as raw text wrapped in backticks, not Markdown links.
- Keep the report short and structured.

## 完成清理报告模板

中文用户使用：

```text
清理报告
状态: `已完成`
会话 ID: `<session-id>`
会话名称: `<thread-name>`
原始对话位置: `<original-session-path>`
移动的会话文件: `<count>`
删除的索引记录: `<count>`
清理的全局状态引用: `<count>`
Trash 目录: `<path>`
后续: `如需恢复，请按 trash 目录内的恢复指南操作；完成后重启 Codex`
```

说明：

- `会话名称` 只有在 `SessionIndex.MatchingRecords` 可取到时才输出。
- `原始对话位置` 只有在 `SessionFiles` 可取到时才输出。
- 如果命中多个会话文件，默认展示第一条原始路径，并补一句“另有 N 个关联文件命中”。
- 字段值保持 raw 文本展示，不要转成 Markdown 链接。
- 保持 6-8 行内完成，优先简明。

英文用户使用：

```text
Cleanup Report
Status: `Completed`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Session Files Moved: `<count>`
Session Index Records Removed: `<count>`
Global State References Removed: `<count>`
Trash Directory: `<path>`
Next Step: `If needed, restore from the matching trash folder, then restart Codex`
```

说明：

- `Thread Name` only appears when available in `SessionIndex.MatchingRecords`.
- `Original Conversation Location` only appears when available in `SessionFiles`.
- If multiple session files are matched, show the first original path and note that additional matched files also exist.
- Keep dynamic values as raw text wrapped in backticks, not Markdown links.
- Keep the report short and structured.

## 失败总结模板

中文用户使用：

```text
清理未完成
状态: `失败`
会话 ID: `<session-id>`
会话名称: `<thread-name>`
原始对话位置: `<original-session-path>`
原因: `<reason>`
写入情况: `<write-status>`
后续: `请先检查 session ID、预览命中结果或当前会话状态`
```

说明：

- `会话名称` 只有在 `SessionIndex.MatchingRecords` 可取到时才输出。
- `原始对话位置` 只有在 `SessionFiles` 可取到时才输出。
- `写入情况` 应明确说明是否未写入，或写入在何处中断。
- 字段值保持 raw 文本展示，不要转成 Markdown 链接。
- 失败总结保持简短，不复述整段 JSON。

英文用户使用：

```text
Cleanup Incomplete
Status: `Failed`
Session ID: `<session-id>`
Thread Name: `<thread-name>`
Original Conversation Location: `<original-session-path>`
Reason: `<reason>`
Write Status: `<write-status>`
Next Step: `Check the session ID, preview hits, or active-thread state before retrying`
```

说明：

- `Thread Name` only appears when available in `SessionIndex.MatchingRecords`.
- `Original Conversation Location` only appears when available in `SessionFiles`.
- `Write Status` should clearly state whether no write occurred or where the write stopped.
- Keep dynamic values as raw text wrapped in backticks, not Markdown links.
- Keep the failure summary short and do not restate the full JSON output.
