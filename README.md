# Codex Pet Dock

English | [简体中文](README.zh-CN.md)

> A macOS desktop companion that floats a transparent HUD beneath your Codex desktop pet,
> showing your weekly quota remaining and weekly token usage at a glance.

**Codex Pet Dock** is a macOS desktop companion. It floats a transparent "dock" directly beneath the desktop pet of the Codex desktop app (`/Applications/ChatGPT.app`, bundle id `com.openai.codex`), showing **weekly quota remaining (WEEK LEFT)** and **weekly token usage (WEEK TOKENS)** in real time. Clicking the dock expands a detail card. It automatically follows the pet as it moves, hides in sync when the pet is hidden, and recaptures it when it reappears — with theme switching, a status-bar menu, and launch-at-login support.

All window enumeration and data access use **public APIs only** — Codex is never modified, no credentials are read, and no conversation content is read.

---

## 📌 Origin & Attribution

This project was inspired by [an original WeChat article](https://mp.weixin.qq.com/s/W4kC9enEmvJm2swhM5fbUw). The article's author later released a **Windows** implementation, [hjxccc/codex-pet-dock](https://github.com/hjxccc/codex-pet-dock), which is the original cross-platform reference for this concept.

This repository is an independent **macOS** implementation. It targets a different platform (macOS on Apple Silicon vs. Windows), uses a different technology stack (native Swift/AppKit and public macOS APIs rather than the Windows toolchain), and was developed separately. It is not a port of the Windows project, but shares the same originating inspiration. Thanks to the original author for the idea. (The article's title, author, and content belong to the original source; this document does not reproduce them.)

---

## ✨ Features

- **Transparent dock HUD**: sits right below the pet without overlapping, showing `WEEK LEFT` (including the current period's reset time) and `WEEK TOKENS`; missing data falls back to a `—` placeholder.
- **Detail card**: click the dock to expand/collapse, listing plan, reset time, cache ratio, input, output, session count, last-updated time, and a local-estimate note.
- **Adaptive following**: follows the dock window's native display cadence on macOS 14+; if a visible window temporarily has no screen, it falls back to a repeating timer and reselects the display link when the screen changes. macOS 13 selects that timer from the current screen's refresh capability, rebuilds it after a refresh-capability change, and caps it at 120 Hz. Dense callbacks are coalesced to the latest pending tick. Stationary detection compares against a fixed jitter anchor and keeps the same elapsed-time meaning across 60/120 Hz and irregular cadence before stepping down to a 0.1-second idle check anchored to each full tick's start; if a bubble probe is not due yet, that check uses only the delay still remaining when the tick completes. An overrun queues one immediate latest-only follow-up without replaying missed checks. It hides with the pet when the pet is hidden or Codex quits, and recaptures on reappearance.
- **Session-bubble avoidance**: when a Codex conversation bubble appears beneath the pet, the dock steps down to avoid overlap. Uses `ScreenCaptureKit` (macOS 14+) to detect whether the bubble is actually drawn (alpha-only pixel statistics — no OCR, no image saving, no color/text recording); while a bubble candidate remains, the application-controlled wait before the next permitted probe start is at most 0.1 seconds, subject to strict single-flight capture. Probe cadence and follow scheduling share one monotonic clock, so system-time adjustments cannot accelerate or delay capture. A successful collapse result wakes one coalesced full layout tick so the dock returns beneath an unmoved pet. On macOS 13, before screen-recording access takes effect, or on capture failure, it conservatively avoids; background capture is skipped while preflight access is unavailable. When the pet is near a screen edge, the dock is clamped horizontally to stay fully on-screen (like a message bar hugging the edge).
- **Real data, strict privacy**:
  - `WEEK LEFT`: read from the official weekly quota (`primary` weekly window) via `codex app-server` JSON-RPC.
  - `WEEK TOKENS`: aggregated from token deltas in the local `~/.codex/sessions` logs.
- **Themes**: 3 built-in programmatic themes, plus external JSON themes loaded from Application Support (with a safe allow-list parser and automatic hot-reload on file changes).
- **Status-bar menu**: theme selection, show/hide dock, launch at login, quit.
- **Launch at login**: via the public `SMAppService` (macOS 13+); failures are explained and never crash.

---

## 🖼️ Effect & Interface

<!-- Screenshot placeholder: consider placing "dock beneath the pet" and "expanded detail card" screenshots here.
     This repository intentionally ships no real screenshots; if you contribute one, ensure it contains no real quota, account, or other sensitive information. -->

Both the dock and the detail card are drawn with native AppKit (`NSPanel` + `NSStackView` + `NSTextField`):

- **Dock** (≈ 200×48, translucent rounded):
  - Left column: `WEEK LEFT` title + remaining percentage + current-period reset time (`MM-dd HH:mm`, local timezone).
  - Right column: `WEEK TOKENS` title + weekly cumulative tokens.
  - Click the dock to toggle the detail card.
- **Detail card** (≈ 230×190): plan / reset time / cache ratio / input / output / session count / last-updated, with a "local estimate" note at the bottom.
- **Status bar**: a pawprint icon in the menu bar; see "Themes & Settings" for the menu.

---

## 📋 Requirements

- **macOS 13 (Ventura) or later** (required by `SMAppService` and modern AppKit).
- **Apple Silicon (arm64)**: release builds target arm64.
- **Swift 5.9+ toolchain** (when building from source).
- **Codex desktop app** (`ChatGPT.app`) installed and signed in (`WEEK LEFT` depends on codex having completed its own authentication).
- **Screen-recording permission**: a hard requirement for cross-app window enumeration; see "Privacy & Permissions".

---

## 🔒 Privacy & Permissions

This project follows strict privacy boundaries (pinned by fixture tests):

- **Does not modify** Codex / `ChatGPT.app`.
- **Does not read** `auth.json`, auth tokens, email, or Chrome Profile.
- **Does not read / log / output conversation content.** `WEEK TOKENS` only extracts `timestamp` and a few numeric fields from `last_token_usage` in the logs.
- **Does not exfiltrate data**: all computation and caching happen locally.
- **Uses no private APIs**: window enumeration relies solely on the public `CGWindowListCopyWindowInfo`; no private CGS calls.
- Authentication for `WEEK LEFT` is performed by the `codex` process inside its own trusted environment; this process only exchanges JSON-RPC text over stdio and parses `usedPercent` / `resetsAt` / `windowDurationMins` / `planType` — it never touches credentials.

**Screen-recording permission (TCC)**: `CGWindowListCopyWindowInfo` is the only public API for cross-app window enumeration; macOS filters it to an empty list when ungranted. `PetDock.app` requests access at most once per process and does not enter background `ScreenCaptureKit` capture while preflight access is unavailable, preventing repeated prompts while preserving conservative bubble avoidance and the status-bar warning. Grant **PetDock** under "System Settings › Privacy & Security › Screen Recording", then quit and relaunch the app for access to take effect.

> ⚠️ ad-hoc signing has no team ID, and TCC authenticates by the ad-hoc signature's code-directory hash; every re-signing (e.g. re-running `make app`) changes that hash and invalidates the grant, requiring re-authorization. For production, prefer a stable developer signature or a notarized build.

---

## 📦 Build, Run & Distribution

Run from the repository root:

```sh
make build        # swift build -c release, produces .build/release/PetDock
make app          # assembles build/PetDock.app and ad-hoc signs it (Identifier=io.github.bluesmilery.codexpetdock)
make run          # builds the app and launches it (private log under Application Support/PetDock/Logs)
make diagnose     # builds and runs a one-shot redacted diagnostic (private Diagnostics/diagnose.txt)
pkill -f PetDock  # stop the app
make clean        # clean build artifacts
make clean-logs   # clean the private Application Support runtime / diagnostic logs
```

`make app` writes replaceable staging at `build/PetDock.app`. For a development handoff, archive a fresh, immutable, commit-bound local candidate under a `YYYY-MM-DD-HHmmss-<label>-<shortSHA>` directory and point user-facing test steps to that archived app; follow the [development candidate artifact procedure](docs/verification/dev-candidate.md#开发候选产物归档).

Diagnostic mode (`--diagnose`) enumerates windows, locates the Codex pet, and writes only redacted structure/count information to `~/Library/Application Support/PetDock/Diagnostics/diagnose.txt` — useful for troubleshooting "pet not detected" issues. Titles, owners, WID/PID values, and exact coordinates are not persisted. If that file is not produced, it usually means screen-recording permission has not been granted.

PetDock stores logs and the token cache under its private `~/Library/Application Support/PetDock/` directories (0700 directories, 0600 files). The Codex helper receives a minimal environment and does not inherit API keys, cookies, proxy credentials, or unknown variables; use Codex's own login state rather than environment-variable authentication.

**Distribution**: the current release is an ad-hoc-signed (no team ID), unnotarized arm64 prebuilt package. Exact checksums and download channels are provided with the release notes.

**Preview installation** (not a one-click trusted install):

1. Download `CodexPetDock-0.1.0-macOS-arm64.zip` and extract it.
2. Move `PetDock.app` to `/Applications` (or any fixed location).
3. Because the app is ad-hoc-signed (no Developer ID, not notarized), macOS Gatekeeper may block the first launch. Go to **System Settings › Privacy & Security** and click **Open Anyway** (or "Open Anyway" in the Gatekeeper dialog). See [Apple's guide](https://support.apple.com/guide/mac-help/mh40616/mac) for details.
4. On first launch, grant **Screen Recording** permission (required for cross-app window enumeration) and restart the app.
5. Ensure the `codex` CLI (`@openai/codex`) is installed and signed in — `WEEK LEFT` depends on it being available on the local machine.

---

## 📊 Data Sources & Semantics

Only two pieces of data are surfaced; their fields and semantics are documented in `docs/architecture/data-layer.md`. The example values below are illustrative placeholders, not any real account data.

| Metric | Source | Parsed fields | Example (placeholder) |
| --- | --- | --- | --- |
| `WEEK LEFT` | `codex app-server` JSON-RPC: `account/rateLimits/read` | `primary.usedPercent` / `resetsAt` / `windowDurationMins` (10080 = 7 days = weekly window) / `planType` | `73%` |
| `WEEK TOKENS` | `~/.codex/sessions/**/*.jsonl` (date-bucketed session logs) | Σ `payload.info.last_token_usage.total_tokens` (per-event deltas; verified non-duplicating across sessions) + input / cached / output breakdown | `~1M` |

**Refresh backoff** (`WEEK LEFT` and `WEEK TOKENS` counted independently):

| Consecutive failures | Next refresh interval |
| --- | --- |
| 0 (success) | 5 minutes |
| 1 | 15 minutes |
| 2 | 30 minutes |
| ≥ 3 | 60 minutes |

Refreshing is paused while the pet is not visible and resumes when it reappears.

---

## 🎨 Themes & Settings

**Built-in themes**: Holographic / Warm Gold / Circuit, sharing the same geometry slot (≈ 200×48). Switching changes only colors, corner radius, border, and font — never layout.

**External themes**: drop a JSON file into `~/Library/Application Support/PetDock/themes/` and it hot-reloads on change. Minimal example (fields can be trimmed down to just the name and three colors):

```json
{
  "name": "My Theme",
  "background": [0.10, 0.18, 0.28, 0.60],
  "accent":     [0.90, 0.80, 0.70, 1.00],
  "label":      [1.00, 1.00, 1.00, 1.00],
  "cornerRadius": 10,
  "borderWidth": 1,
  "font": "rounded",
  "badge": "logo.png"
}
```

**Safe allow-list** (see `Sources/PetDock/Theme.swift`): colors only accept `[r,g,b,a]` with each component ∈ [0,1]; fonts only accept `system` / `rounded` / `monospace`; badges only accept a bare filename `*.png` in the same directory. The parser rejects URLs, path separators, script / CSS / JS fragments, nested objects, and dangerous keywords.

**Status-bar menu**: pawprint icon → **Theme** (submenu, current item checked) / **Show · Hide dock** / **Launch at login** (checked, reflecting the real `SMAppService` state) / **Quit PetDock** (⌘Q).

**Persisted preferences** (`UserDefaults`): selected theme, dock visibility, etc. The launch-at-login state is always taken from the system login items and is not cached separately, avoiding dual-source inconsistency.

---

## 📚 Documentation

The [documentation catalog](docs/README.md) is the single entry point for architecture facts, development workflow, and candidate verification evidence. `.trellis/spec/macos/` contains executable development rules, while `.trellis/tasks/` contains per-task requirements and evidence. When behavior, interfaces, data boundaries, verification status, or development gates change, record `Docs Impact: none | update | new` and update the relevant source in the same commit.

## 🧪 Testing

All tests are pure-function / fixture tests, compiled with `swiftc` against the real sources — **no screen-recording permission and no network required**:

```sh
make test-ui      # pet detection + geometry + follow state machine + bubble visibility + obstacle avoidance (bubble + control button) + clamp + logger rotation + FollowTickPlanner
make test-data    # data layer: weekly aggregation / incremental cache / backoff / pause / desensitization / codex path resolve / rpc stdio e2e
make test-shell   # theme safe-parsing / settings persistence / hot-reload / autostart state mapping / StatusBar TCC hint
make test-privacy # runtime path containment / private storage / helper environment / cache privacy fixtures
make docs-check   # offline public-Markdown links / catalog / legacy-path / privacy gate
make test-docs    # documentation checker unit tests
make test         # full suite (docs gates + privacy + Swift UI/data/shell fixtures)
```

Verification criteria and candidate evidence are documented in [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md); actual current counts come from the test sources and the latest command output. Detailed bubble-visibility coverage is described in [`docs/architecture/dock-obstacle-avoidance.md`](docs/architecture/dock-obstacle-avoidance.md) and defined by `tests/main.swift`.

Privacy boundaries are pinned by fixture tests: data-layer results contain no conversation-content decoys and no credentials. See `docs/architecture/data-layer.md` and `tests/`.

---

## ⚠️ Known Limitations

- **Unstable ad-hoc-signing TCC**: each re-signing changes the code-directory hash, invalidating screen-recording authorization, which must be re-granted.
- **Screen-recording permission is a hard requirement**: without it, Codex windows can't be enumerated and the dock won't appear.
- **`codex app-server` is experimental**: protocol fields may change across codex versions; a stable subset is parsed with graceful degradation for missing fields.
- **Cross-app relative z-order is not controllable**: mitigated with a `.floating` level and non-overlapping geometry.
- **Limited platform scope**: currently only Apple Silicon on macOS 13+, and only for the Codex desktop pet.
- **Launch at login requires running as an `.app`**: `SMAppService` is unavailable for a raw command-line run (not an `.app` bundle); this is expected.
- **Some interactions await real-device verification**: UI automation is blocked by system Accessibility; some manual-interaction items are not yet verified one by one on a real device (see `docs/verification/dev-candidate.md`).

---

## 🤝 Contributing

Issues and pull requests are welcome. Before submitting, please ensure:

1. `make test` (docs gate + Swift suite) passes;
2. the change introduces no code that reads credentials or conversation content, and no private-API calls;
3. record `Docs Impact: none | update | new` and update the catalog when documentation changes;
4. commit messages follow Conventional Commits.

Project layout and key files:

| File | Role |
| --- | --- |
| `Sources/PetDock/main.swift` | Entry: `--diagnose` diagnostic mode / run mode (follow + data + shell) |
| `Sources/PetDock/PetTracker.swift` | bundle-id location + Quartz enumeration + pet detection (Mascot-first) |
| `Sources/PetDock/Geometry.swift` | Quartz ↔ AppKit coordinate conversion (multi-display / negative coords) |
| `Sources/PetDock/Follower.swift` | Adaptive follow state machine (pure function `decide`) |
| `Sources/PetDock/DockPanel.swift` / `DockView.swift` | Transparent dock `NSPanel` + view |
| `Sources/PetDock/DetailPanel.swift` | Detail card |
| `Sources/PetDock/Data/` | Data layer (quota client / log reader / service) |
| `Sources/PetDock/Theme.swift` | Themes: built-in + external safe-parsing + hot-reload |
| `Sources/PetDock/StatusBar.swift` | Status-bar menu |
| `Sources/PetDock/AutoStart.swift` | Launch at login (`SMAppService`) |
| `Sources/PetDock/Settings.swift` | `UserDefaults` preferences |

More design rationale in [`docs/architecture/pet-window-detection.md`](docs/architecture/pet-window-detection.md), [`docs/architecture/data-layer.md`](docs/architecture/data-layer.md), [`docs/architecture/dock-obstacle-avoidance.md`](docs/architecture/dock-obstacle-avoidance.md), and [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md).

---

## 🛠️ Development workflow

- `main` is the **only stable branch** published to GitHub; any commit entering `main` requires **manual confirmation**.
- `dev` is the local integration branch, used to merge feature branches and keep `make test` green.
- New work happens on `feature/*` branches cut from `dev`, merged back into `dev` when done.
- Merging `dev` → `main`, and pushing `main` to GitHub, both require **manual confirmation** — never automated.
- **Do not** use `git push --all`, to avoid pushing local or temporary branches to the remote.
- No remote URL or CI is fabricated in this document; all changes are validated by local `swift build -c release` and `make test` (docs gate + Swift suite). Current test-count evidence lives in [`docs/verification/dev-candidate.md`](docs/verification/dev-candidate.md).

---

## 📄 License

This project is open-sourced under the [MIT License](LICENSE), Copyright (c) 2026 bluesmilery. The MIT license grants the rights to use, copy, modify, merge, publish, distribute, sublicense, and sell the software; see the full terms in the root [`LICENSE`](LICENSE) file.

### Unofficial disclaimer

- This is an **unofficial** community project; it is not affiliated with OpenAI and is not endorsed or sponsored by OpenAI or any third party.
- **OpenAI**, **Codex**, **ChatGPT**, and other names and trademarks belong to their respective owners; this project only provides compatibility and claims no rights over any third-party trademark.
- The MIT license **grants only copyright-related rights in this project's code, and no third-party trademark rights.**
