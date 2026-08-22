# Codex Pet Dock — dev 候选验收

> 本文是 `dev` 分支候选的可重复验收清单和边界说明，不代表已经合入 `main`，也不代表已发布或已完成真机 QA。

## 验收口径

验收结论分为三类，不能互相替代：

1. **自动验证**：在当前工作树执行的构建、独立 swiftc 测试和 fixture 检查；结果以命令退出码和测试输出为准。
2. **静态结论**：由源码、公开 API 规则、隐私约束和纯函数测试推导出的行为边界；不等于真实窗口或 TCC 运行结果。
3. **真机验证**：需要屏幕录制、ScreenCaptureKit、Accessibility、登录项或多显示器环境的手工项目；未实际运行时必须标记未验证。

## 自动验证门禁

候选可重复执行：

```sh
swift build -c release
make docs-check
make test-docs
make test
```

通过条件是 release 构建退出码 0 且 0 warning，docs gate 通过，`make test` 的 test-privacy、test-ui、test-data、test-shell 四个独立入口全部通过。Swift 断言细分以各入口测试源码和实际输出为准，避免在 README/spec 复制易漂移计数。文档测试是额外门禁，不计入 Swift 断言。

文档变更还需在任务和 Review 中记录 `Docs Impact: none | update | new`。`make docs-check` 离线检查本地链接、`docs/README.md` 目录完整性、旧顶层 docs 路径和公开隐私模式；它不检查外部 URL 可达性，也不替代真机验证。

release 构建属于上述自动门禁；构建通过不能推导 `.app` 已启动、UI 已渲染或真机交互已通过。

自动测试使用纯函数、依赖注入和脱敏 fixture，不联网、不读取认证文件、不读取会话正文，也不需要屏幕录制权限。数据层只聚合 `last_token_usage` 数值；BubbleVisibility 只在内存计算 alpha 比例。

## 静态结论

- `selectPet` 通过公开 CGWindowList / AppKit 规则过滤主窗口、辅助控件并选择 Mascot；无合理候选时返回 nil，不误绑主聊天窗口。
- `Geometry.safeDockFrame` 固定底座宽度，按障碍链式下移，执行水平 clamp；垂直越界返回 nil。避让隐藏与宠物可见性、数据暂停语义分离。
- `BubbleVisibilityProbe` 使用 ScreenCaptureKit 公开 API、最多 2Hz、single-flight 和 generation 失效保护；捕获失败时保守按 visible 避让。
- 数据层通过 codex app-server stdio JSON-RPC 和本机日志数值聚合提供 WEEK LEFT / WEEK TOKENS，不复制 `auth.json` 或凭证。
- 日志、诊断与 token cache 只写入 Application Support/PetDock 私有目录（0700/0600）；默认诊断脱敏，不落盘标题、owner、WID/PID 或精确坐标。helper 环境为严格白名单，resolver 拒绝不可信可执行文件。
- Trellis context 路径执行 canonical containment，runtime 只保存 opaque context key 和最小元数据；原始 session/conversation/transcript 值不落盘。
- 文档、测试与源码注释中的示例不得包含真实窗口 ID、坐标、构建指纹、提交标识、认证内容或用户路径。

## 基础手工场景（真机未验证）

以下步骤承接窗口识别与跟随的基础验收；本次文档候选不把它们标记为已完成：

1. `make diagnose`：确认 Codex 进程归属、候选窗口清单、规则命中和选中理由可读。
2. `make run`：确认透明底座出现在宠物正下方并保持几何间隙。
3. 拖动宠物到另一位置，含副屏或负坐标区域，确认底座跟随且不越出可见区。
4. 在 Codex 内隐藏宠物，确认底座与详情隐藏；再次显示后确认重新捕获并跟随。
5. 退出并重新打开 Codex，确认底座隐藏、重开后重新发现宠物。
6. 展开和收起会话气泡，确认展开时底座下移、收起时回到宠物下方；控制按钮出现 / 消失不改变避让分类结论。
7. 在真实屏幕录制授权下验证 BubbleVisibility 的展开→收起→展开可逆性，以及捕获失败时的保守避让。
8. 使用状态栏菜单验证主题、显示 / 隐藏底座、退出和登录自启等 Accessibility / SMAppService 交互。
9. 验证底座与详情卡的透明渲染、字段布局和详情卡点击展开 / 收起。
10. 验证三种内置主题切换，以及外部 JSON 主题文件的安全解析和热加载。
11. 在已登录的真实 Codex 环境中验证 WEEK LEFT / WEEK TOKENS 刷新、窗口边界和独立退避；不输出账户或会话内容。
12. 观察 Follower 移动升频、稳定降频、隐藏与重捕的实际性能和体感。

这些项目依赖 TCC、ScreenCaptureKit、Accessibility、真实多显示器和 `.app` 运行环境，不能由 `make test` 代替。`make app` 属于发布 / 真机阶段命令，本页不把其执行状态写成当前候选结论。

## 开发候选产物归档

`make app` 会删除并重新组装、ad-hoc 签名当前 worktree 的 `build/PetDock.app`。该路径是可变的 staging，不是交给用户测试的开发候选。候选归档是最终 QA 的最后阶段：必须从同一 worktree 的精确清洁 Git 状态开始，先捕获完整与 7 位提交 SHA，再运行门禁和 `make app`，复核 SHA 与清洁状态未变后，才把候选归档到**主工作树**的 `build/candidates/`，即使构建发生在 linked worktree 内：

```text
<primary>/build/candidates/YYYY-MM-DD-HHmmss-<label>-<worktree>-<shortSHA>/PetDock.app
```

- `<primary>` 是 `git worktree list --porcelain` 列出的第一条主工作树路径，不是当前 `git rev-parse --show-toplevel`。linked worktree 自己的 `build/candidates/` 不得作为交付目录。
- `label` 必须是匹配 `^[a-z0-9]+(-[a-z0-9]+)*$` 的单路径组件 slug。`dev` 构建固定为 `dev`；其他开发构建使用脱敏后的 feature 或 task 标签，例如 `app-icon-v2`。不得直接使用含 `/` 的分支名，也不得包含空白、大写字符、空值、首尾连字符或连续连字符。
- `worktree` 同样必须匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`。主工作树固定为 `primary`；独立 worktree 使用其目录名 slug，例如 `08-22-bubble-smooth-feature-handoff`。不得写入本机绝对路径、用户名或 `.ao` 等隐藏数据目录名。
- `shortSHA` 必须是该次最终 QA 所绑定完整提交 SHA 的前 7 个字符。
- 每次交付的候选目录都必须全新且不可变：不得覆盖或复用已有目录；重新构建、提交 SHA 变化或归档时间变化时创建新目录。时间戳精确到秒；若同一秒的目标目录已存在，归档必须失败，使用新的时间戳重新执行完整流程。
- 主工作树的 `build/` 是 gitignore 中的本地构建目录；候选产物不得加入 Git 或提交。历史目录若缺少 `<worktree>` 字段，只作为旧产物保留，新归档必须带该字段。

以下 zsh 示例给出完整顺序；`candidate_label` 使用占位符，执行前替换为本次实际值：

```sh
(
  set -euo pipefail

  candidate_parent=""
  candidate_temp_dir=""
  candidate_dir=""
  candidate_final_owned=false
  cleanup_candidate_path() {
    candidate_cleanup_path="$1"
    candidate_cleanup_kind="$2"
    [[ -n "$candidate_cleanup_path" && -n "$candidate_parent" && \
      ( -e "$candidate_cleanup_path" || -L "$candidate_cleanup_path" ) ]] || return 0

    candidate_cleanup_parent="${candidate_cleanup_path:h}"
    candidate_cleanup_name="${candidate_cleanup_path:t}"
    candidate_cleanup_resolved_parent="$(cd "$candidate_cleanup_parent" && pwd -P)"
    candidate_cleanup_resolve_code=$?
    if (( candidate_cleanup_resolve_code != 0 )) || \
       [[ "$candidate_cleanup_parent" != "$candidate_parent" || \
          "$candidate_cleanup_resolved_parent" != "$candidate_parent" ]]; then
      print -u2 -- "清理 guard 拒绝路径，禁止报告交付：$candidate_cleanup_path"
      return 1
    fi

    if [[ "$candidate_cleanup_kind" == temp ]]; then
      if [[ "$candidate_cleanup_name" != .candidate-* ]]; then
        print -u2 -- "清理 guard 拒绝非临时候选，禁止报告交付：$candidate_cleanup_path"
        return 1
      fi
    elif [[ "$candidate_cleanup_kind" == final ]]; then
      if [[ "$candidate_final_owned" != true || "$candidate_cleanup_path" != "$candidate_dir" ]]; then
        print -u2 -- "清理 guard 拒绝非本轮最终目录，禁止报告交付：$candidate_cleanup_path"
        return 1
      fi
    else
      print -u2 -- "清理 guard 拒绝未知类型，禁止报告交付：$candidate_cleanup_path"
      return 1
    fi

    /bin/rm -rf -- "$candidate_cleanup_path"
    candidate_cleanup_code=$?
    if (( candidate_cleanup_code != 0 )) || \
       [[ -e "$candidate_cleanup_path" || -L "$candidate_cleanup_path" ]]; then
      print -u2 -- "清理失败；请将此精确残留路径移到回收站，且禁止报告交付：$candidate_cleanup_path"
      return 1
    fi
    return 0
  }
  cleanup_candidate_artifacts() {
    candidate_exit_code=$?
    trap - EXIT
    set +e
    cleanup_candidate_path "$candidate_temp_dir" temp
    if [[ "$candidate_final_owned" == true ]]; then
      cleanup_candidate_path "$candidate_dir" final
    fi
    exit "$candidate_exit_code"
  }
  trap cleanup_candidate_artifacts EXIT

  candidate_status="$(git status --porcelain=v1 --untracked-files=all)"
  test -z "$candidate_status"
  candidate_sha="$(git rev-parse --verify 'HEAD^{commit}')"
  candidate_short_sha="$(printf '%s' "$candidate_sha" | cut -c1-7)"
  candidate_label="<dev-or-task-label>"
  [[ "$candidate_label" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
  candidate_current_root="$(git rev-parse --show-toplevel)"
  candidate_primary_root="$(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }')"
  test -n "$candidate_primary_root"
  test -d "$candidate_primary_root"
  if [[ "$candidate_current_root" == "$candidate_primary_root" ]]; then
    candidate_worktree="primary"
  else
    candidate_worktree="${candidate_current_root:t}"
  fi
  [[ "$candidate_worktree" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]

  swift build -c release
  PYTHONDONTWRITEBYTECODE=1 make docs-check
  PYTHONDONTWRITEBYTECODE=1 make test-docs
  PYTHONDONTWRITEBYTECODE=1 make test
  make app

  candidate_reconfirm_sha="$(git rev-parse HEAD)"
  test "$candidate_reconfirm_sha" = "$candidate_sha"
  candidate_status_after="$(git status --porcelain=v1 --untracked-files=all)"
  test -z "$candidate_status_after"
  test -d build/PetDock.app
  mkdir -p "$candidate_primary_root/build/candidates"
  candidate_parent="$(cd "$candidate_primary_root/build/candidates" && pwd -P)"
  candidate_temp_dir="$(mktemp -d "$candidate_parent/.candidate-${candidate_label}-${candidate_worktree}-${candidate_short_sha}.XXXXXX")"
  candidate_temp_app="${candidate_temp_dir}/PetDock.app"

  ditto build/PetDock.app "$candidate_temp_app"
  codesign --verify --deep --strict --verbose=2 "$candidate_temp_app"
  diff -qr build/PetDock.app "$candidate_temp_app"
  cmp build/PetDock.app/Contents/MacOS/PetDock "$candidate_temp_app/Contents/MacOS/PetDock"

  candidate_stamp="$(date '+%Y-%m-%d-%H%M%S')"
  candidate_dir="${candidate_parent}/${candidate_stamp}-${candidate_label}-${candidate_worktree}-${candidate_short_sha}"
  candidate_app="${candidate_dir}/PetDock.app"
  test ! -e "$candidate_dir"
  mkdir "$candidate_dir"
  candidate_final_owned=true
  /bin/mv -n "$candidate_temp_app" "$candidate_app"
  test ! -e "$candidate_temp_app"
  rmdir "$candidate_temp_dir"
  candidate_temp_dir=""

  test -d "$candidate_app"
  codesign --verify --deep --strict --verbose=2 "$candidate_app"
  diff -qr build/PetDock.app "$candidate_app"
  cmp build/PetDock.app/Contents/MacOS/PetDock "$candidate_app/Contents/MacOS/PetDock"
  candidate_final_owned=false
)
```

隔离 subshell 中的 `set -euo pipefail` 确保任一前置检查、门禁、复制、签名、内容比较或发布步骤失败时立即以非零状态终止。app 先复制到主工作树 `build/candidates/` 下唯一的隐藏临时目录并完成全部验证；验证通过后，以 `mkdir` 原子占有尚不存在的最终目录，再移动 app 并复核正式路径。并发创建或同秒冲突会让 `mkdir` 失败，不覆盖已有目录；`mv -n` 后还必须确认临时 app 已消失。

EXIT trap 使用 macOS 13+ 自带的 BSD `/bin/rm` 清理，并始终保留原命令退出码。执行前同时验证非空路径、词法直属父目录与 `pwd -P` 解析父目录；临时路径还必须使用 `.candidate-` 隐藏名称，最终路径还必须是本轮原子占有的精确目录。因此 cleanup 不接受宽泛路径，也不会清理竞争者目录。若 `/bin/rm` 被安全钩子拦截、返回失败或清理后路径仍存在，必须把错误中报告的**唯一精确残留路径**移到回收站，并禁止报告候选已交付；不依赖 Finder 自动化或 TCC。

即使归档前已经存在可通过签名检查的 staging，也不得跳过本流程中的 `make app`；该命令按 Makefile 删除并重建 staging，避免复用旧 bundle。前后两次 Git 检查证明门禁与构建期间 HEAD 未变化，且 tracked / 非忽略 untracked 状态保持清洁；`codesign` 只验证 app 的签名结构，`diff` 与 `cmp` 只验证它与刚生成的 staging 内容一致。精确来源由 QA 记录把捕获的完整 SHA、上述命令及其实际输出绑定在一起，不能仅凭签名结果推断。

交付报告必须给出完整提交 SHA、主工作树归档后的 app 路径、各门禁与 `make app` 的实际结果，以及针对归档路径的 `codesign` 和当前 worktree staging 内容一致性结果。不能由这些检查推断 app 已启动、TCC 已授权或 UI / 真机交互已通过。可保留当前 worktree 的 `build/PetDock.app` 供后续 staging 使用，但面向用户的测试说明必须指向主工作树归档候选路径。归档过程不得启动或安装 app，也不得写入或覆盖 `/Applications`。

## 风险与边界

- ad-hoc 签名没有稳定的开发者身份，重新签名可能要求重新授予屏幕录制权限；发布时应使用稳定签名或 notarized 构建。
- 屏幕录制权限是窗口枚举和像素探测的前提；无授权时只能依赖自动测试与静态结论。
- `codex app-server` 为 experimental 协议，字段可能随 CLI 版本变化；客户端只解析稳定子集并对缺失字段降级。
- 跨应用 z-order 不能由公开 API 完全控制；产品降级是 `.floating` level 加几何不重叠，而不是私有 API。
- 宠物隐藏、Codex 退出、登录自启和多屏硬件结果必须由具备相应权限的真机 QA 单独记录，不能从本页的自动门禁推断。

## 候选交付边界

本页只描述 `dev` 候选的验收条件。只有在独立 Review 与 QA 针对同一完整提交均为 P0/P1/P2 清零、自动门禁通过、真机项目明确标注结果后，才可将 accepted SHA 停放到对应 `feature/` 分支，再由专门合入会话按项目 `AGENTS.md` 第 1 节从 `feature/` 串行 merge 到本地 `dev`；本页不替代人工合入确认，也不授权向 `main` 推送。合入冲突必须保留双方已验收功能，禁止覆盖解决。
