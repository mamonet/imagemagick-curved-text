#!/usr/bin/env bash
# repo path: lib/perspective.sh
# Tilt a flat label into the plane of a product shot taken off-axis.
# Arc handles curvature; this handles the camera. A tilted mockup needs both.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_PERSPECTIVE:-}" ]; then return 0; fi
_LIB_PERSPECTIVE=1

# perspective_apply <in> <out> <tlx> <tly> <trx> <try> <brx> <bry> <blx> <bly>
#
# -distort Perspective takes four source,destination pairs as ONE argument:
#   "sx1,sy1 dx1,dy1  sx2,sy2 dx2,dy2  ..."
# Source points are the label's own corners; destinations are the item's
# corner fields, measured off the mockup in an image editor. Four pairs is the
# exact number the 8-coefficient solve needs; more would be a least-squares
# fit, fewer falls back to Affine.
#
# The destination string is assembled from fields that validate.sh has already
# proved numeric, and is handed over as a single array element. It is never
# interpolated into a command line.
perspective_apply() {
  local in="$1" out="$2"
  local tlx="$3" tly="$4" trx="$5" try="$6" brx="$7" bry="$8" blx="$9" bly="${10}"
  local w h points

  w="$(im_width "$in")"
  h="$(im_height "$in")"

  # Clockwise from top-left, source and destination in matching order.
  points="$(printf '0,0 %s,%s  %s,0 %s,%s  %s,%s %s,%s  0,%s %s,%s' \
    "$tlx" "$tly" \
    "$w"   "$trx" "$try" \
    "$w" "$h" "$brx" "$bry" \
    "$h" "$blx" "$bly")"

  # Same background/virtual-pixel rules as Arc: the transform pulls pixels from
  # outside the source and must find transparency there, not smeared edges.
  im_run "$IM" "$in" \
    -alpha set \
    -background none \
    -virtual-pixel none \
    -distort Perspective "$points" \
    +repage \
    "png32:$out"
}

# Destination corners are absolute mockup coordinates, so a label distorted
# this way is already positioned. Composite it at 0,0 rather than at
# center_x/center_y or it lands twice-offset.
perspective_is_absolute() { return 0; }
