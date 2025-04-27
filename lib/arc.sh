#!/usr/bin/env bash
# repo path: lib/arc.sh
# Bend a flat label along a circular arc. The cheap, reliable curve: good for
# a mug band or a lid rim where the surface is seen close to straight on.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_ARC:-}" ]; then return 0; fi
_LIB_ARC=1

# arc_apply <in> <out> <degrees> [rotate]
#   degrees  angle the label spans, e.g. 40 for a gentle mug curve, 360 = ring
#   rotate   optional rotation of the arc's centre, degrees clockwise
#
# Two flags carry the whole thing:
#   -background none   Arc grows the canvas and fills the new area with the
#                      background colour. Anything but 'none' bakes a solid
#                      rectangle behind the text and the later composite shows
#                      a visible plate over the product.
#   -virtual-pixel none  controls what the resampler reads OUTSIDE the source.
#                      The default (edge) smears the border pixels outwards
#                      along the whole arc, leaving coloured streaks at the
#                      ends. 'none' reads transparent, so the arc ends clean.
# The transparent-background requirement is not cosmetic: it is the difference
# between a wrapped label and a sticker.
arc_apply() {
  local in="$1" out="$2" degrees="$3" rotate="${4:-}"
  local arg="$degrees"
  [ -n "$rotate" ] && arg="$degrees $rotate"

  im_run "$IM" "$in" \
    -alpha set \
    -background none \
    -virtual-pixel none \
    -filter point \
    -distort Arc "$arg" \
    +repage \
    "png32:$out"
}

# Arc bends around the TOP edge of the source. Text meant to sit on the lower
# half of a cylinder needs a 180 rotate, or the curve reads inside-out.
arc_apply_below() {
  local in="$1" out="$2" degrees="$3"
  arc_apply "$in" "$out" "$degrees" "180"
}
