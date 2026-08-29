# Ultra Controller Implementation Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a native, Apple-silicon-only macOS 27 controller for Bose QuietComfort Ultra Headphones Gen 1 through five independently reviewable implementation plans.

**Architecture:** Development stays in the `DenseDevKev/bozo_cc` fork so the Rust implementation and BMAP documentation remain available as a protocol oracle. The shipping application lives in the isolated `apps/macos/UltraController` subtree, uses a pure-Swift `HeadphoneCore`, and owns exactly one CoreBluetooth session in the main app process; this subtree can later be extracted into a standalone repository without changing module interfaces.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreBluetooth, WidgetKit Controls, App Intents, ServiceManagement, XCTest, Xcode 27, `xcodebuild`, XcodeGen as a development-only project generator, Rust/Cargo parity tests, shell release scripts.

**Spec:** `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`

## Global Constraints

- Support only Bose QuietComfort Ultra Headphones, first generation.
- Target macOS 27.0 or newer and `arm64` only.
- Build the native app under `apps/macos/UltraController`; do not link or launch a Rust binary from the app.
- Keep the existing Rust workspace buildable and use it only as a protocol reference and parity-test oracle.
- Use public Apple frameworks only; no Electron, web view, Node process, local server, XPC helper, privileged helper, or private framework.
- Enable App Sandbox from the first runnable app build.
- The main app is the sole Bluetooth owner; the WidgetKit extension never creates a `CBCentralManager`.
- Keep v1 local-only: no account, cloud sync, analytics, telemetry, advertisements, or network entitlement.
- The headphones are authoritative for operational state and stored modes; do not create an app-only preset database.
- Treat every mutation as pending until a BMAP response, follow-up query, or documented expected disconnect confirms its outcome.
- Expose advanced mode fields only after physical-device validation proves deterministic read, write, read-back, and safe reversal.
- Keep Power Off out of Control Center.
- Preserve upstream MIT notices and include an independent/non-Bose affiliation statement.
- Execute from an isolated Git worktree created from `design/qc-ultra-macos-app`.

---

## Plan Set and Dependencies

| Order | Plan | Runnable checkpoint |
|---|---|---|
| 1 | [`2026-08-29-ultra-controller-01-foundation-protocol.md`](./2026-08-29-ultra-controller-01-foundation-protocol.md) | Sandboxed app skeleton builds; Swift BMAP codec matches Rust fixtures; a signed probe reads the physical headset and safely restores essential settings. |
| 2 | [`2026-08-29-ultra-controller-02-session-connectivity.md`](./2026-08-29-ultra-controller-02-session-connectivity.md) | One tested `HeadphoneSession` connects, synchronizes state, reconnects, and performs essential verified commands. |
| 3 | [`2026-08-29-ultra-controller-03-native-surfaces.md`](./2026-08-29-ultra-controller-03-native-surfaces.md) | A non-terminal user can onboard, use the desktop Overview, configure Settings, and control the headset from the app menu bar. |
| 4 | [`2026-08-29-ultra-controller-04-advanced-modes-system-controls.md`](./2026-08-29-ultra-controller-04-advanced-modes-system-controls.md) | Gate A-admitted mode editing works; Gate B selects `directMainProcess`, `openAppAlways`, or `controlsExcluded`. |
| 5 | [`2026-08-29-ultra-controller-05-release-hardening.md`](./2026-08-29-ultra-controller-05-release-hardening.md) | Accessibility, diagnostics, performance, signing, optional notarization, and physical release evidence pass for a v1 candidate. |

Do not start a later plan until the prior plan's checkpoint commands pass and its physical-device evidence is committed. Plans 4 and 5 depend on the final macOS 27 SDK for system-control release validation; protocol and ordinary app work may proceed while the relevant API remains beta.

### Task 0: Create the implementation worktree and branch

**Files:**
- Read: `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`
- Read: all five plan documents in `docs/superpowers/plans/`

**Interfaces:**
- Consumes: approved design branch `design/qc-ultra-macos-app`.
- Produces: isolated worktree on branch `feat/ultra-controller`.

- [ ] **Step 1: Fetch the approved design branch**

```bash
git fetch origin design/qc-ultra-macos-app
git rev-parse --verify origin/design/qc-ultra-macos-app
```

Expected: a commit SHA and exit 0.

- [ ] **Step 2: Create isolated worktree**

```bash
git worktree add ../bozo_cc-ultra-controller \
  -b feat/ultra-controller \
  origin/design/qc-ultra-macos-app
cd ../bozo_cc-ultra-controller
git branch --show-current
```

Expected: `feat/ultra-controller`.

- [ ] **Step 3: Verify starting tree**

```bash
git status --short
cargo test --workspace
```

Expected: clean tree and existing Rust tests pass before Swift work.

- [ ] **Step 4: Record base**

```bash
git rev-parse HEAD > /tmp/ultra-controller-base-sha.txt
cat /tmp/ultra-controller-base-sha.txt
```

Expected: matches `origin/design/qc-ultra-macos-app`.

### Task 1: Execute the five plans in order

**Files:**
- Modify: only files named by active plan.
- Do not modify: `crates/bozo`, `crates/bozod`, or unrelated Rust behavior unless a plan names it.

**Interfaces:**
- Consumes: prior plan's checkpoint/public interfaces.
- Produces: buildable commits on `feat/ultra-controller`.

- [ ] **Step 1: Complete Plan 1**

Do not proceed unless Swift tests, Rust parity, app build, and signed physical probe evidence pass.

- [ ] **Step 2: Complete Plan 2**

Do not proceed unless fake-transport tests, real CoreBluetooth session, essential read-back, reconnect, and sleep/wake pass.

- [ ] **Step 3: Complete Plan 3**

Do not proceed unless onboarding, Overview, Settings, app-menu-bar lifecycle, launch-at-login, localization, and accessibility smoke tests pass.

- [ ] **Step 4: Complete Plan 4 and both gates**

Commit Gate A/B evidence. Omit every failed/unvalidated advanced field. Select exactly one Gate B production policy: `directMainProcess`, `openAppAlways`, or `controlsExcluded`. Never guess process residency and never add a second BLE owner.

- [ ] **Step 5: Complete Plan 5**

Release record contains exact commands/test counts, firmware, performance measurements, signing/notarization status, physical results, and every approved deviation.

### Task 2: Decide whether to extract the app into a standalone repository

**Files:**
- Create only after complete alpha: `docs/release/repository-extraction-decision.md`

**Interfaces:**
- Consumes: stable isolated app subtree/public HeadphoneCore interfaces.
- Produces: explicit keep-in-fork or standalone decision; no implicit move.

- [ ] **Step 1: Measure coupling**

```bash
git log --name-only --pretty=format: -- apps/macos/UltraController fixtures/bmap \
  | sed '/^$/d' | sort -u
```

Expected: production Swift stays in isolated subtree; shared dependencies are neutral fixtures/attribution.

- [ ] **Step 2: Write decision record**

```markdown
# Repository Extraction Decision
## Current coupling
## Benefits of remaining in the Bozo fork
## Benefits of a standalone Ultra Controller repository
## Release and issue-tracker implications
## Decision
## Migration command and rollback
```

- [ ] **Step 3: Keep extraction outside v1 unless explicitly approved**

Do not run `git filter-repo`, subtree split, or repository creation in Plans 1–5.

- [ ] **Step 4: Commit decision**

```bash
git add docs/release/repository-extraction-decision.md
git commit -m "docs: decide Ultra Controller repository strategy"
```
