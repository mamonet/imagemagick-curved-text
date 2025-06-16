#!/usr/bin/env bash
# repo path: lib/cylinderize.sh
# Optional handoff to Fred Weinhaus' cylinderize.sh for a full 3D wrap.
#
# Arc bends a label in 2D; this maps it onto an actual cylinder with radius,
# wrap angle and camera attitude, which is what a tin or a can needs when the
# label runs far enough round to foreshorten at both edges.
#
# Fred's script is NOT bundled and must not be. It ships under his own licence
# (free for non-commercial use, permission required otherwise) from
# https://www.fmwconcepts.com/imagemagick/ . We detect it on PATH and hand our
# already-typeset label to it; the user installs it themselves.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_CYLINDERIZE:-}" ]; then return 0; fi
_LIB_CYLINDERIZE=1

CYLINDERIZE_BIN="${CYLINDERIZE_BIN:-cylinderize.sh}"

cylinderize_available() { command -v "$CYLINDERIZE_BIN" >/dev/null 2>&1; }

cylinderize_require() {
  cylinderize_available && return 0
  die "mode 'cylinderize' needs Fred Weinhaus' cylinderize.sh on PATH.
  Download it from https://www.fmwconcepts.com/imagemagick/ (read his licence),
  chmod +x it, and put it on PATH or set CYLINDERIZE_BIN=/path/to/cylinderize.sh.
  It is deliberately not vendored in this repo."
}

# cylinderize_apply <label> <out> <radius> <length> <wrap> <pitch> <roll> <yaw> <offset_x> <offset_y>
#
# Flag names differ between releases of his script; these match the 3.x usage.
# If yours errors on an option, run `cylinderize.sh -h` and adjust here rather
# than reshaping the JSON.
#   -m cylinder   map onto a cylinder (vs 'cap' for the lid disc)
#   -r radius     cylinder radius in px, at the mockup's scale
#   -l length     cylinder length in px
#   -w wrap       degrees of circumference the label covers
#   -p/-R/-y      pitch / roll / yaw of the camera, degrees
#   -o x,y        translate the rendered cylinder within its canvas
#   -b none       transparent background: the wrap must composite cleanly
cylinderize_apply() {
  local label="$1" out="$2" radius="$3" length="$4" wrap="$5"
  local pitch="${6:-0}" roll="${7:-0}" yaw="${8:-0}" ox="${9:-0}" oy="${10:-0}"
  local args=()

  cylinderize_require

  args=(
    -m cylinder
    -r "$radius"
    -l "$length"
    -w "$wrap"
    -p "$pitch"
    -R "$roll"
    -y "$yaw"
    -o "${ox},${oy}"
    -b none
  )

  # Array expansion: radius/length/etc are separate argv entries, never a
  # string handed to a shell.
  im_run "$CYLINDERIZE_BIN" "${args[@]}" "$label" "png32:$out"
}
