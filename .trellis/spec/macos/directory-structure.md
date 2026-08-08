# Directory Structure

> Sources/PetDock 单模块组织，无子 package。

---

## Layout

```
Sources/PetDock/
├── main.swift                 # AppDelegate 入口 + tick 编排 + --diagnose
├── PetTracker.swift           # CGWindowList 枚举 + PID 缓存 + selectPet
├── Geometry.swift             # Quartz↔AppKit 坐标转换 + safeDockFrame
├── Follower.swift             # hidden/moving/stable 状态机 + 自适应频率
├── BubbleVisibility.swift     # ScreenCaptureKit 像素 alpha 可见性探测
├── PetLogger.swift            # #if DEBUG 门控 + 后台异步日志
├── DockModel.swift            # DockSnapshot 数据模型 + formatTokens
├── DockPanel.swift / DockView.swift / DetailPanel.swift   # NSPanel UI
├── Theme.swift / Settings.swift / ThemeStore.swift / StatusBar.swift / AutoStart.swift  # 产品外壳
└── Data/
    ├── RateLimitClient.swift      # codex app-server JSON-RPC + LineReader
    ├── TokenUsageLogReader.swift  # ~/.codex/sessions 日志增量解析
    ├── LiveDockProvider.swift     # 主线程缓存 + 异步 refresh
    ├── PetDockDataService.swift   # 单 serial queue 并发模型
    ├── CodexExecutableResolver.swift
    └── Backoff.swift

tests/
├── main.swift          # test-ui 入口（selectPet/Geometry/Follower/BubbleVisibility）
├── DataTests.swift     # test-data 入口（@main，纯函数+fixture）
└── shell/main.swift    # test-shell 入口（Theme/Settings/Store/AutoStart/StatusBar）
```

## Rules

- **文件边界严格**：只改分配范围内的文件。新功能优先放进语义最贴合的现有文件，不新建文件除非有清晰职责。
- **测试独立入口**：`tests/` 下三个 main.swift 各自 swiftc 编译，不依赖 SwiftPM test target。新测试加到对应入口。
- **fixture**：`tests/fixtures/sessions/` 是脱敏的会话日志样本，不含真实 token / 正文。
