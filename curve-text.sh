#!/usr/bin/env bash
# repo path: curve-text.sh
# Render curved text onto product mockups from a JSON item list.
#   ./curve-text.sh items.json out/
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/im.sh
. "$SCRIPT_DIR/lib/im.sh"
# shellcheck source=lib/json.sh
. "$SCRIPT_DIR/lib/json.sh"
# shellcheck source=lib/validate.sh
. "$SCRIPT_DIR/lib/validate.sh"
# shellcheck source=lib/label.sh
. "$SCRIPT_DIR/lib/label.sh"
# shellcheck source=lib/arc.sh
. "$SCRIPT_DIR/lib/arc.sh"
# shellcheck source=lib/perspective.sh
. "$SCRIPT_DIR/lib/perspective.sh"
# shellcheck source=lib/displace.sh
. "$SCRIPT_DIR/lib/displace.sh"
# shellcheck source=lib/cylinderize.sh
. "$SCRIPT_DIR/lib/cylinderize.sh"
# shellcheck source=lib/composite.sh
. "$SCRIPT_DIR/lib/composite.sh"

VERBOSE=0

render_item() {
  local obj="$1" index="$2" outdir="$3" tmpdir="$4"
  local mode text font pointsize fill lw lh mockup cx cy
  local slug out label bent

  mode="$(json_req "$obj" '.mode' "$index")"
  validate_item "$obj" "$index" "$mode"

  text="$(json_req "$obj" '.text' "$index")"
  font="$(json_req "$obj" '.font' "$index")"
  mockup="$(json_req "$obj" '.mockup' "$index")"
  cx="$(json_req "$obj" '.center_x' "$index")"
  cy="$(json_req "$obj" '.center_y' "$index")"
  pointsize="$(json_opt "$obj" '.pointsize' '96')"
  fill="$(json_opt "$obj" '.fill' '#222222')"
  lw="$(json_opt "$obj" '.label_width' '1200')"
  lh="$(json_opt "$obj" '.label_height' '400')"

  slug="$(slugify "$text")"
  out="${outdir%/}/$(printf '%02d' "$index")_${slug}.png"
  label="${tmpdir%/}/${index}-label.png"
  bent="${tmpdir%/}/${index}-bent.png"

  # STEP 1: typography, flat and transparent.
  label_render "$text" "$font" "$pointsize" "$fill" "$lw" "$lh" "$label"

  # STEP 2: bend it, per mode.
  case "$mode" in
    arc)
      arc_apply "$label" "$bent" "$(json_req "$obj" '.arc_degrees' "$index")"
      ;;
    perspective)
      perspective_apply "$label" "$bent" \
        "$(json_req "$obj" '.corners.tl[0]' "$index")" "$(json_req "$obj" '.corners.tl[1]' "$index")" \
        "$(json_req "$obj" '.corners.tr[0]' "$index")" "$(json_req "$obj" '.corners.tr[1]' "$index")" \
        "$(json_req "$obj" '.corners.br[0]' "$index")" "$(json_req "$obj" '.corners.br[1]' "$index")" \
        "$(json_req "$obj" '.corners.bl[0]' "$index")" "$(json_req "$obj" '.corners.bl[1]' "$index")"
      ;;
    displace)
      displace_apply "$label" "$(json_req "$obj" '.displace_map' "$index")" "$bent" \
        "$(json_opt "$obj" '.displace_x' '10')" "$(json_opt "$obj" '.displace_y' '4')"
      ;;
    cylinderize)
      cylinderize_apply "$label" "$bent" \
        "$(json_req "$obj" '.cyl_radius' "$index")" \
        "$(json_req "$obj" '.cyl_length' "$index")" \
        "$(json_req "$obj" '.cyl_wrap' "$index")" \
        "$(json_opt "$obj" '.cyl_pitch' '0')" \
        "$(json_opt "$obj" '.cyl_roll' '0')" \
        "$(json_opt "$obj" '.cyl_yaw' '0')"
      ;;
  esac

  # STEP 3: back onto the product.
  composite_place "$mockup" "$bent" "$cx" "$cy" "$out"

  log_item "$index" "$mode" "$out" "$mockup" "$font" "$pointsize" \
    "$(log_params "fill=$fill" "label_width=$lw" "center=${cx},${cy}")"
}

main() {
  local items_file="${1:-}" outdir="${2:-}" tmpdir count i obj

  [ -n "$items_file" ] && [ -n "$outdir" ] \
    || die "usage: curve-text.sh <items.json> <outdir>"

  im_init
  json_require_jq
  json_load "$items_file"
  validate_outdir "$outdir"
  log_manifest_init "$outdir" "$items_file"

  tmpdir="${outdir%/}/.tmp"
  mkdir -p -- "$tmpdir"

  count="$(json_count "$items_file")"
  info "rendering $count item(s) with $IM $IM_VERSION"

  for (( i = 0; i < count; i++ )); do
    obj="$(json_item "$items_file" "$i")"
    render_item "$obj" "$i" "$outdir" "$tmpdir"
  done

  info "done: $count item(s) in $outdir"
}

main "$@"
