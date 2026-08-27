# AC Evidence Topology — cs-live-layer-anchor

候选状态：随本提交冻结（完整 40 位 SHA = 提交后 git rev-parse HEAD；实现者交付报告同步报告）。
基线：ba8b87f（dev 批准基线，worktree codex/cs-live-layer-anchor 初始 HEAD）。

## AC1 症状回归（红→绿）：死层排前时 dock 锚定活层内容底

| 字段 | 内容 |
| --- | --- |
| 症状 / AC | AC1：宿主同时存在死层+活层 CS 时，dock 基础位锚活层真实可见内容底，不再被死层残影下推。 |
| 证据类型 | behavior（生产组合回归） |
| 触发 / 注入 | CGWindowList 顺序合成：死层 wid8001(layer3, 1189,-3,768x912, contentBottom=570→abs570) 排在活层 wid8010(layer4, 1487,-41,768x952, contentBottom=371→abs331) 之前；Mascot 参照窗 wid900(172x179@190, contentBottom=139→脚底330)。fake capturer 注入内存 alpha stats。 |
| 基线来源 / 结果 | ba8b87f 生产源码 + 本提交的测试代码（test-only overlay，可辨识差异仅为测试文件与基线 API 兼容垫片：baseline 编译将 tests 中 referenceInFlight 断言替换为等价 inFlight 检查）。命令与结果见下。 |
| 生产消费者 / 路径 | FollowLayoutPass.placeDock → PetTracker.obstaclesNear(签名去重后保留双 CS 候选) → BubbleVisibilityProbe.updateReferences/probe(真实后台 Task) → 活层一致性窗口选择 → DockPanel.placeBelow(setFrame)。 |
| 最终所有者 / 断言 | 实际 DockPanel.frame（owner read-back）。修复后 frame.y=699(AppKit)=Quartz333=活层内容底331+gap2；基线上同 fixture dock 停在死层幽灵位（y=462 AppKit，即 Quartz 死层锚），断言失败。 |
| 命令 / 结果 | 基线红：swiftc -warnings-as-errors -DPETDOCK_TESTING <tests + ba8b87f 三源文件> … -o /tmp/pdbase5 && /tmp/pdbase5 → T-cla1 FAIL（dock y462=死层锚）、其余既有区段全绿；合计 400 passed/12 failed（全部 12 个 FAIL 均为新增 T-cla* 及依赖新语义改写的 T-cs2/T-sch4d/T-csm* 断言，基线行为下按设计必然失败）。修复绿：同法以工作树源码编译运行 → [CS 活层代表选择] 6 passed, 0 failed；总计 412 passed, 0 failed。日志摘要见 /tmp/pdbase5_run.log 与 /tmp/gate_ui_run.log（评审可复现编译命令）。 |
| 手工缺口 | 合成坐标/wid 与现场相对几何一致但非真机窗口；真机多 CS 层并存 QA 归 AC5（主 Agent）。 |

补充断言（同一 fixture 簇）：
- T-cla1b anchor契约：首 tick 回退 Mascot 窗口底锚（petRects[0]==claPet 完整窗口），cache 生效 tick 的 petRects 高度收缩为活层内容（maxY=331、origin/width 不变）。PASS。
- T-cla1c 参考通道隔离：Mascot 仅出现在参考捕获列表 refs=[900]，障碍通道 knownWids=[8001,8010] 不含 Mascot —— knownWids/复位合同（回归 A）未被参照窗改写。PASS。

## AC2 不回归：既有 T-cs / T-csm / T-anc 全量保持

| 字段 | 内容 |
| --- | --- |
| 症状 / AC | AC2：多同 bounds 实例去重、展开态避让、收起态内容底锚定、保守降级跳过均不回归。 |
| 证据类型 | behavior（既有生产组合回归全量复跑） |
| 触发 / 注入 | 既有 fixture 原样保留（T-cs1..T-cs11、T-csm1..T-csm7 中几何相关项按新语义改写期望值并在下方说明、T-anc1..T-anc5）。 |
| 基线来源 / 结果 | 候选树（冻结 SHA）上全量执行。 |
| 生产消费者 / 路径 | 同 AC1 真实链路。 |
| 最终所有者 / 断言 | 实际 DockPanel.frame / probe 候选集 / 障碍计数序列。关键数值：T-cs6 收起态基础位 362 保持；T-cs10/T-cs10b/T-cs10c 降级语义计数 [0,0]/[0,0]/[1,1] 保持；T-csm5 现场多尺寸几何在显式活层数值化后锚前层内容底 666；T-anc1 现场 44px 空白回归保持 331；T-anc4 拖动粘性保持。 |
| 命令 / 结果 | make test-ui（worktree 内 Makefile 入口）等价直编 /tmp/pdtrue_final → 总计 412 passed, 0 failed。[Composition Surface 气泡通道]16 passed、[Composition Surface 多尺寸幽灵]8 passed、[dock 基础位内容底锚定]7 passed、[BubbleVisibility]176 passed。 |
| 手工缺口 | 无（纯自动覆盖）。 |

语义化改写说明（非弱化，每一处均为把"列表顺序代表"升级为"活层一致性代表"后的直接推论，均有具体断言值）：
- T-csm1/T-csm7/T-csm2：obstaclesNear 不再丢弃不同签名 CS——改为断言两签名实例均在候选集（wid 升序排序不改变集合）。
- T-csm3：同签名重复实例仍去重为 1，代表现为 deduplicatedObstacles 的 wid 升序首个 9004（旧断言的输入顺序首位 9005 是旧路径副产品；现与几何通道签名去重规则完全一致）。
- T-csm5：原 fixture 数值隐含"前层即代表"；现显式数值化为活层一致性场景（前层 contentBottom=454→abs664==脚底；后层 contentBottom=700→abs976 出窗被排除），期望锚 666 并 PASS。
- T-cs2：probe 候选断言从"恰 2 个（CS 代表+ACT）"扩展为"ACT 必在 + CS 恰出现 2 次（主导探测 1 + 参考通道 1）+ Mascot 恰 1 次"，证明参考通道的存在且未混入障碍缓存。
- T-sch4d：captureCallCount 由 1→2（主导 1 + 参考 1），其余调度断言不变。

## AC3 一致性边界

| 字段 | 内容 |
| --- | --- |
| 症状 / AC | AC3/R3：边界 fixture 代表稳定；无候选满足窗口时显式回退并有测试。 |
| 证据类型 | behavior |
| 触发 / 注入 | T-cla2：唯一活层候选 csBottomAbs 恰为 petFoot−ε 下界（abs328=330−2）→ 必须入选为代表（frame.y=702 AppKit=Quartz330 内容底+2→ PASS 数值 330：窗口 [foot−ε, foot+172] 含边界）。T-cla3：死层 abs570、活层 abs698+ 均出窗 → rep=nil → dock 回退 Mascot 窗口底 371（pets 全部等于窗口矩形）。 |
| 基线来源 / 结果 | 冻结候选树上 PASS（gate_ui_run.log 行 348/349）。 |
| 生产消费者 / 路径 | 同 AC1。 |
| 最终所有者 / 断言 | 实际 DockPanel.frame 与 frameSink 收到的 adjustedPet 序列。 |
| 命令 / 结果 | 同全量 UI 门禁；[CS 活层代表选择] 6 passed, 0 failed。 |
| 手工缺口 | 边界值容差 ε=2/上界 172 的现场分布合理性归 AC5 真机采样复核。 |

观察不可用（R3）：
- T-cla4 单 CS + 恒 unavailable → 保守回退窗口底、petRects 每拍均为窗口（PASS）；
- T-cs10/T-cs10b/T-cs10c 恒 unavailable/TCC 拒绝/降级 ACT 整窗避让（全部 PASS，计数口径不变）；
- 冷启动首 tick 无 cache 路径由 T-cs11 与 claRunTwoTickLayout 首 place() 直接覆盖（多 tick 序列断言 PASS）。

## AC4 门禁

| 门禁 | 命令 | 结果 |
| --- | --- | --- |
| Release 构建 0 warning | swift build -c release（worktree） | exit 0；输出 grep -ci warning = 0 |
| UI 测试（独立 swiftc，warnings-as-errors） | make test-ui 等价：swiftc -warnings-as-errors -DPETDOCK_TESTING <14 文件> → 运行 | 编译 exit 0；总计 412 passed, 0 failed |
| docs-check | make docs-check | scanned 15 Markdown files; 0 finding(s); exit 0 |
| test-docs | make test-docs | OK; exit 0 |
| test-privacy（系统 python3 缺 pytest，按惯例改用 <conda-base-python> 运行同一 pytest 入口） | python -m pytest -q tests/test_runtime_privacy.py | 28 passed in 0.81s; exit 0 |
| test-data | make test-data | [DataTests] 全部通过; exit 0 |
| test-shell | make test-shell | 99 passed, 0 failed; exit 0 |

隐私声明：本任务像素处理仍仅限内存 alpha 统计（computeAlphaStats 口径未变）；参考通道只传递 outcome 枚举与统计结构（BubbleCaptureOutcome/BubbleAlphaStats），不记录颜色/文字/图像/WID 映射到落盘遥测；RuntimeEvidence 白名单字段零扩展（T-re2a 快照 key 集合断言保持 PASS）；无新增落盘路径。

## 已知瞬态（AC5 真机观察项）

多 CS 层场景下锚定收敛存在设计内的瞬态窗口：参考通道捕获与完成回调之后，布局锚要在下一个 follow tick 才消费新结果，期间 dock 可能短暂停留在 Mascot 窗口底回退位或上一帧代表位置。该瞬态由显式回退测试覆盖（T-cla3/T-cla4、T-cs10 系列），语义为保守回退而非整窗避让；真机 QA（AC5）应把此类短时过渡与死层残影导致的持续压底区分开——前者随即自愈，后者持续存在。

## 冻结 SHA

（提交后由 git rev-parse HEAD 填写的 40 位完整 SHA 见提交信息与交付报告；本文档随该提交一并进入候选树。）
