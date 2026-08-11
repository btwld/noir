#!/usr/bin/env bash

set -u

mode="${GO_SNAPSHOT_FAKE_MKTEMP_MODE:-normal}"

case "$mode" in
  fail)
    exit 9
    ;;
  out-of-root)
    outside="${GO_SNAPSHOT_FAKE_MKTEMP_OUTSIDE:?missing outside path}"
    /bin/mkdir -m 700 "$outside" || exit 8
    printf '%s\n' "$outside"
    exit 0
    ;;
  symlink)
    link="${GO_SNAPSHOT_FAKE_MKTEMP_LINK:?missing link path}"
    target="${GO_SNAPSHOT_FAKE_MKTEMP_TARGET:?missing target path}"
    /bin/mkdir -m 700 "$target" || exit 8
    /bin/ln -s "$target" "$link" || exit 8
    printf '%s\n' "$link"
    exit 0
    ;;
  public-dir)
    directory="$(/usr/bin/mktemp "$@")" || exit $?
    /bin/chmod 755 "$directory" || exit 8
    printf '%s\n' "$directory"
    exit 0
    ;;
  wrong-prefix)
    exec /usr/bin/mktemp -d \
      "${TMPDIR:?missing TMPDIR}/wrong-go-snapshot-prefix.XXXXXX"
    ;;
  preexisting-fifo-state)
    directory="$(/usr/bin/mktemp "$@")" || exit $?
    : >"$directory/child.anchor-control.fifo" || exit 8
    printf '%s\n' "$directory"
    exit 0
    ;;
  normal) ;;
  *) exit 64 ;;
esac

if [[ "$#" -eq 1 && "$1" == "-d" ]]; then
  exec /usr/bin/mktemp -d "${TMPDIR:?missing TMPDIR}/legacy-wrapper.XXXXXX"
fi

exec /usr/bin/mktemp "$@"
