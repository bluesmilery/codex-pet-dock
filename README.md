# Codex Pet Dock

> macOS 桌面伴侣：在 Codex（ChatGPT 桌面应用，bundle id `com.openai.codex`）的桌面宠物下方，
> 悬浮一个透明「底座」，显示本周剩余额度（WEEK LEFT）与本周 Token 用量（WEEK TOKENS）；
> 点击展开详情卡。自动跟随宠物移动、隐藏与重现重捕，支持主题、状态栏菜单、登录自启。

## 功能

- **透明底座**：紧贴 Codex 桌面宠物下方，显示 `WEEK LEFT` / `WEEK TOKENS`；缺失数据占位 `—`。
- **详情卡**：点击底座展开/关闭，含套餐、重置时间、缓存比例、输入、输出、会话数、更新时间、本机估算提示。
- **自适应跟随**：宠物静止时低频且不重复 `setFrame`，移动时升频，稳定后降频；宠物隐藏/退出时底座与详情同步隐藏，重现后重捕。
- **真实数据**：
  - `WEEK LEFT`：经 `codex app-server` JSON-RPC 读取官方周额度（`primary` 周窗口）。
  - `WEEK TOKENS`：解析 `~/.codex/sessions` 本机会话日志的 token 增量求和。
- **主题**：3 款内置（Holographic / Warm Gold / Circuit）+ 外部 JSON 主题热加载（安全白名单解析）。
- **状态栏菜单**：主题选择、显示/隐藏底座、登录时启动、退出。
- **登录自启**：`SMAppService.mainApp`（macOS 13+），失败可解释、不崩溃。

## 隐私边界（硬约束）

- **不修改** Codex / ChatGPT.app。
- **不读取** `auth.json`、认证 token、邮箱、Chrome Profile。
- **不读取 / 记录 / 输出** 会话正文；`WEEK TOKENS` 仅提取 `timestamp` + `last_token_usage.total_tokens` 两个数值。
- `WEEK LEFT` 的鉴权由 `codex` 进程在其可信环境完成；本进程仅经 stdio 收发 JSON-RPC 文本，只解析 `usedPercent`/`resetsAt`/`windowDurationMins`/`planType`，不碰凭证。
- **不使用** 私有 CGS API；窗口枚举仅用公开 `CGWindowListCopyWindowInfo`。

## 构建

```sh
make build        # swift build -c release
make app          # 组装并 ad-hoc 签名 build/PetDock.app
make test         # UI + 数据 + Shell 全量测试
```

## 分发

最终包：`dist/CodexPetDock-1.0.0-macOS-arm64.zip`（SHA256 `<hash>…`，ad-hoc 签名、未 notarized；用 `ditto` 打包，未改签名）。

## 运行

```sh
make run          # 启动，日志写入 /tmp/petdock.log
make diagnose     # 一次性识别诊断，写入 /tmp/petdock-diagnose.txt
pkill -f PetDock  # 停止
```

## 屏幕录制权限（硬前提）

`CGWindowListCopyWindowInfo` 是唯一公开的跨应用窗口枚举 API；macOS 在**无屏幕录制权限**时
（`CGPreflightScreenCaptureAccess() == false`）会过滤为空列表。首次运行 `PetDock.app` 会触发
系统授权请求；在「系统设置 › 隐私与安全性 › 屏幕录制」允许 **PetDock** 后，退出并重启 app 生效。

> 注：ad-hoc 签名无 team ID，TCC 按 CDHash 认证；每次重新 `codesign`（`make app`）会改变
> CDHash，授权会失效需重新授予。生产建议改用稳定开发者签名 / notarized 构建。

## 状态栏菜单

菜单栏爪印（pawprint）图标：**主题**（子菜单，当前打勾）/ **显示·隐藏底座** / **登录时启动**（打勾）/ **退出 PetDock**（⌘Q）。

## 主题

- 内置：Holographic / Warm Gold / Circuit（共享同一几何槽位 200×48，只换皮不改布局）。
- 外部：`~/Library/Application Support/PetDock/themes/*.json`，文件变化自动热加载。
- 安全：颜色仅接受 `[r,g,b,a]`∈[0,1] 数值；字体仅白名单 token（`system`/`rounded`/`monospace`）；
  拒绝 URL / 路径 / 脚本 / 嵌套对象 / 危险关键字（详见 `Sources/PetDock/Theme.swift`）。

## 登录自启

经 `SMAppService.mainApp` 注册。命令行裸跑（非 `.app`）时不可用（`notFound`），属预期；
需作为 `PetDock.app` 运行。注册后可能需在「系统设置 › 通用 › 登录项」批准。

## 数据口径

| 指标 | 来源 | 字段 |
| --- | --- | --- |
| WEEK LEFT | `codex app-server` JSON-RPC `account/rateLimits/read` | `primary.usedPercent` / `resetsAt` / `windowDurationMins`(=10080 周) / `planType` |
| WEEK TOKENS | `~/.codex/sessions/**/*.jsonl` | Σ `payload.info.last_token_usage.total_tokens`（单次增量） |

刷新退避（各源独立）：成功 5min / 失败 1×15min / 2×30min / ≥3×60min。宠物不可见时暂停刷新。
详见 `docs/data-layer.md`。

## 测试

```sh
make test-ui      # selectPet 识别 + Geometry 坐标 + Follower 状态机（纯函数）
make test-data    # 数据层（周窗口聚合 / 增量缓存 / 退避 / pause，fixture，不联网）
make test-shell   # Theme / Settings / ThemeStore / AutoStart 纯函数
make test         # 全量
```

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `Sources/PetDock/PetTracker.swift` | bundle id 定位 + Quartz 枚举 + 宠物识别（Mascot 优先） |
| `Sources/PetDock/Geometry.swift` | Quartz ↔ AppKit 坐标转换（多屏/负坐标） |
| `Sources/PetDock/Follower.swift` | 自适应跟随状态机（纯函数 `decide`） |
| `Sources/PetDock/DockPanel.swift` / `DockView.swift` | 透明底座 NSPanel + 视图 |
| `Sources/PetDock/DetailPanel.swift` | 详情卡 |
| `Sources/PetDock/Data/` | 数据层（RateLimitClient / TokenUsageLogReader / PetDockDataService） |
| `Sources/PetDock/Theme.swift` | 主题（内置 + 外部安全解析 + 热加载） |
| `Sources/PetDock/StatusBar.swift` | 状态栏菜单 |
| `Sources/PetDock/AutoStart.swift` | 登录自启（SMAppService） |
| `Sources/PetDock/Settings.swift` | UserDefaults 偏好 |
| `Sources/PetDock/main.swift` | 入口：`--diagnose` 诊断模式 / 运行模式（跟随 + 数据 + 外壳） |

## 宠物识别（摘要）

归属过滤 → 排除主窗口（layer0 + 大尺寸）→ 滞回 → **title 含 "Mascot" 优先（吉祥物本体）** → 高 layer → 宠物尺寸；
排除 Voice Controls Backing / Composition Surface 等辅助窗。详见 `docs/pet-window-detection.md`。
