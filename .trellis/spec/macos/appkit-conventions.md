# AppKit Conventions

> NSPanel / 坐标系 / 主线程约束。违反这些是本项目历史 bug 的主要来源。

---

## 坐标系（Quartz vs AppKit）

本项目同时使用两套全局坐标系，**混用是高频 bug 源**：

- **Quartz 全局坐标**（CGWindowList / `kCGWindowBounds`）：主屏**左上**原点，y 向下，副屏可负。
- **AppKit 全局坐标**（`NSScreen.frame` / `NSWindow.setFrame`）：主屏**左下**原点，y 向上。

转换公式（见 `Geometry.appKitRectFromQuartz`）：
```
appKitOriginY = mainScreenHeight - quartzOriginY - height
```

- **水平轴共享**：两系 x 同轴，`visibleFrame.minX/maxX` 可直接用于 Quartz x 的 clamp。
- **垂直轴相反**：避让后的 Quartz rect 比对 `visibleFrame.minY/maxY` 前**必须**经 `appKitRectFromQuartz` 转换。
  直接用 Quartz `dy` 比 AppKit `v.minY/maxY` 在副屏负坐标下会判断错误。

修改 `Geometry.safeDockFrame` / `DetailPanel.placeBelow` 前**必读**其坐标系注释。

## NSPanel / 主线程

- 所有 UI 操作（setFrame / orderOut / addSubview）在**主线程**。后台 Task 完成后 `DispatchQueue.main.async` 切回。
- `NSPanel` 用 `.nonactivatingPanel` + `.hudWindow` 行为，`collectionBehavior` 含 `.fullScreenAuxiliary`（不被全屏遮挡）。
- `setFrame` 会做像素对齐：断言位置容差用 `< 1.0` 而非 `< 0.01`（如 836.5 → 836.0）。

## 并发

- `PetDockDataService` 单 serial queue + `refreshInFlight` 合并（`maxConcurrent == 1`）。
- completion 回调经 main 派发；测试用 `waitPumpingMain`（pump RunLoop）避免主线程死锁，**勿用** `XCTestExpectation`。
- `BubbleVisibilityProbe` 用 `OSAllocatedUnfairLock` + generation 校验保证 single-flight。
- `LineReader` 用 `readabilityHandler`（GCD）替代阻塞 `availableData`，`stop()` 有限时间返回不挂起。

## 显示节拍与调度源存活性

- 有最大启动间隔契约的 tick 必须从本次 tick 的单调开始时间计算下一 deadline；外部 wake 会重置相位，不能继续沿用旧 stable phase。下一次 tick 应在 `max(deadline, workCompletedAt)` 前启动；若串行主线程工作已经跨过 deadline，只保留一个在工作完成后立即执行的 latest-only tick，不补发历史帧，也不再额外等待一个完整 interval。启动间隔验收须区分调度器新增等待、当前串行工作时间与异步 single-flight 在途时间。
- 测试必须覆盖 `wake phase × tick work duration`：相位起点、off-grid wake、工作跨 deadline、工作超过一个或多个 interval；只测 interval 常量或 phase-aligned 情况不构成 cadence 证明。
- `NSWindow.isVisible` 不代表窗口属于某个 display，也不保证 window-bound display link 仍会回调。display-link eligibility 必须检查 `window.screen != nil`，并由 window-screen / screen-parameters 变化通知或等价恢复源触发重新评估。
- display-link 生命周期测试必须覆盖 active → no-screen fallback → screen restored，而不仅是创建失败时的 Timer fallback；任一 source 停止发 beat 后仍须存在可证明的恢复路径。
