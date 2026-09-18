# Verification: the agy (Antigravity CLI) primary and secondmate harness

Active empirical facts and contracts for firstmate's agy adapter operating as a primary session supervisor and secondmate instance.
This record complements [`agy.md`](agy.md), which documents the crewmate and scout adapter mechanics.
The skill reference at [`.agents/skills/harness-adapters/references/harness/agy.md`](../../.agents/skills/harness-adapters/references/harness/agy.md) owns the operator-facing facts; this document owns how the primary and secondmate guarantees were established and verified.

## Subject

| Field | Value |
|---|---|
| Version | `agy 1.2.0` and `agy 1.2.1` |
| Verified | 2026-09-17 |
| Binary | Linux x64 Go-compiled ELF executable (`agy`) |
| Supervision model | Bounded foreground checkpoints (`docs/supervision-protocols/agy.md`) |
| Lock role | Authorized session lock owner (`bin/fm-session-lock-lib.sh`) |
| Secondmate role | Verified secondmate harness (`bin/fm-spawn.sh`, `bin/fm-control-lib.sh`) |

## 1. Session Lock Ownership and Process Ancestry

In Firstmate, only verified primary harnesses may acquire and own the fleet session lock (`state/.lock`).

- **Ancestry Detection**: `bin/fm-session-lock-lib.sh` defines `FM_HARNESS_RE` and `FM_HARNESS_NAMES`. The anchored pattern `^agy$` and literal name `agy` authorize any process tree rooted at an `agy` binary to claim session-lock ownership.
- **Process Verification**: `fm_harness_pid_alive` and `fm_harness_ancestry_pid` inspect `ps -o comm=` and `ps -o args=` to ensure that sub-processes, shell wrappers, or hooks invoked under `agy` resolve ownership back to the parent `agy` PID.
- **Verification**: Covered by `test_agy_session_is_identified` in `tests/fm-session-lock-ancestry.test.sh` and `test_agy_primary_session_lock_ownership` in `tests/fm-agy-primary.test.sh`.

## 2. Primary Supervision Protocol

Because `agy` exposes hook points (`PreToolUse`, `PostToolUse`, `Stop`) but does not provide an in-process native async wake injection channel or custom extension runtime (unlike Claude's Stop-hook park or Pi/omp extension loops), `agy` operates under the **bounded foreground checkpoint** protocol modeled after Codex.

- **Protocol Specification**: [`docs/supervision-protocols/agy.md`](../supervision-protocols/agy.md) sets:
  1. Mandatory wake drain at session start and before checkpoints via `bin/fm-wake-drain.sh`.
  2. Bounded foreground checkpoints via `bin/fm-watch-checkpoint.sh --seconds "${FM_AGY_WATCH_CHECKPOINT:-180}"`.
  3. Strict prohibition of background shell execution (`&`) or uncoordinated `bin/fm-watch-arm.sh` calls.
  4. Immediate processing of emitted wake signals (`signal:`, `stale:`, `check:`, `heartbeat`) followed by wake acknowledgement (`--ack-through`).
  5. Handling of checkpoint expiration (exit code 124 or `checkpoint:` output) by draining queues and continuing to the next checkpoint.
- **Instruction Rendering**: `bin/fm-supervision-instructions.sh --harness agy` emits the `SUPERVISION OPERATING INSTRUCTIONS` block with the agy protocol snippet and the ordinary wake directive:
  `- Ordinary wake: take the next foreground bin/fm-watch-checkpoint.sh checkpoint as directed below.`
- **Repair Line**: `bin/fm-supervision-instructions.sh --harness agy --repair-line` outputs the exact repair instruction:
  `repair missing watcher supervision with a foreground checkpoint: bin/fm-watch-checkpoint.sh --seconds 180.`

## 3. Turn-End Guard and Backstop

To protect fleet integrity during autonomous or human-assisted runs:

- **Hook Evaluation**: `bin/fm-turnend-guard.sh` evaluates the health of the background watcher when a turn attempts to complete.
- **Fail-Closed Blocking**: If tasks remain in flight (`state/*.meta`) and watcher supervision is absent or the beacon has expired, `fm-turnend-guard.sh` exits with code 2 (blocked).
- **Agy-Specific Diagnostic**: Under an `agy` primary, the guard renders the exact `agy` repair line directing the agent to take a foreground checkpoint rather than attempting unsupported background arming.
- **Verification**: Verified by `test_hook_blocks_with_agy_checkpoint_repair_reason` in `tests/fm-turnend-guard.test.sh`.

## 4. Secondmate Launch and Routing

A secondmate runs an isolated Firstmate home in another workspace or pane, acting as a sub-supervisor.

- **Spawn Unblock**: `bin/fm-spawn.sh` accepts `--harness agy --secondmate` without refusal. The former crewmate-only refusal in `bin/fm-spawn.sh` and kind-capability restriction in `bin/fm-control-lib.sh` have been removed for `agy`.
- **Home Trust Pre-Registration**: `bin/fm-agy-trust.sh` supports `--secondmate-home <home> <id>`. Before spawning an `agy` secondmate, `bin/fm-spawn.sh` verifies the existence of `.fm-secondmate-home`, ensures directory safety (rejecting external symlinks), and appends the secondmate home path to `trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json`.
- **Launch Contract**: The secondmate launches with `--prompt-interactive "<charter>"`, `--dangerously-skip-permissions`, and model/effort parameters resolved from `config/secondmate-harness`.
- **Cross-Home Messaging**: `bin/fm-send.sh` correctly tags secondmate inputs with the `[fm-from-firstmate]` correlation marker and newline preservation.
- **Parent Status Reporting**: Secondmate task status and state transitions reflect across homes without collision.
- **Verification**: Verified in `tests/fm-secondmate-harness.test.sh`, `tests/fm-agy-harness.test.sh`, and `tests/fm-send-secondmate-marker.test.sh`.

## 5. Control Plane Mechanics

Control mechanics for `agy` are registered in `bin/fm-control-lib.sh`:

- **Interruption**: Sends `Escape` (count: 1). Does not leave prompt pollution, requiring no clear key.
- **Exit**: Sends `/quit` followed by Enter. Cleanly terminates the `agy` process.
- **Kind Capabilities**: `fm_control_harness_supports_kind` returns success for both `primary` and `secondmate`.
- **Verification**: Verified in `tests/fm-control.test.sh`.
