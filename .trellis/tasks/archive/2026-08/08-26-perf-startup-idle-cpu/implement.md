# Implementation Plan

基线：`dev @ a7639db`；分支 `codex/perf-startup-idle-cpu`；worktree
`../codex-pet-dock-worktrees/perf-startup-idle-cpu`。

1. **测试先行（红）**
   - DataTests：A2 增量（追加含跨边界行）、A3 收缩回退、A4 v2 迁移、增量计数器。
   - UI tests：B1 心跳、B2 identity 恢复快速、B3 工厂每轮一次；C1 策略纯函数。
   - 验证：新测试在未改实现时失败（红）或语义上不可能绿。
2. **A 实现**：CacheEntry v3 + 统一分块行解析器 + 增量/回退/迁移逻辑。
   - 验证：`make test-data` 全绿（含既有测试无回归——以实际计数为准）。
3. **B 实现**：identityDirty 门控 + capturer 工厂 + captureStats(content:)。
   - 验证：`make test-ui` 全绿。
4. **C 实现**：FollowTickPlan 策略 + main.swift 接线。
   - 验证：`make test-ui`；接线人工复核（resume/pause 边沿、首刷完成置位）。
5. **全量门禁**：`swift build -c release` 0 warning；`make test` 全绿。
6. 交付报告：文件、关键 diff、命令与实际输出、失败/未验证项。**不 commit**（主管负责）。
