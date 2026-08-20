# Design — 项目文档重组

## Information Architecture

```text
docs/
├── architecture/
│   ├── data-layer.md
│   ├── dock-obstacle-avoidance.md
│   └── pet-window-detection.md
├── development/
│   └── trellis.md
└── verification/
    └── dev-candidate.md
```

`docs/architecture/` 保存当前实现的设计依据和隐私边界；`docs/development/` 保存贡献者接入说明；`docs/verification/` 保存会随候选变化的验证状态。`.trellis/spec/` 继续作为开发约束，不复制产品事实全文。

## Migration Map

| Current | Target | Treatment |
| --- | --- | --- |
| `docs/data-layer.md` | `docs/architecture/data-layer.md` | 保留核心契约，更新陈旧测试/阶段语言 |
| `docs/dock-obstacle-avoidance.md` | `docs/architecture/dock-obstacle-avoidance.md` | 保留气泡与隐私设计，更新测试口径，不改控制按钮结论 |
| `docs/pet-window-detection.md` | `docs/architecture/pet-window-detection.md` | 保留识别依据，清理阶段性测试快照 |
| `docs/trellis-setup.md` | `docs/development/trellis.md` | 按当前 Codex active 状态重写 |
| `docs/final-success-criteria.md` | `docs/verification/dev-candidate.md` | 改为 dev 候选验收清单/状态，不宣称 main 合入 |
| `docs/success-criteria.md` | merged, then removed | 唯一有效内容并入 verification/architecture |

## Compatibility

- 同一提交内更新 README 中英文版、源码注释及文档间相对链接，不保留会长期漂移的 duplicate stub。
- README 面向公开用户，只链接稳定架构说明和当前 dev 验收说明。
- 文档中的测试数字必须与当前公开口径一致；对细分类计数优先描述覆盖范围，减少未来漂移。

## Boundaries

- 只允许文档、README 和 `PetTracker.swift` 的单行文档路径注释发生变化。
- 不编辑 Swift 可执行逻辑、Makefile、测试或 Trellis 生成目录。
- 不把安全审计 finding 写成已修复；若相关风险尚未修复，只保留准确边界或已知风险表述。

## Rollback

文档迁移是单提交原子变更；若 Review 发现断链或事实错误，回退实现者修复并生成新 commit，旧 Review 失效。集成前可整体不 cherry-pick，不需要兼容性数据迁移。
