# repo path: tests/test_helper.bash
#
# Shared bats helpers.
#
# The point of this file is the ImageMagick stub. These tests assert on the
# COMMAND THAT GETS BUILT, not on pixels, so nothing here needs ImageMagick
# installed and nothing here decodes an image. A fake `magick` goes on PATH,
# records every argv it is handed, answers the handful of queries the libs make
# (-version, -list format, -list font, identify -format), touches the output
# file so the next step's existence checks pass, and exits 0.
#
# Asserting on argv rather than on output is also the only way to test the
# interesting part. Whether `-virtual-pixel none` was passed before `-distort`
# is exactly the kind of bug that produces a plausible-looking wrong image, and
# a pixel comparison against a committed reference would not catch it without
# committing binaries this repo deliberately does not have.
#
# jq is a real dependency and is not stubbed; tests that need it skip when it
# is missing.
# shellcheck shell=bash

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# --- fake ImageMagick -------------------------------------------------------

# Dimensions the stub reports for every `identify -format '%w %h'`. Override in
# a test before calling code that measures a label.
STUB_IM_W="${STUB_IM_W:-800}"
STUB_IM_H="${STUB_IM_H:-200}"

# Fonts the stub claims to know, for validate_font's family-name branch.
STUB_IM_FONTS="${STUB_IM_FONTS:-DejaVu-Sans}"

# Writes the stub to $STUB_BIN/magick and puts it first on PATH.
#   IM_LOG   one line per call, argv joined by single spaces. Grep this.
#   IM_ARGV  one argv element per line, calls separated by a line of "--".
#            Use when a test must prove two arguments are separate words.
setup_stub_im() {
  STUB_BIN="$TEST_TMP/bin"
  IM_LOG="$TEST_TMP/im-calls.log"
  IM_ARGV="$TEST_TMP/im-argv.log"
  mkdir -p "$STUB_BIN"
  : >"$IM_LOG"
  : >"$IM_ARGV"

  cat >"$STUB_BIN/magick" <<'STUB'
#!/usr/bin/env bash
# Recorded fake. Never touches a real image.
set -u

printf '%s\n' "$*" >>"$IM_LOG"
printf '%s\n' "$@" >>"$IM_ARGV"
printf -- '--\n' >>"$IM_ARGV"

case "${1:-}" in
  -version)
    printf 'Version: ImageMagick 7.1.1-21 Q16-HDRI x86_64 (stub)\n'
    exit 0
    ;;
  -list)
    case "${2:-}" in
      format) printf '  PNG*  rw+   Portable Network Graphics\n'
              printf '  JPEG* rw-   Joint Photographic Experts Group\n' ;;
      font)   for f in $STUB_IM_FONTS; do printf '  Font: %s\n' "$f"; done ;;
      *)      : ;;
    esac
    exit 0
    ;;
  identify)
    printf '%s %s' "$STUB_IM_W" "$STUB_IM_H"
    exit 0
    ;;
esac

# A render. Create whatever the last argument names, minus any IM format
# prefix, so the caller's -f checks and the next step both succeed.
out=""
for a in "$@"; do out="$a"; done
case "$out" in
  png32:*|png24:*|png8:*|png:*) out="${out#*:}" ;;
esac
case "$out" in
  -*|'') exit 0 ;;
esac
mkdir -p -- "$(dirname -- "$out")" 2>/dev/null || true
printf 'stub-png' >"$out"
exit 0
STUB
  chmod +x "$STUB_BIN/magick"

  export IM_LOG IM_ARGV STUB_IM_W STUB_IM_H STUB_IM_FONTS
  export PATH="$STUB_BIN:$PATH"
}

# Every recorded call, one per line.
im_calls() { cat "$IM_LOG"; }

# awk, not `grep -c`: grep exits 1 on an empty log, which under `set -e` or a
# `|| printf 0` fallback turns "0" into "00".
im_call_count() { awk 'END{print NR}' "$IM_LOG"; }

im_last_call() { tail -n 1 "$IM_LOG"; }

# The Nth recorded call, 1-based.
im_call() { sed -n "${1}p" "$IM_LOG"; }

# The first call matching a pattern, so a test does not depend on how many
# probe calls (-version, -list) happened first.
im_call_matching() { grep -m1 -- "$1" "$IM_LOG"; }

# --- assertions -------------------------------------------------------------
# Minimal versions so the suite does not require bats-assert.

assert_success() {
  [ "$status" -eq 0 ] || {
    printf 'expected success, got exit %s\noutput: %s\n' "$status" "$output" >&2
    return 1
  }
}

assert_failure() {
  [ "$status" -ne 0 ] || {
    printf 'expected failure, got exit 0\noutput: %s\n' "$output" >&2
    return 1
  }
}

assert_output_contains() {
  case "$output" in
    *"$1"*) return 0 ;;
    *) printf 'expected output to contain: %s\ngot: %s\n' "$1" "$output" >&2; return 1 ;;
  esac
}

assert_output_not_contains() {
  case "$output" in
    *"$1"*) printf 'expected output NOT to contain: %s\ngot: %s\n' "$1" "$output" >&2; return 1 ;;
    *) return 0 ;;
  esac
}

assert_equal() {
  [ "$1" = "$2" ] || { printf 'expected: %s\n     got: %s\n' "$2" "$1" >&2; return 1; }
}

# An ImageMagick call was recorded whose argv contains this substring.
assert_im_called_with() {
  grep -q -- "$1" "$IM_LOG" || {
    printf 'no recorded ImageMagick call contained: %s\ncalls:\n%s\n' "$1" "$(cat "$IM_LOG")" >&2
    return 1
  }
}

assert_im_not_called_with() {
  grep -q -- "$1" "$IM_LOG" && {
    printf 'unexpected ImageMagick call contained: %s\n' "$1" >&2
    return 1
  }
  return 0
}

# Two argv elements are adjacent and separate words. Catches the case where a
# flag and its value were accidentally passed as one string.
assert_im_argv_adjacent() {
  local first="$1" second="$2"
  grep -A1 -x -F -- "$first" "$IM_ARGV" | grep -q -x -F -- "$second" || {
    printf 'expected argv "%s" immediately followed by "%s"\nargv:\n%s\n' \
      "$first" "$second" "$(cat "$IM_ARGV")" >&2
    return 1
  }
}

# --- library loading --------------------------------------------------------

# Source libs in dependency order. log.sh first: it defines die/info/debug that
# the others call. im.sh is loaded but im_init is NOT run, so $IM stays under
# the test's control.
load_libs() {
  local lib
  for lib in "$@"; do
    # shellcheck disable=SC1090
    . "$REPO_ROOT/lib/$lib.sh"
  done
}

# The usual arrangement: real libs, fake binary.
load_libs_with_stub() {
  load_libs log im "$@"
  IM="$STUB_BIN/magick"
  IM_IDENTIFY=("$STUB_BIN/magick" identify)
  IM_VERSION="7.1.1-21"
  IM_MAJOR=7
  export IM IM_VERSION IM_MAJOR
}

# --- fixtures ---------------------------------------------------------------

require_jq() {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# Placeholder files. Nothing reads their contents: validate.sh stats them and
# the stub never decodes them. No binaries in this repo, tests included.
fixture_file() {
  mkdir -p -- "$(dirname -- "$1")"
  printf 'not-a-real-image' >"$1"
}

# A minimal valid item, mode arc, with its mockup and font on disk. Prints the
# compact JSON object. Extra jq assignments can be piped on by the caller.
fixture_item_arc() {
  fixture_file "$TEST_TMP/mockups/mug.png"
  fixture_file "$TEST_TMP/fonts/DejaVuSans-Bold.ttf"
  cat <<JSON
{"mode":"arc","text":"Fresh Roast Daily","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","center_x":640,"center_y":520,"arc_degrees":42}
JSON
}

# Writes an items.json holding the given compact objects, and returns its path.
write_items() {
  local file="$TEST_TMP/items.json" first=1 obj
  {
    printf '['
    for obj in "$@"; do
      [ "$first" = 1 ] || printf ','
      printf '%s' "$obj"
      first=0
    done
    printf ']\n'
  } >"$file"
  printf '%s' "$file"
}

# --- lifecycle --------------------------------------------------------------

# Per-test scratch dir. BATS_TEST_TMPDIR is per-test on bats >= 1.4; fall back
# to mktemp so the suite still runs on older bats.
common_setup() {
  TEST_TMP="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  export TEST_TMP
  setup_stub_im
  cd "$TEST_TMP" || return 1
}

common_teardown() {
  # BATS_TEST_TMPDIR is cleaned by bats. Only clean up what we made ourselves.
  [ -n "${BATS_TEST_TMPDIR:-}" ] || rm -rf -- "$TEST_TMP"
}
