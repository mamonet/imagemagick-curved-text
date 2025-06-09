#!/usr/bin/env bash
# repo path: lib/displace.sh
#
# ==========================================================================
# Displacement: the step that makes text look wrapped rather than pasted.
# ==========================================================================
#
# What the operator actually does
# -------------------------------
# `-compose displace` does not blend two images. It treats the second image as
# a lookup table of OFFSETS and uses it to move the pixels of the first. For
# every pixel position it reads the map's value there, converts it to a signed
# shift, and fetches the source pixel from that shifted position instead.
#
# The convention is centred on mid-grey:
#
#     value 128 (50% grey)  ->  offset 0        pixel stays put
#     value 0   (black)     ->  offset -max     pixel pulled one way
#     value 255 (white)     ->  offset +max     pixel pulled the other way
#
# `-define compose:args=XxY` sets max: X for horizontal, Y for vertical, in
# pixels (append % to make them a fraction of the image, which is what you
# want if the same items.json drives both a web render and a print render).
# Y is optional; "12" alone displaces horizontally only.
#
# Why a shading map is the right map
# ----------------------------------
# On a photographed cylinder, luminance IS geometry. The bottle is brightest
# where its surface faces the light square-on and falls off towards each edge
# as the surface turns away. That luminance ramp is, to a good approximation,
# the same ramp as the horizontal foreshortening: pixels near the silhouette
# edge represent far more real-world surface per screen pixel than pixels at
# the centre. So feeding the product's own greyscale shading in as the map
# compresses the text towards the edges by exactly the amount the surface is
# turning away, for free, with no 3D model and no per-item hand-tweaking.
#
# The same map does a second job. Local highlights, dents, embossing, the ridge
# of a rolled tin seam, the wrinkle in a label: all of them are local
# brightness deviations, so all of them become local offsets. The text bends
# over a highlight and kinks across a seam the way printed ink does. This is
# why the result reads as physical, and it is the reason to build the map from
# the actual product photo (blurred, levelled) rather than from a synthetic
# gradient. A synthetic gradient gives you a clean curve and a dead-looking
# image.
#
# Displacement moves the text; it does not light it. Lighting comes later, in
# lib/composite.sh, where multiply lets the product's shadows fall across the
# glyphs. The two together are the whole trick.
#
# Defect in v1: the map was passed through untouched. Two consequences, both
# silent:
#   1. A colour map has three different channels, and displace reads the red
#      channel for X and the GREEN channel for Y. A photo whose red and green
#      disagree produces vertical offsets nobody asked for, so the text jitters
#      along its baseline.
#   2. The map was whatever size the source photo was. ImageMagick aligns the
#      map to the label at their top-left corners and simply stops where the
#      map runs out. A map larger than the label means only its corner region
#      is ever sampled, so the offsets come from the wrong part of the curve;
#      a map smaller than the label leaves the overhang undisplaced. Either
#      way the text is bent, just not along the curve it was supposed to
#      follow, and it looks almost-right, which is worse.
# Fix: displace_prepare_map() normalises to a single grey channel and resizes
# to the label's exact dimensions before compositing.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_DISPLACE:-}" ]; then return 0; fi
_LIB_DISPLACE=1

# displace_prepare_map <map> <width> <height> <out> [blur_sigma]
#   -colorspace Gray   one channel, so X and Y offsets agree
#   -auto-level        stretch to full 0..255 so the map's mid-point really is
#                      "no offset"; an unstretched photo sits around 60% grey
#                      and drags the entire label sideways
#   -blur 0x<sigma>    sensor noise is high-frequency and becomes per-pixel
#                      jitter in the offsets; the geometry we want is low
#                      frequency, so blur before use
#   -resize WxH!       '!' forces the exact size, ignoring aspect ratio. The
#                      map must match the label pixel for pixel.
displace_prepare_map() {
  local map="$1" width="$2" height="$3" out="$4" sigma="${5:-6}"

  im_run "$IM" "$map" \
    -alpha off \
    -colorspace Gray \
    -auto-level \
    -blur "0x${sigma}" \
    -resize "${width}x${height}!" \
    -depth 8 \
    "png:$out"
}

# displace_apply <label> <map> <out> <amount_x> <amount_y> [tmpdir]
# Prepares the map against this label's dimensions, then displaces.
displace_apply() {
  local label="$1" map="$2" out="$3" ax="$4" ay="$5" tmpdir="${6:-.}"
  local w h prepared

  read -r w h <<<"$(im_size "$label")"
  prepared="${tmpdir%/}/dmap-$(basename -- "$out").png"

  displace_prepare_map "$map" "$w" "$h" "$prepared"

  # Order matters: first image is displaced, second is the map.
  # -alpha set keeps the label's transparency; without it the displaced glyphs
  # come back on an opaque black field.
  im_run "$IM" "$label" "$prepared" \
    -alpha set \
    -compose displace \
    -define compose:args="${ax}x${ay}" \
    -composite \
    +repage \
    "png32:$out"
}
