#!/usr/bin/env bash
# repo path: lib/composite.sh
# Last step: drop the wrapped label back onto the product mockup.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_COMPOSITE:-}" ]; then return 0; fi
_LIB_COMPOSITE=1

# composite_place <product> <label> <center_x> <center_y> <out>
# center_x/center_y are the label's CENTRE on the mockup, which is how you
# actually measure a placement; -geometry wants the top-left, so convert.
composite_place() {
  local product="$1" label="$2" cx="$3" cy="$4" out="$5"
  local lw lh ox oy

  read -r lw lh <<<"$(im_size "$label")"
  ox=$(( cx - lw / 2 ))
  oy=$(( cy - lh / 2 ))

  im_run "$IM" "$product" "$label" \
    -gravity NorthWest \
    -geometry "+${ox}+${oy}" \
    -compose over \
    -composite \
    "png24:$out"
}
