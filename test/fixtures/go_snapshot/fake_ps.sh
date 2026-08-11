#!/usr/bin/env bash

set -u

real_ps="${GO_SNAPSHOT_REAL_PS:?missing GO_SNAPSHOT_REAL_PS}"
counter_file="${GO_SNAPSHOT_FAKE_PS_COUNTER:?missing counter path}"
mode="${GO_SNAPSHOT_FAKE_PS_MODE:?missing fake ps mode}"
target_file="${counter_file}.target"
lock_dir="${counter_file}.lock"
marker_file="${GO_SNAPSHOT_FAKE_PS_MARKER:-}"
gate_file="${GO_SNAPSHOT_FAKE_PS_GATE:-}"
setup_marker="${GO_SNAPSHOT_FAKE_PS_SETUP_MARKER:-}"
setup_gate="${GO_SNAPSHOT_FAKE_PS_SETUP_GATE:-}"
setup_gate_once="${counter_file}.setup-gated"
post_label="${GO_SNAPSHOT_FAKE_PS_POST_LABEL:-}"
post_marker="${GO_SNAPSHOT_FAKE_PS_POST_MARKER:-}"
post_gate="${GO_SNAPSHOT_FAKE_PS_POST_GATE:-}"
post_gate_once="${counter_file}.post-gated"
symbol_marker="${GO_SNAPSHOT_FAKE_PS_SYMBOL_MARKER:-}"
symbol_gate="${GO_SNAPSHOT_FAKE_PS_SYMBOL_GATE:-}"
symbol_gate_ticks="${GO_SNAPSHOT_FAKE_PS_SYMBOL_GATE_TICKS:-1000}"
symbol_gate_once="${counter_file}.symbol-gated"
symbol_capture="${GO_SNAPSHOT_FAKE_PS_SYMBOL_CAPTURE:-}"
test_log="${GO_SNAPSHOT_TEST_LOG:-}"

while ! /bin/mkdir "$lock_dir" 2>/dev/null; do
  /bin/sleep 0.01
done

count=0
if [[ -f "$counter_file" ]]; then
  IFS= read -r count <"$counter_file" || count=0
fi
count=$((count + 1))
printf '%s\n' "$count" >"$counter_file"
/bin/rmdir "$lock_dir"

find_owned_marker() {
  local basename="$1"
  local candidate
  local found=""
  local matches=0
  for candidate in "${TMPDIR%/}"/opentui-go-snapshot.*/"$basename"; do
    if [[ -f "$candidate" && ! -L "$candidate" ]]; then
      found="$candidate"
      matches=$((matches + 1))
    fi
  done
  OWNED_MARKER=""
  if [[ "$matches" -eq 1 ]]; then
    OWNED_MARKER="$found"
    return 0
  fi
  return 1
}

post_signal_observed() {
  local label="$1"
  local trace_file="${OWNED_MARKER%/*}/$label.shell.stderr"
  local line
  [[ -f "$trace_file" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      TRACE\|anchor_tick\|"$label"\|phase=post\|*\|signal=true)
        return 0
        ;;
    esac
  done <"$trace_file"
  return 1
}

setup_transition_is_latest() {
  local trace_file="${OWNED_MARKER%/*}/supervisor.shell.stderr"
  local line
  local transitions=0
  local held_transitions=0
  local latest=""
  [[ -f "$trace_file" && ! -L "$trace_file" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      TRACE\|fifo_state\|*)
        transitions=$((transitions + 1))
        latest="$line"
        [[ "$line" == 'TRACE|fifo_state|setup_running|setup_held' ]] &&
          held_transitions=$((held_transitions + 1))
        ;;
    esac
  done <"$trace_file"
  [[ "$transitions" -gt 0 && "$held_transitions" -eq 1 &&
     "$latest" == 'TRACE|fifo_state|setup_running|setup_held' ]]
}

symbol_transition_is_latest() {
  local trace_file="${OWNED_MARKER%/*}/supervisor.shell.stderr"
  local line
  local transitions=0
  local snapshotting_transitions=0
  local latest=""
  [[ -f "$trace_file" && ! -L "$trace_file" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      TRACE\|symbol_preflight_state\|*)
        transitions=$((transitions + 1))
        latest="$line"
        [[ "$line" == \
          'TRACE|symbol_preflight_state|waiting_held|snapshotting' ]] &&
          snapshotting_transitions=$((snapshotting_transitions + 1))
        ;;
    esac
  done <"$trace_file"
  [[ "$transitions" -gt 0 && "$snapshotting_transitions" -eq 1 &&
     "$latest" == \
       'TRACE|symbol_preflight_state|waiting_held|snapshotting' ]]
}

wait_for_gate() {
  local gate="$1"
  local maximum="${2:-1000}"
  local ticks=0
  while [[ ! -f "$gate" && "$ticks" -lt "$maximum" ]]; do
    /bin/sleep 0.01
    ticks=$((ticks + 1))
  done
}

read_command_identity() {
  local line
  COMMAND_PID=""
  COMMAND_PGID=""
  if [[ "$test_log" == "" || ! -f "$test_log" ]]; then
    return 1
  fi
  while IFS= read -r line; do
    case "$line" in
      command-started\|*)
        IFS='|' read -r _ COMMAND_PID COMMAND_PGID _ <<<"$line"
        ;;
    esac
  done <"$test_log"
  [[ "$COMMAND_PID" =~ ^[1-9][0-9]*$ &&
     "$COMMAND_PGID" =~ ^[1-9][0-9]*$ ]]
}

select_setup_identity() {
  local snapshot="$1"
  local owner_dir="${OWNED_MARKER%/*}"
  local event row_pid row_pgid row_label row_path row_extra
  local first_pgid=""
  local rows=0
  local pid pgid stat extra
  local target_rows=0
  local members=0
  SETUP_PID=""
  SETUP_PGID=""

  while IFS='|' read -r event row_pid row_pgid row_label row_path row_extra; do
    [[ "$event" == mkfifo-invoked ]] || continue
    rows=$((rows + 1))
    if [[ ! "$row_pid" =~ ^[1-9][0-9]*$ ||
          ! "$row_pgid" =~ ^[1-9][0-9]*$ || "$row_extra" != "" ]]; then
      return 1
    fi
    case "$rows" in
      1)
        [[ "$row_label" == watchdog &&
           "$row_path" == "$owner_dir/watchdog.anchor-control.fifo" ]] ||
          return 1
        first_pgid="$row_pgid"
        ;;
      2)
        [[ "$row_label" == child &&
           "$row_path" == "$owner_dir/child.anchor-control.fifo" &&
           "$row_pgid" == "$first_pgid" ]] || return 1
        ;;
      *) return 1 ;;
    esac
  done <"$test_log"
  [[ "$rows" -eq 2 ]] || return 1

  SETUP_PID="$first_pgid"
  SETUP_PGID="$first_pgid"
  while read -r pid pgid stat extra; do
    if [[ "$pid" == "$SETUP_PID" ]]; then
      target_rows=$((target_rows + 1))
      [[ "$pgid" == "$SETUP_PGID" && "$extra" == "" ]] || return 1
      case "$stat" in
        R*|S*|T*|t*) ;;
        *) return 1 ;;
      esac
    fi
    if [[ "$pgid" == "$SETUP_PGID" ]]; then
      members=$((members + 1))
    fi
  done <<<"$snapshot"
  [[ "$target_rows" -eq 1 && "$members" -eq 1 ]]
}

select_symbol_identity() {
  local snapshot="$1"
  local owner_dir="${OWNED_MARKER%/*}"
  local event row_pid row_pgid row_label row_path row_extra
  local rows=0
  local child_pgid=""
  local pid pgid stat extra
  local anchor_rows=0
  local members=0
  SYMBOL_PID=""
  SYMBOL_PGID=""
  SYMBOL_STAT=""

  while IFS='|' read -r event row_pid row_pgid row_label row_path row_extra; do
    [[ "$event" == mkfifo-invoked ]] || continue
    rows=$((rows + 1))
    [[ "$row_pid" =~ ^[1-9][0-9]*$ &&
       "$row_pgid" =~ ^[1-9][0-9]*$ && "$row_extra" == "" ]] || return 1
    if [[ "$row_label" == child &&
          "$row_path" == "$owner_dir/child.anchor-control.fifo" ]]; then
      [[ "$child_pgid" == "" ]] || return 1
      child_pgid="$row_pgid"
    fi
  done <"$test_log"
  [[ "$rows" -eq 2 && "$child_pgid" =~ ^[1-9][0-9]*$ ]] || return 1

  SYMBOL_PID="$child_pgid"
  SYMBOL_PGID="$child_pgid"
  while read -r pid pgid stat extra; do
    [[ "$extra" == "" ]] || return 1
    if [[ "$pid" == "$SYMBOL_PID" ]]; then
      anchor_rows=$((anchor_rows + 1))
      [[ "$pgid" == "$SYMBOL_PGID" ]] || return 1
      case "$stat" in
        R*|S*) SYMBOL_STAT="${stat:0:1}" ;;
        *) return 1 ;;
      esac
    fi
    if [[ "$pgid" == "$SYMBOL_PGID" ]]; then
      members=$((members + 1))
    fi
  done <<<"$snapshot"
  [[ "$anchor_rows" -eq 1 && "$members" -eq 1 ]]
}

print_snapshot_with_pgid_mismatch() {
  local snapshot="$1"
  local target_pid="$2"
  local pid pgid stat extra
  local matches=0
  while read -r pid pgid stat extra; do
    if [[ "$pid" == "$target_pid" ]]; then
      matches=$((matches + 1))
      printf '%s %s %s\n' "$pid" "$((pgid + 1))" "$stat"
    elif [[ "$pid" != "" ]]; then
      printf '%s %s %s\n' "$pid" "$pgid" "$stat"
    fi
  done <<<"$snapshot"
  [[ "$matches" -eq 1 ]]
}

select_post_target() {
  local label="$1"
  local snapshot="$2"
  local trace_file="${OWNED_MARKER%/*}/supervisor.shell.stderr"
  local line signal_pgid
  local signal_rows=0
  local pid pgid stat extra
  local anchor_rows=0
  local members=0
  POST_PID=""
  [[ -f "$trace_file" && ! -L "$trace_file" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      TRACE\|signal\|"$label"\|TERM\|pgid=*)
        signal_pgid="${line##*=}"
        [[ "$signal_pgid" =~ ^[1-9][0-9]*$ ]] || return 1
        POST_PID="$signal_pgid"
        signal_rows=$((signal_rows + 1))
        ;;
    esac
  done <"$trace_file"
  [[ "$signal_rows" -eq 1 ]] || return 1

  while read -r pid pgid stat extra; do
    [[ "$extra" == "" ]] || return 1
    if [[ "$pid" == "$POST_PID" ]]; then
      anchor_rows=$((anchor_rows + 1))
      [[ "$pgid" == "$POST_PID" ]] || return 1
      case "$stat" in
        R*|S*|T*|t*) ;;
        *) return 1 ;;
      esac
    fi
    if [[ "$pgid" == "$POST_PID" ]]; then
      members=$((members + 1))
    fi
  done <<<"$snapshot"
  [[ "$anchor_rows" -eq 1 && "$members" -eq 1 ]]
}

if [[ "$post_label" != "" && "$post_marker" != "" &&
      "$post_gate" != "" && ! -f "$post_gate_once" ]]; then
  post_owned=false
  case "$post_label" in
    child)
      find_owned_marker child.anchor-held && post_owned=true
      ;;
    watchdog)
      find_owned_marker watchdog.anchor-held && post_owned=true
      ;;
  esac
  if [[ "$post_owned" == true ]] && post_signal_observed "$post_label"; then
    : >"$post_gate_once"
    : >"$post_marker"
    wait_for_gate "$post_gate"
    snapshot="$($real_ps "$@")"
    case "$mode" in
      post-child-ceiling|post-watchdog-ceiling)
        mutated_snapshot=""
        if select_post_target "$post_label" "$snapshot" &&
            mutated_snapshot="$(
              print_snapshot_with_pgid_mismatch "$snapshot" "$POST_PID"
            )"; then
          printf 'selected|%s\n' "$POST_PID" >"$post_marker"
          printf '%s\n' "$mutated_snapshot"
        else
          printf 'missing\n' >"$post_marker"
          printf '%s\n' "$snapshot"
        fi
        exit 0
        ;;
      post-child-data|post-watchdog-data)
        printf '%s\n' "$snapshot"
        exit 0
        ;;
    esac
    printf '%s\n' "$snapshot"
    exit 0
  fi
fi

if [[ "$symbol_marker" != "" && "$symbol_gate" != "" &&
      ! -f "$symbol_gate_once" ]] &&
    find_owned_marker symbol-preflight.quiescence-held &&
    symbol_transition_is_latest; then
  : >"$symbol_gate_once"
  if [[ "$mode" == symbol-authorize-before-data ]]; then
    [[ "$symbol_capture" == /* && ! -e "$symbol_capture" &&
       "$test_log" != "" && -f "$test_log" ]] || exit 64
    "$real_ps" "$@" >"$symbol_capture"
    capture_status=$?
    [[ "$capture_status" -eq 0 && -f "$symbol_capture" &&
       ! -L "$symbol_capture" ]] || exit 65
    snapshot="$(<"$symbol_capture")"
    if ! select_symbol_identity "$snapshot"; then
      printf 'selector-failed\n' >"$symbol_marker"
      exit 66
    fi
    printf '%s|%s|%s|captured\n' \
      "$SYMBOL_PID" "$SYMBOL_PGID" "$SYMBOL_STAT" >"$symbol_marker"
    wait_for_gate "$symbol_gate" "$symbol_gate_ticks"
    exec /bin/cat "$symbol_capture"
  fi
  : >"$symbol_marker"
  wait_for_gate "$symbol_gate" "$symbol_gate_ticks"
  exec "$real_ps" "$@"
fi

if [[ "$setup_marker" != "" && "$setup_gate" != "" &&
      ! -f "$setup_gate_once" ]] &&
    find_owned_marker fifo.setup-held && setup_transition_is_latest; then
  : >"$setup_gate_once"
  snapshot="$($real_ps "$@")"
  if ! select_setup_identity "$snapshot"; then
    printf 'selector-failed\n' >"$setup_marker"
    printf '%s\n' "$snapshot"
    exit 0
  fi
  setup_pid="$SETUP_PID"
  setup_pgid="$SETUP_PGID"
  printf '%s|%s|setup-held\n' \
    "$setup_pid" "$setup_pgid" >"$setup_marker"
  wait_for_gate "$setup_gate"
  case "$mode" in
    setup-mismatch)
      print_snapshot_with_pgid_mismatch "$snapshot" "$setup_pid"
      exit 0
      ;;
    setup-nonsole)
      printf '%s\n' "$snapshot"
      printf '%s %s S\n' "$((setup_pid + 1000000))" "$setup_pgid"
      exit 0
      ;;
    setup-abort-boundary|passthrough)
      printf '%s\n' "$snapshot"
      exit 0
      ;;
  esac
  printf '%s\n' "$snapshot"
  exit 0
fi

identity_snapshot="$($real_ps -axo pid=,ppid=,pgid=,stat=)"
supervisor_parent="$($real_ps -o ppid= -p "$PPID")"
supervisor_parent="${supervisor_parent//[[:space:]]/}"
snapshot="$($real_ps "$@")"

if [[ "$mode" == setup-abort-boundary ]] &&
    find_owned_marker fifo.setup-authorized &&
    [[ -f "$setup_marker" && ! -L "$setup_marker" ]]; then
  abort_pid=""
  abort_pgid=""
  abort_phase=""
  abort_extra=""
  IFS='|' read -r abort_pid abort_pgid abort_phase abort_extra \
    <"$setup_marker" || true
  if [[ "$abort_pid" =~ ^[1-9][0-9]*$ &&
        "$abort_pgid" =~ ^[1-9][0-9]*$ &&
        "$abort_phase" == setup-held && "$abort_extra" == "" ]]; then
    while read -r pid pgid stat extra; do
      if [[ "$pgid" == "$abort_pgid" ]]; then
        if [[ "$pid" == "$abort_pid" ]]; then
          printf '%s %s S\n' "$pid" "$pgid"
        fi
      elif [[ "$pid" != "" ]]; then
        printf '%s %s %s\n' "$pid" "$pgid" "$stat"
      fi
    done <<<"$snapshot"
    exit 0
  fi
fi

if [[ "$mode" == reject-child-uncertain && "$count" -eq 2 ]]; then
  target=""
  while read -r pid ppid pgid stat extra; do
    if [[ "$pid" =~ ^[0-9]+$ &&
          ( "$ppid" == "$PPID" || "$ppid" == "$supervisor_parent" ) &&
          "$pgid" == "$pid" && "$extra" == "" ]]; then
      target="$pid $pgid ${stat:-S}"
    fi
  done <<<"$identity_snapshot"
  printf '%s\n' "$target" >"$target_file"
fi

case "$mode:$count" in
  reject-child:2|reject-child-drain-gated:2|reject-child-uncertain:2|reject-watchdog:3)
    exit 0
    ;;
esac

if [[ "$mode" == reject-child-drain-gated && "$count" -eq 3 ]]; then
  [[ "$marker_file" != "" ]] && : >"$marker_file"
  ticks=0
  while [[ "$gate_file" != "" && ! -f "$gate_file" && "$ticks" -lt 500 ]]; do
    /bin/sleep 0.01
    ticks=$((ticks + 1))
  done
fi

if [[ "$mode" == mismatch-child ]] &&
    find_owned_marker child.anchor-held && read_command_identity &&
    mutated_snapshot="$(
      print_snapshot_with_pgid_mismatch "$snapshot" "$COMMAND_PGID"
    )"; then
  printf '%s\n' "$mutated_snapshot"
  exit 0
fi

if [[ "$mode" == reject-child-uncertain ]]; then
  if [[ "$count" -gt 2 ]]; then
    printf '%s\n' "$snapshot"
    if [[ -s "$target_file" ]]; then
      IFS= read -r target <"$target_file" || target=""
      target_pid="${target%% *}"
      if [[ -n "$target" ]] &&
          ! "$real_ps" -p "$target_pid" >/dev/null 2>&1; then
        printf '%s\n' "$target"
      fi
    fi
    exit 0
  fi
fi

if [[ "$mode" == hup-on-supervision && "$count" -eq 4 ]]; then
  [[ "$marker_file" != "" ]] && : >"$marker_file"
  ticks=0
  while [[ "$gate_file" != "" && ! -f "$gate_file" && "$ticks" -lt 500 ]]; do
    /bin/sleep 0.01
    ticks=$((ticks + 1))
  done
  kill -HUP "$supervisor_parent" 2>/dev/null || true
fi

printf '%s\n' "$snapshot"
