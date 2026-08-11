#!/usr/bin/env bash

set -u

mode="${GO_SNAPSHOT_FAKE_MKFIFO_MODE:-normal}"
apply_to="${GO_SNAPSHOT_FAKE_MKFIFO_APPLY_TO:-all}"
real_mkfifo="${GO_SNAPSHOT_REAL_MKFIFO:?missing GO_SNAPSHOT_REAL_MKFIFO}"
real_ps="${GO_SNAPSHOT_REAL_PS:-/bin/ps}"
log_file="${GO_SNAPSHOT_TEST_LOG:?missing GO_SNAPSHOT_TEST_LOG}"
outside_path="${GO_SNAPSHOT_FAKE_MKFIFO_OUTSIDE:-}"
symlink_target="${GO_SNAPSHOT_FAKE_MKFIFO_SYMLINK_TARGET:-}"
pid_log="${GO_SNAPSHOT_FAKE_MKFIFO_PID_LOG:-}"

requested_path=""
if [[ "$#" -eq 3 && "$1" == "-m" && "$2" == "600" ]]; then
  requested_path="$3"
else
  exit 64
fi

owner=unknown
case "${requested_path##*/}" in
  child.anchor-control.fifo) owner=child ;;
  watchdog.anchor-control.fifo) owner=watchdog ;;
esac

pgid="$($real_ps -o pgid= -p "$$" 2>/dev/null)" || pgid=""
pgid="${pgid//[[:space:]]/}"
printf 'mkfifo-invoked|%s|%s|%s|%s\n' \
  "$$" "$pgid" "$owner" "$requested_path" >>"$log_file"

if [[ "$apply_to" != all && "$apply_to" != "$owner" ]]; then
  mode=normal
fi

record_pid() {
  local event="$1"
  local pid="$2"
  local recorded_pgid=""
  [[ "$pid_log" != "" ]] || return 0
  recorded_pgid="$($real_ps -o pgid= -p "$pid" 2>/dev/null)" || recorded_pgid=""
  recorded_pgid="${recorded_pgid//[[:space:]]/}"
  printf '%s|%s|%s|\n' "$event" "$pid" "$recorded_pgid" >>"$pid_log"
}

case "$mode" in
  normal)
    exec "$real_mkfifo" "$@"
    ;;
  fail)
    printf 'fake mkfifo failure\n' >&2
    exit 9
    ;;
  no-create)
    exit 0
    ;;
  regular-file)
    : >"$requested_path" || exit 8
    /bin/chmod 600 "$requested_path" || exit 8
    exit 0
    ;;
  symlink)
    [[ "$symlink_target" != "" ]] || exit 64
    "$real_mkfifo" -m 600 "$symlink_target" || exit 8
    /bin/ln -s "$symlink_target" "$requested_path" || exit 8
    exit 0
    ;;
  public-mode)
    "$real_mkfifo" -m 600 "$requested_path" || exit 8
    /bin/chmod 666 "$requested_path" || exit 8
    exit 0
    ;;
  wrong-path)
    [[ "$outside_path" != "" ]] || exit 64
    "$real_mkfifo" -m 600 "$outside_path" || exit 8
    exit 0
    ;;
  success-output)
    "$real_mkfifo" -m 600 "$requested_path" || exit 8
    printf 'fake mkfifo stdout\n'
    printf 'fake mkfifo stderr\n' >&2
    exit 0
    ;;
  hang)
    record_pid mkfifo-parent "$$"
    trap '' INT TERM HUP
    while :; do
      /bin/sleep 1
    done
    ;;
  fork-hang)
    record_pid mkfifo-parent "$$"
    trap '' INT TERM HUP
    (
      trap '' INT TERM HUP
      while :; do
        /bin/sleep 1
      done
    ) &
    child_pid=$!
    record_pid mkfifo-child "$child_pid"
    wait "$child_pid"
    exit 74
    ;;
  fork-return)
    "$real_mkfifo" -m 600 "$requested_path" || exit 8
    (
      trap '' INT TERM HUP
      while :; do
        /bin/sleep 1
      done
    ) &
    child_pid=$!
    record_pid mkfifo-child "$child_pid"
    exit 0
    ;;
  *)
    exit 64
    ;;
esac
