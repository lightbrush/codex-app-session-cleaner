# Codex Session Layout Reference

## 目的

这份参考资料说明这个 skill 为什么只改少量关键文件，以及为什么默认使用“移动到 trash”而不是永久删除。

## 关键路径

- `sessions/<yyyy>/<mm>/<dd>/rollout-...-<session-id>.jsonl`
  主要的活动会话记录文件。
- `archived_sessions/...`
  已归档会话可能存在的位置。
- `session_index.jsonl`
  会话列表索引。一个会话 ID 可能因为历史写入而出现多条记录，清理时应全部移除。
- `.codex-global-state.json`
  保存 UI 级别状态，例如 projectless 线程列表、workspace hint、终端开关、固定线程等。

## 为什么不直接改数据库

`state_*.sqlite` 和 `logs_*.sqlite` 属于更高风险的数据层：

- 格式和用途不稳定
- 容易引入更难发现的 UI 状态问题
- 本次目标只是按会话 ID 做安全物理清理，不需要碰这些数据库

因此，这个 skill 有意避免修改 SQLite 文件。

## 清理策略

1. 先定位目标会话文件。
2. 先预览，不直接改。
3. 真正执行时，先备份索引文件。
4. 只移除“精确命中 session ID”的索引或状态引用。
5. 会话文件使用 `Move-Item` 移到 `trash`，不做永久删除。

## Trash 目录结构

执行成功后，目标文件会被整理到下面这样的目录结构中：

```text
$CODEX_HOME/trash/session-cleaner/<timestamp>-<session-id>/
├── backups/
│   ├── session_index.jsonl.bak
│   └── .codex-global-state.json.bak
├── session-files/
│   ├── sessions/
│   │   └── rollout-...-<session-id>.jsonl
│   └── archived_sessions/
│       └── rollout-...-<session-id>.jsonl
└── cleanup-manifest.json
```

各部分用途：

- `backups/`
  保存被改写前的索引与全局状态文件，用于恢复。
- `session-files/`
  保存被移动出去的原始会话文件。
- `session-files/sessions/`
  表示该文件原本来自活动会话目录。
- `session-files/archived_sessions/`
  表示该文件原本来自已归档会话目录。
- `cleanup-manifest.json`
  保存本次清理的摘要，便于审计与人工核对。

为什么保留 `sessions/` 或 `archived_sessions/` 这一层：

- 恢复时可以知道文件原本来自哪个作用域目录。
- 避免活动会话文件与归档会话文件混在一起，降低人工恢复时放错位置的风险。
- 便于未来排查“为什么这个会话最初来自 archived_sessions”这类问题。

## 典型预览结果应该包含

- 找到的 `sessions` / `archived_sessions` 文件路径
- `session_index.jsonl` 中匹配记录数量
- `.codex-global-state.json` 中清理的属性路径或数组位置数量
- 最终 `trash` 目标目录

## 已知边界

- 如果用户要删除的是“当前正在聊天的那个线程”，应停止并让用户切到其他线程再执行。
- 如果 UI 仍显示旧会话，通常需要重启 Codex。
- 如果某些未来版本把额外引用迁移到新文件，本 skill 需要迭代更新。

## 恢复边界

恢复时应遵循这些边界：

- 必须使用同一批次 `trash/session-cleaner/<timestamp>-<session-id>/` 目录中的备份与会话文件。
- 不要把某次清理的 `backups/` 与另一次清理的 `session-files/` 混用。
- 如果只恢复索引文件、不恢复对应会话文件，可能导致列表里出现会话，但实体文件不存在。
- 如果只恢复会话文件、不恢复索引与全局状态，可能导致实体文件回来了，但 UI 不显示。
- 本 skill 不涉及 SQLite 恢复，也不建议手动改 `state_*.sqlite` 或 `logs_*.sqlite`。
