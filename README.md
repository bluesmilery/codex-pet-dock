# Codex Pet Dock — P0 技术验证

> 范围严格限定为 P0：最小可运行的 Swift/AppKit macOS 程序，用**公开 API**（Quartz / AppKit）
> 定位 `com.openai.codex`（即 `/Applications/ChatGPT.app`）进程、识别其桌面宠物窗口、
> 用透明 NSPanel 作为底座跟随宠物移动，并验证隐藏 / 退出 / 重捕与多显示器 / 负坐标转换。
>
> **不包含** P1 内容（额度读取、Token 统计、主题、登录自启、安装包、发布）。
> **不使用** 私有 CGS API，**不修改** Codex，**不读取** auth.json / 认证文件 / Chrome Profile。

## 构建

```sh
make build        # swift build -c release
make app          # 组装并 ad-hoc 签名 build/PetDock.app
```

## 运行

```sh
make run          # 启动底座，日志写入 /tmp/petdock.log
make diagnose     # 跑一次识别，结果写入 /tmp/petdock-diagnose.txt
pkill -f PetDock  # 停止
```

## 屏幕录制权限（P0 硬前提）

`CGWindowListCopyWindowInfo` 是唯一公开的跨应用窗口枚举 API；macOS 在**无屏幕录制权限**
时（`CGPreflightScreenCaptureAccess() == false`）会把它过滤为空列表。这与 Claude 的
`bypassPermissions`（工具权限）无关，是 macOS TCC 系统权限。

首次 `make run` / `make diagnose` 时，`PetDock.app` 调用窗口枚举会触发系统弹窗请求
「屏幕录制」授权；在「系统设置 › 隐私与安全性 › 屏幕录制」里允许 **PetDock** 后，
退出并重启 `PetDock.app` 即可枚举到 Codex 窗口。

授权前运行 `make diagnose`，输出里会显示 `preflight: false` 且候选窗口为 0 —— 这是预期表现，
**不视为验证失败**，而是权限前提的诊断证据。

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `Sources/PetDock/PetTracker.swift` | bundle id 定位 + Quartz 枚举 + 宠物识别规则（纯函数） |
| `Sources/PetDock/Geometry.swift` | Quartz(左上原点) ↔ AppKit(左下原点) 坐标转换，多屏/负坐标统一 |
| `Sources/PetDock/DockPanel.swift` | 透明 NSPanel，紧贴宠物下方、不重叠 |
| `Sources/PetDock/main.swift` | 入口：`--diagnose` 诊断模式 / 运行模式（0.5s 轮询跟随） |
| `docs/pet-window-detection.md` | 宠物识别依据（规则 + 实测回填） |
| `docs/success-criteria.md` | SC1–SC7 成功标准与验证记录 |
| `tools/diagnose.swift` | 复用的命令行诊断脚本（采集数据用） |

## 识别规则（摘要）

归属过滤 → 排除主窗口（layer0 + 大尺寸）→ 滞回沿用上次 → **title 含 "Mascot" 优先（吉祥物本体）** → 高 layer → 宠物尺寸范围；明确排除 Voice Controls Backing / Composition Surface 等辅助窗（实测：吉祥物本体 layer=2 低于其 layer=3 子窗口，单纯"高 layer 优先"会误选）。
详见 `docs/pet-window-detection.md`。
