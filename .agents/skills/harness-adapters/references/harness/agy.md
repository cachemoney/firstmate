# Antigravity CLI

Antigravity's `agy` TUI, verified end to end on 2026-09-10 with agy 1.2.0 on Linux through the Herdr backend, and verified as a PRIMARY and SECONDMATE harness on 2026-09-17 with bounded foreground checkpoint supervision and turn-end guard backstops.
`../../../../../docs/verification/agy.md` owns crewmate/scout verification facts, and `../../../../../docs/verification/agy-primary.md` owns primary and secondmate supervision and lock contracts.

## Operating facts

| Fact | Value |
|---|---|
| Binary | Absolute `agy` from `PATH`, refused if absent; a Go-compiled single binary, so the live process name is exactly `agy` with `argv[0]=agy`. |
| Launch | `agy --prompt-interactive "<brief>" --model <id> --effort <level> --dangerously-skip-permissions`, with the resolved absolute binary; the brief auto-submits with no extra Enter. The spawn pre-registers the worktree in agy's trust store first, then waits for a busy turn (answering the folder-trust dialog if it renders anyway) before reporting success. |
| Busy state | No hook or plugin writer, so nothing is armed and no record is seeded; on Herdr the native `working` status classifies busy, and everywhere else the `agy-regex` rendered-tail fallback in `../../../../../bin/fm-busy-lib.sh` does. |
| Rendered tail | Busy status row carries `esc to cancel` on the left; the idle row shows `? for shortcuts` instead. The `Generating...` word beside the braille spinner is free-floating output and is not a signal. |
| Turn end | No turn-end hook or notification touch exists; completion arrives through the worker status protocol and, on Herdr, the native return to `idle`. |
| Exit | `/quit`, one Enter; the process exits. |
| Interrupt | Single `Escape`, which prints the Interrupted row and leaves an idle composer with no repollution, so no clear key follows. |
| Skill | No verified slash-skill form; use natural language. |
| Autonomy | `--dangerously-skip-permissions` auto-approves tool calls for the run. |
| Marker | None; a live TUI carries no `AGY_*` or `ANTIGRAVITY_*` variable. |
| Resume | `--continue` and `--conversation` exist but carry no verified pane-resume contract; use deterministic relaunch. |
| Model | `--model <id>` with the bare catalog id from `agy models` (for example `gemini-3.8-flash-high`); `bin/fm-spawn.sh` refuses a requested id a reachable listing omits. The listing is a remote fetch, so the probe runs stdin-detached under the shared hard bound and an unreachable or hung listing launches unvalidated with a notice. |
| Effort | `--effort low\|medium\|high`; `xhigh` and `max` stay in task metadata under the record-and-omit contract. |
| Composer | Borderless bare `>` row, which the shared classifier reads as `unknown` under the dead-shell rule, never `empty`; steering confirms delivery through native agent-state and the delivery footer instead, the cursor precedent. |

## Trust, and where the decision persists

Every task worktree is a path agy has never seen, so an unregistered launch stops on `Do you trust the contents of this project?` with the safe choice `Yes, I trust this folder` preselected, and an unanswered dialog sends the turn into agy's scratch directory instead of the worktree.
There is no launch flag that suppresses the dialog, but agy honours a `trustedWorkspaces` entry in the captain's own `~/.gemini/antigravity-cli/settings.json` written ahead of launch (verified live), so `../../../../../bin/fm-spawn.sh` pre-registers the worktree through `../../../../../bin/fm-agy-trust.sh` before launch, the claude shape: the helper refuses anything but a linked worktree of the spawning project, records both the logical pane path and its resolved form because agy compares the logical cwd, and preserves every other key in the store.
The post-launch readiness gate is the backstop: it answers a dialog that renders anyway with a single Enter, then requires a busy verdict (Herdr's native `working` status or the pinned `esc to cancel` row) before the spawn reports success, and on a path that was not pre-registered it never counts a busy verdict as ready until the dialog has been answered, because Herdr's native verdict can precede the dialog.
A pane whose brief cannot be confirmed to run in the worktree fails the spawn, records the failure in the task status, and closes the endpoint.
Never steer into a pane still showing the dialog; a spawn that reported success has already cleared it.

## Credential precondition

A verified agy worker ran under a signed-in Google account with no key export and no dialog.
The unauthenticated failure mode was not observed, so treat any auth prompt or refusal as a credential blocker under `../../../../../AGENTS.md` section 9, fix the environment, and retire the endpoint rather than typing into it.

## Detection

Detected by ancestry alone: `../../../../../bin/fm-harness.sh` matches the anchored process name `agy`, never `*agy*`.
No environment marker is promoted: `AGENT=1` observed on a live TUI is an inherited launcher value, not an agy identity, and agy does not clear an inherited `CLAUDECODE` - but a structural agy ancestor now outranks that retained marker, which `../../../../../bin/fm-harness.sh` decides without depending on the spawn's own launch-boundary marker clearing.
agy is an authorized session-lock owner in `../../../../../bin/fm-session-lock-lib.sh` (matching anchored `^agy$` in `FM_HARNESS_RE` and listed in `FM_HARNESS_NAMES`).

## Worker busy state and turn end

`../../../../../bin/fm-spawn.sh` arms no busy generation for agy and writes no sidecar, exactly because no writer could ever clear a seeded record.
`fm_busy_agy_tail_busy` matches the pinned `esc to cancel` status row alone, hardcoded with no environment override, and `fm_busy_classify` reports `unknown agy-regex` rather than idle when it is absent, because a long turn can scroll the marker out of the captured tail.
Teardown removes nothing agy-specific because the spawn leaves nothing behind.

## Primary and secondmate integration

Verified as a primary session supervisor and secondmate harness.
`../../../../../docs/supervision-protocols/agy.md` defines the bounded foreground checkpoint protocol (`bin/fm-watch-checkpoint.sh --seconds "${FM_AGY_WATCH_CHECKPOINT:-180}"`), drain-first handling via `bin/fm-wake-drain.sh`, and wake acknowledgement (`--ack-through`).
The turn-end guard backstop in `../../../../../bin/fm-turnend-guard.sh` blocks unmonitored completion when tasks are in flight, emitting the exact foreground checkpoint repair directive (`repair missing watcher supervision with a foreground checkpoint: bin/fm-watch-checkpoint.sh --seconds 180.`).
Secondmates launch with `--prompt-interactive "<charter>"`, `--dangerously-skip-permissions`, pre-registered home workspace trust via `../../../../../bin/fm-agy-trust.sh --secondmate-home`, and thread model/effort tokens from `config/secondmate-harness`.
