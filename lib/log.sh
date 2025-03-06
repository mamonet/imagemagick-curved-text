#!/usr/bin/env bash
# repo path: lib/log.sh
# Messages + the per-run manifest that ties every output file to its inputs.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_LOG:-}" ]; then return 0; fi
_LIB_LOG=1

LOG_PREFIX="${LOG_PREFIX:-curve-text}"
MANIFEST=""      # set by log_manifest_init

info() { printf '%s: %s\n' "$LOG_PREFIX" "$*" >&2; }
warn() { printf '%s: warning: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s: error: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

# Only printed under --verbose; used for intermediate step chatter.
debug() {
  [ "${VERBOSE:-0}" = "1" ] || return 0
  printf '%s: %s\n' "$LOG_PREFIX" "$*" >&2
}

log_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# One TSV manifest per run. Header carries the run-wide facts (which JSON, which
# ImageMagick), rows carry the per-item facts. Reproducing an image later means
# reading one line, not guessing.
log_manifest_init() {
  local outdir="$1" items_file="$2"
  MANIFEST="${outdir%/}/manifest.tsv"
  {
    printf '# run\t%s\n' "$(log_now)"
    printf '# items\t%s\n' "$items_file"
    printf '# imagemagick\t%s %s\n' "${IM:-unknown}" "${IM_VERSION:-unknown}"
    printf '# host\t%s\n' "$(uname -srm 2>/dev/null || printf 'unknown')"
    printf 'index\tmode\toutput\tmockup\tfont\tpointsize\tparams\n'
  } >"$MANIFEST"
  debug "manifest: $MANIFEST"
}

# Per-item parameter line: echoed to the terminal and appended to the manifest.
# params is a pre-joined "k=v k=v" string of the mode-specific knobs.
log_item() {
  local index="$1" mode="$2" output="$3" mockup="$4" font="$5" pointsize="$6" params="$7"
  info "[$index] mode=$mode font=$(basename -- "$font") pointsize=$pointsize $params -> $output"
  [ -n "$MANIFEST" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$index" "$mode" "$output" "$mockup" "$font" "$pointsize" "$params" >>"$MANIFEST"
}

# Join "k=v" pairs into the params column without tabs or newlines leaking in.
log_params() {
  local joined="" pair
  for pair in "$@"; do
    joined+="${joined:+ }${pair//[$'\t\n']/ }"
  done
  printf '%s' "$joined"
}
