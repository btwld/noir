#!/usr/bin/env bash

set +e
set -u
set -m

TMP_DIR="${P9_043_DEBUG_PROBE_DIR:?missing probe directory}"

if [[ "${P9_043_DEBUG_PROBE_MODE:-child}" == parent ]]; then
  if [[ "$(type -t _p9_043_debug_gate)" != function ]]; then
    printf 'bootstrap-not-sourced\n' >"$P9_043_DEBUG_HOOK_FAILED"
    exit 96
  fi
  symbol_preflight_quiescence_parent_candidate="$TMP_DIR/symbol-preflight.quiescence-parent.candidate"
  symbol_preflight_quiescence_child_candidate="$TMP_DIR/symbol-preflight.quiescence-child.candidate"
  symbol_preflight_quiescence_disposition="$TMP_DIR/symbol-preflight.quiescence-disposition"
  symbol_preflight_quiescence_parent_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-parent.ln.stderr"
  symbol_preflight_quiescence_child_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-child.ln.stderr"
  symbol_preflight_quiescence_authorized="$TMP_DIR/symbol-preflight.quiescence-authorized"
  symbol_preflight_quiescence_rejected="$TMP_DIR/symbol-preflight.quiescence-rejected"

  probe_child=''
  probe_watchdog=''
  cleanup_parent_probe() {
    if [[ "$probe_child" =~ ^[1-9][0-9]*$ ]]; then
      builtin kill -TERM "$probe_child" 2>/dev/null || true
      wait "$probe_child" 2>/dev/null || true
    fi
    if [[ "$probe_watchdog" =~ ^[1-9][0-9]*$ ]]; then
      builtin kill -TERM "$probe_watchdog" 2>/dev/null || true
      wait "$probe_watchdog" 2>/dev/null || true
    fi
  }
  trap cleanup_parent_probe EXIT

  /usr/bin/perl -e '$SIG{TERM}=sub { exit 0 }; sleep 300' &
  probe_child=$!
  /usr/bin/perl -e '$SIG{TERM}=sub { exit 0 }; sleep 300' &
  probe_watchdog=$!
  printf '%s\n' "$probe_child" >"$P9_043_DEBUG_PROBE_CHILD_PID"
  printf '%s\n' "$probe_watchdog" >"$P9_043_DEBUG_PROBE_WATCHDOG_PID"
  printf 'authorize\n' >"$symbol_preflight_quiescence_parent_candidate"
  printf 'reject:unexpected-data\n' \
    >"$symbol_preflight_quiescence_child_candidate"

  # shellcheck disable=SC2217 # Match the production descriptor topology.
  /bin/ln "$symbol_preflight_quiescence_parent_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_parent_ln_stderr" 3>&- 8>&- 9>&-
  symbol_parent_election_status=$?
  printf '%s\n' "$symbol_parent_election_status" \
    >"$P9_043_DEBUG_PROBE_LINK_STATUS"

  if [[ "${P9_043_DEBUG_PROBE_LINK_MODE:-success}" == both ]]; then
    # shellcheck disable=SC2034 # The sourced DEBUG trap consumes these globals.
    P9_043_DEBUG_POSTLINK_STOPPED="$P9_043_DEBUG_SECOND_POSTLINK_STOPPED"
    # shellcheck disable=SC2034 # The sourced DEBUG trap consumes these globals.
    P9_043_DEBUG_POSTLINK_CONTINUED="$P9_043_DEBUG_SECOND_POSTLINK_CONTINUED"
    # shellcheck disable=SC2034 # The sourced DEBUG trap consumes these globals.
    P9_043_DEBUG_EXPECT_PARENT_STATUS=1
    # shellcheck disable=SC2034 # The sourced DEBUG trap consumes these globals.
    P9_043_DEBUG_EXPECT_PARENT_RECORD='reject:unexpected-data'
    /bin/rm -f "$symbol_preflight_quiescence_disposition"
    # shellcheck disable=SC2217 # Match the production descriptor topology.
    /bin/ln "$symbol_preflight_quiescence_child_candidate" \
      "$symbol_preflight_quiescence_disposition" \
      </dev/null >/dev/null \
      2>"$symbol_preflight_quiescence_child_ln_stderr"
    # shellcheck disable=SC2217 # Match the production descriptor topology.
    /bin/ln "$symbol_preflight_quiescence_parent_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_parent_ln_stderr" 3>&- 8>&- 9>&-
    symbol_parent_election_status=$?
    printf '%s\n' "$symbol_parent_election_status" \
      >"$P9_043_DEBUG_PROBE_SECOND_LINK_STATUS"
  fi
  cleanup_parent_probe
  trap - EXIT
  exit 0
fi

# shellcheck disable=SC2034 # The sourced DEBUG trap consumes these globals.
symbol_preflight_quiescence_parent_candidate="$TMP_DIR/symbol-preflight.quiescence-parent.candidate"
symbol_preflight_quiescence_child_candidate="$TMP_DIR/symbol-preflight.quiescence-child.candidate"
symbol_preflight_quiescence_disposition="$TMP_DIR/symbol-preflight.quiescence-disposition"
# shellcheck disable=SC2034 # The sourced DEBUG trap consumes this global.
symbol_preflight_quiescence_parent_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-parent.ln.stderr"
symbol_preflight_quiescence_child_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-child.ln.stderr"
# shellcheck disable=SC2034 # The sourced DEBUG trap consumes this global.
symbol_preflight_quiescence_authorized="$TMP_DIR/symbol-preflight.quiescence-authorized"
# shellcheck disable=SC2034 # The sourced DEBUG trap consumes this global.
symbol_preflight_quiescence_rejected="$TMP_DIR/symbol-preflight.quiescence-rejected"

false
observed_status=$?
printf '%s\n' "$observed_status" >"$P9_043_DEBUG_PROBE_STATUS"
printf 'reject:unexpected-data\n' \
  >"$symbol_preflight_quiescence_child_candidate"

(
  exec 8<>/dev/null
  # shellcheck disable=SC2217 # Match the production descriptor topology.
  /bin/ln "$symbol_preflight_quiescence_child_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_child_ln_stderr" 3>&- 8>&- 9>&-
  printf '%s\n' "$?" >"$P9_043_DEBUG_PROBE_LINK_STATUS"
) &
probe_child=$!
printf '%s\n' "$probe_child" >"$P9_043_DEBUG_PROBE_CHILD_PID"
# Linux Bash can treat a stopped job as a completed `wait` observation and
# resume it during shell exit. Keep the probe owner alive without consuming
# the terminal status until the test has continued the child explicitly.
while builtin kill -0 "$probe_child" 2>/dev/null; do
  /bin/sleep 0.01
done
wait "$probe_child"
