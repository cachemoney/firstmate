#!/usr/bin/env bash
# Behavior tests for Antigravity CLI (agy) as a Firstmate PRIMARY and SECONDMATE
# harness (docs/verification/agy-primary.md, docs/supervision-protocols/agy.md,
# bin/fm-session-lock-lib.sh, bin/fm-supervision-instructions.sh,
# bin/fm-turnend-guard.sh, bin/fm-control-lib.sh, bin/fm-spawn.sh).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-agy-primary)
fm_git_identity fmtest fmtest@example.invalid

LOCK_LIB="$ROOT/bin/fm-session-lock-lib.sh"
CONTROL_LIB="$ROOT/bin/fm-control-lib.sh"
SUPERVISION_SH="$ROOT/bin/fm-supervision-instructions.sh"
TURNEND_GUARD_SH="$ROOT/bin/fm-turnend-guard.sh"
TRUST_SH="$ROOT/bin/fm-agy-trust.sh"
SPAWN_SH="$ROOT/bin/fm-spawn.sh"

lib_eval() {  # <fakebin> <expression>
  local fakebin=$1 expr=$2
  PATH="$fakebin:$PATH" bash -c "
    . \"\$0\"
    kill() { return 0; }
    $expr
  " "$LOCK_LIB"
}

make_primary_dir() {
  local dir=$1
  mkdir -p "$dir/state" "$dir/bin" "$dir/docs"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m init
  : > "$dir/AGENTS.md"
  cp "$ROOT/bin/fm-turnend-guard.sh" "$dir/bin/fm-turnend-guard.sh"
  cp "$ROOT/bin/fm-supervision-instructions.sh" "$dir/bin/fm-supervision-instructions.sh"
  cp "$ROOT/bin/fm-session-lock-lib.sh" "$dir/bin/fm-session-lock-lib.sh"
  cp "$ROOT/bin/fm-harness.sh" "$dir/bin/fm-harness.sh"
  cp "$ROOT/bin/fm-primary-scope-lib.sh" "$dir/bin/fm-primary-scope-lib.sh"
  cp "$ROOT/bin/fm-supervision-lib.sh" "$dir/bin/fm-supervision-lib.sh"
  cp "$ROOT/bin/fm-wake-lib.sh" "$dir/bin/fm-wake-lib.sh"
  cp "$ROOT/bin/fm-hook-host-lib.sh" "$dir/bin/fm-hook-host-lib.sh"
  cp "$ROOT/bin/fm-operational-input.sh" "$dir/bin/fm-operational-input.sh"
  cp -R "$ROOT/docs/supervision-protocols" "$dir/docs/supervision-protocols"
  chmod +x "$dir"/bin/*.sh
  printf '%s\n' "$dir"
}

test_agy_primary_session_lock_ownership() {
  local dir fakebin got
  dir="$TMP_ROOT/session-lock"
  fakebin=$(fm_fakebin "$dir")
  mkdir -p "$dir/state"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  750:comm=) printf '%s\n' agy ;;
  750:args=) printf '%s\n' 'agy' ;;
  750:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' 'bash script.sh' ;;
  *:ppid=) printf '%s\n' 750 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '750\n' > "$dir/state/.lock"

  got=$(lib_eval "$fakebin" 'fm_harness_ancestry_pid') \
    || fail "the agy session was not found in ancestry"
  [ "$got" = 750 ] || fail "ancestry resolved '$got', expected agy session pid 750"

  lib_eval "$fakebin" 'fm_harness_pid_alive 750' \
    || fail "a live agy session was not recognized as a harness"

  lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" \
    || fail "the agy session holding the lock did not recognize itself as owner"

  pass "session-lock: agy session is authorized and identified as session lock owner"
}

test_agy_primary_supervision_instructions() {
  local out
  out=$("$SUPERVISION_SH" --harness agy)
  assert_contains "$out" "SUPERVISION OPERATING INSTRUCTIONS - primary harness: agy" \
    "supervision instructions header missing agy harness"
  assert_contains "$out" "Mode: Antigravity CLI (agy) foreground checkpoint." \
    "supervision instructions missing agy checkpoint mode"
  assert_contains "$out" "bin/fm-watch-checkpoint.sh --seconds" \
    "supervision instructions missing watch-checkpoint command"
  assert_contains "$out" "- Ordinary wake: take the next foreground bin/fm-watch-checkpoint.sh checkpoint as directed below." \
    "supervision instructions missing ordinary wake directive"
  pass "supervision-instructions: renders agy protocol and wake instructions"
}

test_agy_primary_supervision_repair_line() {
  local out
  out=$("$SUPERVISION_SH" --harness agy --repair-line)
  assert_equals "repair missing watcher supervision with a foreground checkpoint: bin/fm-watch-checkpoint.sh --seconds 180." \
    "$out" "repair line for agy does not match expected output"
  pass "supervision-instructions: repair line produces exact agy checkpoint directive"
}

test_agy_primary_turnend_guard_blocking() {
  local dir fakebin out status
  dir=$(make_primary_dir "$TMP_ROOT/turnend-guard")
  fakebin=$(fm_fakebin "$dir/fakebin")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  750:comm=) printf '%s\n' agy ;;
  750:args=) printf '%s\n' 'agy' ;;
  750:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' 'bash /repo/bin/fm-turnend-guard.sh' ;;
  *:ppid=) printf '%s\n' 750 ;;
esac
SH
  chmod +x "$fakebin/ps"
  : > "$dir/state/task1.meta"
  touch "$dir/state/.last-watcher-beat"
  out=$(printf '{"stop_hook_active":false}' | env -u CLAUDECODE PATH="$fakebin:$PATH" FM_HOME="$dir" bash "$dir/bin/fm-turnend-guard.sh" 2>&1); status=$?
  expect_code 2 "$status" "turn-end guard must block when task is in-flight and watcher is unhealthy"
  assert_contains "$out" "repair missing watcher supervision with a foreground checkpoint: bin/fm-watch-checkpoint.sh --seconds 180." \
    "turn-end guard must output agy checkpoint repair line"
  pass "turnend-guard: blocks unmonitored agy turn end with checkpoint repair instruction"
}

test_agy_control_mechanics() {
  # shellcheck source=/dev/null
  . "$CONTROL_LIB"

  fm_control_harness_supported agy || fail "agy must be supported in control plane"
  fm_control_harness_supports_kind agy primary || fail "agy must support primary kind"
  fm_control_harness_supports_kind agy secondmate || fail "agy must support secondmate kind"
  fm_control_harness_supports_kind agy crewmate || fail "agy must support crewmate kind"
  fm_control_harness_supports_kind agy scout || fail "agy must support scout kind"

  local exit_cmd interrupt_key interrupt_count clear_key
  exit_cmd=$(fm_control_exit_command agy)
  [ "$exit_cmd" = "/quit" ] || fail "expected exit command /quit, got '$exit_cmd'"

  interrupt_key=$(fm_control_interrupt_key agy)
  [ "$interrupt_key" = "Escape" ] || fail "expected interrupt key Escape, got '$interrupt_key'"

  interrupt_count=$(fm_control_interrupt_repeat agy)
  [ "$interrupt_count" = "1" ] || fail "expected interrupt count 1, got '$interrupt_count'"

  clear_key=$(fm_control_interrupt_clear_key agy)
  [ -z "$clear_key" ] || fail "expected empty composer clear key, got '$clear_key'"

  pass "control: agy supports primary and secondmate with verified exit and interrupt mechanics"
}

test_agy_secondmate_trust_registration() {
  local w sm_home store out rc
  w="$TMP_ROOT/trust-registration"
  sm_home="$w/sm-home"
  mkdir -p "$sm_home/bin" "$sm_home/config" "$sm_home/data" "$sm_home/state" "$sm_home/projects"
  touch "$sm_home/AGENTS.md"
  printf 'sm-id\n' > "$sm_home/.fm-secondmate-home"
  store="$w/user/.gemini/antigravity-cli/settings.json"
  mkdir -p "$(dirname "$store")"
  printf '%s\n' '{"trustedWorkspaces":[]}' > "$store"

  out=$(HOME="$w/user" "$TRUST_SH" --secondmate-home "$sm_home" "sm-id" 2>&1)
  rc=$?
  expect_code 0 "$rc" "secondmate trust registration should succeed: $out"

  node -e '
    const fs = require("fs");
    const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const p = process.argv[2];
    if (!Array.isArray(s.trustedWorkspaces) || !s.trustedWorkspaces.includes(p)) {
      process.exit(1);
    }
  ' "$store" "$sm_home" || fail "secondmate home path was not added to trustedWorkspaces"

  # Scope refusal on mismatched ID
  out=$(HOME="$w/user" "$TRUST_SH" --secondmate-home "$sm_home" "wrong-id" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "trust registration should refuse mismatched secondmate ID"

  pass "trust: --secondmate-home registers valid home and refuses mismatched identity"
}

make_launch_capturing_tmux() {
  local dir=$1 fakebin="$1/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  capture-pane)
    if [ -n "${FM_FAKE_PANE_CAPTURE:-}" ]; then
      printf '%s\n' "$FM_FAKE_PANE_CAPTURE"
    else
      printf 'working\nesc to cancel\n'
    fi
    exit 0
    ;;
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|kill-window) exit 0 ;;
  send-keys)
    if [ -n "${FM_FAKE_LAUNCH_LOG:-}" ]; then
      prev=
      for a in "$@"; do
        if [ "$prev" = "-l" ]; then
          printf '%s\n' "$a" >> "$FM_FAKE_LAUNCH_LOG"
        fi
        prev=$a
      done
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$fakebin/tmux"
  printf '%s\n' "$fakebin"
}

meta_field() {
  local file=$1 key=$2
  grep "^${key}=" "$file" | head -n 1 | cut -d= -f2-
}

test_agy_secondmate_spawn_contract() {
  local w sm fakebin launchlog launch meta rc store
  w="$TMP_ROOT/spawn-agy-secondmate"
  sm="$w/sm"
  launchlog="$w/launch.log"
  mkdir -p "$w/home/config" "$w/home/state" "$w/home/data" "$w/home/projects"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf 'sm\n' > "$sm/.fm-secondmate-home"
  printf 'charter\n' > "$sm/data/charter.md"
  printf 'agy\n' > "$w/home/config/secondmate-harness"

  fakebin=$(make_launch_capturing_tmux "$w/tmux")
  cat > "$fakebin/agy" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = models ]; then
  printf 'gemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n'
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/agy"
  store="$w/home/user-home/.gemini/antigravity-cli/settings.json"
  mkdir -p "$(dirname "$store")"
  printf '%s\n' '{"trustedWorkspaces":[]}' > "$store"

  : > "$launchlog"
  rc=0
  PATH="$fakebin:$PATH" TMUX='' CLAUDECODE=1 \
    FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$w/home" HOME="$w/home/user-home" CLAUDE_CONFIG_DIR='' \
    FM_STATE_OVERRIDE="$w/home/state" FM_DATA_OVERRIDE="$w/home/data" \
    FM_PROJECTS_OVERRIDE="$w/home/projects" FM_CONFIG_OVERRIDE="$w/home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_PATH="$sm" \
    FM_AGY_READY_POLLS=2 FM_AGY_POLL_INTERVAL=0 \
    "$SPAWN_SH" sm "$sm" --secondmate >/dev/null 2>&1 || rc=$?

  [ "$rc" -eq 0 ] || fail "an agy secondmate spawn should succeed"
  meta="$w/home/state/sm.meta"
  [ "$(meta_field "$meta" harness)" = agy ] || fail "an agy secondmate must record its own harness"
  [ "$(meta_field "$meta" kind)" = secondmate ] || fail "an agy secondmate must record kind=secondmate"
  launch=$(cat "$launchlog")
  assert_contains "$launch" "--prompt-interactive" \
    "an agy secondmate must launch with --prompt-interactive"
  assert_contains "$launch" "--dangerously-skip-permissions" \
    "an agy secondmate must launch with --dangerously-skip-permissions"
  pass "spawn: agy is accepted for secondmates and launches with primary contract"
}

test_agy_primary_session_lock_ownership
test_agy_primary_supervision_instructions
test_agy_primary_supervision_repair_line
test_agy_primary_turnend_guard_blocking
test_agy_control_mechanics
test_agy_secondmate_trust_registration
test_agy_secondmate_spawn_contract
