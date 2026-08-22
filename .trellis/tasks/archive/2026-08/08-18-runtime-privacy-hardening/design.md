# 运行时隐私加固设计

## 1. 范围与边界

本任务以一个 Trellis 任务交付五项修复。它们共同构成公开候选的运行时隐私门禁，并共享测试、文档和最终历史扫描；拆成多个可独立集成的子任务会增加中间状态和 Review 重复，故保持单一候选、单一实现负责人。

修改分为两组：

1. Trellis/Codex 平台层：context 路径、runtime session 元数据和模板 hash。
2. PetDock 应用层：私有文件存储、诊断/日志、Codex helper 环境与信任、token cache 去标识化。

## 2. Trellis context 路径约束

### 2.1 合法路径合同

- task/context JSONL 只接受仓库相对路径。
- 读取前使用 canonical path 解析；解析结果必须位于 canonical repository root 内。
- 绝对路径、含逃逸 `..` 的路径、解析后越界的 symlink 统一拒绝。
- 目录条目逐个文件再次做 containment 校验，不能只检查父目录。
- 拒绝行为返回空/错误并输出不含敏感目标内容的提示；不把目标文件内容或绝对路径注入模型。

### 2.2 兼容性

仓库内普通文件、目录、归档 task 自引用、二进制识别、单文件上限和总预算保持原行为。`task_context.py` 的 add/validate 与 hook 实际读取采用同一约束，防止“CLI 通过、hook 越界”。

### 2.3 Trellis 生成文件

修改 `.codex/hooks/inject-subagent-context.py`、`.trellis/scripts/common/task_context.py`、`.trellis/scripts/common/active_task.py` 后，同步 `.trellis/.template-hashes.json` 对应 SHA-256。最终运行 `trellis update --dry-run`，确认没有未解释的模板漂移；不引入 `.claude/`。

## 3. 私有文件存储与诊断日志

### 3.1 共享私有存储原语

新增最小 `PrivateStorage` 工具，统一：

- 创建 `~/Library/Application Support/PetDock` 及子目录并显式设为 `0700`。
- 创建/打开持久化文件时显式设为 `0600`。
- 对日志使用 no-follow、append/create 语义；拒绝 symlink 或非普通文件。
- 提供 diagnostics、logs 和 token cache 的标准 URL，避免各模块自行拼接 `/tmp`。

该工具是三个消费者共用的最小抽象，不扩展为通用文件系统框架。

### 3.2 诊断内容

- 默认 `--diagnose` 只输出候选数量、命中规则、授权状态和脱敏后的结构信息。
- 不输出或落盘 title、owner、真实 WID/PID、精确 bounds、screen localizedName/frame。
- 诊断文件使用私有 Diagnostics 目录中的稳定文件名，便于 `make diagnose` 检查；稳定性由 `0700/0600`、no-follow 和普通文件校验保护，不再依赖全局 `/tmp`。
- `tools/diagnose.swift` 同步采用脱敏输出，不保留另一条泄露路径。

### 3.3 PetLogger

- 默认日志迁移到私有 Logs 目录。
- 保留异步队列、release 默认关闭、flush、1 MiB 上限和单份轮转。
- open/rotate 使用安全原语；symlink fixture 必须失败且不能修改目标文件。
- 运行日志去除真实 WID；错误文本只保留现有非正文状态，不新增窗口标题或响应正文。

## 4. Codex helper 最小环境与信任

### 4.1 环境白名单

`childEnvironment` 从空字典构建，而不是复制父环境：

- 保留：`HOME`、`TMPDIR`、`LANG`、`LC_ALL`、`LC_CTYPE`（存在时）。
- `PATH` 固定为 codex 所在目录加系统目录 `/usr/bin:/bin:/usr/sbin:/sbin`，去重；不保留父 PATH 的其他条目。
- 可保留明确的非秘密路径配置 `CODEX_HOME`，但不保留 `OPENAI_API_KEY`、其他 token/cookie、代理变量或未知变量。

### 4.2 Resolver 信任校验

- override、PATH、用户常见位置和系统候选仍保留当前优先级。
- 每个候选解析 symlink 后须为普通可执行文件，owner 为当前用户或 root，文件及关键目录不得 group/world writable。
- 校验 canonical target，但保留原 launch URL 以兼容 nvm/npm symlink 与同目录 node 查找。
- 不使用 shell，不读取认证文件，不要求 npm 安装具备 Developer ID 签名。

## 5. Trellis runtime 元数据

- context key 继续由 session/conversation/transcript 输入经 hash/sanitize 派生，以维持多会话隔离。
- 持久化 JSON 只保存 `platform`、`last_seen_at`、`current_task`、`current_run` 等工作流必要字段；删除原始 session/conversation/transcript 值。
- runtime/sessions 目录显式 `0700`；JSON 通过同目录私有临时文件 `0600` 后 atomic replace。
- 现有 resolve、fallback、clear 和 task archive 行为保持不变。

## 6. Token cache 去标识化

- cache key 从绝对 `file.path` 改为版本化 SHA-256 标识，例如 `v2:<digest>`；digest 输入为 sessions root 下规范化的相对路径。
- 序列化内容不再包含 home、`.codex/sessions`、日期路径明文或 rollout UUID。
- 当前扫描文件集合、命中和 stale 淘汰全部基于同一 key 函数。
- 加载时丢弃非 `v2:` 旧 key；首次刷新重建，不迁移旧隐私字段。
- cache 目录/文件复用 `PrivateStorage` 的 `0700/0600` 与安全原子写。

## 7. 测试设计

### Python / Trellis

新增独立隐私测试入口，使用临时仓库和合成文件覆盖：合法内部文件、绝对路径、`..`、逃逸 symlink、目录子项、raw session metadata 不落盘、runtime 权限和多会话隔离。加入 `make test-privacy` 并由 `make test` 调用。

### Swift

- UI/Logger：私有权限、no-follow/symlink、轮转、release gate、日志无 WID。
- Data：环境白名单、敏感变量剔除、受控 PATH、resolver 权限/symlink、token cache key 去标识化、旧格式失效、命中/淘汰和权限。
- 诊断脱敏尽量下沉为纯格式化函数，用合成 `WinCandidate`/screen descriptor 测试，不调用真实 CGWindow/TCC。

## 8. 文档、兼容与回滚

- 更新 Makefile、README 双语、`docs/architecture/data-layer.md`、`docs/development/trellis.md`、`docs/verification/dev-candidate.md` 和 macOS privacy spec。
- 明确环境变量认证不再支持；使用 Codex 自身登录态。
- 旧 `/tmp/petdock.log` 与 `/tmp/petdock-diagnose.txt` 不主动删除，避免越权清理用户已有文件；文档给出一次性手工清理说明。
- 回滚以实现 commit 为单位；旧 cache 自动失效，不需要数据迁移回滚。
- 不执行真实 TCC/ScreenCaptureKit/窗口枚举；这些继续列为未验证。
