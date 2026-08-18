# Design

## Boundaries

改动限定在 app 启动权限策略、气泡可见性探测/回调、跟随时序、对应 UI 测试及 README。几何识别阈值、窗口候选规则、数据层和主题层保持不变。

## Permission flow

1. 启动时通过一个可测试的进程内策略决定是否调用 `CGRequestScreenCaptureAccess()`；preflight 已通过或本进程已经请求过时不再请求。
2. `BubbleVisibilityProbe` 注入 `canCapture` 能力检查。每次先同步刷新 `knownWids`，再决定是否启动异步捕获。
3. `canCapture=false` 时不进入 ScreenCaptureKit capturer，并让当前候选按保守 `.visible` 读取；这阻断后台 2 Hz 的系统请求源，同时不制造气泡重叠。
4. preflight 后续变为 true 时，下一次 probe 可自然恢复捕获，无持久化权限副本。

## Bubble visibility to layout flow

`probe` 完成 generation 校验并写入新 cache 后，只有结果实际变化才发出一次可注入通知。运行时通知切回主线程并立即安排一次 follow tick；该 tick 重新枚举当前窗口、计算唯一障碍集并调用 `safeDockFrame`。通知只加速已有布局路径，不直接跨线程操作 AppKit。

空候选、reset 和旧 generation 结果不发送可见性更新；single-flight 及 identity/generation 语义保持不变。

## Follow timing

保留 `hidden / moving / stable` 状态机，只调整两个常量：

- moving：约 1/60 秒；
- stable：不高于 0.1 秒。

连续稳定达到既有阈值后仍进入 stable；检测到实质位移后立即回到 moving。此方案不增加权限、监听器或新架构，代价是 idle 窗口枚举由 2 Hz 提高到最多 10 Hz，换取拖动启动延迟上限显著降低。

## Compatibility and privacy

- macOS 13 没有截图路径，继续保守避让。
- macOS 14+ 只有 preflight 已通过才使用公开 ScreenCaptureKit。
- 不保存图像、不 OCR、不记录颜色、文字、真实窗口 ID、PID 或坐标。

## Rollback

三个行为通过独立代码块和测试覆盖；如出现性能回归，可只回退跟随常量而保留权限门控与气泡回位通知。若通知路径引起重入，则回退即时唤醒、保留下一 stable tick 的缓存读取。
