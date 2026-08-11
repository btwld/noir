#!/bin/bash

set -u

wrapper="$1"
run_owner="$2"
dispatch="$3"
audit_library="$4"
control="$5"

[[ "$wrapper" == /* && -f "$wrapper" && ! -L "$wrapper" ]] || exit 80
[[ "$run_owner" == /* && -d "$run_owner" && ! -L "$run_owner" ]] || exit 81
[[ "$dispatch" == /* && -d "$dispatch" && ! -L "$dispatch" ]] || exit 82
[[ "$audit_library" == /* && -f "$audit_library" && ! -L "$audit_library" ]] || exit 83
[[ "$control" == /* && -x "$control" && ! -L "$control" ]] || exit 84
[[ "$control" == "$dispatch/control" ]] || exit 89

printf '%s\n' "$$" >"$run_owner/bootstrap.pid" || exit 85
loader_events="$run_owner/loader-events.raw"
[[ "$loader_events" == /* && -f "$loader_events" && ! -L "$loader_events" ]] || exit 86
export LOADER_EVENTS="$loader_events"

case "$(uname -s)" in
  Darwin) export DYLD_INSERT_LIBRARIES="$audit_library" ;;
  Linux) export LD_PRELOAD="$audit_library" ;;
  *) exit 87 ;;
esac
export HOME="$run_owner/poison-home"
export TMPDIR="$run_owner/poison-tmp"
export PKG_CONFIG_PATH="$run_owner/poison-pkg"
export PKG_CONFIG_LIBDIR="$run_owner/poison-pkg-libdir"
export DYLD_LIBRARY_PATH="$run_owner/poison-dyld"
export LD_LIBRARY_PATH="$run_owner/poison-ld"
export FAKE_SECRET="loader-secret"
export PATH="$dispatch"

for tool in uname tr mktemp mkdir rm ps stat mkfifo nm go pkg-config; do
  resolved="$(builtin type -P "$tool")" || exit 90
  [[ "$resolved" == "$dispatch/$tool" ]] || exit 91
done
[[ -f /bin/ln && -x /bin/ln && ! -d /bin/ln ]] || exit 92
[[ -f /bin/sleep && -x /bin/sleep && ! -d /bin/sleep ]] || exit 93

"$control" </dev/null >"$run_owner/loader-control.stdout.raw" \
  2>"$run_owner/loader-control.stderr.raw" || exit 88

# shellcheck disable=SC1090 # The test validates and pins this absolute wrapper.
source "$wrapper"
exit 125
