#!/usr/bin/env bash
# Capture a bitmap screenshot of an iTerm2 window by its title.
# Usage: ./scripts/screenshot_iterm.sh <window-title> [out.png]
set -euo pipefail

title="${1:-}"
out="${2:-.context/screenshots/$(date +%s).png}"

if [[ -z "$title" ]]; then
  echo "usage: $0 <window-title> [out.png]" >&2
  exit 2
fi

mkdir -p "$(dirname "$out")"
wid="$(GetWindowID iTerm2 "$title")"
screencapture -l "$wid" -x "$out"
echo "$out"
