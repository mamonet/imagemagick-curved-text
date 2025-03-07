#!/usr/bin/env bash
# repo path: lib/json.sh
# jq accessors. Values are returned on stdout and captured into arrays by the
# caller; nothing read here is ever eval'd or spliced into a command line.
# shellcheck shell=bash
set -euo pipefail

if [ -n "${_LIB_JSON:-}" ]; then return 0; fi
_LIB_JSON=1

json_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || die "jq not found: install jq (https://jqlang.github.io/jq/) and retry"
}

# Whole-file checks up front so a typo fails once, not per item.
json_load() {
  local file="$1"
  [ -f "$file" ] || die "items file not found: $file"
  jq -e 'type == "array"' "$file" >/dev/null 2>&1 \
    || die "items file must be a JSON array of objects: $file"
  jq -e 'length > 0' "$file" >/dev/null 2>&1 \
    || die "items file is an empty array: $file"
}

json_count() { jq 'length' "$1"; }

# Compact single item, passed around as a string and re-queried per field.
json_item() {
  local file="$1" index="$2"
  jq -ce --argjson i "$index" '.[$i]' "$file" \
    || die "no item at index $index in $file"
}

# Required field. Absent, null or empty string is fatal.
# Note: jq's `//` also swallows `false`; no boolean field is required here.
json_req() {
  local obj="$1" path="$2" index="${3:-?}" val
  val="$(printf '%s' "$obj" | jq -r "$path // empty")" \
    || die "[$index] malformed item JSON while reading $path"
  [ -n "$val" ] || die "[$index] missing required field: $path"
  printf '%s' "$val"
}

# Optional field with a default. A missing optional is not an error.
json_opt() {
  local obj="$1" path="$2" default="$3" val
  val="$(printf '%s' "$obj" | jq -r "$path // empty")" || val=""
  if [ -z "$val" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

json_has() {
  local obj="$1" path="$2"
  printf '%s' "$obj" | jq -e "$path != null" >/dev/null 2>&1
}

# Filename-safe slug from the item text. Lowercase, runs of non-alphanumerics
# collapse to a single dash, trimmed, capped so paths stay sane.
slugify() {
  local raw="$1" slug
  slug="$(printf '%s' "$raw" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  [ -n "$slug" ] || slug="item"
  printf '%s' "${slug:0:48}"
}
