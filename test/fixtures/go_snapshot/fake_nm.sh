#!/bin/bash

set -u

fixture_dir="${BASH_SOURCE[0]%/*}"
if [[ "$fixture_dir" == "${BASH_SOURCE[0]}" ]]; then
  fixture_dir="."
fi
fixture_dir="$(cd "$fixture_dir" && pwd -P)" || exit 90
mode_file="$fixture_dir/mode"
events_file="$fixture_dir/events"
release_gate="$fixture_dir/release-gate"
append_gate="$fixture_dir/append-gate"
append_complete="$fixture_dir/append-complete"

[[ -f "$mode_file" && ! -L "$mode_file" ]] || exit 91
IFS= read -r mode <"$mode_file" || exit 92

ps_tool=/bin/ps
[[ -x "$ps_tool" ]] || ps_tool=/usr/bin/ps
pgid="$($ps_tool -o pgid= -p "$$" 2>/dev/null)" || pgid=""
pgid="${pgid//[[:space:]]/}"
printf 'invoked|pid=%s|pgid=%s|argc=%s\n' "$$" "$pgid" "$#" >>"$events_file"
index=0
for argument in "$@"; do
  printf 'argv|%s|%s\n' "$index" "$argument" >>"$events_file"
  index=$((index + 1))
done

for name in HOME TMPDIR PKG_CONFIG_PATH PKG_CONFIG_LIBDIR \
  DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH LD_PRELOAD LD_LIBRARY_PATH \
  LOADER_EVENTS FAKE_SECRET; do
  if [[ "${!name+x}" == x ]]; then
    printf 'poison|%s=present\n' "$name" >>"$events_file"
  else
    printf 'poison|%s=absent\n' "$name" >>"$events_file"
  fi
done

prefix=""
if [[ "${1:-}" == "-gU" ]]; then
  prefix="_"
elif [[ "${1:-}" == "-D" && "${2:-}" == "--defined-only" ]]; then
  prefix=""
else
  printf 'invalid-argv\n' >>"$events_file"
  exit 93
fi

native_symbols=(
  textBufferGetCharPtr
  textBufferGetFgPtr
  textBufferGetBgPtr
  textBufferGetAttributesPtr
  textBufferSetCell
  textBufferGetLineStartsPtr
  textBufferGetLineWidthsPtr
)
pending_symbols=(
  textBufferConcat
  textBufferResize
  textBufferGetCapacity
)

emit_symbol() {
  printf '0000000000000000 T %s%s\n' "$prefix" "$1"
}

case "$mode" in
  exact-seven)
    for symbol in "${native_symbols[@]}"; do emit_symbol "$symbol"; done
    ;;
  added)
    for symbol in "${native_symbols[@]}"; do emit_symbol "$symbol"; done
    emit_symbol "${pending_symbols[0]}"
    ;;
  lost)
    for symbol in "${native_symbols[@]:1}"; do emit_symbol "$symbol"; done
    ;;
  added-and-lost)
    for symbol in "${native_symbols[@]:1}"; do emit_symbol "$symbol"; done
    for symbol in "${pending_symbols[@]}"; do emit_symbol "$symbol"; done
    ;;
  tool-error|gated-tool-error|forking-tool-error)
    if [[ "$mode" == gated-tool-error ]]; then
      while [[ ! -f "$release_gate" ]]; do /bin/sleep 0.01; done
    fi
    if [[ "$mode" == forking-tool-error ]]; then
      /usr/bin/perl -e '$SIG{TERM}="IGNORE"; $SIG{INT}="IGNORE"; sleep 300' &
      printf 'descendant|pid=%s\n' "$!" >>"$events_file"
    fi
    printf 'private nm failure secret\n' >&2
    exit 9
    ;;
  hung-forking)
    /usr/bin/perl -e '$SIG{TERM}="IGNORE"; $SIG{INT}="IGNORE"; sleep 300' &
    printf 'descendant|pid=%s\n' "$!" >>"$events_file"
    while :; do /bin/sleep 1; done
    ;;
  forking-success-delayed-append)
    for symbol in "${native_symbols[@]}"; do emit_symbol "$symbol"; done
    (
      trap '' INT TERM
      while [[ ! -f "$append_gate" ]]; do /bin/sleep 0.01; done
      emit_symbol "${pending_symbols[0]}"
      : >"$append_complete"
      while :; do /bin/sleep 1; done
    ) &
    printf 'descendant|pid=%s\n' "$!" >>"$events_file"
    ;;
  forking-success-descriptor-holder)
    for symbol in "${native_symbols[@]}"; do emit_symbol "$symbol"; done
    (
      trap '' INT TERM
      while :; do /bin/sleep 1; done
    ) &
    printf 'descendant|pid=%s\n' "$!" >>"$events_file"
    ;;
  *)
    printf 'invalid-mode|%s\n' "$mode" >>"$events_file"
    exit 94
    ;;
esac

exit 0
