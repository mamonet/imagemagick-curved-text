#!/usr/bin/env bash
# repo path: lib/label.sh
# STEP 1: render the text to a standalone transparent label.
#
# Why this happens before any bending: every distortion operator (Arc,
# Perspective, displace, cylinderize) resamples the pixels it is handed. It
# cannot add detail, only spend it. Text that is badly laid out flat comes out
# of a distortion badly laid out and soft, and no amount of curvature tuning
# afterwards recovers it. So: settle the face, the size, the wrapping and the
# colour here, at a resolution well above the final placement, and treat the
# result as an immutable asset for the rest of the pipeline.
#
# Defect in v1: `-size WxH caption:` treats the pointsize as an upper bound.
# caption: silently scales the text DOWN to make it fit the box, so a short
# string filled the box at ~96pt while a long one landed at ~60pt. Every item
# rendered "correctly" and the set looked inconsistent, with no error anywhere.
# Fix: give caption: a width only ("-size ${width}x"). With no height
# constraint the pointsize is honoured exactly and the box grows downwards
# instead. Height is then an outcome we measure, not an input we impose.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_LABEL:-}" ]; then return 0; fi
_LIB_LABEL=1

# label_render <text> <font> <pointsize> <fill> <width> <out> [interline] [pad]
#   width    wrap width in px; height grows to fit
#   interline extra leading in px (negative tightens)
#   pad      transparent border, headroom so distortion filters do not clip
label_render() {
  local text="$1" font="$2" pointsize="$3" fill="$4" width="$5" out="$6"
  local interline="${7:-0}" pad="${8:-24}"

  # caption:@- reads the string from stdin: a leading '@' in the text would
  # otherwise make ImageMagick treat it as a filename to read.
  printf '%s' "$text" | im_run "$IM" \
    -background none \
    -fill "$fill" \
    -font "$font" \
    -pointsize "$pointsize" \
    -interline-spacing "$interline" \
    -gravity center \
    -size "${width}x" \
    caption:@- \
    -trim +repage \
    -bordercolor none -border "${pad}x${pad}" \
    -depth 8 \
    "png32:$out"
}

# Guard against a wrap width the text cannot honour (one very long word).
# Better a loud failure than a label that overhangs the mockup by 200px.
label_assert_width() {
  local label="$1" max="$2" index="${3:-?}" w
  w="$(im_width "$label")"
  [ "$w" -le "$max" ] \
    || die "[$index] label is ${w}px wide, exceeds label_width ${max}px: shorten the text or lower pointsize"
}
