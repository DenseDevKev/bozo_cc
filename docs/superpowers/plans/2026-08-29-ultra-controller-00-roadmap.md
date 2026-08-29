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
| 1 | [`2026-08-29-ultra-controller-01-foundation-protocol.md`](./2026-08-29-ultra-controller-01-foundation-protocol.md) | Sandboxed app skeleton builds; Swift BMAP codec matches Rust fixtures; a debug probe reads the physical headset. |
| 2 | [`2026-08-29-ultra-controller-02-session-connectivity.md`](./2026-08-29-ultra-controller-02-session-connectivity.md) | One tested `HeadphoneSession` connects, synchronizes state, reconnects, and performs essential verified commands. |
| 3 | [`2026-08-29-ultra-controller-03-native-surfaces.md`](./2026-08-29-ultra-controller-03-native-surfaces.md) | A non-terminal user can onboard, use the desktop Overview, configure Settings, and control the headset from the app menu bar. |
| 4 | [`2026-08-29-ultra-controller-04-advanced-modes-system-controls.md`](./2026-08-29-ultra-controller-04-advanced-modes-system-controls.md) | Validated advanced mode editing works; Control Center uses the measured main-process lifecycle or the approved open-app fallback. |
| 5 | [`2026-08-29-ultra-controller-05-release-hardening.md`](./2026-08-29-ultra-controller-05-release-hardening.md) | Accessibility, diagnostics, performance, signing, notarization, and the physical release checklist pass for a v1 candidate. |

Do not start a later plan until the prior plan's checkpoint commands pass and its physical-device evidence is committed. Plans 4 and 5 depend on the final macOS 27 SDK for Control Center release validation; protocol and ordinary app work may proceed while that API remains beta.

### Task 0: Create the implementation worktree and branch

**Files:**
- Read: `docs/superpowers/specs/2026-08-29-qc-ultra-macos-controller-design.md`
- Read: all five plan documents in `docs/superpowers/plans/`

**Interfaces:**
- Consumes: approved design branch `design/qc-ultra-macos-app`.
- Produces: isolated worktree on branch `feat/ultra-controller`.

- [ ] **Step 1: Fetch the approved design branch**

Run:

```bash
git fetch origin design/qc-ultra-macos-app
git rev-parse --verify origin/design/qc-ultra-macos-app
```

Expected: the second command prints a commit SHA and exits 0.

- [ ] **Step 2: Create the isolated worktree**

Run from the existing checkout:

```bash
git worktree add ../bozo_cc-ultra-controller \
  -b feat/ultra-controller \
  origin/design/qc-ultra-macos-app
cd ../bozo_cc-ultra-controller
```

Expected: `git branch --show-current` prints `feat/ultra-controller`.

- [ ] **Step 3: Verify the starting tree**

Run:

```bash
git status --short
cargo test --workspace
```

Expected: the working tree is clean and all existing Rust tests pass before Swift files are added.

- [ ] **Step 4: Record the implementation base**

Run:

```bash
git rev-parse HEAD > /tmp/ultra-controller-base-sha.txt
cat /tmp/ultra-controller-base-sha.txt
```

Expected: the printed SHA matches `origin/design/qc-ultra-macos-app`.

### Task 1: Execute the five plans in order

**Files:**
- Modify: only the files named by the active plan.
- Do not modify: `crates/bozo`, `crates/bozod`, or unrelated Rust behavior unless a plan explicitly names the file.

**Interfaces:**
- Consumes: the checkpoint and public interfaces produced by the prior plan.
- Produces: a sequence of buildable commits on `feat/ultra-controller`.

- [ ] **Step 1: Complete Plan 1 and run its full checkpoint**

Run the commands under Plan 1's final verification task. Do not proceed unless Swift tests, Rust parity tests, the app build, and the physical read-only probe evidence all pass.

- [ ] **Step 2: Complete Plan 2 and run its full checkpoint**

Run the commands under Plan 2's final verification task. Do not proceed unless fake-transport session tests, the real CoreBluetooth connection, essential command read-back, reconnect, and sleep/wake tests pass.

- [ ] **Step 3: Complete Plan 3 and run its full checkpoint**

Run the commands under Plan 3's final verification task. Do not proceed unless onboarding, Overview, Settings, app-menu-bar lifecycle, launch-at-login, and UI accessibility smoke tests pass.

- [ ] **Step 4: Complete Plan 4 and run both feasibility gates**

Commit the Gate A and Gate B evidence documents. Omit any advanced field that fails Gate A. Use the open-app fallback for any lifecycle state that fails Gate B; never add a second BLE owner.

- [ ] **Step 5: Complete Plan 5 and produce the release report**

The release report must contain exact test commands, physical firmware version, Instruments measurements, signing/notarization results, and any accepted deviation from the performance targets.

### Task 2: Decide whether to extract the app into a standalone repository

**Files:**
- Create only after the v1 alpha checkpoint: `docs/release/repository-extraction-decision.md`

**Interfaces:**
- Consumes: stable `apps/macos/UltraController` subtree and public `HeadphoneCore` interfaces.
- Produces: an explicit keep-in-fork or extract-to-standalone decision; no code move occurs implicitly.

- [ ] **Step 1: Measure coupling after the first complete alpha**

Run:

```bash
git log --name-only --pretty=format: -- apps/macos/UltraController fixtures/bmap \
  | sed '/^$/d' | sort -u
```

Expected: production Swift files remain inside `apps/macos/UltraController`; shared dependencies are limited to neutral fixtures and documented attribution.

- [ ] **Step 2: Write the decision record**

Create `docs/release/repository-extraction-decision.md` with exactly these headings:

```markdown
# Repository Extraction Decision

## Current coupling
## Benefits of remaining in the Bozo fork
## Benefits of a standalone Ultra Controller repository
## Release and issue-tracker implications
## Decision
## Migration command and rollback
```

- [ ] **Step 3: Keep extraction outside v1 unless the decision explicitly approves it**

Do not use `git filter-repo`, subtree split, or repository creation as part of implementation plans 1–5. The app's isolated layout preserves the option without delaying a personal alpha.

- [ ] **Step 4: Commit the decision record**

```bash
git add docs/release/repository-extraction-decision.md
git commit -m "docs: decide Ultra Controller repository strategy"
```
