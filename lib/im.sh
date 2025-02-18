#!/usr/bin/env bash
# repo path: lib/im.sh
# ImageMagick detection + invocation shim. Source lib/log.sh before this.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_IM:-}" ]; then return 0; fi
_LIB_IM=1

# Standalone fallback so this lib is usable before log.sh is sourced.
if ! declare -F die >/dev/null 2>&1; then
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }
fi

IM=""            # "magick" (IM7) or "convert" (IM6)
IM_MAJOR=""
IM_VERSION=""
IM_IDENTIFY=()   # array: IM7 needs the "magick" prefix, IM6 does not
IM_MIN_MAJOR=6

# Locate ImageMagick once. Prefers IM7 because IM6's `convert` is deprecated
# and, on Windows, collides with the system convert.exe.
im_init() {
  if command -v magick >/dev/null 2>&1; then
    IM="magick"
    IM_IDENTIFY=(magick identify)
  elif command -v convert >/dev/null 2>&1; then
    IM="convert"
    IM_IDENTIFY=(identify)
  else
    die "ImageMagick not found: need 'magick' (IM7) or 'convert' (IM6) on PATH"
  fi

  # sed -n '1s//p' rather than `head -1`: head closes the pipe early and
  # pipefail would then trip on SIGPIPE.
  IM_VERSION="$("$IM" -version 2>/dev/null | sed -n '1s/.*ImageMagick \([0-9][0-9.-]*\).*/\1/p')"
  [ -n "$IM_VERSION" ] || die "'$IM -version' is not recognisable ImageMagick output"

  IM_MAJOR="${IM_VERSION%%.*}"
  case "$IM_MAJOR" in
    ''|*[!0-9]*) die "cannot read major version from '$IM_VERSION'" ;;
  esac
  [ "$IM_MAJOR" -ge "$IM_MIN_MAJOR" ] \
    || die "ImageMagick $IM_VERSION too old; need >= ${IM_MIN_MAJOR}.x"

  export IM IM_MAJOR IM_VERSION
}

# Run a command, echoing it first under --verbose. %q quoting means the echoed
# line can be pasted into a shell and reproduces the render exactly.
im_run() {
  if [ "${VERBOSE:-0}" = "1" ]; then
    printf '+' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  fi
  "$@"
}

# Width and height of the first frame, as "W H".
im_size() {
  local file="$1" out
  out="$("${IM_IDENTIFY[@]}" -format '%w %h' "${file}[0]")" \
    || die "cannot read image dimensions: $file"
  printf '%s' "$out"
}

im_width()  { im_size "$1" | cut -d' ' -f1; }
im_height() { im_size "$1" | cut -d' ' -f2; }

# Fail early if a delegate/format we depend on is not compiled in.
im_require_format() {
  local fmt="$1"
  "$IM" -list format | grep -qi "^ *${fmt}\**  *[rw]" \
    || die "ImageMagick build has no read/write support for '$fmt'"
}
