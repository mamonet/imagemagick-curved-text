#!/usr/bin/env bash
# repo path: lib/validate.sh
# Pre-flight checks. Everything that can be caught before the first render is
# caught here, so a 30-item run does not die halfway through.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_VALIDATE:-}" ]; then return 0; fi
_LIB_VALIDATE=1

VALID_MODES="arc perspective displace cylinderize"

validate_number() {
  local val="$1" what="$2" index="${3:-?}"
  case "$val" in
    ''|*[!0-9.+-]*) die "[$index] $what must be numeric, got '$val'" ;;
  esac
}

validate_outdir() {
  local outdir="$1"
  mkdir -p -- "$outdir" || die "cannot create output dir: $outdir"
  [ -w "$outdir" ] || die "output dir not writable: $outdir"
}

validate_file() {
  local path="$1" what="$2" index="${3:-?}"
  [ -n "$path" ] || die "[$index] empty $what path"
  [ -f "$path" ] || die "[$index] $what not found: $path"
  [ -r "$path" ] || die "[$index] $what not readable: $path"
}

# A font is either a file we can stat or a family name ImageMagick knows.
# Checking the family list avoids the silent fallback to the default face,
# which is the classic "why does item 7 look different" bug.
validate_font() {
  local font="$1" index="${2:-?}"
  case "$font" in
    */*|*.ttf|*.otf|*.ttc)
      validate_file "$font" "font file" "$index"
      ;;
    *)
      "$IM" -list font | grep -qi "Font: ${font}\$" \
        || die "[$index] font '$font' is not a file and not in '$IM -list font'"
      ;;
  esac
}

validate_mode() {
  local mode="$1" index="${2:-?}" known
  for known in $VALID_MODES; do
    [ "$mode" = "$known" ] && return 0
  done
  die "[$index] unknown mode '$mode' (want one of: $VALID_MODES)"
}

# Fields every item needs regardless of mode.
validate_common() {
  local obj="$1" index="$2" mockup font
  json_req "$obj" '.text' "$index" >/dev/null
  mockup="$(json_req "$obj" '.mockup' "$index")"
  font="$(json_req "$obj" '.font' "$index")"
  validate_file "$mockup" "mockup" "$index"
  validate_font "$font" "$index"
  validate_number "$(json_opt "$obj" '.pointsize' '96')" "pointsize" "$index"
  validate_number "$(json_req "$obj" '.center_x' "$index")" "center_x" "$index"
  validate_number "$(json_req "$obj" '.center_y' "$index")" "center_y" "$index"
}

validate_arc() {
  local obj="$1" index="$2"
  validate_number "$(json_req "$obj" '.arc_degrees' "$index")" "arc_degrees" "$index"
}

validate_perspective() {
  local obj="$1" index="$2" corner
  for corner in tl tr br bl; do
    validate_number "$(json_req "$obj" ".corners.${corner}[0]" "$index")" "corners.$corner x" "$index"
    validate_number "$(json_req "$obj" ".corners.${corner}[1]" "$index")" "corners.$corner y" "$index"
  done
}

validate_displace() {
  local obj="$1" index="$2" map
  map="$(json_req "$obj" '.displace_map' "$index")"
  validate_file "$map" "displacement map" "$index"
  validate_number "$(json_opt "$obj" '.displace_x' '10')" "displace_x" "$index"
  validate_number "$(json_opt "$obj" '.displace_y' '4')" "displace_y" "$index"
}

validate_cylinderize() {
  local obj="$1" index="$2" field
  for field in cyl_radius cyl_length cyl_wrap; do
    validate_number "$(json_req "$obj" ".${field}" "$index")" "$field" "$index"
  done
}

# Dispatcher: run the common checks then the mode-specific ones.
validate_item() {
  local obj="$1" index="$2" mode="$3"
  validate_mode "$mode" "$index"
  validate_common "$obj" "$index"
  case "$mode" in
    arc)         validate_arc "$obj" "$index" ;;
    perspective) validate_perspective "$obj" "$index" ;;
    displace)    validate_displace "$obj" "$index" ;;
    cylinderize) validate_cylinderize "$obj" "$index" ;;
  esac
}
