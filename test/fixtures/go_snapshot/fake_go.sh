#!/usr/bin/env bash

set -u

log_file="${GO_SNAPSHOT_TEST_LOG:?missing GO_SNAPSHOT_TEST_LOG}"
mode="${GO_SNAPSHOT_TEST_MODE:?missing GO_SNAPSHOT_TEST_MODE}"
real_ps="${GO_SNAPSHOT_REAL_PS:-/bin/ps}"
descendant_fixture="${GO_SNAPSHOT_DESCENDANT_FIXTURE:?missing descendant fixture}"
visible_command_fixture="${GO_SNAPSHOT_VISIBLE_COMMAND_FIXTURE:?missing visible fixture}"
command_gate="${GO_SNAPSHOT_COMMAND_GATE:-}"

pgid_for() {
  local pid="$1"
  local row
  row="$($real_ps -o pgid= -p "$pid" 2>/dev/null)" || row=""
  row="${row//[[:space:]]/}"
  printf '%s' "$row"
}

record() {
  local event="$1"
  local detail="${2:-}"
  printf '%s|%s|%s|%s\n' "$event" "$$" "$(pgid_for "$$")" "$detail" >>"$log_file"
}

record_fixed_fds() {
  local fd8=closed
  local fd9=closed
  [[ -e /dev/fd/8 ]] && fd8=open
  [[ -e /dev/fd/9 ]] && fd9=open
  record fixed-fds "fd8=$fd8,fd9=$fd9"
}

if [[ "${1:-}" != "run" || "${2:-}" != "." ]]; then
  record invalid-invocation "$*"
  exit 64
fi
shift 2

record command-started "$mode"
record_fixed_fds
arg_index=0
for arg in "$@"; do
  printf 'argv|%s|%s|%s\n' "$arg_index" "${#arg}" "$arg" >>"$log_file"
  arg_index=$((arg_index + 1))
done
printf 'cwd|%s\n' "$PWD" >>"$log_file"

case "$mode" in
  success)
    printf 'fixture stdout\n'
    printf 'fixture stderr\n' >&2
    exit 0
    ;;
  gated-success)
    ticks=0
    while [[ "$command_gate" != "" && ! -f "$command_gate" && "$ticks" -lt 200 ]]; do
      /bin/sleep 0.05 2>/dev/null
      ticks=$((ticks + 1))
    done
    [[ "$command_gate" != "" && -f "$command_gate" ]] || exit 66
    printf 'fixture gated stdout\n'
    printf 'fixture gated stderr\n' >&2
    exit 0
    ;;
  nonzero)
    printf 'fixture nonzero stdout\n'
    printf 'fixture nonzero stderr\n' >&2
    exit 23
    ;;
  exit127)
    printf 'fixture 127 stdout\n'
    printf 'fixture 127 stderr\n' >&2
    exit 127
    ;;
  exit138)
    printf 'fixture 138 stdout\n'
    printf 'fixture 138 stderr\n' >&2
    exit 138
    ;;
  signal)
    printf 'fixture signal stdout\n'
    printf 'fixture signal stderr\n' >&2
    exec 2>/dev/null
    /usr/bin/perl "$descendant_fixture" &
    descendant_pid=$!
    record descendant-recorded "$descendant_pid"

    on_int() {
      record command-int INT
      kill -INT "$descendant_pid" 2>/dev/null || true
      wait "$descendant_pid" 2>/dev/null || true
      exit 0
    }
    on_term() {
      record command-term TERM
      kill -TERM "$descendant_pid" 2>/dev/null || true
      wait "$descendant_pid" 2>/dev/null || true
      exit 0
    }
    trap on_int INT
    trap on_term TERM
    while :; do
      /bin/sleep 1 2>/dev/null
    done
    ;;
  stubborn-visible-term)
    exec /usr/bin/perl "$visible_command_fixture"
    ;;
  stubborn|delayed127|delayed138|race-late127)
    printf 'fixture %s stdout\n' "$mode"
    printf 'fixture %s stderr\n' "$mode" >&2
    exec 2>/dev/null
    /usr/bin/perl "$descendant_fixture" &
    descendant_pid=$!
    record descendant-recorded "$descendant_pid"
    trap 'record command-int-ignored INT' INT
    trap 'record command-term-ignored TERM' TERM

    if [[ "$mode" == delayed127 ||
          "$mode" == delayed138 ||
          "$mode" == race-late127 ]]; then
      ticks=0
      tick_limit=30
      [[ "$mode" == race-late127 ]] && tick_limit=12
      while [[ "$ticks" -lt "$tick_limit" ]]; do
        /bin/sleep 0.1 2>/dev/null
        ticks=$((ticks + 1))
      done
      kill -KILL "$descendant_pid" 2>/dev/null || true
      wait "$descendant_pid" 2>/dev/null || true
      if [[ "$mode" == delayed127 || "$mode" == race-late127 ]]; then
        exit 127
      fi
      exit 138
    fi

    while :; do
      /bin/sleep 1 2>/dev/null
    done
    ;;
  *)
    record invalid-mode "$mode"
    exit 64
    ;;
esac
