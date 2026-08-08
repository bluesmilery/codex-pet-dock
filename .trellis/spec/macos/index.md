# macOS / Swift / AppKit Development Guidelines

> 本项目（codex-pet-dock）是 **Swift / AppKit / macOS 单体桌面工具**，
> 非 web / 非 backend。本目录替代 Trellis 默认的 web backend/frontend spec。

---

## Overview

- 单体 macOS 应用（`io.github.bluesmilery.codexpetdock`），无 submodule、无前端。
- 构建：`swift build -c release`（SwiftPM），测试：`make test`（swiftc 独立入口，非 SwiftPM）。
- 目标 macOS 13+（ScreenCaptureKit 像素捕获 macOS 14+，缺失时保守降级）。
- **无后端、无数据库、无网络服务**：数据经 codex app-server stdio JSON-RPC + 本机日志文件读取。

## Guidelines Index

| Guide | Description |
|-------|-------------|
| [Directory Structure](./directory-structure.md) | Sources/PetDock 模块组织 |
| [AppKit Conventions](./appkit-conventions.md) | NSPanel/AppKit 坐标系/主线程约束 |
| [Quality Guidelines](./quality-guidelines.md) | 0 warning / TDD / 真机 QA |
| [Privacy Guidelines](./privacy-guidelines.md) | TCC / 隐私脱敏边界 |

---

**Language**: spec 文档可用中文（与项目 AGENTS.md 一致），代码注释随代码。
