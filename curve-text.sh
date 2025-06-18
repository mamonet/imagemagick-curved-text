#!/usr/bin/env bash
# repo path: curve-text.sh
# Render curved text onto product mockups from a JSON item list.
#   ./curve-text.sh items.json out/ [--only N] [--mode M] [--verbose] [--keep-intermediates]
#
# Changes over v1: option parsing, single-item runs for iterating on one
# placement, a mode override for comparing techniques on the same item,
# and a real temp dir removed by a trap instead of a .tmp left in out/.
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
ONLY=""
MODE_OVERRIDE=""
KEEP_INTERMEDIATES=0
TMPDIR_RUN=""

usage() {
  cat <<'EOF'
usage: curve-text.sh <items.json> <outdir> [options]

  --only N               render just item N (0-based, matching the JSON array
                         and the manifest index)
  --mode MODE            override every item's mode: arc | perspective |
                         displace | cylinderize
  --verbose              echo each ImageMagick command as it runs
  --keep-intermediates   keep the flat label and bent label next to the output
                         instead of deleting the temp dir
  -h, --help             this text

Outputs <outdir>/<index>_<slug>.png plus <outdir>/manifest.tsv, which records
the parameters behind every file.
EOF
}

cleanup() {
  [ -n "$TMPDIR_RUN" ] || return 0
  [ "$KEEP_INTERMEDIATES" = "1" ] && { info "intermediates kept in $TMPDIR_RUN"; return 0; }
  rm -rf -- "$TMPDIR_RUN"
}

parse_args() {
  ITEMS_FILE=""
  OUTDIR=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --only)   [ "$#" -ge 2 ] || die "--only needs a number"; ONLY="$2"; shift 2 ;;
      --only=*) ONLY="${1#*=}"; shift ;;
      --mode)   [ "$#" -ge 2 ] || die "--mode needs a value"; MODE_OVERRIDE="$2"; shift 2 ;;
      --mode=*) MODE_OVERRIDE="${1#*=}"; shift ;;
      --verbose|-v)         VERBOSE=1; shift ;;
      --keep-intermediates) KEEP_INTERMEDIATES=1; shift ;;
      -h|--help)            usage; exit 0 ;;
      --) shift; break ;;
      -*) usage >&2; die "unknown option: $1" ;;
      *)
        if   [ -z "$ITEMS_FILE" ]; then ITEMS_FILE="$1"
        elif [ -z "$OUTDIR" ];     then OUTDIR="$1"
        else die "unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  [ -n "$ITEMS_FILE" ] && [ -n "$OUTDIR" ] || { usage >&2; exit 2; }
  [ -z "$ONLY" ] || validate_number "$ONLY" "--only"
  [ -z "$MODE_OVERRIDE" ] || validate_mode "$MODE_OVERRIDE" "--mode"
  export VERBOSE
}

render_item() {
  local obj="$1" index="$2" outdir="$3" tmpdir="$4"
  local mode text font pointsize fill lw interline pad mockup cx cy
  local blend opacity floor slug out label bent params

  mode="$(json_req "$obj" '.mode' "$index")"
  [ -z "$MODE_OVERRIDE" ] || mode="$MODE_OVERRIDE"
  validate_item "$obj" "$index" "$mode"

  text="$(json_req "$obj" '.text' "$index")"
  font="$(json_req "$obj" '.font' "$index")"
  mockup="$(json_req "$obj" '.mockup' "$index")"
  cx="$(json_req "$obj" '.center_x' "$index")"
  cy="$(json_req "$obj" '.center_y' "$index")"
  pointsize="$(json_opt "$obj" '.pointsize' '96')"
  fill="$(json_opt "$obj" '.fill' '#222222')"
  lw="$(json_opt "$obj" '.label_width' '1200')"
  interline="$(json_opt "$obj" '.interline' '0')"
  pad="$(json_opt "$obj" '.pad' '24')"
  opacity="$(json_opt "$obj" '.opacity' '0.92')"
  floor="$(json_opt "$obj" '.level_floor' '18')"
  blend="$(json_opt "$obj" '.blend' "$(composite_pick_blend "$fill")")"

  slug="$(slugify "$text")"
  out="${outdir%/}/$(printf '%02d' "$index")_${slug}.png"
  label="${tmpdir%/}/${index}-label.png"
  bent="${tmpdir%/}/${index}-bent.png"

  # STEP 1: typography, flat and transparent, at a fixed pointsize.
  label_render "$text" "$font" "$pointsize" "$fill" "$lw" "$label" "$interline" "$pad"
  label_assert_width "$label" "$(( lw + 2 * pad ))" "$index"

  # STEP 2: bend it.
  params="$(log_params "fill=$fill" "label_width=$lw" "blend=$blend" "opacity=$opacity")"
  case "$mode" in
    arc)
      local degrees rotate
      degrees="$(json_req "$obj" '.arc_degrees' "$index")"
      rotate="$(json_opt "$obj" '.arc_rotate' '')"
      arc_apply "$label" "$bent" "$degrees" "$rotate"
      params="$params $(log_params "arc_degrees=$degrees" "arc_rotate=${rotate:-0}")"
      ;;
    perspective)
      perspective_apply "$label" "$bent" \
        "$(json_req "$obj" '.corners.tl[0]' "$index")" "$(json_req "$obj" '.corners.tl[1]' "$index")" \
        "$(json_req "$obj" '.corners.tr[0]' "$index")" "$(json_req "$obj" '.corners.tr[1]' "$index")" \
        "$(json_req "$obj" '.corners.br[0]' "$index")" "$(json_req "$obj" '.corners.br[1]' "$index")" \
        "$(json_req "$obj" '.corners.bl[0]' "$index")" "$(json_req "$obj" '.corners.bl[1]' "$index")"
      params="$params $(log_params 'placement=absolute-corners')"
      ;;
    displace)
      local map dx dy
      map="$(json_req "$obj" '.displace_map' "$index")"
      dx="$(json_opt "$obj" '.displace_x' '10')"
      dy="$(json_opt "$obj" '.displace_y' '4')"
      displace_apply "$label" "$map" "$bent" "$dx" "$dy" "$tmpdir"
      params="$params $(log_params "displace_map=$map" "displace=${dx}x${dy}")"
      ;;
    cylinderize)
      local radius length wrap pitch roll yaw ox oy
      radius="$(json_req "$obj" '.cyl_radius' "$index")"
      length="$(json_req "$obj" '.cyl_length' "$index")"
      wrap="$(json_req "$obj" '.cyl_wrap' "$index")"
      pitch="$(json_opt "$obj" '.cyl_pitch' '0')"
      roll="$(json_opt "$obj" '.cyl_roll' '0')"
      yaw="$(json_opt "$obj" '.cyl_yaw' '0')"
      ox="$(json_opt "$obj" '.cyl_offset_x' '0')"
      oy="$(json_opt "$obj" '.cyl_offset_y' '0')"
      cylinderize_apply "$label" "$bent" \
        "$radius" "$length" "$wrap" "$pitch" "$roll" "$yaw" "$ox" "$oy"
      params="$params $(log_params "radius=$radius" "length=$length" "wrap=$wrap" \
        "pitch=$pitch" "roll=$roll" "yaw=$yaw")"
      ;;
  esac

  # STEP 3: back onto the product, under its lighting.
  if [ "$mode" = "perspective" ]; then
    composite_place_absolute "$mockup" "$bent" "$out" "$blend" "$opacity" "$floor"
  else
    composite_place "$mockup" "$bent" "$cx" "$cy" "$out" "$blend" "$opacity" "$floor"
    params="$params $(log_params "center=${cx},${cy}")"
  fi

  log_item "$index" "$mode" "$out" "$mockup" "$font" "$pointsize" "$params"
}

main() {
  local count i obj rendered=0

  parse_args "$@"

  im_init
  im_require_format PNG
  json_require_jq
  json_load "$ITEMS_FILE"
  validate_outdir "$OUTDIR"
  log_manifest_init "$OUTDIR" "$ITEMS_FILE"

  if [ "$KEEP_INTERMEDIATES" = "1" ]; then
    TMPDIR_RUN="${OUTDIR%/}/intermediates"
    mkdir -p -- "$TMPDIR_RUN"
  else
    TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/curve-text.XXXXXX")"
  fi
  trap cleanup EXIT INT TERM

  count="$(json_count "$ITEMS_FILE")"
  if [ -n "$ONLY" ]; then
    [ "$ONLY" -ge 0 ] && [ "$ONLY" -lt "$count" ] \
      || die "--only $ONLY out of range (0..$(( count - 1 )))"
  fi
  info "$IM $IM_VERSION, $count item(s) in $ITEMS_FILE"

  for (( i = 0; i < count; i++ )); do
    if [ -n "$ONLY" ] && [ "$i" != "$ONLY" ]; then continue; fi
    obj="$(json_item "$ITEMS_FILE" "$i")"
    render_item "$obj" "$i" "$OUTDIR" "$TMPDIR_RUN"
    rendered=$(( rendered + 1 ))
  done

  info "done: $rendered image(s) in $OUTDIR (manifest: ${OUTDIR%/}/manifest.tsv)"
}

main "$@"
