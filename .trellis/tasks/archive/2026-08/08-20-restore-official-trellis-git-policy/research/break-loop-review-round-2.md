# 第二轮 Review break-loop 分析

## 1. Root Cause Category

- **Category**: C - Change Propagation Failure
- **Specific Cause**: 实现把包含多个独立约束的 `AGENTS.md` 复合句整体替换，只验证了 `.claude/` 目标表述是否消失，没有核对同句中不属于本任务的私有 refs / bundle id 分叉规则是否保留。同时，迁移检查把历史 task 当作不可改写的静态证据，没有区分“保留历史结论”和“继续用现在时陈述已失效策略”。

## 2. Why Fixes Failed

1. 初始实现：范围搜索聚焦 `.claude/`、workspace 和隐私模式，未建立 base 中被删除政策关键词的保留清单，属于不完整传播检查。
2. 第一轮 amend：只修正“本机邮箱”措辞，没有重新检查全部独立约束和新入库历史资料的时间语义，旧 Review 又因 SHA 变化失效。
3. 第二轮 Review：机械门禁均通过，说明现有 docs/test 检查只验证链接、格式和敏感模式，不能发现复合句误删与历史现在时漂移。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|----------|-----------|-----------------|--------|
| P1 | Documentation | 在 documentation spec 增加复合规则的未改子句保留检查 | DONE |
| P1 | Review | 对照 base/HEAD 搜索被删除的独立政策关键词并逐项解释 | DONE |
| P2 | Historical evidence | 新纳入 Git 的历史资料对已失效现在时策略增加“当时基线”限定 | DONE |
| P2 | Campaign reset | 新候选重新从 Review round 1 开始，旧 SHA 证据不复用 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: 同一规则条目同时描述隐私、发布和平台文件时，按单一关键词整条替换都可能删除无关约束。
- **Design Improvement**: 内容迁移同时检查敏感模式与时间语义；“历史内容保留”不等于让失效状态继续以现在时存在。
- **Process Improvement**: Review Readiness 除新增内容外，还要检查 base 中消失的政策词项，并解释每个删除项。

## 5. Knowledge Capture

- [x] 更新 PRD、design 和 implement 的验收矩阵。
- [x] 更新 `.trellis/spec/macos/documentation-guidelines.md`。
- [x] 新实现候选修复两个 finding，并完成官方模板、ignore/config、dry-run、inventory、隐私扫描和项目门禁的全候选自检。
- [ ] 对新 SHA 重新执行正式 Review round 1 和 QA。
