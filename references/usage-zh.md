# 中文使用说明

## 适用场景

这个 skill 用来按会话 ID 安全物理清理本地 Codex 会话，适合下面这些需求：

- “把某个会话从本地彻底清掉”
- “按 session id 删除会话”
- “把某个线程的本地痕迹移走，但不要永久删除”
- “清理 session_index 和全局状态里的会话引用”

它默认面向 Windows 与 macOS，核心脚本使用 Python 标准库实现，最低要求 `Python 3.9+`。

## 清理原则

这个 skill 不直接永久删除文件，而是遵循下面的安全原则：

1. 先预览，再执行。
2. 会话文件只移动到 `trash`，不使用危险删除。
3. 只清理与目标会话 ID 精确匹配的索引和状态引用。
4. 不修改 `state_*.sqlite`、`logs_*.sqlite` 这类高风险数据库文件。
5. 如果目标就是当前活跃会话，应停止执行，切到其他会话后再处理。

## 目录影响范围

执行时可能读取或改写这些位置：

- `$CODEX_HOME\sessions\...`
- `$CODEX_HOME\archived_sessions\...`
- `$CODEX_HOME\session_index.jsonl`
- `$CODEX_HOME\.codex-global-state.json`
- `$CODEX_HOME\trash\session-cleaner\...`

## 路径说明

为了避免在文档里暴露任何真实用户名或本机隐私路径，这份文档统一使用匿名占位符：

- `C:\Users\<user>\.codex`
  表示当前用户的 Codex 根目录示例。
- `<skill-dir>`
  表示 skill 的安装目录，例如 `C:\Users\<user>\.codex\skills\codex-session-cleaner`。
- `<session-id>`
  表示目标会话 ID。

如果实际环境里已经设置了 `CODEX_HOME`，优先按 `$CODEX_HOME` 理解这些路径。

## 推荐使用方式

显式调用 skill：

```text
请使用 $codex-session-cleaner 预览清理会话 <session-id>
```

或：

```text
请使用 $codex-session-cleaner 物理清理会话 <session-id>
```

## 命令行直接运行

Windows 先预览：

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>"
```

Windows 确认后再执行：

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

Windows 如果需要指定 Codex 根目录：

```powershell
python "C:\Users\<user>\.codex\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --codex-home "C:\Users\<user>\.codex" `
  --apply
```

macOS 先预览：

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>"
```

macOS 确认后再执行：

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

macOS 如果需要指定 Codex 根目录：

```bash
python3 "/Users/<user>/.codex/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --codex-home "/Users/<user>/.codex" \
  --apply
```

也可以使用环境变量风格的匿名路径说明：

```powershell
python "$CODEX_HOME\skills\codex-session-cleaner\scripts\remove-session-by-id.py" `
  --session-id "<session-id>" `
  --apply
```

```bash
python3 "$CODEX_HOME/skills/codex-session-cleaner/scripts/remove-session-by-id.py" \
  --session-id "<session-id>" \
  --apply
```

## 预览输出怎么看

预览模式会输出一份 JSON 摘要，重点看这几项：

- `SessionFiles`
  表示将被移动到 `trash` 的会话文件。
- `SessionIndex.RemovedCount`
  表示 `session_index.jsonl` 中会移除多少条记录。
- `GlobalState.RemovedReferenceCount`
  表示 `.codex-global-state.json` 中会清理多少个精确引用。
- `Trash.TrashRoot`
  表示执行后备份和会话文件会被放到哪里。

## 执行后的结果

执行模式会做这些事情：

1. 备份 `session_index.jsonl`
2. 备份 `.codex-global-state.json`
3. 把目标会话文件移动到 `trash\session-cleaner\...`
4. 输出一份 `cleanup-manifest.json`

## Trash 文件夹结构

典型结构如下：

```text
$CODEX_HOME/trash/session-cleaner/<timestamp>-<session-id>/
├── backups/
│   ├── session_index.jsonl.bak
│   └── .codex-global-state.json.bak
├── session-files/
│   ├── sessions/
│   └── archived_sessions/
└── cleanup-manifest.json
```

你可以这样理解：

- `backups/`
  放被改写前的索引和全局状态备份。
- `session-files/`
  放被移动出来的原始会话文件。
- `sessions/` / `archived_sessions/`
  保留原始来源作用域，方便恢复时放回正确目录。
- `cleanup-manifest.json`
  放本次清理摘要，便于核对。

## 恢复指南

如果需要人工恢复，请按这个顺序操作：

1. 找到目标 `trash` 目录
   例如 `$CODEX_HOME/trash/session-cleaner/<timestamp>-<session-id>/`
2. 恢复 `backups/session_index.jsonl.bak`
   覆盖回原始 `session_index.jsonl`
3. 恢复 `backups/.codex-global-state.json.bak`
   覆盖回原始 `.codex-global-state.json`
4. 将 `session-files/...` 下的会话文件移回原目录
   根据它位于 `sessions/` 还是 `archived_sessions/` 放回对应位置
5. 重启 Codex
   让 UI 刷新并重新读取会话状态

恢复边界说明：

- 应使用同一批次 `trash` 目录里的备份和会话文件一起恢复。
- 如果只恢复索引、不恢复会话文件，列表和实体文件会不一致。
- 如果只恢复会话文件、不恢复索引或全局状态，UI 可能仍然不显示。
- 不涉及 SQLite 恢复，也不建议手动修改数据库。

## 完成后的结构化简报示例

```text
清理报告
状态: `已完成，请重启Codex以确认`
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

- `原始对话位置` 通常来自 `SessionFiles` 中的原始会话文件路径。
- 如果命中多个会话文件，默认展示第一条路径，并补充说明还有其他关联文件命中。
- 所有动态值统一使用反引号包裹，并保持 raw 文本展示，不要写成 `[]()` 链接。

## 预览结果示例

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

- `原始对话位置` 通常来自 `SessionFiles` 中的原始会话文件路径。
- 如果命中多个会话文件，默认展示第一条路径，并补充说明还有其他关联文件命中。
- 所有动态值统一使用反引号包裹，并保持 raw 文本展示，不要写成 `[]()` 链接。

## 失败总结示例

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

- `原因` 应该是直接、简短的失败原因，不要复读整段报错堆栈。
- `写入情况` 应明确说明是否未写入，或写入在何处中断。
- 所有动态值统一使用反引号包裹，并保持 raw 文本展示，不要写成 `[]()` 链接。

## 风险提示

- 不要在当前正在聊天的会话里直接清理当前会话自己。
- 如果预览结果为 0 命中，不要强行执行，应先检查会话 ID 是否正确。
- 如果用户想永久删除，这个 skill 也应先使用移动到 `trash` 的策略，不要跳过安全缓冲层。
