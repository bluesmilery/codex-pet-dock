# 气泡收起与平滑跟随：延期交接

## 当前结论

- 状态：`deferred`，未 `accepted`，任务仍保持 `in_progress`。
- 停放分支：`feature/fix-bubble-collapse-smooth-follow`。
- 冻结产品候选：`cfc0731625d80d02960f0ce0eb346fee576ea798`。
- 本文件的提交是纯文档提交；冻结产品候选是其直接祖先。既有 Review、自动测试和候选归档结论只绑定上述产品候选，不自动覆盖本文件提交或未来 merge SHA。
- 未合入 `dev`。用户决定先停放本轮成果，原始真机问题留待后续迭代继续修复。

## 本轮已完成

1. 气泡探测、调度与布局链增加了生产组合回归，覆盖统一单调时钟、latest-only tick、分类变化唤醒和最终 `DockPanel.frame` 所有者。
2. 完全隐藏路径区分成功统计、成功清单中目标缺失以及捕获失败；只有曾成功观察的目标才允许由后续清单缺失失效，失败路径继续保守避让。
3. moving 状态加入最长 32ms 的线性插值，追踪最新目标、不排队历史位置、不允许过冲；安全复位路径仍可立即落位。
4. 增加默认关闭的运行时证据，并将生产 sink 固定在私有 Diagnostics 边界；测试专用构造只在 `PETDOCK_TESTING` 下开放。
5. 加固运行时证据隐私门禁，包括构造器/别名逃逸、Make 变量间接注入测试 flag 等绕过。
6. 同步测试、README、架构说明、候选归档说明和 Trellis 证据拓扑规则。

## 已验证证据

以下结论均绑定冻结产品候选 `cfc0731625d80d02960f0ce0eb346fee576ea798`：

- 正式只读 Review：P0/P1/P2 均为 0。
- `swift build -c release`：通过，0 warning。
- 完整自动 QA 两轮通过：
  - docs-check：14 个 Markdown，0 finding；
  - test-docs：10 passed；
  - test-privacy：28 passed；
  - test-ui：282 passed；
  - test-shell：99 passed；
  - test-data：全部通过。
- 已生成并核验 ad-hoc 签名的提交绑定候选；staging 与归档内容一致。归档位置遵循：
  `<QA_WORKTREE>/build/candidates/2026-08-22-040631-v9-runtime-evidence-47895d8/PetDock.app`。
- Diagnostics 目录权限为 `0700`，证据文件权限为 `0600`；`candidateSHA` 与冻结候选匹配。

自动测试、静态检查和候选签名不代表真机图 1→图 2→图 3 已通过。

## 未完成与已知风险

1. 用户最初报告的核心问题仍未形成有效真机结论：会话从折叠态进一步完全隐藏后，Dock 是否及时回到宠物基础位，当前为“未验证”，不得写成已修复。
2. 慢拖、快拖的连续轨迹、相邻采样最大位移、回落耗时和最终位置误差未取得有效数据；32ms 插值只有自动证据，没有合格的真机体感结论。
3. TCC、ScreenCaptureKit 目标缺失分支、多屏和高刷新率真机表现均未完成有效验收。
4. 多次视觉 QA 尝试不能作为产品结论：
   - 宿主 Codex/ChatGPT 受 Computer Use 安全限制，不能由 Agent 操作；
   - 只连接候选 PetDock 可以检查其自有 Dock/详情窗口，但无法自行制造宿主会话卡的图 1→图 2→图 3 状态；
   - 用户手动操作的一轮发生在观察环境未就绪时：旧候选与无证据参数的新候选并存，几何采样器实际为 0Hz，故没有可归因时间线；
   - 该轮观察 Agent 的实际模型也不符合约定，结论已作废；后续新建的 Kimi 观察 Agent 在准备完成前按用户要求停止。
5. 最后一次无效现场曾观察到旧候选与新候选并存。下一轮开始前必须只读核对并通过普通 Quit 清理 PetDock 实例，不能复用该现场。

## 下一轮恢复步骤

1. 从本 feature 分支创建新的 `codex/` 实现或诊断分支和唯一 worktree；不要直接修改 feature 或 `dev`。
2. 冻结新的完整候选 SHA 后，先确认只存在一个 PetDock 进程；其 executable 必须来自精确候选路径，并带：
   `--runtime-evidence=<FULL_CANDIDATE_SHA>`。
3. 建立新的证据边界，记录起始 tick、时间和白名单计数；不得把旧证据文件的累计值归因到新操作。
4. 视觉 QA 使用用户指定且已预检可用的 `kimi/k3 + max`。Agent 必须先报告实际模型身份，模型不匹配则停止。
5. 在让用户开始操作前，必须完成 READY 门禁：
   - 唯一候选 PID、路径和参数已核对；
   - worktree HEAD 精确且 tracked clean；
   - 10–20Hz 被动几何采样器已连续运行至少 2 秒，并实际产出带时间戳样本；
   - 起始 runtime evidence 快照已保存。
6. READY 后再由用户手动执行：图 1 停留 → 图 2 停留 → 图 3 停留 → 恢复，重复三轮，再分别慢拖和快拖。Agent 只观察，不控制宿主。
7. 将窗口坐标时间线与 runtime evidence 对齐，至少量化：图 2→图 3 回落耗时、最终位置误差、相邻采样最大位移、是否存在阶跃/过冲/抖动。
8. 若真实症状仍存在，按 `触发/扰动 → 生产消费者 → 调度/回调 → DockPanel.frame` 证据链定位并实施最小修复；新 SHA 必须重新完整 Review 和 QA。

## 后续集成注意事项

- 当前 feature 与后续 `dev` 集成只能在专门的合入会话中进行。
- 本 feature 的产品候选不是当时最新 `dev` 的后代；两边在 Trellis 规范、任务材料、`AGENTS.md`、`Makefile`、README、`main.swift`、测试和候选文档等处均有重叠。
- 合入必须手工组合双方意图，禁止整文件选择 ours/theirs，也不能删除任一方已验收功能或测试来消除冲突。
- merge 产生的新 SHA 是全新候选，冻结产品候选的 Review、测试、候选归档和 QA 结论均不可复用。
- 在核心真机问题解决并完成正式 QA 前，不应将本 feature 标记为 `accepted` 或归档当前任务。
