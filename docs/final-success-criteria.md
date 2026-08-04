# Codex Pet Dock — 最终成功标准（Release Candidate）

> 候选版本：`PetDock.app` 1.0.0（build 2），分支 `public-history checkpoint`（base `main` 657a984）。
> 本文件记录构建 / 测试 / 代码评审结论，以及需真机验证的待办项。

## 构建（已验证）

- `make build`（`swift build -c release`）：`Build complete!`，退出码 0，无警告。
- 产物：`.build/release/PetDock`（arm64 Mach-O）。
- `.app` 组装（`make app`，ad-hoc 签名 `Identifier=io.github.bluesmilery.codexpetdock`）：**待主项目最终 make app**（见末尾流程）。

## 测试（已验证，全绿）

`make test` = test-ui + test-data + test-shell，**221 项全部通过，0 failed**。

| 套件 | 项数 | 覆盖 |
| --- | --- | --- |
| test-ui | 36 | selectPet 识别（Mascot 优先 / 不误绑主窗口 / 滞回 / petShaped / **合理回退排除 384x95·18x6 辅助**）+ Geometry 坐标（多屏 / 负坐标）+ Follower 状态机 + **Dock 几何/reset 显示/placeBelow 宽度回归** |
| test-data | 94 | Token 聚合Σ / 脱敏 / 分项、增量缓存、缓存淘汰、parseLine 鲁棒、WeekLeft 解析 / 窗口 / 重置 / cancel、退避表、pause 语义、service 端到端、LiveDockProvider 映射、并发安全、**codex 路径解析 12 项 + 子进程 PATH prepend 5 项 + resetsAt 格式化 MM-dd HH:mm / nil 占位** |
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
- `public-history checkpoint`（base 761a653）：`CodexExecutableResolver` 解析 codex 绝对路径（env 覆盖 > PATH > nvm/volta/brew），`RateLimitClient` 用 `executableURL` 直接启动，修复 .app（launchd 环境）找不到 nvm codex 致 WEEK LEFT 占位。
- `public-history checkpoint` 子进程 PATH（追加）：`RateLimitClient.childEnvironment` 把 codex 父目录 prepend 到子进程 `PATH`（去重、保留原 PATH），修复 codex 脚本 `#!/usr/bin/env node` 在子进程找不到同目录 node（nvm codex/node 同目录）致 app-server 立即退出。launchd 等价环境（`env -i HOME=<user> PATH=/usr/bin:/bin`）脱敏实测 `account/rateLimits/read` 成功。

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

Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.

### ✅ 已自动验证（公开 / 系统方式）
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
- **WEEK TOKENS**：解析 `~/.codex/sessions`（脱敏，仅数值聚合），近 7 天 sample/event 与 total 为非占位正值（具体数值因本机而异，已脱敏）。
Remove historical SHA, private ref, and internal worker/task provenance while preserving public intent.
- **重开 + 重捕**：`pkill` → `open`（新 pid），日志 `pet=true` 重捕（moving/setFrame=true），设置默认恢复，**未重签**。
Rewrite matched statement as a synthetic, number-free runtime verification statement.
Rewrite matched statement as a synthetic, number-free runtime verification statement.
Rewrite matched statement as a synthetic, number-free runtime verification statement.

Rewrite matched statement as a synthetic, number-free runtime verification statement.
- 点击底座开关详情卡（套餐 / 重置 / 缓存 / 输入 / 输出 / 会话 / 更新时间可见）。
- 三内置主题切换（即时换皮 / 勾选 / UserDefaults 持久化；当前 domain 未建 = 未操作）。
- 显示 / 隐藏菜单控制底座 + 详情。
- 登录自启 toggle（SMAppService，需 `.app` 菜单）。
- 底座坐标精测（tmux 无法自定义脚本枚举 PetDock 窗口坐标）。

## 分发包

Rewrite matched statement as a synthetic, number-free runtime verification statement.
- SHA256 / CDHash：构建特定指纹已删除（ad-hoc 签名每次 `make app` 都改变，公开固定值无意义且易误导）；最终分发时由发布流程重新生成。

## 已知风险（跨阶段）

0. **bundle id 变更（公开发布清理）**：应用自身 bundle id 由 `io.github.bluesmilery.codexpetdock` 改为
   `io.github.bluesmilery.codexpetdock`（目标 Codex 应用 `com.openai.codex` **不变**）。
   代码层 `AutoStart` 用 `SMAppService.mainApp`（系统按 app bundle id 注册，未硬编码），故无需改代码；影响：
   ① **TCC（屏幕录制）** 按 bundle id + 签名授权 → 新 id 需在「系统设置 › 隐私与安全性 › 屏幕录制」重新授予；
   ② **登录自启**（`SMAppService`）按 app bundle id 注册 → 新 id 需重新启用；
   ③ 旧 `io.github.bluesmilery.codexpetdock` 的 TCC 授权 / 登录项残留可在系统设置手动清理。
   本项目尚未选择开源许可证（未随附 LICENSE）；公开分发前需确定授权。
1. ad-hoc 签名 TCC 不稳定（每次重签 CDHash 变 → 屏幕录制授权失效）。
2. 屏幕录制权限是硬前提。
3. `codex app-server` 为 experimental，协议字段可能随版本变化（已做稳定子集 + 降级）。
4. 跨应用窗口相对 z-order 不可控（`.floating` level + 几何不重叠降级）。
5. **codex 路径解析（已修复）**：.app 由 launchd 启动时进程 PATH 无 nvm，`/bin/sh -lc`（非交互 shell
   不读 `~/.zshrc`）找不到 codex → WEEK LEFT 永久占位。已由 `CodexExecutableResolver`（文件系统查找：
   env 覆盖 > `PATH` > `~/.local/bin` / `~/.nvm/versions/node/*/bin` / `~/.volta/bin` /
   `/opt/homebrew/bin` / `/usr/local/bin`，nvm 多版本语义版本降序）+ `RateLimitClient`（`executableURL`
   直接启动，不经 `/bin/sh -lc`）修复。env 覆盖先展开 `~` 且必须为绝对路径（否则 `overrideNotAbsolute`），
   PATH 仅接受绝对目录（跳过空 / 相对），系统候选目录可注入（测试传空隔离）；解析器测试 12 项
   （env 优先 / 不可执行 / tilde 展开 / 相对拒绝、PATH 仅绝对 / 跳过空相对、nvm 多版本、缺失、不可执行、symlink）。
6. **WEEK LEFT 到期时间 + 窗口跟随几何（已修复）**：① 主底座 WEEK LEFT 单元显示本周期到期时间
   （`resetsAt`，MM-dd HH:mm 本机时区，nil 占位不崩，不改底座 200x48 外框）；② `DockPanel.placeBelow`
   底座宽度固定 `dockWidth(200)`、按 pet 中心对齐，不再被 `pet.width` 撑大（Mascot 消失误选 384x95 时旧
   `max(dockWidth,pet.width)` 把底座 200→384）；③ `selectPet` 回退用 `isReasonablePet`（petShaped + 最小边≥50
   + 非辅助 title），排除 384x95 / 18x6 / Voice Controls / Composition Surface，无合理候选则 nil 隐藏。
