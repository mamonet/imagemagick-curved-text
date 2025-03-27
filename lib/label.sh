#!/usr/bin/env bash
# repo path: lib/label.sh
# STEP 1: render the text to a standalone transparent label.
#
# Nothing bends text well. Every distortion operator resamples, and resampling
# only ever costs sharpness, so the typography has to be correct while it is
# still flat and orthogonal. Render big, render on transparency, then bend.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_LABEL:-}" ]; then return 0; fi
_LIB_LABEL=1

# label_render <text> <font> <pointsize> <fill> <width> <height> <out>
# Fixed WxH box, caption: wraps the text into it.
label_render() {
  local text="$1" font="$2" pointsize="$3" fill="$4" width="$5" height="$6" out="$7"

  # caption:@- reads the string from stdin. Inlining it as "caption:$text"
  # would let a leading '@' make ImageMagick open a file off disk.
  printf '%s' "$text" | im_run "$IM" \
    -background none \
    -fill "$fill" \
    -font "$font" \
    -pointsize "$pointsize" \
    -gravity center \
    -size "${width}x${height}" \
    caption:@- \
    -trim +repage \
    "png32:$out"
}
