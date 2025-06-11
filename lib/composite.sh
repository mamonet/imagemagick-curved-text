#!/usr/bin/env bash
# repo path: lib/composite.sh
# Last step: drop the wrapped label back onto the product mockup.
#
# Defect in v1: `-compose over` pastes opaque pixels. The geometry was right -
# the text curved with the mug - but it sat at a constant density across the
# whole surface, straight over the product's shadow side and over its
# specular highlight alike. Real ink is under the lighting, not on top of it,
# and the eye reads uniform density as a sticker instantly.
# Fix: composite with multiply (or overlay), so the mockup's own luminance
# modulates the glyphs and existing shadows fall across the text. Multiply
# alone has the opposite failure though: dark text multiplied into a dark
# region goes to near-black and the text disappears. So the label's tonal range
# is clamped with -level before blending - its blacks are lifted to a floor, so
# the darkest the composite can go is bounded and the text stays legible in
# shadow while still picking up the gradient.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_COMPOSITE:-}" ]; then return 0; fi
_LIB_COMPOSITE=1

# composite_place <product> <label> <cx> <cy> <out> [blend] [opacity] [floor]
#   blend    multiply | overlay | over   (see composite_pick_blend)
#   opacity  0..1, scales the label's alpha; 0.9 or so reads as printed ink
#   floor    black-point lift %, the clamp; higher = safer on dark products
#
# center_x/center_y are the label's CENTRE on the mockup, which is how a
# placement is actually measured. -geometry wants a top-left, so convert.
composite_place() {
  local product="$1" label="$2" cx="$3" cy="$4" out="$5"
  local blend="${6:-multiply}" opacity="${7:-0.92}" floor="${8:-18}"
  local lw lh ox oy

  read -r lw lh <<<"$(im_size "$label")"
  ox=$(( cx - lw / 2 ))
  oy=$(( cy - lh / 2 ))

  # The label is preprocessed inside parens so the -level and -channel work
  # apply to it alone and never touch the product underneath.
  #   -channel RGB -level floor%,100%   the clamp; alpha excluded so glyph
  #                                     antialiasing survives
  #   -channel A -evaluate multiply     global opacity, edges stay soft
  im_run "$IM" "$product" \
    '(' "$label" \
        -alpha set \
        -channel RGB -level "${floor}%,100%" +channel \
        -channel A -evaluate multiply "$opacity" +channel \
    ')' \
    -gravity NorthWest \
    -geometry "+${ox}+${oy}" \
    -compose "$blend" \
    -composite \
    +repage \
    "png24:$out"
}

# Perspective output is already in mockup coordinates (its destination corners
# were absolute), so it composites at the origin, not at center_x/center_y.
composite_place_absolute() {
  local product="$1" label="$2" out="$3"
  local blend="${4:-multiply}" opacity="${5:-0.92}" floor="${6:-18}"
  local pw ph

  read -r pw ph <<<"$(im_size "$product")"
  im_run "$IM" "$product" \
    '(' "$label" \
        -alpha set \
        -background none -extent "${pw}x${ph}" \
        -channel RGB -level "${floor}%,100%" +channel \
        -channel A -evaluate multiply "$opacity" +channel \
    ')' \
    -gravity NorthWest \
    -geometry '+0+0' \
    -compose "$blend" \
    -composite \
    +repage \
    "png24:$out"
}

# Rule of thumb, overridable per item:
#   dark ink on a light product -> multiply (ink absorbs light)
#   light ink on a dark product -> screen  (multiply would erase it)
#   mid-tone ink, glossy surface -> overlay (keeps highlights hot)
composite_pick_blend() {
  local fill="$1"
  case "$fill" in
    '#f'*|'#e'*|white|'#ffffff') printf 'screen' ;;
    *)                           printf 'multiply' ;;
  esac
}
