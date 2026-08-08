# P0 技术验证 — 成功标准与验证记录

> 范围：最小可运行 Swift/AppKit macOS 项目；用公开 API（Quartz / AppKit）定位 Codex 进程、识别宠物窗口、创建透明 NSPanel 跟随，并验证隐藏 / 退出 / 消失的回退与多显示器坐标转换。
> 不含：额度读取、Token 统计、主题、登录自启、安装包、发布及一切 P1 内容。不使用私有 CGS API，不修改 Codex，不读取 auth.json / 认证文件 / Chrome Profile。

## 可验证的成功标准（Success Criteria）

- **SC1 可构建**：主程序能用一条命令编译成功（退出码 0），产物可执行。
- **SC2 进程定位**：运行时能通过 bundle id `com.openai.codex` 拿到主应用 PID 并打印。
- **SC3 窗口枚举与识别**：能枚举该 PID 名下所有窗口，并按文档化的可解释规则选出宠物窗口（输出候选窗口清单 + 命中规则 + 选中理由），且不误选主聊天窗口。
- **SC4 NSPanel 跟随**：透明 NSPanel 创建并显示，宠物窗口移动后面板按既定几何关系（底座紧贴宠物下方）跟随更新。
- **SC5 回退与重捕**：宠物窗口隐藏 / Codex 退出 / 窗口消失后面板自动隐藏；宠物窗口再次出现后能重新捕获并重新跟随。
- **SC6 坐标转换**：多显示器 / 负坐标场景下，Quartz 全局坐标（左上原点）与 AppKit NSScreen 坐标（左下原点）转换正确，面板位置与目标显示器一致。
- **SC7 降级方案**：跨应用窗口相对层级无法用公开 API 精确控制时，验证底座始终紧贴宠物下方、与宠物不重叠，作为可接受的降级。

## 手工验证步骤（Manual Verification）

1. 构建：`make build`（见下方构建记录）。
2. 诊断：`make diagnose`，确认输出里能看到宠物窗口被正确选中（wid、命中规则、理由）。
3. 运行：`make run`，观察屏幕上出现透明面板，位于宠物窗口下方。
4. 拖动宠物窗口到另一位置（含跨显示器 / 屏幕左侧负坐标区域），观察面板跟随且贴合。
5. 隐藏宠物（Codex 应用内关闭宠物开关），观察面板隐藏。
6. 再次显示宠物，观察面板重新出现并跟随。
7. 退出 Codex 应用，观察面板隐藏；重新打开 Codex，观察面板重新出现。

## 构建与运行结果（运行后回填）

- 构建命令：`make app`（= `swift build -c release` + 组装 .app + ad-hoc 签名）
- 构建结果：`Build complete!`，退出码 0，无警告；产物 `build/PetDock.app`（arm64 Mach-O，ad-hoc 签名 Identifier=io.github.bluesmilery.codexpetdock）；构建特定 CDHash 已删除（ad-hoc 每次签名变化，公开固定值易误导）
- 各 SC 实测结果（真实运行，preflight=true；窗口数 / PID / wid 为示例，已脱敏）：
  - **SC1 可构建** ✅ 通过：`swift build -c release` 退出码 0、无警告，`.app` 可执行。
  - **SC2 进程定位** ✅ 通过：bundle id `com.openai.codex` → 定位到 `/Applications/ChatGPT.app` 主进程（PID / 版本因机器而异，已脱敏）。
  - **SC3 窗口枚举与识别** ✅ 通过：`CGWindowListCopyWindowInfo([], kCGNullWindowID)` 枚举全局窗口、codex 多窗口（union 候选）；选中 Mascot 本体 `title="Codex Pet Mascot Effect"` layer=2 172×179，命中 `title~Mascot`；主窗口 ChatGPT 1728×1050 正确 [MAIN] 排除，Voice Controls Backing / Composition Surface 等辅助窗亦排除。
  - **SC4 NSPanel 跟随** ✅ 通过：0.5s 轮询持续跟随 Mascot，日志 dockAppKit 每 tick 更新，滞回稳定（wid 不变）。
  - **SC5 回退与重捕** ⚠️ 部分通过：重新捕获 ✅ 真实（PetDock 重启后重新选中 Mascot 并跟随）；隐藏逻辑 ✅（代码 `hideIfNeeded` + selftest T5「无可见→nil」）；**宠物隐藏 / Codex 退出真实触发未执行**（需用户在 ChatGPT 内操作，受"不修改 Codex"约束，本轮未触发）。
  - **SC6 坐标转换** ✅ 通过：宠物副屏负坐标 quartz=(<qx>,<qy>)172×179 → 面板 dockAppKit=(<ax>,<ay>)；公式 `<H>-(<qy>+179+2)-30=<ay>`（`<H>` 为主屏高度）与日志一致；screen=副屏正确；selftest Geometry 4/4。（坐标/分辨率因机器而异，已脱敏）
  - **SC7 降级方案** ✅ 通过：面板 `.floating` level；宠物底部 AppKit_y=<petBottom>、面板顶部=<panelTop>，gap=2 紧贴下方不重叠。（坐标因机器而异，已脱敏）
- 无需 TCC 的纯函数测试：selectPet 11/11 PASS（含 Mascot 优先/回退/不误绑）、Geometry 4/4 PASS。
- 未解决风险：
  1. ad-hoc 签名无 team ID，TCC 按 CDHash 认证 → 每次重签屏幕录制授权失效，需重新授权；生产应用稳定签名/notarized 构建。
  2. 屏幕录制权限是硬前提：无授权 `CGWindowListCopyWindowInfo` 返回空。
  3. 识别依赖 title 含 "Mascot"；若 Codex 改名需更新规则（已留 R4.2 高 layer / R4.3 petShaped 回退）。
  4. SC5 宠物隐藏 / Codex 退出未真实触发，仅逻辑验证，待用户配合。
  5. `unionCandidates` 每 tick 双 `CGWindowList` 调用，功能正确、性能可优化（P1）。
  6. 跨应用窗口相对 z-order 不可控（SC7 降级）：仅 `.floating` level + 几何不重叠兜底。

## 诊断依据

见 `pet-window-detection.md`（基于真实窗口枚举结果提炼）。
