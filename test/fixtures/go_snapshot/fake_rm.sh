#!/usr/bin/env bash

set -u

mode="${GO_SNAPSHOT_FAKE_RM_MODE:-normal}"
observation="${GO_SNAPSHOT_TEST_OBSERVATION:-}"
real_stat="${GO_SNAPSHOT_REAL_STAT:-/usr/bin/stat}"
raw_capture="${GO_SNAPSHOT_FAKE_RM_RAW_CAPTURE:-}"

is_final=false
final_path=""
if [[ "$#" -eq 3 && "$1" == "-rf" && "$2" == "--" ]]; then
  is_final=true
  final_path="$3"
fi

# shellcheck disable=SC2129 # Each record is intentionally termination-observable.
record_final_state() {
  [[ "$observation" != "" ]] || return 0
  printf 'REMOVE|attempt|%s\n' "$final_path" >>"$observation"
  for sink in \
    supervisor.shell.stderr \
    child.shell.stderr \
    watchdog.shell.stderr \
    child.mkfifo.stdout \
    child.mkfifo.stderr \
    watchdog.mkfifo.stdout \
    watchdog.mkfifo.stderr; do
    if [[ -f "$final_path/$sink" ]]; then
      printf 'SINK|%s|begin\n' "$sink" >>"$observation"
      /bin/cat "$final_path/$sink" >>"$observation"
      printf 'SINK|%s|end\n' "$sink" >>"$observation"
    fi
  done

  for entry in \
    watchdog.deadline.pid \
    watchdog.deadline-started \
    fifo.setup-begin \
    fifo.setup-held \
    fifo.setup-authorized \
    fifo.setup-closed \
    fifo.setup.watchdog-create-error \
    fifo.setup.watchdog-invalid \
    fifo.setup.child-create-error \
    fifo.setup.child-invalid \
    fifo.setup.quiescence-error \
    fifo.setup.protocol-error; do
    path="$final_path/$entry"
    if [[ -f "$path" && ! -L "$path" ]]; then
      printf 'MARKER|%s|present\n' "$entry" >>"$observation"
    fi
  done

  for entry in \
    symbol-preflight.stdout.raw \
    symbol-preflight.stderr.raw \
    symbol-preflight.result \
    symbol-preflight.quiescence-held \
    symbol-preflight.quiescence-parent.candidate \
    symbol-preflight.quiescence-child.candidate \
    symbol-preflight.quiescence-disposition \
    symbol-preflight.quiescence-authorized \
    symbol-preflight.quiescence-rejected \
    symbol-preflight.quiescence-closed; do
    path="$final_path/$entry"
    if [[ -f "$path" && ! -L "$path" ]]; then
      printf 'P9_STATE|%s|present\n' "$entry" >>"$observation"
    elif [[ ! -e "$path" && ! -L "$path" ]]; then
      printf 'P9_STATE|%s|absent\n' "$entry" >>"$observation"
    else
      printf 'P9_STATE|%s|invalid\n' "$entry" >>"$observation"
    fi
  done

  for entry in child.anchor-control.fifo watchdog.anchor-control.fifo; do
    path="$final_path/$entry"
    if [[ -p "$path" && ! -L "$path" ]]; then
      printf 'FIFO|%s|present\n' "$entry" >>"$observation"
    fi
  done

  for entry in \
    child.candidate \
    watchdog.candidate \
    outcome \
    symbol-preflight.quiescence-parent.candidate \
    symbol-preflight.quiescence-child.candidate \
    symbol-preflight.quiescence-disposition; do
    path="$final_path/$entry"
    if [[ -f "$path" && ! -L "$path" ]]; then
      if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        inode="$($real_stat -f '%i' "$path")"
        size="$($real_stat -f '%z' "$path")"
      else
        inode="$($real_stat -c '%i' "$path")"
        size="$($real_stat -c '%s' "$path")"
      fi
      IFS= read -r first_line <"$path" || first_line=""
      printf 'FS|%s|inode=%s|size=%s|line=%s\n' \
        "$entry" "$inode" "$size" "$first_line" >>"$observation"
    fi
  done

  for entry in \
    child.ln.stderr \
    watchdog.ln.stderr \
    symbol-preflight.quiescence-parent.ln.stderr \
    symbol-preflight.quiescence-child.ln.stderr; do
    path="$final_path/$entry"
    if [[ -f "$path" ]]; then
      if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        size="$($real_stat -f '%z' "$path")"
      else
        size="$($real_stat -c '%s' "$path")"
      fi
      printf 'LINK_STDERR|%s|size=%s\n' "$entry" "$size" \
        >>"$observation"
    fi
  done
}

capture_symbol_raw_state() {
  [[ "$raw_capture" == /* && -d "$raw_capture" && ! -L "$raw_capture" ]] ||
    exit 65
  child_consumed=false
  watchdog_consumed=false
  while IFS= read -r row; do
    case "$row" in
      *'TRACE|wait_consumed|child|'*) child_consumed=true ;;
      *'TRACE|wait_consumed|watchdog|'*) watchdog_consumed=true ;;
    esac
  done <"$final_path/supervisor.shell.stderr"
  [[ "$child_consumed" == true && "$watchdog_consumed" == true ]] || exit 66

  for stream in stdout stderr; do
    source="$final_path/symbol-preflight.$stream.raw"
    [[ -f "$source" && ! -L "$source" ]] || exit 67
    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
      inode_before="$($real_stat -f '%i' "$source")" || exit 68
      size_before="$($real_stat -f '%z' "$source")" || exit 68
    else
      inode_before="$($real_stat -c '%i' "$source")" || exit 68
      size_before="$($real_stat -c '%s' "$source")" || exit 68
    fi
    /bin/cp "$source" "$raw_capture/$stream.first" || exit 69
    printf '%s|%s\n' "$inode_before" "$size_before" \
      >"$raw_capture/$stream.before" || exit 69
  done

  /bin/sleep 0.1
  for stream in stdout stderr; do
    source="$final_path/symbol-preflight.$stream.raw"
    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
      inode_after="$($real_stat -f '%i' "$source")" || exit 70
      size_after="$($real_stat -f '%z' "$source")" || exit 70
    else
      inode_after="$($real_stat -c '%i' "$source")" || exit 70
      size_after="$($real_stat -c '%s' "$source")" || exit 70
    fi
    /bin/cp "$source" "$raw_capture/$stream.second" || exit 71
    IFS='|' read -r inode_before size_before \
      <"$raw_capture/$stream.before" || exit 71
    printf 'SYMBOL_RAW|%s|inode=%s|size=%s|inode_after=%s|size_after=%s\n' \
      "$stream" "$inode_before" "$size_before" \
      "$inode_after" "$size_after" >>"$observation"
  done
}

if [[ "$is_final" == true ]]; then
  case "$mode" in
    signal-final-int|signal-final-term)
      signal=TERM
      [[ "$mode" == signal-final-int ]] && signal=INT
      if [[ "$observation" != "" ]]; then
        printf 'INJECT|final_rm|%s\n' "$signal" >>"$observation"
      fi
      kill "-$signal" "$PPID" 2>/dev/null || true
      /bin/sleep 0.1
      ;;
    capture-symbol-raw|fail-final|normal) ;;
    *) exit 64 ;;
  esac
  record_final_state
  if [[ "$mode" == capture-symbol-raw ]]; then
    capture_symbol_raw_state
  fi
  if [[ "$mode" == fail-final ]]; then
    exit 9
  fi
fi

exec /bin/rm "$@"
