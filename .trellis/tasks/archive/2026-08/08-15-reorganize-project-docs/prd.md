# 整理项目文档结构与陈旧内容

## Goal

把 `docs/` 从阶段性平铺文档整理为长期可维护的项目文档：保留仍被 README、源码和维护流程依赖的产品事实，消除过时 Trellis 指令、重复 P0 验收记录和会漂移的阶段性表述，并明确区分架构说明、开发接入和候选验收记录。

## Background

- 当前 `docs/` 有 6 个 Markdown 文件，共 537 行。
- `README.md` / `README.zh-CN.md` 直接引用 `data-layer.md`、`pet-window-detection.md`、`final-success-criteria.md`。
- `Sources/PetDock/PetTracker.swift` 的阈值注释直接引用 `docs/pet-window-detection.md`。
- `docs/trellis-setup.md:18-38` 仍要求 `trellis init --claude` 并以 `.claude/` 为当前平台；实际仓库已经使用被跟踪的 `.codex/` 和 `.agents/`，`trellis platforms` 显示 Codex active。
- `docs/success-criteria.md` 是早期 P0 阶段记录，其识别依据和验收内容已分别被 `pet-window-detection.md` 与 `final-success-criteria.md` 覆盖。
- `docs/data-layer.md:89` 仍写 26 项数据测试，而当前公开口径是 123 项；`docs/dock-obstacle-avoidance.md:80` 仍写 BubbleVisibility 11 项，而当前公开口径是 49 项。
- `.trellis/spec/` 是开发约束，不替代面向维护者和用户的产品架构与验证文档。

## Requirements

1. 将长期产品设计文档迁移至 `docs/architecture/`：
   - `data-layer.md`
   - `pet-window-detection.md`
   - `dock-obstacle-avoidance.md`
2. 将 Trellis 接入说明迁移并重写为 `docs/development/trellis.md`：
   - 以当前 Codex 平台为准；
   - 准确说明 `.agents/`、`.codex/`、`.trellis/` 中标准生成内容、项目定制内容和本地 ignored 状态；
   - 开发者身份使用通用占位 `<developer>`，不得写本机隐私路径；
   - 不把 `.claude/` 描述为当前项目的必需平台。
3. 将当前候选验收文档迁移为 `docs/verification/dev-candidate.md`：
   - 明确它是 `dev` 候选状态，不宣称已经合入 `main`；
   - 保留自动验证、静态结论、真机未验证三类边界；
   - 移除已经失真的“make app 待执行”等绝对状态，改成可重复执行的验收清单和最近验证口径；
   - 不写构建特定 SHA、CDHash、真实 wid、坐标或用户路径。
4. 将 `docs/success-criteria.md` 中仍有价值且未重复的手工 P0 验证步骤/风险合并到新的候选验收或窗口识别文档，然后删除旧文件。
5. 更新架构文档中的陈旧阶段语言和测试口径：
   - 数据层采用当前 `test-data=123` 口径，或使用不易漂移的套件引用；
   - BubbleVisibility 采用当前 49 项口径，或使用不易漂移的套件引用；
   - 不修改 dock 底座/控制按钮避让行为及其产品结论；只整理文档。
6. 更新 `README.md`、`README.zh-CN.md`、源码注释和仓库内所有相对链接，使旧路径无残留、所有本地 Markdown 链接可解析。
7. 不修改 Swift 行为、测试实现、构建配置、Trellis 模板或用户未跟踪文件。

## Acceptance Criteria

- [x] `docs/` 只保留新的分类目录和必要文档，不再存在旧的 6 个顶层 Markdown 文件。
- [x] README 中英文版和 `PetTracker.swift` 均引用新路径，仓库内无旧文档路径残留。
- [x] `docs/development/trellis.md` 与当前 `trellis platforms`、tracked/ignored 事实一致，不再指导 `--claude` 初始化。
- [x] `docs/verification/dev-candidate.md` 不再声称 dev 内容已合入 main，并清楚区分已自动验证与真机未验证。
- [x] 旧 `success-criteria.md` 的唯一有效内容已迁移，旧文件删除后不丢失必要手工验收步骤。
- [x] 文档不包含 `/Users/<name>`、真实 wid/坐标、CDHash、凭证、Co-Authored-By 或构建特定 hash。
- [x] Markdown 相对链接检查通过；`git diff --check` 通过。
- [x] 文档改动不触发业务代码变化；如唯一源码改动为路径注释，Swift 构建行为保持不变。
- [x] 独立 Review 对目标完整 SHA 得出 P0/P1/P2=0；独立 QA 对同一 SHA 验证通过。

## Out of Scope

- 修改 dock 底座或控制按钮避让实现、测试和产品规则。
- 修复此前安全审计提出的数据读取、主题加载或子进程边界问题。
- 改写 Git 历史、main/dev 分支关系、发布 tag 或 GitHub 内容。
- 真机 TCC、ScreenCaptureKit、多显示器、Accessibility 交互验证。
- 修改 `.agents/`、`.codex/`、`.trellis/` 的生成内容或配置。
