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
- `BubbleVisibilityProbe` 使用 ScreenCaptureKit 公开 API，下一次允许启动捕获的受应用控制等待最长 0.1 秒，并保持 strict single-flight、generation 与候选 identity（bounds/owner/layer 等）失效保护；捕获 cadence、绝对 retry deadline 与 scheduler 共用 `systemUptime` 单调时钟，墙钟校准不参与间隔计算；成功取得窗口清单但目标缺失仅在同 generation 已有成功统计观察时按 hidden 处理，首次 targetMissing 和权限 / 清单 / 截图 / 统计 unavailable 仍按 visible 保守避让。
- moving 跟随在 macOS 14+ 仅当底座可见且实际 `panel.screen` 非空时使用窗口绑定的 AppKit `CADisplayLink`；screen 暂时为空时使 link 失效并使用 Timer fallback，screen 变化通过 coalesced wake 重新选择。macOS 13 使用按屏幕能力、能力变化时重建且 capped 到 120 Hz 的 repeating Timer。回调 latest-only 合并；stable 以静止锚点、单调 elapsed time 与名义 `4/60s` 判定，0.1 秒探测由每次完整 tick 的起点派生，气泡 probe 因 cadence 尚未 due 而跳过时在 tick 完成处按绝对 due deadline 重算剩余 delay；若工作已经跨过 deadline，仅立即合并一次 follow-up，不补错过的节拍；不使用 `CVDisplayLink`。
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
6. 分别测试消息卡片收起与全部消息 / 控制 UI 隐藏：确认展开时底座下移、收起或成功观察到目标缺失时回到宠物下方；控制按钮出现 / 消失不改变避让分类结论。
7. 在真实屏幕录制授权下验证 BubbleVisibility 的展开→收起→展开可逆性，以及捕获失败时的保守避让。
8. 使用状态栏菜单验证主题、显示 / 隐藏底座、退出和登录自启等 Accessibility / SMAppService 交互。
9. 验证底座与详情卡的透明渲染、字段布局和详情卡点击展开 / 收起。
10. 验证三种内置主题切换，以及外部 JSON 主题文件的安全解析和热加载。
11. 在已登录的真实 Codex 环境中验证 WEEK LEFT / WEEK TOKENS 刷新、窗口边界和独立退避；不输出账户或会话内容。
12. 分别在 60 Hz 和可用的高刷屏观察 moving 跟随、最长 32ms 线性跟随、stable 降频、隐藏与重捕的实际性能和体感；若有 macOS 13 环境，单独验证 repeating Timer fallback。

这些项目依赖 TCC、ScreenCaptureKit、Accessibility、真实多显示器和 `.app` 运行环境，不能由 `make test` 代替。`make app` 属于发布 / 真机阶段命令，本页不把其执行状态写成当前候选结论。

## Runtime 证据采样（QA 专用，默认关闭）

runtime 聚合诊断默认关闭：不提供启动参数时不创建诊断文件，也不增加捕获或计时开销。QA 需要区分真实 full-hide 触发分支时，用精确候选的可执行文件显式启动：

```sh
<candidate>/Contents/MacOS/PetDock --runtime-evidence=<candidate-full-sha>
```

输出写入 PetDock 私有 Diagnostics（`~/Library/Application Support/PetDock/Diagnostics/runtime-evidence.json`；目录 0700、文件 0600、no-follow fail-closed），内容只包含白名单内的聚合计数：tick 数、bubble/control 障碍数、capture outcome / visibility 枚举计数、identity-change / wake callback 计数、可见障碍数，以及实际底座 frame 相对本 tick 无障碍基础 frame 的匿名 dy bucket（base / (0,32] / (32,64] / >64）。文件中的 `candidateSHA` 绑定 QA 启动时显式提供的候选 SHA；该值必须通过解析器与边界测试的同一合同：恰好 40 个 ASCII 小写十六进制字符（0-9/a-f，当前仓库 Git SHA-1 完整对象 SHA），7/39/41/64 位缩写或区间、大写、非十六进制与全角等 Unicode 形态一律解析失败并保持诊断关闭。该 SHA 只允许出现在私有诊断产物中，不写入被跟踪文件。

任意生产 sink 由编译层合同封死，而非文本扫描：持有 `outputURL` 的具体 collector 类型整体为文件私有，其他生产文件只依赖不含地址能力的 recorder 协议，并经同文件 `makeRuntimeEvidenceRecorder(candidateSHA:flushNow:)` 工厂取得 existential；工厂签名不含输出地址参数，落盘位置固定为 PetDock 私有 Diagnostics 证据文件。测试自定义临时 sink 只能经 `#if PETDOCK_TESTING` 包裹的同文件 `makeRuntimeEvidenceRecorderForTesting(candidateSHA:outputURL:flushNow:)` 进入，release 构建在词法阶段排除该入口。外部命名/构造具体类型、生产调用传入地址或 release 引用测试工厂都以真实编译失败作为主证据；不再用 Swift declaration inventory、constructor regex 或自制 parser 声称语言级封闭。Makefile flag 守卫按 shell token 同时识别 `-DNAME` 与 `-D NAME`，并要求测试 flag 只在 test-ui recipe 中定义一次；`Package.swift` 不得定义该 flag。

上述编译层合同由 `make test-privacy` 内的真实编译 probe 持续验证：每次隐私门禁都会在无测试 flag 的 release 组合上编译三个探针——外部文件命名/构造具体 collector、生产 facade 传入 `outputURL` 地址参数、release 源引用测试专用 facade——三者都必须编译失败才算通过。具体类型内新增任何 initializer、subscript、property 或 method 都不会改变该边界：类型本身文件私有，成员不会因此对其他生产文件可见。测试 fixture 如需命名证据文件，只能使用不含任何目录/路径能力的 filename 常量。

`PETDOCK_TESTING` 的 flag 布线采用双层守卫且不解析 Make 语法：`PETDOCK_TESTING` 是不可分割的稳定 identifier，整个 Makefile（变量定义、注释、任意 recipe）按 identifier 边界计数必须恰好出现一次——藏进 make 变量再由其他 recipe 引用时，构建期展开会生效但计数层已经失败；把唯一出现移入变量间接引用时，计数为 1 但 direct swiftc token 扫描看不到真实 `-D`，同样失败。随后 shell token guard 继续证明这唯一出现是 test-ui swiftc 命令上合法的 `-DNAME` 或 `-D NAME` 形态，并拒绝悬空 `-D`。任何变量、注释或间接布线形态都 fail-closed。

采样在既有 follow tick 内更新，不新建持续捕获流或计时器。落盘采用 dirty 抑制加最小 0.5 秒单调节流（时钟由生产 follow 单调时钟注入，诊断文件自身不读取系统时间）：首个证据立即写出；其后仅在被当前 generation/identity 接受的捕获、identity 变化、wake、layout 状态变化或 dy bucket 变化产生新证据、且距上次写盘尝试至少 0.5 秒时写盘，窗口内的持续抖动合并为到期后的一次写；写盘失败保留 dirty 并受同一节流约束。无变化的显示 tick 不产生写 IO。该机制只验证 instrumentation：自动测试中注入的 fake outcome 仍标为 plumbing-only；在真实图 1→图 2→图 3 操作中取得同一候选的脱敏聚合之前，不得宣称 full-hide 症状已修复或根因已确认。

## 开发候选产物归档

`make app` 会删除并重新组装、ad-hoc 签名 `build/PetDock.app`。该路径是可变的 staging，不是交给用户测试的开发候选。候选归档是最终 QA 的最后阶段：必须从同一 worktree 的精确清洁 Git 状态开始，先捕获完整与 7 位提交 SHA，再运行门禁和 `make app`，复核 SHA 与清洁状态未变后，才归档一份新的本地候选：

```text
build/candidates/YYYY-MM-DD-HHmmss-<label>-<shortSHA>/PetDock.app
```

- `label` 必须是匹配 `^[a-z0-9]+(-[a-z0-9]+)*$` 的单路径组件 slug。`dev` 构建固定为 `dev`；其他开发构建使用脱敏后的 feature 或 task 标签，例如 `app-icon-v2`。不得直接使用含 `/` 的分支名，也不得包含空白、大写字符、空值、首尾连字符或连续连字符。
- `shortSHA` 必须是该次最终 QA 所绑定完整提交 SHA 的前 7 个字符。
- 每次交付的候选目录都必须全新且不可变：不得覆盖或复用已有目录；重新构建、提交 SHA 变化或归档时间变化时创建新目录。时间戳精确到秒；若同一秒的目标目录已存在，归档必须失败，使用新的时间戳重新执行完整流程。
- `build/` 是 gitignore 中的本地构建目录；候选产物不得加入 Git 或提交。

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
  candidate_repo_root="$(git rev-parse --show-toplevel)"
  mkdir -p "$candidate_repo_root/build/candidates"
  candidate_parent="$(cd "$candidate_repo_root/build/candidates" && pwd -P)"
  candidate_temp_dir="$(mktemp -d "$candidate_parent/.candidate-${candidate_label}-${candidate_short_sha}.XXXXXX")"
  candidate_temp_app="${candidate_temp_dir}/PetDock.app"

  ditto build/PetDock.app "$candidate_temp_app"
  codesign --verify --deep --strict --verbose=2 "$candidate_temp_app"
  diff -qr build/PetDock.app "$candidate_temp_app"
  cmp build/PetDock.app/Contents/MacOS/PetDock "$candidate_temp_app/Contents/MacOS/PetDock"

  candidate_stamp="$(date '+%Y-%m-%d-%H%M%S')"
  candidate_dir="${candidate_parent}/${candidate_stamp}-${candidate_label}-${candidate_short_sha}"
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

隔离 subshell 中的 `set -euo pipefail` 确保任一前置检查、门禁、复制、签名、内容比较或发布步骤失败时立即以非零状态终止。app 先复制到 `build/candidates/` 下唯一的隐藏临时目录并完成全部验证；验证通过后，以 `mkdir` 原子占有尚不存在的最终目录，再移动 app 并复核正式路径。并发创建或同秒冲突会让 `mkdir` 失败，不覆盖已有目录；`mv -n` 后还必须确认临时 app 已消失。

EXIT trap 使用 macOS 13+ 自带的 BSD `/bin/rm` 清理，并始终保留原命令退出码。执行前同时验证非空路径、词法直属父目录与 `pwd -P` 解析父目录；临时路径还必须使用 `.candidate-` 隐藏名称，最终路径还必须是本轮原子占有的精确目录。因此 cleanup 不接受宽泛路径，也不会清理竞争者目录。若 `/bin/rm` 被安全钩子拦截、返回失败或清理后路径仍存在，必须把错误中报告的**唯一精确残留路径**移到回收站，并禁止报告候选已交付；不依赖 Finder 自动化或 TCC。

即使归档前已经存在可通过签名检查的 staging，也不得跳过本流程中的 `make app`；该命令按 Makefile 删除并重建 staging，避免复用旧 bundle。前后两次 Git 检查证明门禁与构建期间 HEAD 未变化，且 tracked / 非忽略 untracked 状态保持清洁；`codesign` 只验证 app 的签名结构，`diff` 与 `cmp` 只验证它与刚生成的 staging 内容一致。精确来源由 QA 记录把捕获的完整 SHA、上述命令及其实际输出绑定在一起，不能仅凭签名结果推断。

交付报告必须给出完整提交 SHA、归档后的 app 路径、各门禁与 `make app` 的实际结果，以及针对归档路径的 `codesign` 和 staging 内容一致性结果。不能由这些检查推断 app 已启动、TCC 已授权或 UI / 真机交互已通过。可保留 `build/PetDock.app` 供后续 staging 使用，但面向用户的测试说明必须指向归档候选路径。归档过程不得启动或安装 app，也不得写入或覆盖 `/Applications`。

## 风险与边界

- ad-hoc 签名没有稳定的开发者身份，重新签名可能要求重新授予屏幕录制权限；发布时应使用稳定签名或 notarized 构建。
- 屏幕录制权限是窗口枚举和像素探测的前提；无授权时只能依赖自动测试与静态结论。
- `codex app-server` 为 experimental 协议，字段可能随 CLI 版本变化；客户端只解析稳定子集并对缺失字段降级。
- 跨应用 z-order 不能由公开 API 完全控制；产品降级是 `.floating` level 加几何不重叠，而不是私有 API。
- 宠物隐藏、Codex 退出、登录自启和多屏硬件结果必须由具备相应权限的真机 QA 单独记录，不能从本页的自动门禁推断。

## 候选交付边界

本页只描述 `dev` 候选的验收条件。只有在独立 Review 与 QA 针对同一完整提交均为 P0/P1/P2 清零、自动门禁通过、真机项目明确标注结果后，才可将 accepted SHA 停放到对应 `feature/` 分支，再由专门合入会话按项目 `AGENTS.md` 第 1 节从 `feature/` 串行 merge 到本地 `dev`；本页不替代人工合入确认，也不授权向 `main` 推送。合入冲突必须保留双方已验收功能，禁止覆盖解决。
