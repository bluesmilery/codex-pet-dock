# Design — docs-as-code 管理门禁

## Responsibility Model

```text
docs/                  项目事实：what / why / current evidence
.trellis/spec/         执行规则：how to change / required gates
.trellis/tasks/        单次任务：requirements / plan / review evidence
Git                    版本与审计记录
Make + checker         可重复质量门禁
```

完整事实只保存在一个位置。README 和 spec 使用摘要与链接，不复制字段表、测试矩阵或真机结论全文。

## Documentation Catalog

`docs/README.md` 是唯一目录入口，表格至少包含：文档、类型、事实来源、更新触发条件。检查器要求除目录页自身外的每份 `docs/**/*.md` 至少被目录页本地链接一次。

## Checker Architecture

`tools/check_docs.py` 同时提供可导入函数和 CLI：

- `check_repository(root: Path) -> list[Finding]`
- `main() -> int`

检查顺序固定：输入清单 → 本地链接 → catalog 完整性 → legacy path → 隐私模式。Finding 按 path/line/code 排序，保证本地、Review 和未来 CI 输出稳定。

### Link Contract

- 扫描普通链接和图片链接中的本地目标。
- `http:`、`https:`、`mailto:` 和纯 `#anchor` 不联网、不检查。
- 去除 query/fragment，URL decode 后按包含链接的 Markdown 文件目录解析。
- 目标必须存在并留在仓库根目录；目录链接允许存在的目录。

### Catalog Contract

- `docs/README.md` 必须存在。
- `docs/README.md` 必须链接所有其他 `docs/**/*.md`。
- README 双语只需链接 catalog，不要求重复完整目录表。

### Privacy Contract

只检测带真实值的高置信模式，避免规则文档自我命中：

- `/Users/<literal-user>/...`，允许 `/Users/<user>` 等尖括号占位符；
- `wid=<digits>` 或等价格式；
- 带具体数字的运行时坐标表达；
- `CDHash=<hex>`、40/64 位构建特定 hash；
- `Co-Authored-By:` trailer。

检查范围仅限公开 Markdown，不读取 `auth.json`、session JSONL、浏览器 Profile 或 Git 凭证。

## Test Design

`tests/test_check_docs.py` 使用 `tempfile.TemporaryDirectory` 构造最小仓库 fixture，直接调用 checker API。先写失败断言，再实现 checker。测试至少覆盖 clean、broken link、uncatalogued doc、legacy path、private path/wid 五类。

## Make Integration

```make
PYTHON ?= python3

docs-check:
	$(PYTHON) tools/check_docs.py

test-docs:
	$(PYTHON) tests/test_check_docs.py

test: docs-check test-docs test-ui test-data test-shell
```

公开口径表述为“394 项 Swift 断言 + docs-check/docs unit tests”，避免把 Python unittest 数量混入既有 Swift 数字。

## Compatibility and Rollback

- 不增加运行时依赖，不改变 App 产物。
- 开发机需可执行 Python 3；可通过 `make PYTHON=<interpreter>` 覆盖。
- 如门禁误报，优先修正规则或增加明确的占位符例外，不允许用宽泛 ignore 绕过。
- 所有改动为一个可独立回退的 docs/build/test/spec 提交链；未通过 Review/QA 不集成 dev。
