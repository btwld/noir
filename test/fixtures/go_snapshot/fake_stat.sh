#!/usr/bin/env bash

set -u

real_stat="${GO_SNAPSHOT_REAL_STAT:?missing GO_SNAPSHOT_REAL_STAT}"
mode="${GO_SNAPSHOT_FAKE_STAT_MODE:-passthrough}"
marker="${GO_SNAPSHOT_FAKE_STAT_MARKER:-}"
release="${GO_SNAPSHOT_FAKE_STAT_RELEASE:-}"

case "$mode" in
  passthrough) ;;
  gated-child-fifo)
    requested_path="${!#}"
    if [[ "${requested_path##*/}" == child.anchor-control.fifo ]]; then
      [[ "$marker" != "" && "$release" != "" ]] || exit 64
      : >"$marker" || exit 8
      ticks=0
      while [[ ! -f "$release" && "$ticks" -lt 1000 ]]; do
        /bin/sleep 0.01
        ticks=$((ticks + 1))
      done
      [[ -f "$release" ]] || exit 8
      printf '600\n'
      exit 0
    fi
    ;;
  *)
    exit 64
    ;;
esac

exec "$real_stat" "$@"
