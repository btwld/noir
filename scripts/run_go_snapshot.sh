#!/usr/bin/env bash

# Preserve the caller's stderr before making every shell-owned diagnostic
# channel private. Only the actual Go command receives fd 3 as its stderr.
exec 3>&2
exec 2>/dev/null
exec 8>&-
exec 9>&-

set +e
set -u
set -o pipefail

TMP_DIR=""
TMP_PARENT=""
TMP_BASENAME=""

child_pid=""
child_pgid=""
child_launch_state="not_launched"
child_anchor_owned=false
child_terminal_consumed=false
child_cleanup_action="unset"

watchdog_pid=""
watchdog_pgid=""
watchdog_launch_state="not_launched"
watchdog_anchor_owned=false
watchdog_terminal_consumed=false
watchdog_cleanup_action="unset"

signal_pending=""
cause_record="unset"
cleanup_started=false
cleanup_failed=false
retained_diagnostic_emitted=false
timeout_seconds=90
fifo_setup_state="unstarted"
fifo_setup_diagnostic=""
fifo_setup_diagnostic_emitted=false
fifo_deadline_observations=0
watchdog_deadline_pid_value=""
HOLD_RESULT=""
FIFO_ERROR_DIAGNOSTIC=""
SYMBOL_PREFLIGHT_RESULT=""
symbol_preflight_diagnostic_emitted=false
symbol_preflight_quiescence_state="not_reached"
symbol_preflight_child_quiescence_state="not_reached"
symbol_parent_disposition=""
symbol_parent_election_status=0
SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION=""
SYMBOL_PREFLIGHT_ELECTION_PREEMPTED=false

MKFIFO_TOOL=""
child_anchor_fifo=""
watchdog_anchor_fifo=""
child_mkfifo_stdout=""
child_mkfifo_stderr=""
watchdog_mkfifo_stdout=""
watchdog_mkfifo_stderr=""
watchdog_deadline_pid=""
watchdog_deadline_started=""
fifo_setup_begin=""
fifo_setup_held=""
fifo_setup_authorized=""
fifo_setup_closed=""
fifo_watchdog_create_error=""
fifo_watchdog_invalid=""
fifo_child_create_error=""
fifo_child_invalid=""
fifo_quiescence_error=""
fifo_setup_protocol_error=""

OUTCOME_CAUSE=""
OUTCOME_STATUS=""

SNAPSHOT_OK=false
SNAPSHOT_ANCHOR_PRESENT=false
SNAPSHOT_ANCHOR_PGID=""
SNAPSHOT_ANCHOR_STAT=""
SNAPSHOT_MEMBER_COUNT=0
SNAPSHOT_EXPECTED_MEMBER_PRESENT=false
SNAPSHOT_EXPECTED_MEMBER_STAT=""
READ_LINE=""

owned_diagnostic() {
  printf '%s\n' "$1" >&3
}

trace_event() {
  printf 'TRACE|%s\n' "$1" >&2
}

private_marker_valid() {
  local path="$1"
  [[ "$path" != "" && -f "$path" && ! -L "$path" && -O "$path" ]]
}

private_path_absent() {
  local path="$1"
  [[ "$path" != "" && ! -e "$path" && ! -L "$path" ]]
}

transition_fifo_setup() {
  local next="$1"
  case "$fifo_setup_state:$next" in
    unstarted:waiting_deadline|waiting_deadline:deadline_owned|\
      deadline_owned:setup_running|setup_running:setup_held|\
      setup_held:authorized|authorized:child_closed|unstarted:failed|\
      waiting_deadline:failed|deadline_owned:failed|setup_running:failed|\
      setup_held:failed|authorized:failed) ;;
    *) return 1 ;;
  esac
  trace_event "fifo_state|$fifo_setup_state|$next"
  fifo_setup_state="$next"
  return 0
}

transition_symbol_preflight_quiescence() {
  local next="$1"
  case "$symbol_preflight_quiescence_state:$next" in
    not_reached:waiting_held|waiting_held:snapshotting|\
      waiting_held:aborted|waiting_held:protocol_failed|\
      snapshotting:authorized|snapshotting:rejected|\
      snapshotting:aborted|snapshotting:protocol_failed) ;;
    *) return 1 ;;
  esac
  trace_event \
    "symbol_preflight_state|$symbol_preflight_quiescence_state|$next"
  symbol_preflight_quiescence_state="$next"
  return 0
}

transition_symbol_preflight_child_quiescence() {
  local next="$1"
  case "$symbol_preflight_child_quiescence_state:$next" in
    not_reached:held|held:electing_rejection|held:authorized_closed|\
      held:rejected|held:aborted|held:protocol_failed|\
      electing_rejection:rejected|\
      electing_rejection:aborted|electing_rejection:protocol_failed) ;;
    *) return 1 ;;
  esac
  trace_event \
    "symbol_preflight_child_state|$symbol_preflight_child_quiescence_state|$next"
  symbol_preflight_child_quiescence_state="$next"
  return 0
}

select_fifo_setup_failure() {
  local diagnostic="$1"
  if [[ "$fifo_setup_state" != "failed" &&
        "$fifo_setup_state" != "child_closed" ]]; then
    transition_fifo_setup failed || true
  fi
  fifo_setup_diagnostic="$diagnostic"
  commit_cause protocol 1 || true
}

emit_fifo_setup_diagnostic() {
  if [[ "$fifo_setup_diagnostic_emitted" != true &&
        "$fifo_setup_diagnostic" != "" &&
        "$cause_record" == "protocol:1" ]]; then
    owned_diagnostic "$fifo_setup_diagnostic"
    fifo_setup_diagnostic_emitted=true
  fi
}

early_exit() {
  local status="$1"
  trap - EXIT
  exec 3>&-
  exit "$status"
}

mark_cleanup_failure() {
  cleanup_failed=true
}

commit_cause() {
  local proposed="$1"
  local status="$2"
  if [[ "$cause_record" != "unset" ]]; then
    return 1
  fi
  # This single assignment is the selection linearization point. Bash runs an
  # asynchronous trap either before or after a simple assignment, never in the
  # middle of its parameter expansion and commit.
  cause_record="${signal_pending:-$proposed:$status}"
  trace_event \
    "cause|${cause_record%%:*}|status=${cause_record##*:}"
  return 0
}

# shellcheck disable=SC2329 # Invoked only by trap-reachable handlers.
record_signal() {
  local signal_name="$1"
  local signal_status="$2"
  if [[ "$cause_record" == "unset" ]]; then
    signal_pending="${signal_pending:-signal:$signal_status}"
    trace_event \
      "signal_pending|${signal_pending%%:*}|status=${signal_pending##*:}"
  else
    trace_event "late_signal|$signal_name|ignored|cause=${cause_record%%:*}"
  fi
}

# shellcheck disable=SC2329 # Invoked by the INT trap.
record_int() {
  record_signal INT 130
}

# shellcheck disable=SC2329 # Invoked by the TERM trap.
record_term() {
  record_signal TERM 143
}

diagnose_retained_removal() {
  if [[ "$retained_diagnostic_emitted" != true ]]; then
    owned_diagnostic \
      "cleanup could not remove; retained temporary directory: $TMP_DIR"
    retained_diagnostic_emitted=true
  fi
}

read_exact_line() {
  local path="$1"
  local extra=""
  READ_LINE=""
  if [[ ! -f "$path" || -L "$path" ]]; then
    return 1
  fi
  if ! exec 4<"$path"; then
    return 1
  fi
  if ! IFS= read -r READ_LINE <&4; then
    exec 4<&-
    return 1
  fi
  if IFS= read -r extra <&4 || [[ -n "$extra" ]]; then
    : "$extra"
    exec 4<&-
    return 1
  fi
  exec 4<&-
  return 0
}

symbol_preflight_quiescence_record_is() {
  local path="$1"
  local expected="$2"
  private_marker_valid "$path" &&
    read_exact_line "$path" &&
    [[ "$READ_LINE" == "$expected" ]]
}

admit_symbol_preflight_child_election_prefix() {
  if [[ -e "$symbol_preflight_quiescence_disposition" ||
        -L "$symbol_preflight_quiescence_disposition" ]]; then
    private_marker_valid "$symbol_preflight_quiescence_disposition" ||
      return 1
    private_marker_valid "$symbol_preflight_quiescence_child_candidate" ||
      return 1
    private_marker_valid "$symbol_preflight_quiescence_child_ln_stderr" ||
      return 1
  elif [[ -e "$symbol_preflight_quiescence_child_ln_stderr" ||
          -L "$symbol_preflight_quiescence_child_ln_stderr" ]]; then
    private_marker_valid "$symbol_preflight_quiescence_child_ln_stderr" ||
      return 1
    private_marker_valid "$symbol_preflight_quiescence_child_candidate" ||
      return 1
  elif [[ -e "$symbol_preflight_quiescence_child_candidate" ||
          -L "$symbol_preflight_quiescence_child_candidate" ]]; then
    private_marker_valid "$symbol_preflight_quiescence_child_candidate" ||
      return 1
  fi
  return 0
}

validate_symbol_preflight_quiescence_disposition() {
  local value=""
  local winner=""

  SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION=""
  private_marker_valid "$symbol_preflight_quiescence_disposition" ||
    return 1
  read_exact_line "$symbol_preflight_quiescence_disposition" || return 1
  value="$READ_LINE"
  case "$value" in
    authorize|reject:snapshot)
      winner="$symbol_preflight_quiescence_parent_candidate"
      ;;
    reject:unexpected-data|reject:ceiling)
      winner="$symbol_preflight_quiescence_child_candidate"
      ;;
    *) return 1 ;;
  esac
  symbol_preflight_quiescence_record_is "$winner" "$value" || return 1
  [[ "$symbol_preflight_quiescence_disposition" -ef "$winner" ]] ||
    return 1
  if [[ "$winner" == "$symbol_preflight_quiescence_parent_candidate" ]]; then
    private_marker_valid "$symbol_preflight_quiescence_parent_ln_stderr" ||
      return 1
    [[ ! -s "$symbol_preflight_quiescence_parent_ln_stderr" ]] || return 1
  else
    private_marker_valid "$symbol_preflight_quiescence_child_ln_stderr" ||
      return 1
    [[ ! -s "$symbol_preflight_quiescence_child_ln_stderr" ]] || return 1
  fi
  if [[ "$winner" == "$symbol_preflight_quiescence_child_candidate" &&
          ( -e "$symbol_preflight_quiescence_parent_candidate" ||
            -L "$symbol_preflight_quiescence_parent_candidate" ) ]]; then
    private_marker_valid "$symbol_preflight_quiescence_parent_candidate" ||
      return 1
    read_exact_line "$symbol_preflight_quiescence_parent_candidate" ||
      return 1
    case "$READ_LINE" in
      authorize|reject:snapshot) ;;
      *) return 1 ;;
    esac
    [[ ! "$symbol_preflight_quiescence_disposition" -ef \
      "$symbol_preflight_quiescence_parent_candidate" ]] || return 1
  fi
  SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION="$value"
  return 0
}

elect_symbol_preflight_quiescence_disposition() {
  local owner="$1"
  local value="$2"
  local candidate=""
  local link_stderr=""

  SYMBOL_PREFLIGHT_ELECTION_PREEMPTED=false

  case "$owner:$value" in
    parent:authorize|parent:reject:snapshot)
      candidate="$symbol_preflight_quiescence_parent_candidate"
      link_stderr="$symbol_preflight_quiescence_parent_ln_stderr"
      ;;
    child:reject:unexpected-data|child:reject:ceiling)
      candidate="$symbol_preflight_quiescence_child_candidate"
      link_stderr="$symbol_preflight_quiescence_child_ln_stderr"
      ;;
    *) return 1 ;;
  esac

  if ! private_path_absent "$candidate" ||
      ! private_path_absent "$link_stderr" ||
      ! printf '%s\n' "$value" >"$candidate" ||
      ! symbol_preflight_quiescence_record_is "$candidate" "$value"; then
    return 1
  fi

  if [[ "$owner" == child &&
        ( -e "$child_release" || -L "$child_release" ) ]]; then
    if private_marker_valid "$child_release"; then
      SYMBOL_PREFLIGHT_ELECTION_PREEMPTED=true
      return 2
    fi
    return 1
  fi
  if [[ "$owner" == parent &&
        ( "$signal_pending" != "" ||
          -e "$outcome" || -L "$outcome" ||
          -e "$child_protocol_error" || -L "$child_protocol_error" ||
          -e "$watchdog_protocol_error" ||
          -L "$watchdog_protocol_error" ) ]]; then
    SYMBOL_PREFLIGHT_ELECTION_PREEMPTED=true
    return 2
  fi

  if [[ "$owner" == child ]]; then
    # shellcheck disable=SC2217 # Freeze every inherited descriptor explicitly.
    /bin/ln "$symbol_preflight_quiescence_child_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_child_ln_stderr" 3>&- 8>&- 9>&-
  else
    # shellcheck disable=SC2217 # Freeze every inherited descriptor explicitly.
    /bin/ln "$symbol_preflight_quiescence_parent_candidate" "$symbol_preflight_quiescence_disposition" </dev/null >/dev/null 2>"$symbol_preflight_quiescence_parent_ln_stderr" 3>&- 8>&- 9>&-
  fi
  : "$?"
  private_marker_valid "$link_stderr" || return 1
  validate_symbol_preflight_quiescence_disposition || return 1
  return 0
}

snapshot_group() {
  local expected_pid="$1"
  local expected_pgid="$2"
  local expected_member_pid="${3:-}"
  local snapshot=""
  local row_pid=""
  local row_pgid=""
  local row_stat=""
  local row_extra=""
  local anchor_rows=0
  local expected_member_rows=0

  SNAPSHOT_OK=false
  SNAPSHOT_ANCHOR_PRESENT=false
  SNAPSHOT_ANCHOR_PGID=""
  SNAPSHOT_ANCHOR_STAT=""
  SNAPSHOT_MEMBER_COUNT=0
  SNAPSHOT_EXPECTED_MEMBER_PRESENT=false
  SNAPSHOT_EXPECTED_MEMBER_STAT=""

  if ! snapshot="$(ps -axo pid=,pgid=,stat= 3>&-)"; then
    return 1
  fi

  while read -r row_pid row_pgid row_stat row_extra; do
    if [[ "$row_pid" == "" && "$row_pgid" == "" && "$row_stat" == "" ]]; then
      continue
    fi
    if [[ ! "$row_pid" =~ ^[0-9]+$ ||
          ! "$row_pgid" =~ ^[0-9]+$ ||
          "$row_stat" == "" ||
          "$row_extra" != "" ]]; then
      return 1
    fi
    if [[ "$row_pid" == "$expected_pid" ]]; then
      anchor_rows=$((anchor_rows + 1))
      SNAPSHOT_ANCHOR_PRESENT=true
      SNAPSHOT_ANCHOR_PGID="$row_pgid"
      SNAPSHOT_ANCHOR_STAT="$row_stat"
    fi
    if [[ "$row_pgid" == "$expected_pgid" ]]; then
      SNAPSHOT_MEMBER_COUNT=$((SNAPSHOT_MEMBER_COUNT + 1))
    fi
    if [[ "$expected_member_pid" != "" &&
          "$row_pid" == "$expected_member_pid" &&
          "$row_pgid" == "$expected_pgid" ]]; then
      expected_member_rows=$((expected_member_rows + 1))
      SNAPSHOT_EXPECTED_MEMBER_STAT="$row_stat"
    fi
  done <<<"$snapshot"

  if [[ "$anchor_rows" -gt 1 ]]; then
    return 1
  fi
  if [[ "$expected_member_rows" -eq 1 ]]; then
    SNAPSHOT_EXPECTED_MEMBER_PRESENT=true
  elif [[ "$expected_member_rows" -gt 1 ]]; then
    return 1
  fi
  SNAPSHOT_OK=true
  return 0
}

snapshot_pid_absent() {
  local expected_pid="$1"
  local snapshot=""
  local row_pid=""
  local row_pgid=""
  local row_stat=""
  local row_extra=""

  if ! snapshot="$(ps -axo pid=,pgid=,stat= 3>&-)"; then
    return 1
  fi
  while read -r row_pid row_pgid row_stat row_extra; do
    if [[ "$row_pid" == "" && "$row_pgid" == "" && "$row_stat" == "" ]]; then
      continue
    fi
    if [[ ! "$row_pid" =~ ^[0-9]+$ ||
          ! "$row_pgid" =~ ^[0-9]+$ ||
          "$row_stat" == "" ||
          "$row_extra" != "" ]]; then
      return 1
    fi
    if [[ "$row_pid" == "$expected_pid" ]]; then
      return 2
    fi
  done <<<"$snapshot"
  return 0
}

supported_live_state() {
  local state="$1"
  case "$state" in
    R*|S*|T*|t*) return 0 ;;
    *) return 1 ;;
  esac
}

verify_anchor() {
  local pid="$1"
  local other_pgid="$2"
  if [[ ! "$pid" =~ ^[0-9]+$ || "$pid" == "0" ]]; then
    return 1
  fi
  if ! snapshot_group "$pid" "$pid"; then
    return 1
  fi
  if [[ "$SNAPSHOT_OK" != true ||
        "$SNAPSHOT_ANCHOR_PRESENT" != true ||
        "$SNAPSHOT_ANCHOR_PGID" != "$pid" ]]; then
    return 1
  fi
  if ! supported_live_state "$SNAPSHOT_ANCHOR_STAT"; then
    return 1
  fi
  if [[ "$pid" == "$$" ||
        "$pid" == "$wrapper_pgid" ||
        ( "$other_pgid" != "" && "$pid" == "$other_pgid" ) ]]; then
    return 1
  fi
  return 0
}

wait_for_both_ready() {
  local ticks=0
  while [[ "$ticks" -lt 50 ]]; do
    if [[ -f "$child_ready" && -f "$watchdog_ready" ]]; then
      return 0
    fi
    /bin/sleep 0.1 3>&-
    ticks=$((ticks + 1))
  done
  return 1
}

evaluate_hold_boundary() {
  local phase="$1"
  local label="$2"
  local release_path="$3"
  local success_path="$4"
  local protocol_path="$5"
  local slot="$6"

  if [[ "$phase" == "setup" && "$label" == "child" ]]; then
    if [[ -e "$release_path" || -L "$release_path" ]]; then
      if ! private_marker_valid "$release_path"; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      if [[ -e "$success_path" || -L "$success_path" ]]; then
        : >"$protocol_path" || true
      fi
      trace_event "hold|child|phase=setup|aborted|slot=$slot"
      HOLD_RESULT="aborted"
      return 0
    fi
    if [[ -e "$success_path" || -L "$success_path" ]]; then
      if ! private_marker_valid "$success_path"; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      trace_event "hold|child|phase=setup|authorized|slot=$slot"
      HOLD_RESULT="authorized"
      return 0
    fi
    return 1
  fi

  if [[ "$phase" == "symbol-preflight-quiescence" &&
        "$label" == "child" ]]; then
    local authorized="$symbol_preflight_quiescence_authorized"
    local rejected="$symbol_preflight_quiescence_rejected"
    if [[ -e "$release_path" || -L "$release_path" ]]; then
      if ! private_marker_valid "$release_path"; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      if [[ -e "$authorized" || -L "$authorized" ||
            -e "$rejected" || -L "$rejected" ||
            -e "$symbol_preflight_quiescence_disposition" ||
            -L "$symbol_preflight_quiescence_disposition" ]]; then
        : >"$protocol_path" || true
      fi
      trace_event \
        "hold|child|phase=symbol-preflight-quiescence|aborted|slot=$slot"
      HOLD_RESULT="aborted"
      return 0
    fi
    if [[ ( -e "$authorized" || -L "$authorized" ) &&
          ( -e "$rejected" || -L "$rejected" ) ]]; then
      : >"$protocol_path" || true
      HOLD_RESULT="protocol"
      return 0
    fi
    if [[ -e "$authorized" || -L "$authorized" ]]; then
      if ! private_marker_valid "$authorized" ||
          ! validate_symbol_preflight_quiescence_disposition ||
          [[ "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" != authorize ]] ||
          [[ -e "$symbol_preflight_quiescence_child_candidate" ||
             -L "$symbol_preflight_quiescence_child_candidate" ||
             -e "$symbol_preflight_quiescence_child_ln_stderr" ||
             -L "$symbol_preflight_quiescence_child_ln_stderr" ]]; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      trace_event \
        "hold|child|phase=symbol-preflight-quiescence|authorized|slot=$slot"
      HOLD_RESULT="authorized"
      return 0
    fi
    if [[ -e "$rejected" || -L "$rejected" ]]; then
      if ! private_marker_valid "$rejected" ||
          ! validate_symbol_preflight_quiescence_disposition ||
          [[ "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" != reject:* ]]; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      trace_event \
        "hold|child|phase=symbol-preflight-quiescence|rejected|slot=$slot"
      HOLD_RESULT="rejected"
      return 0
    fi
    return 1
  fi

  if [[ "$phase" == "post" &&
        ( "$label" == "child" || "$label" == "watchdog" ) ]]; then
    if [[ -e "$release_path" || -L "$release_path" ]]; then
      if ! private_marker_valid "$release_path"; then
        : >"$protocol_path" || true
        HOLD_RESULT="protocol"
        return 0
      fi
      trace_event "hold|$label|phase=post|released|slot=$slot"
      HOLD_RESULT="released"
      return 0
    fi
    return 1
  fi

  : >"$protocol_path" || true
  HOLD_RESULT="protocol"
  return 0
}

symbol_preflight_release_preempts_rejection() {
  local release_path="$1"
  local protocol_path="$2"
  local slot="$3"
  if [[ ! -e "$release_path" && ! -L "$release_path" ]]; then
    return 1
  fi
  if ! private_marker_valid "$release_path"; then
    : >"$protocol_path" || true
    transition_symbol_preflight_child_quiescence protocol_failed || true
    HOLD_RESULT="protocol"
    return 0
  fi
  if [[ -e "$symbol_preflight_quiescence_disposition" ||
        -L "$symbol_preflight_quiescence_disposition" ||
        -e "$symbol_preflight_quiescence_authorized" ||
        -L "$symbol_preflight_quiescence_authorized" ||
        -e "$symbol_preflight_quiescence_rejected" ||
        -L "$symbol_preflight_quiescence_rejected" ]]; then
    : >"$protocol_path" || true
  fi
  trace_event \
    "hold|child|phase=symbol-preflight-quiescence|aborted|slot=$slot"
  transition_symbol_preflight_child_quiescence aborted || true
  HOLD_RESULT="aborted"
  return 0
}

elect_symbol_preflight_child_rejection() {
  local value="$1"
  local slot="$2"
  local event="$3"
  local release_path="$4"
  local protocol_path="$5"
  local election_status=0

  if symbol_preflight_release_preempts_rejection \
      "$release_path" "$protocol_path" "$slot"; then
    return 0
  fi
  if ! transition_symbol_preflight_child_quiescence electing_rejection; then
    : >"$protocol_path" || true
    transition_symbol_preflight_child_quiescence protocol_failed || true
    HOLD_RESULT="protocol"
    return 0
  fi
  elect_symbol_preflight_quiescence_disposition child "$value"
  election_status=$?
  if [[ "$election_status" -ne 0 ]]; then
    if [[ "$SYMBOL_PREFLIGHT_ELECTION_PREEMPTED" == true ]] &&
        symbol_preflight_release_preempts_rejection \
          "$release_path" "$protocol_path" "$slot"; then
      return 0
    fi
    : >"$protocol_path" || true
    transition_symbol_preflight_child_quiescence protocol_failed || true
    HOLD_RESULT="protocol"
    return 0
  fi
  if symbol_preflight_release_preempts_rejection \
      "$release_path" "$protocol_path" "$slot"; then
    return 0
  fi

  case "$event" in
    unexpected-data)
      trace_event \
        "anchor_tick|child|phase=symbol-preflight-quiescence|slot=$slot|result=unexpected-data|signal=${anchor_signal_observed:-false}"
      ;;
    ceiling)
      trace_event \
        "hold|child|phase=symbol-preflight-quiescence|ceiling|slot=30"
      ;;
    *)
      : >"$protocol_path" || true
      transition_symbol_preflight_child_quiescence protocol_failed || true
      HOLD_RESULT="protocol"
      return 0
      ;;
  esac

  case "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" in
    reject:snapshot|reject:unexpected-data|reject:ceiling)
      transition_symbol_preflight_child_quiescence rejected || true
      HOLD_RESULT="rejected"
      ;;
    authorize)
      : >"$protocol_path" || true
      transition_symbol_preflight_child_quiescence protocol_failed || true
      HOLD_RESULT="protocol"
      ;;
    *)
      : >"$protocol_path" || true
      transition_symbol_preflight_child_quiescence protocol_failed || true
      HOLD_RESULT="protocol"
      ;;
  esac
  return 0
}

hold_anchor_fifo() {
  local phase="$1"
  local label="$2"
  local fd="$3"
  local release_path="$4"
  local success_path="$5"
  local protocol_path="$6"
  local slot=0
  local value=""
  local read_status=0
  local signal_seen=false

  HOLD_RESULT=""
  if evaluate_hold_boundary \
      "$phase" "$label" "$release_path" "$success_path" \
      "$protocol_path" "$slot"; then
    return 0
  fi

  while [[ "$slot" -lt 30 ]]; do
    IFS= read -r -t 1 -u "$fd" value
    read_status=$?
    slot=$((slot + 1))
    if [[ "$read_status" -eq 0 ]]; then
      if [[ "$phase" == "symbol-preflight-quiescence" &&
            "$label" == child ]]; then
        elect_symbol_preflight_child_rejection \
          reject:unexpected-data "$slot" unexpected-data \
          "$release_path" "$protocol_path"
        return 0
      fi
      : >"$protocol_path" || true
      trace_event \
        "anchor_tick|$label|phase=$phase|slot=$slot|result=unexpected-data|signal=${anchor_signal_observed:-false}"
      HOLD_RESULT="unexpected-data"
      return 0
    fi
    signal_seen="${anchor_signal_observed:-false}"
    trace_event \
      "anchor_tick|$label|phase=$phase|slot=$slot|result=tick|signal=$signal_seen"
    anchor_signal_observed=false
    if evaluate_hold_boundary \
        "$phase" "$label" "$release_path" "$success_path" \
        "$protocol_path" "$slot"; then
      return 0
    fi
  done

  if [[ "$phase" == "symbol-preflight-quiescence" &&
        "$label" == child ]]; then
    elect_symbol_preflight_child_rejection \
      reject:ceiling 30 ceiling "$release_path" "$protocol_path"
    return 0
  fi
  : >"$protocol_path" || true
  trace_event "hold|$label|phase=$phase|ceiling|slot=30"
  HOLD_RESULT="ceiling"
  return 0
}

hold_failed_anchor() {
  local label="$1"
  local phase="$2"
  local reason="$3"
  trace_event "failure_hold|$label|phase=$phase|reason=$reason|start"
  exec 3>&-
  set +m
  trap '' INT TERM HUP
  /bin/sleep 30 3>&- 8>&- 9>&-
  trace_event "failure_hold|$label|phase=$phase|reason=$reason|return"
  return 0
}

wait_for_fifo_setup_begin() {
  local ticks=0
  while [[ "$ticks" -lt 50 ]]; do
    if [[ -e "$child_release" || -L "$child_release" ]]; then
      private_marker_valid "$child_release" || return 1
      return 2
    fi
    if [[ -e "$fifo_setup_begin" || -L "$fifo_setup_begin" ]]; then
      private_marker_valid "$fifo_setup_begin" || return 1
      return 0
    fi
    /bin/sleep 0.1 3>&- 8>&- 9>&-
    ticks=$((ticks + 1))
  done
  return 1
}

stat_mode_is_600() {
  local path="$1"
  local mode=""
  if [[ "$OS_NAME" == "darwin" ]]; then
    mode="$(stat -f '%Lp' "$path" 3>&- 8>&- 9>&-)" || return 1
  else
    mode="$(stat -c '%a' "$path" 3>&- 8>&- 9>&-)" || return 1
  fi
  [[ "$mode" =~ ^0*600$ ]]
}

validate_empty_capture() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" && -O "$path" && ! -s "$path" ]] ||
    return 1
  stat_mode_is_600 "$path"
}

validate_anchor_fifo() {
  local path="$1"
  local basename="$2"
  local stdout_capture="$3"
  local stderr_capture="$4"
  [[ "${path%/*}" == "$TMP_DIR" &&
     "${path##*/}" == "$basename" &&
     -p "$path" && ! -L "$path" && -O "$path" ]] || return 1
  stat_mode_is_600 "$path" || return 1
  validate_empty_capture "$stdout_capture" || return 1
  validate_empty_capture "$stderr_capture"
}

observe_fifo_setup_error() {
  local marker=""
  local diagnostic=""
  FIFO_ERROR_DIAGNOSTIC=""
  for marker in \
    "$fifo_watchdog_create_error" \
    "$fifo_watchdog_invalid" \
    "$fifo_child_create_error" \
    "$fifo_child_invalid" \
    "$fifo_setup_protocol_error"; do
    if [[ ! -e "$marker" && ! -L "$marker" ]]; then
      continue
    fi
    case "$marker" in
      "$fifo_watchdog_create_error")
        diagnostic="could not create Go snapshot watchdog anchor FIFO"
        ;;
      "$fifo_watchdog_invalid")
        diagnostic="invalid Go snapshot watchdog anchor FIFO"
        ;;
      "$fifo_child_create_error")
        diagnostic="could not create Go snapshot child anchor FIFO"
        ;;
      "$fifo_child_invalid")
        diagnostic="invalid Go snapshot child anchor FIFO"
        ;;
      *) diagnostic="could not complete Go snapshot FIFO setup" ;;
    esac
    if ! private_marker_valid "$marker"; then
      diagnostic="could not complete Go snapshot FIFO setup"
    fi
    FIFO_ERROR_DIAGNOSTIC="$diagnostic"
    return 0
  done
  return 1
}

publish_child_candidate() {
  local status="$1"
  printf 'child:%s\n' "$status" >"$child_candidate" || {
    : >"$child_protocol_error"
    return 1
  }
  if /bin/ln "$child_candidate" "$outcome" 2>"$child_link_stderr" 3>&-; then
    return 0
  fi
  if [[ -f "$outcome" && ! -L "$outcome" &&
        -f "$watchdog_candidate" &&
        "$outcome" -ef "$watchdog_candidate" ]] &&
      read_exact_line "$outcome" && [[ "$READ_LINE" == "timeout" ]]; then
    return 0
  fi
  : >"$child_protocol_error"
  return 1
}

publish_watchdog_candidate() {
  printf 'timeout\n' >"$watchdog_candidate" || {
    : >"$watchdog_protocol_error"
    return 1
  }
  if /bin/ln "$watchdog_candidate" "$outcome" \
      2>"$watchdog_link_stderr" 3>&-; then
    return 0
  fi
  if [[ -f "$outcome" && ! -L "$outcome" &&
        -f "$child_candidate" &&
        "$outcome" -ef "$child_candidate" ]] &&
      read_exact_line "$outcome" &&
      [[ "$READ_LINE" =~ ^child:([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
    return 0
  fi
  : >"$watchdog_protocol_error"
  return 1
}

validate_outcome() {
  local digits=""
  local normalized=""
  local value=0
  OUTCOME_CAUSE=""
  OUTCOME_STATUS=""
  if [[ ! -f "$outcome" || -L "$outcome" ]]; then
    return 1
  fi

  if [[ -f "$child_candidate" && "$outcome" -ef "$child_candidate" ]]; then
    if [[ -f "$watchdog_candidate" &&
          "$outcome" -ef "$watchdog_candidate" ]]; then
      return 1
    fi
    if ! read_exact_line "$outcome" ||
        [[ ! "$READ_LINE" =~ ^child:[0-9]+$ ]]; then
      return 1
    fi
    digits="${READ_LINE#child:}"
    normalized="$digits"
    while [[ "${#normalized}" -gt 1 && "${normalized:0:1}" == "0" ]]; do
      normalized="${normalized#0}"
    done
    if [[ "${#normalized}" -gt 3 ]]; then
      return 1
    fi
    value=$((10#$normalized))
    if [[ "$value" -gt 255 ]]; then
      return 1
    fi
    OUTCOME_CAUSE="child"
    OUTCOME_STATUS="$value"
    return 0
  fi

  if [[ -f "$watchdog_candidate" &&
        "$outcome" -ef "$watchdog_candidate" ]]; then
    if ! read_exact_line "$outcome" || [[ "$READ_LINE" != "timeout" ]]; then
      return 1
    fi
    OUTCOME_CAUSE="timeout"
    OUTCOME_STATUS=124
    return 0
  fi
  return 1
}

anchor_identity_is_live() {
  local label="$1"
  local pid=""
  local pgid=""
  local owned=false
  if [[ "$label" == "child" ]]; then
    pid="$child_pid"
    pgid="$child_pgid"
    owned="$child_anchor_owned"
  else
    pid="$watchdog_pid"
    pgid="$watchdog_pgid"
    owned="$watchdog_anchor_owned"
  fi
  if [[ "$owned" != true ]]; then
    return 1
  fi
  if ! snapshot_group "$pid" "$pgid"; then
    return 1
  fi
  [[ "$SNAPSHOT_OK" == true &&
     "$SNAPSHOT_ANCHOR_PRESENT" == true &&
     "$SNAPSHOT_ANCHOR_PGID" == "$pgid" ]] || return 1
  supported_live_state "$SNAPSHOT_ANCHOR_STAT"
}

freeze_anchor() {
  local label="$1"
  local pid=""
  local pgid=""
  if [[ "$label" == "child" ]]; then
    if [[ "$child_cleanup_action" != "unset" ]]; then
      mark_cleanup_failure
      return 1
    fi
    pid="$child_pid"
    pgid="$child_pgid"
    child_cleanup_action="frozen"
    child_anchor_owned=false
  else
    if [[ "$watchdog_cleanup_action" != "unset" ]]; then
      mark_cleanup_failure
      return 1
    fi
    pid="$watchdog_pid"
    pgid="$watchdog_pgid"
    watchdog_cleanup_action="frozen"
    watchdog_anchor_owned=false
  fi
  trace_event "action|$label|frozen|pid=$pid|pgid=$pgid"
  mark_cleanup_failure
}

send_group_signal() {
  local label="$1"
  local signal_name="$2"
  local pgid=""
  if ! anchor_identity_is_live "$label"; then
    freeze_anchor "$label"
    return 1
  fi
  if [[ "$label" == "child" ]]; then
    pgid="$child_pgid"
  else
    pgid="$watchdog_pgid"
  fi
  trace_event \
    "snapshot|$label|pid=$pgid|pgid=$SNAPSHOT_ANCHOR_PGID|stat=$SNAPSHOT_ANCHOR_STAT|members=$SNAPSHOT_MEMBER_COUNT"
  trace_event "signal|$label|$signal_name|pgid=$pgid"
  if ! kill "-$signal_name" -- "-$pgid" 3>&-; then
    mark_cleanup_failure
    return 1
  fi
  return 0
}

choose_final_anchor_action() {
  local label="$1"
  local pid=""
  local pgid=""
  local release=""
  local state=""
  local members=0
  if [[ "$label" == "child" ]]; then
    pid="$child_pid"
    pgid="$child_pgid"
    release="$child_release"
    if [[ "$child_anchor_owned" != true ]]; then
      return 1
    fi
    if [[ "$child_cleanup_action" != "unset" ]]; then
      mark_cleanup_failure
      return 1
    fi
  else
    pid="$watchdog_pid"
    pgid="$watchdog_pgid"
    release="$watchdog_release"
    if [[ "$watchdog_anchor_owned" != true ]]; then
      return 1
    fi
    if [[ "$watchdog_cleanup_action" != "unset" ]]; then
      mark_cleanup_failure
      return 1
    fi
  fi

  if ! snapshot_group "$pid" "$pgid" ||
      [[ "$SNAPSHOT_OK" != true ||
         "$SNAPSHOT_ANCHOR_PRESENT" != true ||
         "$SNAPSHOT_ANCHOR_PGID" != "$pgid" ]] ||
      ! supported_live_state "$SNAPSHOT_ANCHOR_STAT"; then
    freeze_anchor "$label"
    return 1
  fi
  state="$SNAPSHOT_ANCHOR_STAT"
  members="$SNAPSHOT_MEMBER_COUNT"
  trace_event \
    "snapshot|$label|pid=$pid|pgid=$SNAPSHOT_ANCHOR_PGID|stat=$state|members=$members"

  if [[ "$members" -gt 1 || "$state" == T* || "$state" == t* ]]; then
    trace_event "signal|$label|KILL|pgid=$pgid"
    if ! kill -KILL -- "-$pgid" 3>&-; then
      mark_cleanup_failure
    fi
    if [[ "$label" == "child" ]]; then
      child_cleanup_action="final_kill_attempted"
      child_anchor_owned=false
    else
      watchdog_cleanup_action="final_kill_attempted"
      watchdog_anchor_owned=false
    fi
    trace_event "action|$label|final_kill|pid=$pid|pgid=$pgid"
    return 0
  fi

  if [[ "$members" -eq 1 && ( "$state" == R* || "$state" == S* ) ]]; then
    if ! : >"$release"; then
      mark_cleanup_failure
    fi
    if [[ "$label" == "child" ]]; then
      child_cleanup_action="release_attempted"
      child_anchor_owned=false
    else
      watchdog_cleanup_action="release_attempted"
      watchdog_anchor_owned=false
    fi
    trace_event "action|$label|release|pid=$pid|pgid=$pgid"
    return 0
  fi

  freeze_anchor "$label"
  return 1
}

consume_terminal_status() {
  local label="$1"
  local pid=""
  local ticks=0
  local observed_absent=false
  local wait_status=0
  if [[ "$label" == "child" ]]; then
    if [[ "$child_terminal_consumed" == true ]]; then
      return 0
    fi
    pid="$child_pid"
  else
    if [[ "$watchdog_terminal_consumed" == true ]]; then
      return 0
    fi
    pid="$watchdog_pid"
  fi

  while [[ "$ticks" -lt 5 ]]; do
    snapshot_pid_absent "$pid"
    case "$?" in
      0)
        observed_absent=true
        trace_event "pid_absent|$label|pid=$pid"
        break
        ;;
      1)
        mark_cleanup_failure
        ;;
      2) ;;
    esac
    /bin/sleep 1 3>&-
    ticks=$((ticks + 1))
  done

  if [[ "$observed_absent" != true ]]; then
    mark_cleanup_failure
    return 1
  fi
  trace_event "wait_attempt|$label|pid=$pid"
  wait "$pid" || wait_status=$?
  trace_event "wait_cached|$label|pid=$pid|status=$wait_status"
  case "$wait_status" in
    [0-9]|[0-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
    *) mark_cleanup_failure ;;
  esac
  if [[ "$label" == "child" ]]; then
    child_terminal_consumed=true
  else
    watchdog_terminal_consumed=true
  fi
  trace_event "wait_consumed|$label|pid=$pid|status=$wait_status|count=1"
  return 0
}

cleanup_accepted_anchor() {
  local label="$1"
  local first_signal="$2"
  local still_owned=false
  local cleanup_action="unset"
  local held=""
  local anchor_pid=""

  if [[ "$label" == "child" ]]; then
    [[ "$child_launch_state" == "accepted" ]] || return 0
    [[ "$child_terminal_consumed" != true ]] || return 0
    cleanup_action="$child_cleanup_action"
    held="$child_held"
    anchor_pid="$child_pid"
  else
    [[ "$watchdog_launch_state" == "accepted" ]] || return 0
    [[ "$watchdog_terminal_consumed" != true ]] || return 0
    cleanup_action="$watchdog_cleanup_action"
    held="$watchdog_held"
    anchor_pid="$watchdog_pid"
  fi

  if [[ "$cleanup_action" == "unset" ]]; then
    send_group_signal "$label" "$first_signal" || true
    /bin/sleep 1 3>&-
    if [[ -f "$held" ]]; then
      trace_event "held|$label|pid=$anchor_pid"
    fi

    if [[ "$first_signal" == "INT" ]]; then
      if [[ "$label" == "child" ]]; then
        still_owned="$child_anchor_owned"
      else
        still_owned="$watchdog_anchor_owned"
      fi
      if [[ "$still_owned" == true ]]; then
        send_group_signal "$label" TERM || true
        /bin/sleep 1 3>&-
      fi
    fi

    if [[ "$label" == "child" ]]; then
      still_owned="$child_anchor_owned"
    else
      still_owned="$watchdog_anchor_owned"
    fi
    if [[ "$still_owned" == true ]]; then
      choose_final_anchor_action "$label" || true
    fi
  fi
  consume_terminal_status "$label" || true
}

all_launched_terminal_consumed() {
  if [[ "$child_launch_state" != "not_launched" &&
        "$child_terminal_consumed" != true ]]; then
    return 1
  fi
  if [[ "$watchdog_launch_state" != "not_launched" &&
        "$watchdog_terminal_consumed" != true ]]; then
    return 1
  fi
  return 0
}

remove_temp_owner() {
  local expected_path=""
  if [[ "$TMP_DIR" == "" ]]; then
    return 0
  fi
  if [[ "$TMP_PARENT" == "/" ]]; then
    expected_path="/$TMP_BASENAME"
  else
    expected_path="$TMP_PARENT/$TMP_BASENAME"
  fi
  if [[ "$expected_path" != "$TMP_DIR" ||
        "$TMP_BASENAME" != opentui-go-snapshot.* ]]; then
    mark_cleanup_failure
    return 1
  fi
  if ! rm -rf -- "$TMP_DIR" 3>&-; then
    mark_cleanup_failure
    diagnose_retained_removal
    return 1
  fi
  return 0
}

cleanup_all() {
  local child_first=TERM
  if [[ "$cleanup_started" == true ]]; then
    return 0
  fi
  cleanup_started=true
  set +e
  set +o pipefail
  trace_event "cleanup|start|cause=${cause_record%%:*}"

  if [[ "$watchdog_launch_state" == "accepted" ]]; then
    : >"$watchdog_cancel" || mark_cleanup_failure
  fi
  if [[ "$cause_record" == "signal:130" ]]; then
    child_first=INT
  fi
  cleanup_accepted_anchor child "$child_first"
  cleanup_accepted_anchor watchdog TERM

  if all_launched_terminal_consumed; then
    remove_temp_owner || true
  else
    mark_cleanup_failure
    if [[ "$retained_diagnostic_emitted" != true ]]; then
      owned_diagnostic \
        "cleanup could not prove terminal consumption; retained temporary directory: $TMP_DIR"
      retained_diagnostic_emitted=true
    fi
  fi
  return 0
}

finalize() {
  local final_status="${cause_record##*:}"
  cleanup_all
  if [[ "$cleanup_failed" == true && "$final_status" -eq 0 ]]; then
    final_status=1
  fi
  if [[ "$cleanup_failed" == true ]]; then
    owned_diagnostic "Go snapshot cleanup did not complete safely."
  fi
  trap - EXIT
  exec 3>&-
  exit "$final_status"
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
unexpected_exit() {
  local observed_status="$?"
  if [[ "$cleanup_started" != true ]]; then
    if [[ "$observed_status" -eq 0 ]]; then
      observed_status=1
    fi
    commit_cause protocol "$observed_status" || true
    finalize
  fi
  trap - EXIT
  exec 3>&-
  exit "$observed_status"
}

# shellcheck disable=SC2329 # Invoked by the HUP trap.
unexpected_hup() {
  if [[ "$cleanup_started" == true ]]; then
    trace_event "late_signal|HUP|ignored|cause=${cause_record%%:*}"
    return 0
  fi
  commit_cause protocol 129 || true
  finalize
}

drain_unaccepted_anchor() {
  local label="$1"
  local pid=""
  local ticks=0
  local absent=false
  local wait_status=0
  if [[ "$label" == "child" ]]; then
    [[ "$child_launch_state" != "not_launched" ]] || return 0
    pid="$child_pid"
  else
    [[ "$watchdog_launch_state" != "not_launched" ]] || return 0
    pid="$watchdog_pid"
  fi
  trace_event "validation_drain|$label|start|pid=$pid"

  while [[ "$ticks" -lt 7 ]]; do
    snapshot_pid_absent "$pid"
    case "$?" in
      0)
        absent=true
        trace_event "pid_absent|$label|pid=$pid"
        break
        ;;
      1) ;;
      2) ;;
    esac
    /bin/sleep 1 3>&-
    ticks=$((ticks + 1))
  done
  if [[ "$absent" != true ]]; then
    return 1
  fi
  trace_event "wait_attempt|$label|pid=$pid"
  wait "$pid" || wait_status=$?
  trace_event "wait_cached|$label|pid=$pid|status=$wait_status"
  case "$wait_status" in
    [0-9]|[0-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
    *) return 1 ;;
  esac
  if [[ "$label" == "child" ]]; then
    child_terminal_consumed=true
    child_anchor_owned=false
  else
    watchdog_terminal_consumed=true
    watchdog_anchor_owned=false
  fi
  trace_event "wait_consumed|$label|pid=$pid|status=$wait_status|count=1"
  return 0
}

finish_validation_failure() {
  local failed_label="$1"
  local final_status=1
  local retained=false
  commit_cause protocol 1 || true
  cleanup_started=true
  set +e
  set +o pipefail
  trace_event "cleanup|start|cause=${cause_record%%:*}"

  if [[ "${cause_record%%:*}" != "signal" ]]; then
    owned_diagnostic "failed to verify $failed_label process-group anchor"
  fi

  if ! drain_unaccepted_anchor child; then
    retained=true
  fi
  if ! drain_unaccepted_anchor watchdog; then
    retained=true
  fi
  if [[ "$retained" == true ]]; then
    owned_diagnostic \
      "cleanup could not prove terminal consumption; retained temporary directory: $TMP_DIR"
  else
    if ! remove_temp_owner; then
      retained=true
      diagnose_retained_removal
    fi
  fi

  final_status="${cause_record##*:}"
  trap - EXIT
  exec 3>&-
  exit "$final_status"
}

parse_timeout() {
  local raw=""
  local normalized=""
  if [[ "${GO_SNAPSHOT_TIMEOUT_SECONDS+x}" != x ]]; then
    timeout_seconds=90
    return 0
  fi
  raw="$GO_SNAPSHOT_TIMEOUT_SECONDS"
  if [[ "$raw" == "" || ! "$raw" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  normalized="$raw"
  while [[ "${#normalized}" -gt 1 && "${normalized:0:1}" == "0" ]]; do
    normalized="${normalized#0}"
  done
  if [[ "${#normalized}" -gt 4 ]]; then
    return 1
  fi
  timeout_seconds=$((10#$normalized))
  [[ "$timeout_seconds" -ge 1 && "$timeout_seconds" -le 3600 ]]
}

close_symbol_preflight_result() {
  local value="$1"
  if ! private_path_absent "$symbol_preflight_result" ||
      ! printf '%s\n' "$value" >"$symbol_preflight_result" ||
      ! private_marker_valid "$symbol_preflight_result" ||
      ! read_exact_line "$symbol_preflight_result" ||
      [[ "$READ_LINE" != "$value" ]]; then
    : >"$child_protocol_error" || true
    return 1
  fi
  SYMBOL_PREFLIGHT_RESULT="$value"
  return 0
}

publish_symbol_preflight_failure() {
  local value="$1"
  close_symbol_preflight_result "$value" || return 2
  trace_event "symbol_preflight|fail-tool-published"
  publish_child_candidate 1 || {
    : >"$child_protocol_error" || true
    return 2
  }
  return 1
}

parse_symbol_preflight_output() {
  local line=""
  local token=""
  local index=0
  local malformed=false
  local -a fields=()
  local char_ptr=0
  local fg_ptr=0
  local bg_ptr=0
  local attributes_ptr=0
  local set_cell=0
  local line_starts_ptr=0
  local line_widths_ptr=0
  local concat=0
  local resize=0
  local capacity=0
  local missing=""
  local added=""

  if [[ ! -f "$symbol_preflight_stdout" ||
        -L "$symbol_preflight_stdout" ||
        ! -O "$symbol_preflight_stdout" ||
        ! -f "$symbol_preflight_stderr" ||
        -L "$symbol_preflight_stderr" ||
        ! -O "$symbol_preflight_stderr" ||
        -s "$symbol_preflight_stderr" ]] ||
      ! exec 4<"$symbol_preflight_stdout"; then
    publish_symbol_preflight_failure fail:tool
    return $?
  fi

  while IFS= read -r line <&4 || [[ "$line" != "" ]]; do
    fields=()
    IFS=$' \t' read -r -a fields <<<"$line"
    if [[ "${#fields[@]}" -eq 0 ]]; then
      continue
    fi
    index=$((${#fields[@]} - 1))
    token="${fields[$index]}"
    if [[ "$OS_NAME" == darwin && "$token" == _* ]]; then
      token="${token#_}"
    fi
    case "$token" in
      textBufferGetCharPtr) char_ptr=$((char_ptr + 1)) ;;
      textBufferGetFgPtr) fg_ptr=$((fg_ptr + 1)) ;;
      textBufferGetBgPtr) bg_ptr=$((bg_ptr + 1)) ;;
      textBufferGetAttributesPtr)
        attributes_ptr=$((attributes_ptr + 1))
        ;;
      textBufferSetCell) set_cell=$((set_cell + 1)) ;;
      textBufferGetLineStartsPtr)
        line_starts_ptr=$((line_starts_ptr + 1))
        ;;
      textBufferGetLineWidthsPtr)
        line_widths_ptr=$((line_widths_ptr + 1))
        ;;
      textBufferConcat) concat=$((concat + 1)) ;;
      textBufferResize) resize=$((resize + 1)) ;;
      textBufferGetCapacity) capacity=$((capacity + 1)) ;;
    esac
  done
  exec 4<&-

  for count in \
    "$char_ptr" "$fg_ptr" "$bg_ptr" "$attributes_ptr" "$set_cell" \
    "$line_starts_ptr" "$line_widths_ptr" "$concat" "$resize" \
    "$capacity"; do
    if [[ "$count" -gt 1 ]]; then
      malformed=true
    fi
  done
  if [[ "$malformed" == true ]]; then
    publish_symbol_preflight_failure fail:tool
    return $?
  fi

  if [[ "$char_ptr" -eq 0 ]]; then missing="textBufferGetCharPtr"; fi
  if [[ "$fg_ptr" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferGetFgPtr"
  fi
  if [[ "$bg_ptr" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferGetBgPtr"
  fi
  if [[ "$attributes_ptr" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferGetAttributesPtr"
  fi
  if [[ "$set_cell" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferSetCell"
  fi
  if [[ "$line_starts_ptr" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferGetLineStartsPtr"
  fi
  if [[ "$line_widths_ptr" -eq 0 ]]; then
    missing="${missing:+$missing,}textBufferGetLineWidthsPtr"
  fi
  if [[ "$concat" -gt 0 ]]; then added="textBufferConcat"; fi
  if [[ "$resize" -gt 0 ]]; then
    added="${added:+$added,}textBufferResize"
  fi
  if [[ "$capacity" -gt 0 ]]; then
    added="${added:+$added,}textBufferGetCapacity"
  fi

  if [[ "$missing" != "" || "$added" != "" ]]; then
    close_symbol_preflight_result \
      "fail:drift:${missing:--}:${added:--}" || return 2
    publish_child_candidate 1 || {
      : >"$child_protocol_error" || true
      return 2
    }
    return 1
  fi
  close_symbol_preflight_result pass || return 2
  p9_043_symbol_preflight_passed=true
  readonly p9_043_symbol_preflight_passed
  return 0
}

run_selected_artifact_symbol_preflight() {
  local direct_status=0
  local hold_result=""
  local close_status=0

  (
    exec 3>&-
    exec 8>&-
    exec 9>&-
    exec -c "${symbol_nm_argv[@]}"
  ) </dev/null >"$symbol_preflight_stdout" 2>"$symbol_preflight_stderr"
  direct_status=$?
  trace_event "symbol_preflight|nm-direct-status|status=$direct_status"
  if [[ "$direct_status" -ne 0 ]]; then
    publish_symbol_preflight_failure fail:tool
    return $?
  fi

  if ! private_path_absent "$symbol_preflight_quiescence_held" ||
      ! private_path_absent "$symbol_preflight_quiescence_parent_candidate" ||
      ! private_path_absent "$symbol_preflight_quiescence_child_candidate" ||
      ! private_path_absent "$symbol_preflight_quiescence_disposition" ||
      ! private_path_absent "$symbol_preflight_quiescence_parent_ln_stderr" ||
      ! private_path_absent "$symbol_preflight_quiescence_child_ln_stderr" ||
      ! private_path_absent "$symbol_preflight_quiescence_authorized" ||
      ! private_path_absent "$symbol_preflight_quiescence_rejected" ||
      ! private_path_absent "$symbol_preflight_quiescence_closed" ||
      [[ ! -p "$child_anchor_fifo" || -L "$child_anchor_fifo" ||
         ! -O "$child_anchor_fifo" ]] ||
      ! exec 8<>"$child_anchor_fifo"; then
    exec 8>&-
    publish_symbol_preflight_failure fail:tool
    return $?
  fi
  trace_event \
    "fifo|child|symbol-preflight-quiescence-opened|fd=8"
  if ! : >"$symbol_preflight_quiescence_held" ||
      ! private_marker_valid "$symbol_preflight_quiescence_held"; then
    exec 8>&-
    trace_event \
      "fifo|child|symbol-preflight-quiescence-closed|fd=8"
    publish_symbol_preflight_failure fail:tool
    return $?
  fi
  trace_event \
    "hold|child|phase=symbol-preflight-quiescence|held|slot=0"
  if ! transition_symbol_preflight_child_quiescence held; then
    exec 8>&-
    trace_event \
      "fifo|child|symbol-preflight-quiescence-closed|fd=8"
    : >"$child_protocol_error" || true
    return 2
  fi
  hold_anchor_fifo symbol-preflight-quiescence child 8 \
    "$child_release" "" "$child_protocol_error"
  hold_result="$HOLD_RESULT"
  exec 8>&-
  close_status=$?
  trace_event \
    "fifo|child|symbol-preflight-quiescence-closed|fd=8"

  case "$hold_result" in
    aborted)
      trace_event "symbol_preflight|abort"
      return 2
      ;;
    authorized)
      if ! validate_symbol_preflight_quiescence_disposition ||
          [[ "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" != authorize ]] ||
          ! private_marker_valid "$symbol_preflight_quiescence_authorized" ||
          [[ -e "$symbol_preflight_quiescence_child_candidate" ||
             -L "$symbol_preflight_quiescence_child_candidate" ||
             -e "$symbol_preflight_quiescence_child_ln_stderr" ||
             -L "$symbol_preflight_quiescence_child_ln_stderr" ]] ||
          [[ -e "$symbol_preflight_quiescence_rejected" ||
             -L "$symbol_preflight_quiescence_rejected" ]]; then
        : >"$child_protocol_error" || true
        transition_symbol_preflight_child_quiescence protocol_failed || true
        return 2
      fi
      ;;
    rejected)
      if [[ "$symbol_preflight_child_quiescence_state" == held ]]; then
        transition_symbol_preflight_child_quiescence rejected || true
      fi
      publish_symbol_preflight_failure fail:tool
      return $?
      ;;
    *)
      : >"$child_protocol_error" || true
      if [[ "$symbol_preflight_child_quiescence_state" == held ]]; then
        transition_symbol_preflight_child_quiescence protocol_failed || true
      fi
      return 2
      ;;
  esac
  if [[ "$close_status" -ne 0 || -e /dev/fd/8 || -e /dev/fd/9 ]] ||
      ! : >"$symbol_preflight_quiescence_closed" ||
      ! private_marker_valid "$symbol_preflight_quiescence_closed" ||
      ! validate_symbol_preflight_quiescence_disposition ||
      [[ "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" != authorize ]] ||
      ! private_marker_valid "$symbol_preflight_quiescence_authorized" ||
      [[ -e "$symbol_preflight_quiescence_child_candidate" ||
         -L "$symbol_preflight_quiescence_child_candidate" ||
         -e "$symbol_preflight_quiescence_child_ln_stderr" ||
         -L "$symbol_preflight_quiescence_child_ln_stderr" ]] ||
      [[ -e "$symbol_preflight_quiescence_rejected" ||
         -L "$symbol_preflight_quiescence_rejected" ]] ||
      ! transition_symbol_preflight_child_quiescence authorized_closed; then
    publish_symbol_preflight_failure fail:tool
    return $?
  fi
  trace_event "symbol_preflight|parse-start"
  parse_symbol_preflight_output
}

run_child_precommands() {
  run_selected_artifact_symbol_preflight || return $?
  [[ "$SYMBOL_PREFLIGHT_RESULT" == pass &&
     "${p9_043_symbol_preflight_passed:-}" == true ]]
}

emit_symbol_preflight_diagnostic() {
  local missing=""
  local added=""
  local rest=""
  if [[ "$symbol_preflight_diagnostic_emitted" == true ||
        "$cause_record" != child:1 ]] ||
      ! read_exact_line "$symbol_preflight_result"; then
    return 0
  fi
  case "$READ_LINE" in
    fail:tool)
      owned_diagnostic \
        "OpenTUI symbol preflight failed for $symbol_selected_path: host nm inspection failed."
      ;;
    fail:drift:*)
      rest="${READ_LINE#fail:drift:}"
      missing="${rest%%:*}"
      added="${rest#*:}"
      if [[ "$missing" != - && "$added" != - ]]; then
        owned_diagnostic \
          "OpenTUI symbol preflight failed for $symbol_selected_path: missing native symbol(s): $missing; pending symbol(s) now exported: $added; retire or narrow the shim via tasks/plan.md Task 3."
      elif [[ "$missing" != - ]]; then
        owned_diagnostic \
          "OpenTUI symbol preflight failed for $symbol_selected_path: missing native symbol(s): $missing."
      elif [[ "$added" != - ]]; then
        owned_diagnostic \
          "OpenTUI symbol preflight failed for $symbol_selected_path: pending symbol(s) now exported: $added; retire or narrow the shim via tasks/plan.md Task 3."
      else
        return 0
      fi
      ;;
    *) return 0 ;;
  esac
  symbol_preflight_diagnostic_emitted=true
}

if ! parse_timeout; then
  owned_diagnostic \
    "invalid GO_SNAPSHOT_TIMEOUT_SECONDS: expected decimal integer 1..3600"
  early_exit 64
fi

for required_tool in go pkg-config uname tr mktemp mkdir rm ps stat mkfifo; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    owned_diagnostic "missing required Go snapshot tool: $required_tool"
    early_exit 1
  fi
done
NM_TOOL=""
if ! NM_TOOL="$(builtin type -P nm 3>&- 2>/dev/null)" ||
    [[ "$NM_TOOL" == "" ]]; then
  owned_diagnostic "missing required Go snapshot tool: nm"
  early_exit 1
fi
if [[ "$NM_TOOL" != /* ||
      "$NM_TOOL" == *$'\n'* || "$NM_TOOL" == *$'\r'* ||
      ! -f "$NM_TOOL" || ! -x "$NM_TOOL" ]]; then
  owned_diagnostic "invalid resolved Go snapshot tool path: nm"
  early_exit 1
fi
readonly NM_TOOL
MKFIFO_TOOL="$(command -v mkfifo 3>&- 2>/dev/null)" || MKFIFO_TOOL=""
if [[ "$MKFIFO_TOOL" == "" || "$MKFIFO_TOOL" != /* ||
      ! -x "$MKFIFO_TOOL" || -d "$MKFIFO_TOOL" ]]; then
  owned_diagnostic "missing required Go snapshot tool: mkfifo"
  early_exit 1
fi
readonly MKFIFO_TOOL
if [[ ! -x /bin/ln || ! -x /bin/sleep ]]; then
  owned_diagnostic "missing required Go snapshot tool: /bin/ln or /bin/sleep"
  early_exit 1
fi

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
if [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="."
fi
if ! ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"; then
  owned_diagnostic "could not resolve the Go snapshot repository root"
  early_exit 1
fi
TOOL_DIR="$ROOT_DIR/tools/parity/go_snapshot"
HEADER_DIR="$ROOT_DIR/external/opentui/packages/go"
CACHE_ROOT="$ROOT_DIR/.dart_tool/go"

if ! UNAME_SYSTEM="$(uname -s 3>&-)" ||
    ! OS_NAME="$(printf '%s' "$UNAME_SYSTEM" | tr '[:upper:]' '[:lower:]' 3>&-)" ||
    ! ARCH_NAME="$(uname -m 3>&-)"; then
  owned_diagnostic "could not determine the Go snapshot host"
  early_exit 1
fi

case "$OS_NAME" in
  darwin)
    HOST_OS="darwin"
    LIB_OS_DIR="macos"
    LIB_EXT="dylib"
    LIB_ENV_VAR="DYLD_LIBRARY_PATH"
    ;;
  linux)
    HOST_OS="linux"
    LIB_OS_DIR="linux"
    LIB_EXT="so"
    LIB_ENV_VAR="LD_LIBRARY_PATH"
    ;;
  *)
    owned_diagnostic "unsupported host OS: $OS_NAME"
    early_exit 1
    ;;
esac

case "$ARCH_NAME" in
  arm64|aarch64)
    HOST_ARCH="arm64"
    GO_ARCH="arm64"
    ;;
  x86_64|amd64)
    HOST_ARCH="x64"
    GO_ARCH="amd64"
    ;;
  *)
    owned_diagnostic "unsupported host architecture: $ARCH_NAME"
    early_exit 1
    ;;
esac

LIB_DIR="$ROOT_DIR/native/$LIB_OS_DIR/$HOST_ARCH"
LIB_PATH="$LIB_DIR/libopentui.$LIB_EXT"
if [[ ! -f "$LIB_PATH" ]]; then
  owned_diagnostic "missing native library: $LIB_PATH"
  early_exit 1
fi
if [[ ! -f "$HEADER_DIR/opentui.h" ]]; then
  owned_diagnostic "missing OpenTUI header: $HEADER_DIR/opentui.h"
  early_exit 1
fi
if [[ ! -d "$TOOL_DIR" ]]; then
  owned_diagnostic "missing Go snapshot tool directory: $TOOL_DIR"
  early_exit 1
fi

symbol_selected_path="$LIB_PATH"
if [[ "$OS_NAME" == darwin ]]; then
  symbol_nm_argv=("$NM_TOOL" -gU "$symbol_selected_path")
else
  symbol_nm_argv=("$NM_TOOL" -D --defined-only "$symbol_selected_path")
fi
readonly symbol_selected_path
readonly -a symbol_nm_argv

TMP_ROOT="${TMPDIR:-/tmp}"
if [[ "$TMP_ROOT" != /* || ! -d "$TMP_ROOT" || -L "$TMP_ROOT" ]]; then
  owned_diagnostic "invalid TMPDIR for Go snapshot wrapper"
  early_exit 1
fi
if ! TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)" ||
    [[ "$TMP_ROOT" == "" || "$TMP_ROOT" != /* ]]; then
  owned_diagnostic "invalid TMPDIR for Go snapshot wrapper"
  early_exit 1
fi
if [[ "$TMP_ROOT" == "/" ]]; then
  TMP_TEMPLATE="/opentui-go-snapshot.XXXXXX"
else
  TMP_TEMPLATE="$TMP_ROOT/opentui-go-snapshot.XXXXXX"
fi
umask 077
if ! TMP_CANDIDATE="$(mktemp -d "$TMP_TEMPLATE" 3>&-)" ||
    [[ "$TMP_CANDIDATE" == "" ]]; then
  owned_diagnostic "could not create the Go snapshot temporary directory"
  early_exit 1
fi
TMP_CANDIDATE_PARENT="${TMP_CANDIDATE%/*}"
if [[ "$TMP_CANDIDATE_PARENT" == "" && "$TMP_CANDIDATE" == /* ]]; then
  TMP_CANDIDATE_PARENT="/"
fi
TMP_CANDIDATE_BASENAME="${TMP_CANDIDATE##*/}"
if [[ "$OS_NAME" == "darwin" ]]; then
  TMP_CANDIDATE_MODE="$(stat -f '%Lp' "$TMP_CANDIDATE" 3>&-)" ||
    TMP_CANDIDATE_MODE=""
else
  TMP_CANDIDATE_MODE="$(stat -c '%a' "$TMP_CANDIDATE" 3>&-)" ||
    TMP_CANDIDATE_MODE=""
fi
if [[ "$TMP_CANDIDATE_PARENT" != "$TMP_ROOT" ||
      "$TMP_CANDIDATE_BASENAME" != opentui-go-snapshot.* ||
      ! -d "$TMP_CANDIDATE" || -L "$TMP_CANDIDATE" ||
      ! -O "$TMP_CANDIDATE" ||
      ! "$TMP_CANDIDATE_MODE" =~ ^[0-7]{3,4}$ ]] ||
    (( (8#$TMP_CANDIDATE_MODE & 077) != 0 )); then
  owned_diagnostic "invalid temporary directory returned by mktemp"
  early_exit 1
fi
TMP_DIR="$TMP_CANDIDATE"
TMP_PARENT="$TMP_CANDIDATE_PARENT"
TMP_BASENAME="$TMP_CANDIDATE_BASENAME"
readonly TMP_DIR TMP_PARENT TMP_BASENAME

supervisor_stderr="$TMP_DIR/supervisor.shell.stderr"
child_stderr="$TMP_DIR/child.shell.stderr"
watchdog_stderr="$TMP_DIR/watchdog.shell.stderr"
: >"$supervisor_stderr"
: >"$child_stderr"
: >"$watchdog_stderr"
exec 2>"$supervisor_stderr"

child_ready="$TMP_DIR/child.ready"
watchdog_ready="$TMP_DIR/watchdog.ready"
child_release="$TMP_DIR/child.release"
watchdog_release="$TMP_DIR/watchdog.release"
watchdog_cancel="$TMP_DIR/watchdog.cancel"
child_held="$TMP_DIR/child.anchor-held"
watchdog_held="$TMP_DIR/watchdog.anchor-held"
child_candidate="$TMP_DIR/child.candidate"
watchdog_candidate="$TMP_DIR/watchdog.candidate"
outcome="$TMP_DIR/outcome"
child_link_stderr="$TMP_DIR/child.ln.stderr"
watchdog_link_stderr="$TMP_DIR/watchdog.ln.stderr"
child_protocol_error="$TMP_DIR/child.protocol-error"
watchdog_protocol_error="$TMP_DIR/watchdog.protocol-error"
symbol_preflight_stdout="$TMP_DIR/symbol-preflight.stdout.raw"
symbol_preflight_stderr="$TMP_DIR/symbol-preflight.stderr.raw"
symbol_preflight_result="$TMP_DIR/symbol-preflight.result"
symbol_preflight_quiescence_held="$TMP_DIR/symbol-preflight.quiescence-held"
symbol_preflight_quiescence_parent_candidate="$TMP_DIR/symbol-preflight.quiescence-parent.candidate"
symbol_preflight_quiescence_child_candidate="$TMP_DIR/symbol-preflight.quiescence-child.candidate"
symbol_preflight_quiescence_disposition="$TMP_DIR/symbol-preflight.quiescence-disposition"
symbol_preflight_quiescence_parent_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-parent.ln.stderr"
symbol_preflight_quiescence_child_ln_stderr="$TMP_DIR/symbol-preflight.quiescence-child.ln.stderr"
symbol_preflight_quiescence_authorized="$TMP_DIR/symbol-preflight.quiescence-authorized"
symbol_preflight_quiescence_rejected="$TMP_DIR/symbol-preflight.quiescence-rejected"
symbol_preflight_quiescence_closed="$TMP_DIR/symbol-preflight.quiescence-closed"

child_anchor_fifo="$TMP_DIR/child.anchor-control.fifo"
watchdog_anchor_fifo="$TMP_DIR/watchdog.anchor-control.fifo"
child_mkfifo_stdout="$TMP_DIR/child.mkfifo.stdout"
child_mkfifo_stderr="$TMP_DIR/child.mkfifo.stderr"
watchdog_mkfifo_stdout="$TMP_DIR/watchdog.mkfifo.stdout"
watchdog_mkfifo_stderr="$TMP_DIR/watchdog.mkfifo.stderr"
watchdog_deadline_pid="$TMP_DIR/watchdog.deadline.pid"
watchdog_deadline_started="$TMP_DIR/watchdog.deadline-started"
fifo_setup_begin="$TMP_DIR/fifo.setup-begin"
fifo_setup_held="$TMP_DIR/fifo.setup-held"
fifo_setup_authorized="$TMP_DIR/fifo.setup-authorized"
fifo_setup_closed="$TMP_DIR/fifo.setup-closed"
fifo_watchdog_create_error="$TMP_DIR/fifo.setup.watchdog-create-error"
fifo_watchdog_invalid="$TMP_DIR/fifo.setup.watchdog-invalid"
fifo_child_create_error="$TMP_DIR/fifo.setup.child-create-error"
fifo_child_invalid="$TMP_DIR/fifo.setup.child-invalid"
fifo_quiescence_error="$TMP_DIR/fifo.setup.quiescence-error"
fifo_setup_protocol_error="$TMP_DIR/fifo.setup.protocol-error"
readonly child_anchor_fifo watchdog_anchor_fifo
readonly child_mkfifo_stdout child_mkfifo_stderr
readonly watchdog_mkfifo_stdout watchdog_mkfifo_stderr
readonly watchdog_deadline_pid watchdog_deadline_started
readonly fifo_setup_begin fifo_setup_held fifo_setup_authorized fifo_setup_closed
readonly fifo_watchdog_create_error fifo_watchdog_invalid
readonly fifo_child_create_error fifo_child_invalid
readonly fifo_quiescence_error fifo_setup_protocol_error
readonly symbol_preflight_stdout symbol_preflight_stderr
readonly symbol_preflight_result symbol_preflight_quiescence_held
readonly symbol_preflight_quiescence_parent_candidate
readonly symbol_preflight_quiescence_child_candidate
readonly symbol_preflight_quiescence_disposition
readonly symbol_preflight_quiescence_parent_ln_stderr
readonly symbol_preflight_quiescence_child_ln_stderr
readonly symbol_preflight_quiescence_authorized
readonly symbol_preflight_quiescence_rejected
readonly symbol_preflight_quiescence_closed

trap unexpected_exit EXIT
trap record_int INT
trap record_term TERM
trap unexpected_hup HUP

for private_path in \
  "$child_anchor_fifo" \
  "$watchdog_anchor_fifo" \
  "$child_mkfifo_stdout" \
  "$child_mkfifo_stderr" \
  "$watchdog_mkfifo_stdout" \
  "$watchdog_mkfifo_stderr" \
  "$watchdog_deadline_pid" \
  "$watchdog_deadline_started" \
  "$fifo_setup_begin" \
  "$fifo_setup_held" \
  "$fifo_setup_authorized" \
  "$fifo_setup_closed" \
  "$fifo_watchdog_create_error" \
  "$fifo_watchdog_invalid" \
  "$fifo_child_create_error" \
  "$fifo_child_invalid" \
  "$fifo_quiescence_error" \
  "$fifo_setup_protocol_error" \
  "$symbol_preflight_stdout" \
  "$symbol_preflight_stderr" \
  "$symbol_preflight_result" \
  "$symbol_preflight_quiescence_held" \
  "$symbol_preflight_quiescence_parent_candidate" \
  "$symbol_preflight_quiescence_child_candidate" \
  "$symbol_preflight_quiescence_disposition" \
  "$symbol_preflight_quiescence_parent_ln_stderr" \
  "$symbol_preflight_quiescence_child_ln_stderr" \
  "$symbol_preflight_quiescence_authorized" \
  "$symbol_preflight_quiescence_rejected" \
  "$symbol_preflight_quiescence_closed"; do
  if ! private_path_absent "$private_path"; then
    transition_fifo_setup failed || true
    owned_diagnostic "invalid Go snapshot private FIFO setup state"
    commit_cause protocol 1 || true
    finalize
  fi
done

# shellcheck disable=SC2016 # pkg-config variables must remain literal.
if ! printf '%s\n' \
    "prefix=$ROOT_DIR" \
    'exec_prefix=${prefix}' \
    "libdir=$LIB_DIR" \
    "includedir=$HEADER_DIR" \
    '' \
    'Name: opentui' \
    'Description: Local OpenTUI parity snapshot tool' \
    'Version: 0' \
    'Libs: -L${libdir} -lopentui' \
    'Cflags: -I${includedir}' >"$TMP_DIR/opentui.pc"; then
  owned_diagnostic "could not prepare Go snapshot pkg-config metadata"
  commit_cause protocol 1 || true
  finalize
fi

preflight_a="$TMP_DIR/link-preflight-a"
preflight_b="$TMP_DIR/link-preflight-b"
preflight_outcome="$TMP_DIR/link-preflight-outcome"
preflight_stderr="$TMP_DIR/link-preflight.stderr"
printf 'a\n' >"$preflight_a" || {
  owned_diagnostic "could not prepare Go snapshot hard-link preflight"
  commit_cause protocol 1 || true
  finalize
}
printf 'b\n' >"$preflight_b" || {
  owned_diagnostic "could not prepare Go snapshot hard-link preflight"
  commit_cause protocol 1 || true
  finalize
}
if ! /bin/ln "$preflight_a" "$preflight_outcome" \
    2>"$preflight_stderr" 3>&- ||
    /bin/ln "$preflight_b" "$preflight_outcome" \
      2>"$preflight_stderr" 3>&- ||
    [[ ! "$preflight_outcome" -ef "$preflight_a" ||
       "$preflight_outcome" -ef "$preflight_b" ]] ||
    ! read_exact_line "$preflight_outcome" || [[ "$READ_LINE" != a ]]; then
  owned_diagnostic "Go snapshot hard-link preflight failed"
  commit_cause protocol 1 || true
  finalize
fi
rm -f -- "$preflight_a" "$preflight_b" "$preflight_outcome" \
  "$preflight_stderr" 3>&- || {
  owned_diagnostic "could not remove Go snapshot hard-link preflight state"
  commit_cause protocol 1 || true
  finalize
}

export PKG_CONFIG_PATH="$TMP_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CGO_ENABLED=1
export GOOS="$HOST_OS"
export GOARCH="$GO_ARCH"
export GOCACHE="$CACHE_ROOT/build-cache"
export GOPATH="$CACHE_ROOT/gopath"
export GOMODCACHE="$GOPATH/pkg/mod"
if ! mkdir -p "$GOCACHE" "$GOMODCACHE" 3>&-; then
  owned_diagnostic "could not create Go snapshot cache directories"
  commit_cause protocol 1 || true
  finalize
fi
if [[ "$LIB_ENV_VAR" == "DYLD_LIBRARY_PATH" ]]; then
  export DYLD_LIBRARY_PATH="$LIB_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

command_cwd="$TOOL_DIR"
command=(go run . "$@")

if ! snapshot_group "$$" "$$" ||
    [[ "$SNAPSHOT_ANCHOR_PRESENT" != true ]]; then
  owned_diagnostic "could not establish the Go snapshot wrapper identity"
  commit_cause protocol 1 || true
  finalize
fi
wrapper_pgid="$SNAPSHOT_ANCHOR_PGID"

set -m
(
  exec 2>"$child_stderr"
  anchor_signal_observed=false
  trap 'anchor_signal_observed=true' INT TERM
  if ! wait_for_both_ready; then
    exec 3>&-
    exit 73
  fi

  wait_for_fifo_setup_begin
  setup_wait_status=$?
  if [[ "$setup_wait_status" -eq 2 ]]; then
    exec 3>&-
    exit 74
  fi
  if [[ "$setup_wait_status" -ne 0 ]]; then
    : >"$fifo_setup_protocol_error" || true
    exec 8>&-
    hold_failed_anchor child setup deadline
    exit 74
  fi

  if ! private_path_absent "$watchdog_anchor_fifo"; then
    : >"$fifo_watchdog_invalid" || true
    exec 8>&-
    hold_failed_anchor child setup watchdog-preexisting
    exit 74
  fi
  "$MKFIFO_TOOL" -m 600 "$watchdog_anchor_fifo" \
    >"$watchdog_mkfifo_stdout" 2>"$watchdog_mkfifo_stderr" \
    3>&- 8>&- 9>&-
  watchdog_mkfifo_status=$?
  if [[ "$watchdog_mkfifo_status" -ne 0 ]]; then
    : >"$fifo_watchdog_create_error" || true
    exec 8>&-
    hold_failed_anchor child setup watchdog-create
    exit 74
  fi
  if ! validate_anchor_fifo \
      "$watchdog_anchor_fifo" "watchdog.anchor-control.fifo" \
      "$watchdog_mkfifo_stdout" "$watchdog_mkfifo_stderr"; then
    : >"$fifo_watchdog_invalid" || true
    exec 8>&-
    hold_failed_anchor child setup watchdog-invalid
    exit 74
  fi

  if ! private_path_absent "$child_anchor_fifo"; then
    : >"$fifo_child_invalid" || true
    exec 8>&-
    hold_failed_anchor child setup child-preexisting
    exit 74
  fi
  "$MKFIFO_TOOL" -m 600 "$child_anchor_fifo" \
    >"$child_mkfifo_stdout" 2>"$child_mkfifo_stderr" \
    3>&- 8>&- 9>&-
  child_mkfifo_status=$?
  if [[ "$child_mkfifo_status" -ne 0 ]]; then
    : >"$fifo_child_create_error" || true
    exec 8>&-
    hold_failed_anchor child setup child-create
    exit 74
  fi
  if ! validate_anchor_fifo \
      "$child_anchor_fifo" "child.anchor-control.fifo" \
      "$child_mkfifo_stdout" "$child_mkfifo_stderr"; then
    : >"$fifo_child_invalid" || true
    exec 8>&-
    hold_failed_anchor child setup child-invalid
    exit 74
  fi

  if [[ ! -p "$child_anchor_fifo" || -L "$child_anchor_fifo" ||
        ! -O "$child_anchor_fifo" ]] ||
      ! exec 8<>"$child_anchor_fifo"; then
    : >"$fifo_setup_protocol_error" || true
    exec 8>&-
    hold_failed_anchor child setup open
    exit 74
  fi
  trace_event "fifo|child|setup-opened|fd=8"
  if ! : >"$fifo_setup_held" || ! private_marker_valid "$fifo_setup_held"; then
    exec 8>&-
    trace_event "fifo|child|setup-closed|fd=8"
    : >"$fifo_setup_protocol_error" || true
    hold_failed_anchor child setup held-marker
    exit 74
  fi

  hold_anchor_fifo setup child 8 \
    "$child_release" "$fifo_setup_authorized" "$fifo_setup_protocol_error"
  setup_hold_result="$HOLD_RESULT"
  exec 8>&-
  setup_close_status=$?
  trace_event "fifo|child|setup-closed|fd=8"
  if [[ "$setup_close_status" -ne 0 ]]; then
    : >"$fifo_setup_protocol_error" || true
    exec 8>&-
    hold_failed_anchor child setup close
    exit 74
  fi

  case "$setup_hold_result" in
    aborted)
      exec 3>&-
      exit 74
      ;;
    authorized) ;;
    ceiling)
      exec 3>&-
      exit 74
      ;;
    *)
      : >"$fifo_setup_protocol_error" || true
      hold_failed_anchor child setup "$setup_hold_result"
      exit 74
      ;;
  esac

  if ! private_marker_valid "$fifo_setup_authorized" ||
      [[ -e "$child_release" || -L "$child_release" ]] ||
      [[ -e /dev/fd/8 || -e /dev/fd/9 ]]; then
    : >"$fifo_setup_protocol_error" || true
    exec 8>&-
    exec 9>&-
    hold_failed_anchor child setup authorization
    exit 74
  fi
  if ! : >"$fifo_setup_closed" || ! private_marker_valid "$fifo_setup_closed"; then
    : >"$fifo_setup_protocol_error" || true
    exec 8>&-
    exec 9>&-
    hold_failed_anchor child setup closed-marker
    exit 74
  fi

  run_child_precommands
  child_precommand_status=$?
  if [[ "$child_precommand_status" -eq 0 ]]; then
    if ! cd "$command_cwd"; then
      exec 3>&-
      : >"$child_protocol_error" || true
    else
      "${command[@]}" 2>&3 3>&- 8>&- 9>&-
      child_command_status=$?
      exec 3>&-
      publish_child_candidate "$child_command_status" || true
    fi
  else
    if ! exec 3>&-; then
      : >"$child_protocol_error" || true
    elif [[ "$child_precommand_status" -ne 1 ]]; then
      : >"$child_protocol_error" || true
    fi
  fi

  if [[ ! -p "$child_anchor_fifo" || -L "$child_anchor_fifo" ||
        ! -O "$child_anchor_fifo" ]] ||
      ! exec 8<>"$child_anchor_fifo"; then
    : >"$child_protocol_error" || true
    exec 8>&-
    hold_failed_anchor child post open
    exit 74
  fi
  trace_event "fifo|child|post-opened|fd=8"
  if ! : >"$child_held" || ! private_marker_valid "$child_held"; then
    : >"$child_protocol_error" || true
    exec 8>&-
    trace_event "fifo|child|post-closed|fd=8"
    hold_failed_anchor child post held-marker
    exit 74
  fi
  hold_anchor_fifo post child 8 \
    "$child_release" "" "$child_protocol_error"
  child_post_result="$HOLD_RESULT"
  exec 8>&-
  trace_event "fifo|child|post-closed|fd=8"
  case "$child_post_result" in
    released) exit 0 ;;
    ceiling) exit 74 ;;
    *)
      : >"$child_protocol_error" || true
      hold_failed_anchor child post "$child_post_result"
      exit 74
      ;;
  esac
) &
child_pid=$!
child_pgid="$child_pid"
child_launch_state="captured_unaccepted"
set +m

if ! verify_anchor "$child_pid" ""; then
  child_launch_state="validation_failed"
  finish_validation_failure child
fi
child_launch_state="accepted"
child_anchor_owned=true

set -m
(
  exec 2>"$watchdog_stderr"
  exec 3>&-
  anchor_signal_observed=false
  trap 'anchor_signal_observed=true' INT TERM
  if ! wait_for_both_ready; then
    exit 73
  fi

  set +m
  /bin/sleep "$timeout_seconds" 3>&- 8>&- 9>&- &
  deadline_pid=$!
  if [[ "$deadline_pid" =~ ^[1-9][0-9]*$ ]] &&
      printf '%s\n' "$deadline_pid" >"$watchdog_deadline_pid" &&
      private_marker_valid "$watchdog_deadline_pid" &&
      : >"$watchdog_deadline_started" &&
      private_marker_valid "$watchdog_deadline_started"; then
    :
  else
    : >"$watchdog_protocol_error" || true
  fi
  wait "$deadline_pid"
  deadline_status=$?
  if [[ "$deadline_status" -ge 128 ]]; then
    wait "$deadline_pid"
    deadline_status=$?
  fi
  : "$deadline_status"
  if [[ ! -e "$watchdog_cancel" && ! -L "$watchdog_cancel" ]]; then
    publish_watchdog_candidate || true
  fi

  if [[ ! -p "$watchdog_anchor_fifo" || -L "$watchdog_anchor_fifo" ||
        ! -O "$watchdog_anchor_fifo" ]] ||
      ! exec 9<>"$watchdog_anchor_fifo"; then
    : >"$watchdog_protocol_error" || true
    exec 9>&-
    hold_failed_anchor watchdog post open
    exit 74
  fi
  trace_event "fifo|watchdog|post-opened|fd=9"
  if ! : >"$watchdog_held" || ! private_marker_valid "$watchdog_held"; then
    : >"$watchdog_protocol_error" || true
    exec 9>&-
    trace_event "fifo|watchdog|post-closed|fd=9"
    hold_failed_anchor watchdog post held-marker
    exit 74
  fi
  hold_anchor_fifo post watchdog 9 \
    "$watchdog_release" "" "$watchdog_protocol_error"
  watchdog_post_result="$HOLD_RESULT"
  exec 9>&-
  trace_event "fifo|watchdog|post-closed|fd=9"
  case "$watchdog_post_result" in
    released) exit 0 ;;
    ceiling) exit 74 ;;
    *)
      : >"$watchdog_protocol_error" || true
      hold_failed_anchor watchdog post "$watchdog_post_result"
      exit 74
      ;;
  esac
) &
watchdog_pid=$!
watchdog_pgid="$watchdog_pid"
watchdog_launch_state="captured_unaccepted"
set +m

if ! verify_anchor "$watchdog_pid" "$child_pgid"; then
  watchdog_launch_state="validation_failed"
  finish_validation_failure watchdog
fi
watchdog_launch_state="accepted"
watchdog_anchor_owned=true

if ! : >"$child_ready" || ! : >"$watchdog_ready"; then
  commit_cause protocol 1 || true
fi
if [[ "$cause_record" == "unset" ]]; then
  transition_fifo_setup waiting_deadline ||
    select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
fi

while [[ "$cause_record" == "unset" ]]; do
  if [[ "$signal_pending" != "" ]]; then
    commit_cause signal "${signal_pending##*:}" || true
    break
  fi
  if [[ -e "$outcome" ]]; then
    if [[ "$fifo_setup_state" == "authorized" &&
          ( -e "$fifo_setup_closed" || -L "$fifo_setup_closed" ) ]]; then
      if private_marker_valid "$fifo_setup_closed"; then
        transition_fifo_setup child_closed || true
      else
        transition_fifo_setup failed || true
      fi
    fi
    if ! validate_outcome; then
      if [[ "$fifo_setup_state" != "child_closed" ]]; then
        select_fifo_setup_failure \
          "could not complete Go snapshot FIFO setup"
      else
        commit_cause protocol 1 || true
      fi
    else
      if [[ "$fifo_setup_state" != "child_closed" ]]; then
        transition_fifo_setup failed || true
      fi
      commit_cause "$OUTCOME_CAUSE" "$OUTCOME_STATUS" || true
    fi
    break
  fi
  if [[ "$fifo_setup_state" != "child_closed" ]] &&
      observe_fifo_setup_error; then
    select_fifo_setup_failure "$FIFO_ERROR_DIAGNOSTIC"
    break
  fi
  if [[ -f "$child_protocol_error" ||
        -f "$watchdog_protocol_error" ]]; then
    commit_cause protocol 1 || true
    break
  fi

  if [[ "$fifo_setup_state" == "waiting_deadline" ]]; then
    if [[ -e "$watchdog_deadline_started" ||
          -L "$watchdog_deadline_started" ]]; then
      deadline_valid=true
      if ! private_marker_valid "$watchdog_deadline_started" ||
          ! private_marker_valid "$watchdog_deadline_pid" ||
          ! read_exact_line "$watchdog_deadline_pid" ||
          [[ ! "$READ_LINE" =~ ^[1-9][0-9]*$ ]]; then
        deadline_valid=false
      else
        watchdog_deadline_pid_value="$READ_LINE"
      fi
      if [[ "$deadline_valid" == true ]]; then
        if ! snapshot_group \
            "$watchdog_pid" "$watchdog_pgid" \
            "$watchdog_deadline_pid_value" ||
            [[ "$SNAPSHOT_OK" != true ||
               "$SNAPSHOT_ANCHOR_PRESENT" != true ||
               "$SNAPSHOT_ANCHOR_PGID" != "$watchdog_pgid" ||
               "$SNAPSHOT_MEMBER_COUNT" -ne 2 ||
               "$SNAPSHOT_EXPECTED_MEMBER_PRESENT" != true ]] ||
            ! supported_live_state "$SNAPSHOT_ANCHOR_STAT" ||
            ! supported_live_state "$SNAPSHOT_EXPECTED_MEMBER_STAT"; then
          deadline_valid=false
        fi
      fi
      if [[ "$deadline_valid" != true ]]; then
        select_fifo_setup_failure \
          "could not establish Go snapshot FIFO setup deadline owner"
        break
      fi
      transition_fifo_setup deadline_owned || {
        select_fifo_setup_failure \
          "could not establish Go snapshot FIFO setup deadline owner"
        break
      }
      if ! : >"$fifo_setup_begin" ||
          ! private_marker_valid "$fifo_setup_begin"; then
        select_fifo_setup_failure \
          "could not complete Go snapshot FIFO setup"
        break
      fi
      transition_fifo_setup setup_running || {
        select_fifo_setup_failure \
          "could not complete Go snapshot FIFO setup"
        break
      }
    else
      fifo_deadline_observations=$((fifo_deadline_observations + 1))
      if [[ "$fifo_deadline_observations" -ge 50 ]]; then
        select_fifo_setup_failure \
          "could not establish Go snapshot FIFO setup deadline owner"
        break
      fi
    fi
  elif [[ "$fifo_setup_state" == "setup_running" &&
          ( -e "$fifo_setup_held" || -L "$fifo_setup_held" ) ]]; then
    if ! private_marker_valid "$fifo_setup_held"; then
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    fi
    transition_fifo_setup setup_held || {
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    }
    setup_snapshot_valid=true
    if ! snapshot_group "$child_pid" "$child_pgid"; then
      setup_snapshot_valid=false
    fi

    if [[ "$signal_pending" != "" ]]; then
      commit_cause signal "${signal_pending##*:}" || true
      transition_fifo_setup failed || true
      break
    fi
    if [[ -e "$outcome" ]]; then
      if ! validate_outcome; then
        select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      else
        commit_cause "$OUTCOME_CAUSE" "$OUTCOME_STATUS" || true
        transition_fifo_setup failed || true
      fi
      break
    fi
    if observe_fifo_setup_error; then
      select_fifo_setup_failure "$FIFO_ERROR_DIAGNOSTIC"
      break
    fi
    if [[ "$setup_snapshot_valid" != true ||
          "$SNAPSHOT_OK" != true ||
          "$SNAPSHOT_ANCHOR_PRESENT" != true ||
          "$SNAPSHOT_ANCHOR_PGID" != "$child_pgid" ||
          "$SNAPSHOT_MEMBER_COUNT" -ne 1 ]] ||
        ! supported_live_state "$SNAPSHOT_ANCHOR_STAT"; then
      : >"$fifo_quiescence_error" || true
      select_fifo_setup_failure \
        "could not verify Go snapshot FIFO setup quiescence"
      break
    fi
    if ! : >"$fifo_setup_authorized" ||
        ! private_marker_valid "$fifo_setup_authorized"; then
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    fi
    transition_fifo_setup authorized || {
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    }
  elif [[ "$fifo_setup_state" == "authorized" &&
          ( -e "$fifo_setup_closed" || -L "$fifo_setup_closed" ) ]]; then
    if ! private_marker_valid "$fifo_setup_closed"; then
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    fi
    transition_fifo_setup child_closed || {
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
      break
    }
  fi

  if [[ "$fifo_setup_state" == "child_closed" &&
        "$symbol_preflight_quiescence_state" == "not_reached" &&
        ( -e "$symbol_preflight_quiescence_held" ||
          -L "$symbol_preflight_quiescence_held" ) ]]; then
    symbol_snapshot_authorize=false
    if ! transition_symbol_preflight_quiescence waiting_held; then
      commit_cause protocol 1 || true
      break
    fi
    if [[ "$signal_pending" != "" ]]; then
      transition_symbol_preflight_quiescence aborted || true
      commit_cause signal "${signal_pending##*:}" || true
      break
    fi
    if [[ -e "$outcome" || -L "$outcome" ]]; then
      if validate_outcome; then
        transition_symbol_preflight_quiescence aborted || true
        commit_cause "$OUTCOME_CAUSE" "$OUTCOME_STATUS" || true
      else
        transition_symbol_preflight_quiescence protocol_failed || true
        commit_cause protocol 1 || true
      fi
      break
    fi
    if [[ -e "$child_protocol_error" || -L "$child_protocol_error" ||
          -e "$watchdog_protocol_error" ||
          -L "$watchdog_protocol_error" ]]; then
      transition_symbol_preflight_quiescence protocol_failed || true
      commit_cause protocol 1 || true
      break
    fi
    if ! private_marker_valid "$symbol_preflight_quiescence_held" ||
        [[ -e "$symbol_preflight_quiescence_parent_candidate" ||
           -L "$symbol_preflight_quiescence_parent_candidate" ||
           -e "$symbol_preflight_quiescence_parent_ln_stderr" ||
           -L "$symbol_preflight_quiescence_parent_ln_stderr" ||
           -e "$symbol_preflight_quiescence_authorized" ||
           -L "$symbol_preflight_quiescence_authorized" ||
           -e "$symbol_preflight_quiescence_rejected" ||
           -L "$symbol_preflight_quiescence_rejected" ||
           -e "$symbol_preflight_quiescence_closed" ||
           -L "$symbol_preflight_quiescence_closed" ]] ||
        ! admit_symbol_preflight_child_election_prefix; then
      transition_symbol_preflight_quiescence protocol_failed || true
      : >"$child_protocol_error" || true
      commit_cause protocol 1 || true
      break
    fi
    if ! transition_symbol_preflight_quiescence snapshotting; then
      : >"$child_protocol_error" || true
      commit_cause protocol 1 || true
      break
    fi
    if snapshot_group "$child_pid" "$child_pgid" &&
        [[ "$SNAPSHOT_OK" == true &&
           "$SNAPSHOT_ANCHOR_PRESENT" == true &&
           "$SNAPSHOT_ANCHOR_PGID" == "$child_pgid" &&
           "$SNAPSHOT_MEMBER_COUNT" -eq 1 ]] &&
        supported_live_state "$SNAPSHOT_ANCHOR_STAT"; then
      symbol_snapshot_authorize=true
    fi

    if [[ "$signal_pending" != "" ]]; then
      transition_symbol_preflight_quiescence aborted || true
      commit_cause signal "${signal_pending##*:}" || true
      break
    fi
    if [[ -e "$outcome" || -L "$outcome" ]]; then
      if validate_outcome; then
        transition_symbol_preflight_quiescence aborted || true
        commit_cause "$OUTCOME_CAUSE" "$OUTCOME_STATUS" || true
      else
        transition_symbol_preflight_quiescence protocol_failed || true
        commit_cause protocol 1 || true
      fi
      break
    fi
    if [[ -e "$child_protocol_error" || -L "$child_protocol_error" ||
          -e "$watchdog_protocol_error" || -L "$watchdog_protocol_error" ]] ||
        ! private_marker_valid "$symbol_preflight_quiescence_held" ||
        [[ -e "$symbol_preflight_quiescence_authorized" ||
           -L "$symbol_preflight_quiescence_authorized" ||
           -e "$symbol_preflight_quiescence_rejected" ||
           -L "$symbol_preflight_quiescence_rejected" ||
           -e "$symbol_preflight_quiescence_closed" ||
           -L "$symbol_preflight_quiescence_closed" ]]; then
      transition_symbol_preflight_quiescence protocol_failed || true
      commit_cause protocol 1 || true
      break
    fi

    if [[ "$symbol_snapshot_authorize" == true ]]; then
      symbol_parent_disposition=authorize
    else
      symbol_parent_disposition=reject:snapshot
    fi
    elect_symbol_preflight_quiescence_disposition \
      parent "$symbol_parent_disposition"
    symbol_parent_election_status=$?
    if [[ "$symbol_parent_election_status" -ne 0 &&
          "$SYMBOL_PREFLIGHT_ELECTION_PREEMPTED" != true ]]; then
      transition_symbol_preflight_quiescence protocol_failed || true
      commit_cause protocol 1 || true
      break
    fi

    if [[ "$signal_pending" != "" ]]; then
      transition_symbol_preflight_quiescence aborted || true
      commit_cause signal "${signal_pending##*:}" || true
      break
    fi
    if [[ -e "$outcome" || -L "$outcome" ]]; then
      if validate_outcome; then
        transition_symbol_preflight_quiescence aborted || true
        commit_cause "$OUTCOME_CAUSE" "$OUTCOME_STATUS" || true
      else
        transition_symbol_preflight_quiescence protocol_failed || true
        commit_cause protocol 1 || true
      fi
      break
    fi
    if [[ -e "$child_protocol_error" || -L "$child_protocol_error" ||
          -e "$watchdog_protocol_error" ||
          -L "$watchdog_protocol_error" ]] ||
        ! private_marker_valid "$symbol_preflight_quiescence_held" ||
        [[ -e "$symbol_preflight_quiescence_authorized" ||
           -L "$symbol_preflight_quiescence_authorized" ||
           -e "$symbol_preflight_quiescence_rejected" ||
           -L "$symbol_preflight_quiescence_rejected" ||
           -e "$symbol_preflight_quiescence_closed" ||
           -L "$symbol_preflight_quiescence_closed" ]] ||
        ! validate_symbol_preflight_quiescence_disposition; then
      transition_symbol_preflight_quiescence protocol_failed || true
      commit_cause protocol 1 || true
      break
    fi

    case "$SYMBOL_PREFLIGHT_QUIESCENCE_DISPOSITION" in
      authorize)
        if ! : >"$symbol_preflight_quiescence_authorized" ||
            ! private_marker_valid \
              "$symbol_preflight_quiescence_authorized" ||
            [[ -e "$symbol_preflight_quiescence_rejected" ||
               -L "$symbol_preflight_quiescence_rejected" ]] ||
            ! transition_symbol_preflight_quiescence authorized; then
          transition_symbol_preflight_quiescence protocol_failed || true
          commit_cause protocol 1 || true
          break
        fi
        trace_event \
          "symbol_preflight|quiescence-snapshot|decision=authorize"
        ;;
      reject:snapshot|reject:unexpected-data|reject:ceiling)
        if ! : >"$symbol_preflight_quiescence_rejected" ||
            ! private_marker_valid \
              "$symbol_preflight_quiescence_rejected" ||
            [[ -e "$symbol_preflight_quiescence_authorized" ||
               -L "$symbol_preflight_quiescence_authorized" ]] ||
            ! transition_symbol_preflight_quiescence rejected; then
          transition_symbol_preflight_quiescence protocol_failed || true
          commit_cause protocol 1 || true
          break
        fi
        trace_event \
          "symbol_preflight|quiescence-snapshot|decision=reject"
        ;;
      *)
        transition_symbol_preflight_quiescence protocol_failed || true
        commit_cause protocol 1 || true
        break
        ;;
    esac
  fi

  if ! anchor_identity_is_live child; then
    freeze_anchor child
    if [[ "$fifo_setup_state" == "authorized" ]]; then
      select_fifo_setup_failure "could not complete Go snapshot FIFO setup"
    elif [[ "$fifo_setup_state" != "child_closed" ]]; then
      select_fifo_setup_failure \
        "could not verify Go snapshot FIFO setup quiescence"
    else
      commit_cause protocol 1 || true
    fi
    break
  fi
  if ! anchor_identity_is_live watchdog; then
    freeze_anchor watchdog
    commit_cause protocol 1 || true
    break
  fi
  /bin/sleep 0.05 3>&-
done

emit_fifo_setup_diagnostic
emit_symbol_preflight_diagnostic
if [[ "${cause_record%%:*}" == "timeout" ]]; then
  owned_diagnostic \
    "Go snapshot timed out after $timeout_seconds seconds in snapshot mode."
fi

finalize
