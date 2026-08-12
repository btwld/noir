#!/bin/sh
set -eu

expected_hash='zg-0.14.1-oGqU3IQ_tALZIiBN026_NTaPJqU-Upm8P_C7QED2Rzm8'
mkdir -p /opt/zig-global-cache
actual_hash=$(
  /opt/zig/zig fetch \
    --global-cache-dir /opt/zig-global-cache \
    /tmp/zg-v0.14.1.tar.gz
)
if [ "$actual_hash" != "$expected_hash" ]; then
  printf 'zg package hash mismatch: expected %s, got %s\n' \
    "$expected_hash" "$actual_hash" >&2
  exit 1
fi
