# Codex Pet Dock

[English](README.md) | 简体中文

> 一款 macOS 桌面伴侣：在 Codex 桌面宠物的正下方悬浮一个透明 HUD，一眼看到本周剩余额度与本周 Token 用量。

**Codex Pet Dock** 是一款 macOS 桌面伴侣：在 Codex 桌面应用（`/Applications/ChatGPT.app`，bundle id `com.openai.codex`）的桌面宠物正下方，悬浮一个透明「底座」，实时显示**本周剩余额度（WEEK LEFT）**与**本周 Token 用量（WEEK TOKENS）**；点击底座可展开详情卡。它会自动跟随宠物移动、在宠物隐藏时同步隐藏并在重现后重新捕获，并提供主题切换、状态栏菜单与登录自启。

所有窗口枚举与数据读取均使用**公开 API**，不修改 Codex、不读取凭证、不读取会话正文。

---

## 📌 来源与致谢

本项目的灵感来自一篇[原始微信公众号文章](https://mp.weixin.qq.com/s/W4kC9enEmvJm2swhM5fbUw)。该文章作者随后发布了 **Windows** 平台的实现 [hjxccc/codex-pet-dock](https://github.com/hjxccc/codex-pet-dock)，是这一概念的原始跨平台参考。

本仓库是一个独立的 **macOS** 实现：目标平台不同（macOS / Apple Silicon 与 Windows）、技术栈不同（原生 Swift/AppKit 与公开 macOS API，而非 Windows 工具链），系独立开发，并非 Windows 项目的移植，但共享同一灵感来源。感谢原作者带来的启发。（文章标题、作者与内容均归原作者所有，本文不作转述。）

---

## ✨ 功能亮点

- **透明底座 HUD**：紧贴宠物下方、不重叠，显示 `WEEK LEFT`（含本周期到期时间）与 `WEEK TOKENS`；数据缺失时以 `—` 占位。
- **详情卡**：点击底座展开 / 关闭，列出套餐、重置时间、缓存比例、输入、输出、会话数、更新时间，以及本机估算说明。
- **自适应跟随**：宠物移动时以约 60 Hz 跟随并定位，静止时在 0.1 秒内探测到重新移动，随后自动降频且不重复刷新位置；宠物隐藏或 Codex 退出时底座与详情同步隐藏，重现后重新捕获。
- **会话气泡避让**：当 Codex 会话气泡出现在宠物下方时，底座自动下移避开重叠。使用 `ScreenCaptureKit`（macOS 14+）检测气泡是否实际绘制内容（仅 alpha 像素统计——不 OCR、不保存图像、不记录颜色或文字）；成功识别收起态后会立即唤醒布局，即使宠物未移动也让底座回到正下方。macOS 13、屏幕录制 preflight 尚未生效或捕获失败时保守避让；preflight 不可用期间跳过后台捕获。宠物靠近屏幕边缘时，底座水平 clamp 到屏内（像消息条一样贴边展示）。
- **真实数据，严格隐私**：
  - `WEEK LEFT`：经 `codex app-server` 的 JSON-RPC 读取官方周额度（`primary` 周窗口）。
  - `WEEK TOKENS`：聚合 `~/.codex/sessions` 本机会话日志的 token 增量。
- **主题**：内置 3 款程序化主题，并支持从 Application Support 加载外部 JSON 主题（带安全白名单解析、文件变化自动热加载）。
- **状态栏菜单**：主题选择、显示 / 隐藏底座、登录时启动、退出。
- **登录自启**：基于公开 `SMAppService`（macOS 13+），失败时可解释、不崩溃。

---

## 🖼️ 效果与界面

<!-- 截图占位：建议在此处放置「底座贴在宠物下方」与「点击展开详情卡」的截图。
     本仓库暂不包含真实截图；如贡献截图，请确保画面不含真实额度、账号或任何敏感信息。 -->

底座与详情卡均为原生 AppKit（`NSPanel` + `NSStackView` + `NSTextField`）绘制：

- **底座**（约 200×48，半透明圆角）：
  - 左列：`WEEK LEFT` 标题 + 剩余百分比 + 本周期到期时间（`MM-dd HH:mm`，本机时区）。
  - 右列：`WEEK TOKENS` 标题 + 本周累计 token。
  - 点击底座切换详情卡。
- **详情卡**（约 230×190）：套餐 / 重置时间 / 缓存比例 / 输入 / 输出 / 会话数 / 更新时间，底部附「本机估算」说明。
- **状态栏**：菜单栏的爪印（pawprint）图标，下拉菜单见「主题与设置」。

---

## 📋 系统要求

- **macOS 13（Ventura）或更高**（`SMAppService`、现代 AppKit 需要）。
- **Apple Silicon（arm64）**：发布包按 arm64 构建。
- **Swift 5.9+ 工具链**（从源码构建时）。
- **Codex 桌面应用**（`ChatGPT.app`）已安装，且已登录（`WEEK LEFT` 依赖 codex 已完成自身鉴权）。
- **屏幕录制权限**：跨应用窗口枚举的硬前提，详见「隐私与权限」。

---

## 🔒 隐私与权限

本项目遵循严格的隐私边界（已由 fixture 测试固化）：

- **不修改** Codex / `ChatGPT.app`。
- **不读取** `auth.json`、认证 token、邮箱、Chrome Profile。
- **不读取 / 记录 / 输出会话正文**。`WEEK TOKENS` 仅从日志中提取 `timestamp` 与 `last_token_usage` 的若干数值字段。
- **不外发数据**：所有计算与缓存均在本地完成。
- **不使用私有 API**：窗口枚举仅用公开的 `CGWindowListCopyWindowInfo`，不调用私有 CGS 接口。
- `WEEK LEFT` 的鉴权由 `codex` 进程在其自身可信环境内完成；本进程仅经 stdio 收发 JSON-RPC 文本，只解析 `usedPercent` / `resetsAt` / `windowDurationMins` / `planType`，不接触任何凭证。

**屏幕录制权限（TCC）**：`CGWindowListCopyWindowInfo` 是唯一公开的跨应用窗口枚举 API；macOS 在未授权时会将其过滤为空列表。`PetDock.app` 每个进程至多主动请求一次权限；preflight 不可用期间不进入后台 `ScreenCaptureKit` 捕获，避免反复提示，同时保留气泡保守避让与状态栏提醒。请在「系统设置 › 隐私与安全性 › 屏幕录制」中允许 **PetDock**，然后退出并重启 app 使权限生效。

> ⚠️ ad-hoc 签名没有 team ID，TCC 按 ad-hoc 签名的代码目录哈希认证；每次重新签名（如重新执行 `make app`）都会改变该哈希值，使授权失效而需要重新授予。生产环境建议改用稳定开发者签名或 notarized 构建。

---

## 📦 构建、运行与分发

在仓库根目录执行：

```sh
make build        # swift build -c release，产出 .build/release/PetDock
make app          # 组装 build/PetDock.app 并 ad-hoc 签名（Identifier=io.github.bluesmilery.codexpetdock）
make run          # 构建 app、启动（日志写入 Application Support/PetDock/Logs 私有目录）
make diagnose     # 构建并跑一次脱敏诊断（写入 Diagnostics/diagnose.txt 私有文件）
pkill -f PetDock  # 停止运行
make clean        # 清理构建产物
make clean-logs   # 清理 Application Support/PetDock 私有运行 / 诊断日志
```

`make app` 写入的 `build/PetDock.app` 是可覆盖的 staging。交付开发构建时，应归档一份全新、不可变且绑定提交的本地候选，并让面向用户的测试步骤指向该归档 app；详见[开发候选产物归档流程](docs/verification/dev-candidate.md#开发候选产物归档)。

诊断模式（`--diagnose`）会枚举窗口、定位 Codex 宠物，并仅将数量/层级/可见性等脱敏结构写入 `~/Library/Application Support/PetDock/Diagnostics/diagnose.txt`，用于排查「识别不到宠物」类问题；默认不落盘标题、owner、真实 WID/PID 或精确坐标。若该文件未生成，通常意味着屏幕录制权限尚未授予。

日志、诊断与 token 缓存统一位于 `~/Library/Application Support/PetDock/` 私有目录（目录 0700、文件 0600），日志拒绝 symlink 重定向。Codex helper 仅接收最小白名单环境，不继承 API key、cookie、代理凭证或未知变量；依赖环境变量认证的用户请改用 Codex 自身登录态。

**分发**：当前发布包为 ad-hoc 签名（无 team ID）、未 notarized 的 arm64 预编译包。具体校验值与下载方式以发布说明为准。

**预览安装**（非一键可信安装）：

1. 下载 `CodexPetDock-0.1.0-macOS-arm64.zip` 并解压。
2. 将 `PetDock.app` 移至 `/Applications`（或任意固定位置）。
3. 因应用为 ad-hoc 签名（无 Developer ID、未公证），macOS Gatekeeper 可能拦截首次启动。前往**系统设置 › 隐私与安全性**，点击**仍要打开**（或在 Gatekeeper 对话框中选"打开"）。详见 [Apple 官方指南](https://support.apple.com/guide/mac-help/mh40616/mac)。
4. 首次启动后，授予**屏幕录制**权限（跨应用窗口枚举所需），然后重启应用。
5. 确保本机已安装并登录 `codex` CLI（`@openai/codex`）——`WEEK LEFT` 依赖其可用。

---

## 📊 数据来源与口径

仅承载两项数据，均已在 `docs/architecture/data-layer.md` 中记录字段与口径。下表示例值为说明用占位，非任何真实账户数据。

| 指标 | 来源 | 解析字段 | 显示示例（占位） |
| --- | --- | --- | --- |
| `WEEK LEFT` | `codex app-server` JSON-RPC：`account/rateLimits/read` | `primary.usedPercent` / `resetsAt` / `windowDurationMins`（10080 = 7 天 = 周窗口）/ `planType` | `73%` |
| `WEEK TOKENS` | `~/.codex/sessions/**/*.jsonl`（按日期分桶的会话日志） | Σ `payload.info.last_token_usage.total_tokens`（单次增量，已验证跨会话求和不重复） + 输入 / 缓存 / 输出分项 | `~1M` |

**刷新退避**（`WEEK LEFT` 与 `WEEK TOKENS` 各自独立计数）：

| 连续失败次数 | 下次刷新间隔 |
| --- | --- |
| 0（成功） | 5 分钟 |
| 1 | 15 分钟 |
| 2 | 30 分钟 |
| ≥ 3 | 60 分钟 |

宠物不可见时，数据刷新会自动暂停，可见后恢复。

---

## 🎨 主题与设置

**内置主题**：Holographic / Warm Gold / Circuit，共享同一几何槽位（约 200×48），切换只改变颜色、圆角、边框与字体，不改变布局。

**外部主题**：将 JSON 文件放入 `~/Library/Application Support/PetDock/themes/`，文件变化会自动热加载。最小示例（字段均可省略到仅含名称与三种颜色）：

```json
{
  "name": "My Theme",
  "background": [0.10, 0.18, 0.28, 0.60],
  "accent":     [0.90, 0.80, 0.70, 1.00],
  "label":      [1.00, 1.00, 1.00, 1.00],
  "cornerRadius": 10,
  "borderWidth": 1,
  "font": "rounded",
  "badge": "logo.png"
}
```

**安全白名单**（见 `Sources/PetDock/Theme.swift`）：颜色仅接受 `[r,g,b,a]` 且每个分量 ∈ [0,1]；字体仅接受 `system` / `rounded` / `monospace`；徽标仅接受同目录下的纯文件名 `*.png`。解析器会拒绝 URL、路径分隔符、脚本 / CSS / JS 片段、嵌套对象与危险关键字。

**状态栏菜单**：菜单栏爪印图标 → **主题**（子菜单，当前项打勾）/ **显示 / 隐藏底座** / **登录时启动**（打勾，按 `SMAppService` 真实状态）/ **退出 PetDock**（⌘Q）。

**持久化偏好**（`UserDefaults`）：选中的主题、底座可见性等。登录自启的真实状态以系统登录项为准，不单独缓存，避免双源不一致。

---

## 📚 文档目录

请从[文档目录](docs/README.md)进入架构事实、开发流程和候选验收证据。`.trellis/spec/macos/` 保存可执行的开发规则，`.trellis/tasks/` 保存单次任务的需求与证据。行为、接口、数据边界、验证状态或开发门禁变化时，在任务和 Review 中记录 `Docs Impact: none | update | new`，并在同一提交更新对应事实源。

## 🧪 测试

全部为纯函数 / fixture 测试，用 `swiftc` 编译真实源码后运行，**不依赖屏幕录制权限、不联网**：

```sh
make test-ui      # 宠物识别 + 坐标转换 + 跟随状态机 + 气泡可见性 + 障碍避让（气泡 + 控制按钮）+ 边缘 clamp + 日志轮转 + FollowTickPlanner
make test-data    # 数据层：周窗口聚合 / 增量缓存 / 退避 / 暂停 / 脱敏 / codex 路径解析 / rpc stdio 端到端
make test-shell   # 主题安全解析 / 设置持久化 / 热加载 / 自启状态映射 / StatusBar TCC 提示
make test-privacy # 运行时路径 containment / 私有存储 / helper 环境 / cache 隐私 fixture
make docs-check   # 离线检查公开 Markdown 链接 / 目录 / 旧路径 / 隐私门禁
make test-docs    # 文档检查器单元测试
make test         # 全量（docs gate + privacy + Swift UI/data/shell fixture）
```

验证准则与候选证据记录在 [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md)；实际当前计数以测试源码和最新命令输出为准。气泡可见性覆盖范围见 [`docs/architecture/dock-obstacle-avoidance.md`](docs/architecture/dock-obstacle-avoidance.md)，具体用例以 `tests/main.swift` 为准。

隐私边界由 fixture 测试固化：数据层结果不包含会话正文诱饵、不包含凭证。详见 `docs/architecture/data-layer.md` 与 `tests/`。

---

## ⚠️ 已知限制

- **ad-hoc 签名 TCC 不稳定**：每次重新签名会改变代码目录哈希，导致屏幕录制授权失效，需重新授予。
- **屏幕录制权限是硬前提**：未授权时无法枚举到 Codex 窗口，底座不会出现。
- **`codex app-server` 为 experimental**：协议字段可能随 codex 版本变化；已做稳定子集解析与缺失字段降级。
- **跨应用窗口相对 z-order 不可控**：以 `.floating` 层级 + 几何不重叠的方式降级处理。
- **平台范围有限**：当前仅适配 Apple Silicon 上的 macOS 13+，且仅针对 Codex 桌面宠物。
- **登录自启需作为 `.app` 运行**：命令行裸跑（非 `.app` bundle）时 `SMAppService` 不可用，属预期。
- **部分交互待真机验证**：UI 自动化受系统 Accessibility 限制，部分手工交互项尚未在真机逐项验证（见 `docs/verification/dev-candidate.md`）。

---

## 🤝 贡献

欢迎通过 issue 与 pull request 反馈问题与改进。提交前请确保：

1. `make test`（docs gate + Swift 测试套件）通过；
2. 不引入读取凭证、会话正文或调用私有 API 的代码；
3. 记录 `Docs Impact: none | update | new`，文档变更时同步目录；
4. 提交信息遵循约定式提交（Conventional Commits）风格。

项目结构与关键文件见下表：

| 文件 | 作用 |
| --- | --- |
| `Sources/PetDock/main.swift` | 入口：`--diagnose` 诊断模式 / 运行模式（跟随 + 数据 + 外壳） |
| `Sources/PetDock/PetTracker.swift` | bundle id 定位 + Quartz 枚举 + 宠物识别（Mascot 优先） |
| `Sources/PetDock/Geometry.swift` | Quartz ↔ AppKit 坐标转换（多屏 / 负坐标） |
| `Sources/PetDock/Follower.swift` | 自适应跟随状态机（纯函数 `decide`） |
| `Sources/PetDock/DockPanel.swift` / `DockView.swift` | 透明底座 `NSPanel` + 视图 |
| `Sources/PetDock/DetailPanel.swift` | 详情卡 |
| `Sources/PetDock/Data/` | 数据层（额度客户端 / 日志读取 / 服务） |
| `Sources/PetDock/Theme.swift` | 主题：内置 + 外部安全解析 + 热加载 |
| `Sources/PetDock/StatusBar.swift` | 状态栏菜单 |
| `Sources/PetDock/AutoStart.swift` | 登录自启（`SMAppService`） |
| `Sources/PetDock/Settings.swift` | `UserDefaults` 偏好 |

更多设计依据见 [`docs/architecture/pet-window-detection.md`](docs/architecture/pet-window-detection.md)、[`docs/architecture/data-layer.md`](docs/architecture/data-layer.md)、[`docs/architecture/dock-obstacle-avoidance.md`](docs/architecture/dock-obstacle-avoidance.md) 与 [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md)。

---

## 🛠️ 开发流程（Development workflow）

- `main` 是发布到 GitHub 的**唯一稳定分支**；任何提交进入 `main` 前必须**人工确认**。
- `dev` 为本地集成分支，用于合并各 feature 分支并跑通 `make test`。
- 新功能在从 `dev` 派生的 `feature/*` 分支上开发，完成后合并回 `dev`。
- `dev` → `main` 的合并，以及 `main` 推送到 GitHub，均需**人工确认**后执行，绝不自动推送。
- **禁止**使用 `git push --all`，以免误推本地或临时分支到远端。
- 不在本文虚构远端地址或 CI；所有变更以本地 `swift build -c release` 与 `make test`（docs gate + Swift 测试套件）验证为准；当前测试数量见 [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md)。

---

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源，Copyright (c) 2026 bluesmilery。MIT 许可授予使用、复制、修改、合并、发布、分发、再授权与销售本软件的权利；完整条款见根目录 [`LICENSE`](LICENSE) 文件。

### 非官方声明

- 本项目为**非官方**的社区项目，与 OpenAI 无任何隶属关系，也未获得 OpenAI 或任何第三方的背书或赞助。
- **OpenAI**、**Codex**、**ChatGPT** 等名称与商标归其各自权利人所有；本项目仅作兼容性适配，不主张对任何第三方商标的权利。
- MIT 许可证**仅授予本项目代码的版权相关权利，不授予任何第三方商标权**。
