#!/usr/bin/env bash
# repo path: lib/displace.sh
# Push the label around using the product's own shading map, so the text
# follows the surface instead of lying flat across it.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_DISPLACE:-}" ]; then return 0; fi
_LIB_DISPLACE=1

# displace_apply <label> <map> <out> <amount_x> <amount_y>
#
# -compose displace reads the map's channel values as per-pixel offsets:
# mid-grey means "leave this pixel alone", darker/lighter shift it left/right
# (or up/down) by up to the compose:args amount. Feed it a map made from the
# bottle's shading and the text bulges where the bottle bulges.
displace_apply() {
  local label="$1" map="$2" out="$3" ax="$4" ay="$5"

  im_run "$IM" "$label" "$map" \
    -alpha set \
    -compose displace \
    -define compose:args="${ax}x${ay}" \
    -composite \
    "png32:$out"
}
