# Codex Pet Dock — 最终成功标准（Release Candidate）

> 候选版本：`PetDock.app` 1.0.0（build 2），分支 `public-history checkpoint`（base `main` 657a984）。
> 本文件记录构建 / 测试 / 代码评审结论，以及需真机验证的待办项。

## 构建（已验证）

- `make build`（`swift build -c release`）：`Build complete!`，退出码 0，无警告。
- 产物：`.build/release/PetDock`（arm64 Mach-O）。
- `.app` 组装（`make app`，ad-hoc 签名 `Identifier=io.github.bluesmilery.codexpetdock`）：**待主项目最终 make app**（见末尾流程）。

## 测试（已验证，全绿）

`make test` = test-ui + test-data + test-shell，**191 项全部通过，0 failed**。

| 套件 | 项数 | 覆盖 |
| --- | --- | --- |
| test-ui | 26 | selectPet 识别 11（Mascot 优先 / 不误绑主窗口 / 滞回 / petShaped）+ Geometry 坐标 4（多屏 / 负坐标）+ Follower 状态机 11（静止 / 移动 / 稳定 / 隐藏 / 重捕 / 频率阶） |
| test-data | 74 | Token 聚合Σ / 脱敏 / 分项、增量缓存、缓存淘汰、parseLine 鲁棒、WeekLeft 解析 / 窗口 / 重置 / cancel、退避表、pause 语义、service 端到端、LiveDockProvider 映射、并发安全 |
| test-shell | 91 | Theme 内置 / 外部安全解析（颜色 / 字体 / 徽标 / 危险关键字）、Settings 持久化、ThemeStore fixture 热加载、AutoStart 状态映射 |

纯函数测试（不依赖屏幕录制权限 / 不联网），用 `swiftc` 编译真实源码运行。

## 代码评审结论（历次切片已合入 main）

Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.

隐私边界经 fixture 测试固化：结果不含会话正文诱饵、不读 auth / 凭证。

## 待真机验证（需最终 make app + 屏幕录制授权后）

以下项已通过编译 + 纯函数测试，但**未在真机运行**（受「不 make app / 不 codesign」约束，
避免反复触发 TCC 重授权）。最终 `make app` + 授权后逐项验证：

1. **UI 渲染**：底座透明圆角 + WEEK LEFT / TOKENS 文本；详情卡字段布局。
2. **点击交互**：点击底座展开 / 关闭详情卡。
3. **跟随**：宠物移动时底座紧贴下方移动；多屏 / 负坐标下位置正确。
4. **隐藏 / 重捕**：宠物隐藏或 Codex 退出时底座 + 详情隐藏；重现后重捕跟随。
5. **主题切换**：状态栏菜单切换 3 内置主题即时换皮；外部 JSON 主题热加载。
6. **状态栏菜单**：主题子菜单勾选、显示 / 隐藏底座、退出。
7. **登录自启**：作为 `.app` 注册 `SMAppService`，重启后自启（或系统设置登录项可见）。
8. **真实数据**：WEEK LEFT（codex app-server，需 codex 已登录）/ WEEK TOKENS（`~/.codex/sessions` 聚合）刷新与退避。
9. **性能**：Follower 自适应频率（移动升频 / 静止降频）实际体感。

## 已知风险（跨阶段）

1. ad-hoc 签名 TCC 不稳定（每次重签 CDHash 变 → 屏幕录制授权失效）。
2. 屏幕录制权限是硬前提。
3. `codex app-server` 为 experimental，协议字段可能随版本变化（已做稳定子集 + 降级）。
4. 跨应用窗口相对 z-order 不可控（`.floating` level + 几何不重叠降级）。
