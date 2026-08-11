P9_043_DEBUG_SUPERVISOR_PID=''
if [[ "${P9_043_DEBUG_START_FIFO:-}" != '' ]]; then
  unset BASH_ENV
  if [[ "${P9_043_DEBUG_START_FIFO:-}" != /* ||
        "${P9_043_DEBUG_SUPERVISOR_PID_FILE:-}" != /* ||
        "${P9_043_DEBUG_STARTED:-}" != /* ||
        ! -p "$P9_043_DEBUG_START_FIFO" ||
        -L "$P9_043_DEBUG_START_FIFO" ||
        ! -O "$P9_043_DEBUG_START_FIFO" ]]; then
    printf 'bootstrap-paths\n' >"${P9_043_DEBUG_HOOK_FAILED:-/dev/null}"
    exit 97
  fi
  IFS= read -r p9_043_start_token <"$P9_043_DEBUG_START_FIFO" ||
    p9_043_start_token=''
  IFS= read -r P9_043_DEBUG_SUPERVISOR_PID \
    <"$P9_043_DEBUG_SUPERVISOR_PID_FILE" ||
    P9_043_DEBUG_SUPERVISOR_PID=''
  if [[ "$p9_043_start_token" != start ||
        ! "$P9_043_DEBUG_SUPERVISOR_PID" =~ ^[1-9][0-9]*$ ]]; then
    printf 'bootstrap-record\n' >"$P9_043_DEBUG_HOOK_FAILED"
    exit 98
  fi
  readonly P9_043_DEBUG_SUPERVISOR_PID
  : >"$P9_043_DEBUG_STARTED"
fi

_p9_043_debug_gate() {
  local entry_status=$?
  local expected_command=''
  local expected_parent_command=''
  local expected_pre_admission_command=''
  local expected_child_postlink_command=''
  local expected_parent_status=''
  local expected_parent_record=''
  local candidate=''
  local disposition=''
  local parent_candidate=''
  local authorized=''
  local rejected=''
  local first_line=''
  local extra_line=''

  # shellcheck disable=SC2016 # Match the literal pending Bash command.
  expected_command='/bin/ln "$symbol_preflight_quiescence_child_candidate" "$symbol_preflight_quiescence_disposition" < /dev/null > /dev/null 2> "$symbol_preflight_quiescence_child_ln_stderr" 3>&- 8>&- 9>&-'
  # shellcheck disable=SC2016 # Match the literal pending Bash command.
  expected_parent_command='symbol_parent_election_status=$?'
  expected_pre_admission_command='symbol_snapshot_authorize=false'
  expected_child_postlink_command='election_status=$?'

  if [[ "$BASH_COMMAND" == "$expected_pre_admission_command" &&
        "${P9_043_DEBUG_PRE_ADMISSION_STOPPED:-}" != "" ]]; then
    candidate="${symbol_preflight_quiescence_child_candidate:-}"
    disposition="${symbol_preflight_quiescence_disposition:-}"
    parent_candidate="${symbol_preflight_quiescence_parent_candidate:-}"
    authorized="${symbol_preflight_quiescence_authorized:-}"
    rejected="${symbol_preflight_quiescence_rejected:-}"
    if [[ "$entry_status" -ne 0 ||
          "${P9_043_DEBUG_PRE_ADMISSION_STOPPED:-}" != /* ||
          "${P9_043_DEBUG_PRE_ADMISSION_CONTINUED:-}" != /* ||
          "${fifo_setup_state:-}" != child_closed ||
          "${symbol_preflight_quiescence_state:-}" != not_reached ||
          ! -f "${symbol_preflight_quiescence_held:-}" ||
          -L "${symbol_preflight_quiescence_held:-}" ||
          -e "$candidate" || -L "$candidate" ||
          -e "$disposition" || -L "$disposition" ||
          -e "$parent_candidate" || -L "$parent_candidate" ||
          -e "$authorized" || -L "$authorized" ||
          -e "$rejected" || -L "$rejected" ]]; then
      printf 'pre-admission-guard\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL "$P9_043_DEBUG_SUPERVISOR_PID"
    fi
    printf 'ready|pre-admission\n' \
      >"$P9_043_DEBUG_PRE_ADMISSION_STOPPED"
    builtin kill -STOP "$P9_043_DEBUG_SUPERVISOR_PID"
    printf 'continued|pre-admission\n' \
      >"$P9_043_DEBUG_PRE_ADMISSION_CONTINUED"
    return 0
  fi

  if [[ "$BASH_COMMAND" == "$expected_child_postlink_command" &&
        "${P9_043_DEBUG_CHILD_POSTLINK_STOPPED:-}" != "" ]]; then
    candidate="${symbol_preflight_quiescence_child_candidate:-}"
    disposition="${symbol_preflight_quiescence_disposition:-}"
    parent_candidate="${symbol_preflight_quiescence_parent_candidate:-}"
    authorized="${symbol_preflight_quiescence_authorized:-}"
    rejected="${symbol_preflight_quiescence_rejected:-}"
    if [[ "$entry_status" -ne 0 || ! -e /dev/fd/8 ||
          "${P9_043_DEBUG_CHILD_POSTLINK_STOPPED:-}" != /* ||
          "${P9_043_DEBUG_CHILD_POSTLINK_CONTINUED:-}" != /* ||
          ! -f "$candidate" || -L "$candidate" ||
          ! -f "$disposition" || -L "$disposition" ||
          ! -f "${symbol_preflight_quiescence_child_ln_stderr:-}" ||
          -s "${symbol_preflight_quiescence_child_ln_stderr:-}" ||
          ! "$disposition" -ef "$candidate" ||
          -e "$parent_candidate" || -L "$parent_candidate" ||
          -e "$authorized" || -L "$authorized" ||
          -e "$rejected" || -L "$rejected" ]]; then
      printf 'child-postlink-guard\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL 0
    fi
    IFS= read -r first_line <"$disposition" || first_line=''
    if [[ "$first_line" != 'reject:unexpected-data' ]]; then
      printf 'child-postlink-record\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL 0
    fi
    printf 'ready|child-winner\n' \
      >"$P9_043_DEBUG_CHILD_POSTLINK_STOPPED"
    builtin kill -STOP 0
    if [[ ! "$disposition" -ef "$candidate" ||
          ! -f "$rejected" || -L "$rejected" ||
          -e "$authorized" || -L "$authorized" ]]; then
      printf 'child-postlink-mutated\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL 0
    fi
    printf 'continued|child-winner\n' \
      >"$P9_043_DEBUG_CHILD_POSTLINK_CONTINUED"
    return 0
  fi

  if [[ "$BASH_COMMAND" == "$expected_parent_command" &&
        "${P9_043_DEBUG_POSTLINK_STOPPED:-}" != "" ]]; then
    disposition="${symbol_preflight_quiescence_disposition:-}"
    parent_candidate="${symbol_preflight_quiescence_parent_candidate:-}"
    candidate="${symbol_preflight_quiescence_child_candidate:-}"
    authorized="${symbol_preflight_quiescence_authorized:-}"
    rejected="${symbol_preflight_quiescence_rejected:-}"
    expected_parent_status="${P9_043_DEBUG_EXPECT_PARENT_STATUS:-0}"
    expected_parent_record="${P9_043_DEBUG_EXPECT_PARENT_RECORD:-authorize}"
    if [[ ! "$expected_parent_status" =~ ^[0-9]+$ ||
          ( "$expected_parent_record" == authorize &&
            "$expected_parent_status" -ne 0 ) ||
          ( "$expected_parent_record" == reject:unexpected-data &&
            "$expected_parent_status" -eq 0 ) ||
          ( "$expected_parent_record" != authorize &&
            "$expected_parent_record" != reject:unexpected-data ) ||
          "$entry_status" -ne "$expected_parent_status" ||
          "${P9_043_DEBUG_POSTLINK_STOPPED:-}" != /* ||
          "${P9_043_DEBUG_POSTLINK_CONTINUED:-}" != /* ||
          "${P9_043_DEBUG_HOOK_FAILED:-}" != /* ||
          ! -f "$disposition" || -L "$disposition" ||
          ! -f "$parent_candidate" || -L "$parent_candidate" ||
          ! -f "$candidate" || -L "$candidate" ||
          ( "$expected_parent_record" == authorize &&
            ( ! "$disposition" -ef "$parent_candidate" ||
              "$disposition" -ef "$candidate" ) ) ||
          ( "$expected_parent_record" == reject:unexpected-data &&
            ( ! "$disposition" -ef "$candidate" ||
              "$disposition" -ef "$parent_candidate" ) ) ||
          -e "$authorized" || -L "$authorized" ||
          -e "$rejected" || -L "$rejected" ||
          -e "$P9_043_DEBUG_POSTLINK_STOPPED" ||
          -L "$P9_043_DEBUG_POSTLINK_STOPPED" ||
          -e "$P9_043_DEBUG_POSTLINK_CONTINUED" ||
          -L "$P9_043_DEBUG_POSTLINK_CONTINUED" ]]; then
      printf 'postlink-guard\n' >"${P9_043_DEBUG_HOOK_FAILED:-/dev/null}"
      builtin kill -KILL "$P9_043_DEBUG_SUPERVISOR_PID"
    fi
    {
      IFS= read -r -u 7 first_line || first_line=''
      IFS= read -r -u 7 extra_line || extra_line=''
    } 7<"$disposition"
    if [[ "$first_line" != "$expected_parent_record" ||
          "$extra_line" != '' ]]; then
      printf 'postlink-record\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL "$P9_043_DEBUG_SUPERVISOR_PID"
    fi
    if [[ "${P9_043_DEBUG_EXPECT_PARENT_STATUS+x}" == x ]]; then
      printf 'ready|%s|status=%s\n' \
        "$expected_parent_record" "$entry_status" \
        >"$P9_043_DEBUG_POSTLINK_STOPPED"
    else
      printf 'ready|authorize\n' >"$P9_043_DEBUG_POSTLINK_STOPPED"
    fi
    builtin kill -STOP "$P9_043_DEBUG_SUPERVISOR_PID"
    if [[ ! -f "$disposition" || -L "$disposition" ||
          ( "$expected_parent_record" == authorize &&
            ( ! "$disposition" -ef "$parent_candidate" ||
              "$disposition" -ef "$candidate" ) ) ||
          ( "$expected_parent_record" == reject:unexpected-data &&
            ( ! "$disposition" -ef "$candidate" ||
              "$disposition" -ef "$parent_candidate" ) ) ||
          -e "$authorized" || -L "$authorized" ||
          -e "$rejected" || -L "$rejected" ]]; then
      printf 'postlink-mutated\n' >"$P9_043_DEBUG_HOOK_FAILED"
      builtin kill -KILL "$P9_043_DEBUG_SUPERVISOR_PID"
    fi
    if [[ "${P9_043_DEBUG_EXPECT_PARENT_STATUS+x}" == x ]]; then
      printf 'continued|%s|status=%s\n' \
        "$expected_parent_record" "$entry_status" \
        >"$P9_043_DEBUG_POSTLINK_CONTINUED"
    else
      printf 'continued|authorize\n' >"$P9_043_DEBUG_POSTLINK_CONTINUED"
    fi
    return 0
  fi

  [[ "$BASH_COMMAND" == "$expected_command" &&
     "${P9_043_DEBUG_PRELINK_STOPPED:-}" != "" ]] || return 0

  candidate="${symbol_preflight_quiescence_child_candidate:-}"
  disposition="${symbol_preflight_quiescence_disposition:-}"
  parent_candidate="${symbol_preflight_quiescence_parent_candidate:-}"
  authorized="${symbol_preflight_quiescence_authorized:-}"
  rejected="${symbol_preflight_quiescence_rejected:-}"

  if [[ "$entry_status" -ne 0 ||
        "${P9_043_DEBUG_PRELINK_STOPPED:-}" != /* ||
        "${P9_043_DEBUG_CONTINUED:-}" != /* ||
        "${P9_043_DEBUG_HOOK_FAILED:-}" != /* ||
        "$candidate" != "${TMP_DIR:-}/symbol-preflight.quiescence-child.candidate" ||
        "$disposition" != "${TMP_DIR:-}/symbol-preflight.quiescence-disposition" ||
        "$parent_candidate" != "${TMP_DIR:-}/symbol-preflight.quiescence-parent.candidate" ||
        "$authorized" != "${TMP_DIR:-}/symbol-preflight.quiescence-authorized" ||
        "$rejected" != "${TMP_DIR:-}/symbol-preflight.quiescence-rejected" ||
        ! -f "$candidate" || -L "$candidate" || ! -O "$candidate" ||
        -e "$disposition" || -L "$disposition" ||
        -e "$authorized" || -L "$authorized" ||
        -e "$rejected" || -L "$rejected" ||
        -e "$P9_043_DEBUG_PRELINK_STOPPED" ||
        -L "$P9_043_DEBUG_PRELINK_STOPPED" ||
        -e "$P9_043_DEBUG_CONTINUED" || -L "$P9_043_DEBUG_CONTINUED" ||
        -e "$P9_043_DEBUG_HOOK_FAILED" || -L "$P9_043_DEBUG_HOOK_FAILED" ||
        ! -e /dev/fd/8 ]]; then
    printf 'prelink-guard\n' >"${P9_043_DEBUG_HOOK_FAILED:-/dev/null}"
    builtin kill -KILL 0
  fi
  {
    IFS= read -r -u 7 first_line || first_line=''
    IFS= read -r -u 7 extra_line || extra_line=''
  } 7<"$candidate"
  if [[ "$first_line" != 'reject:unexpected-data' || "$extra_line" != '' ]]; then
    printf 'candidate-record\n' >"$P9_043_DEBUG_HOOK_FAILED"
    builtin kill -KILL 0
  fi

  printf 'ready|reject:unexpected-data\n' >"$P9_043_DEBUG_PRELINK_STOPPED"
  builtin kill -STOP 0

  if [[ ! -f "$disposition" || -L "$disposition" || ! -O "$disposition" ||
        ! -f "$parent_candidate" || -L "$parent_candidate" ||
        ! "$disposition" -ef "$parent_candidate" ||
        "$disposition" -ef "$candidate" ||
        ! -f "$authorized" || -L "$authorized" ||
        -e "$rejected" || -L "$rejected" ]]; then
    printf 'post-cont-election\n' >"$P9_043_DEBUG_HOOK_FAILED"
    builtin kill -KILL 0
  fi
  IFS= read -r first_line <"$disposition" || first_line=''
  if [[ "$first_line" != 'authorize' ]]; then
    printf 'post-cont-record\n' >"$P9_043_DEBUG_HOOK_FAILED"
    builtin kill -KILL 0
  fi
  printf 'continued\n' >"$P9_043_DEBUG_CONTINUED"
  return 0
}

set -T
trap '_p9_043_debug_gate' DEBUG
