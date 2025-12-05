#!/usr/bin/env bats
# repo path: tests/cli.bats
# End-to-end runs of curve-text.sh against the fake ImageMagick. Nothing here
# decodes an image; the assertions are on which files were produced, what the
# manifest recorded, and what the CLI said.

load test_helper

CURVE="" # set in setup

setup() {
  common_setup
  require_jq
  CURVE="$REPO_ROOT/curve-text.sh"

  fixture_file "$TEST_TMP/mockups/mug.png"
  fixture_file "$TEST_TMP/mockups/bottle.png"
  fixture_file "$TEST_TMP/mockups/bottle-shading.png"
  fixture_file "$TEST_TMP/fonts/DejaVuSans-Bold.ttf"

  ITEMS="$(write_items \
    '{"mode":"arc","text":"Fresh Roast Daily","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","label_width":1100,"pointsize":96,"arc_degrees":42,"center_x":640,"center_y":520}' \
    '{"mode":"displace","text":"Cold Pressed","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/bottle.png","label_width":900,"displace_map":"mockups/bottle-shading.png","displace_x":14,"displace_y":4,"arc_degrees":30,"center_x":512,"center_y":760}' \
    '{"mode":"arc","text":"Loose Leaf No. 3","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","label_width":1400,"arc_degrees":90,"center_x":600,"center_y":640}')"
}

teardown() { common_teardown; }

out_png_count() { find out -maxdepth 1 -name '*.png' 2>/dev/null | wc -l | tr -d ' '; }
manifest_rows() { grep -c '^[0-9]' out/manifest.tsv; }

# --- the happy path ---------------------------------------------------------

@test "a run renders one image per item" {
  run "$CURVE" "$ITEMS" out
  assert_success
  assert_equal "$(out_png_count)" "3"
}

@test "output files are named <index>_<slug>.png" {
  run "$CURVE" "$ITEMS" out
  assert_success
  [ -f out/00_fresh-roast-daily.png ]
  [ -f out/01_cold-pressed.png ]
  [ -f out/02_loose-leaf-no-3.png ]
}

@test "the run writes a manifest with one row per rendered item" {
  run "$CURVE" "$ITEMS" out
  assert_success
  [ -f out/manifest.tsv ]
  assert_equal "$(manifest_rows)" "3"
}

@test "the manifest records the parameters behind each file" {
  # A result has to trace back to its inputs without guessing.
  run "$CURVE" "$ITEMS" out
  assert_success
  grep -q 'arc_degrees=42' out/manifest.tsv
  grep -q 'displace=14x4' out/manifest.tsv
  grep -q 'DejaVuSans-Bold.ttf' out/manifest.tsv
  grep -q '^# imagemagick' out/manifest.tsv
}

@test "the output directory is created if it does not exist" {
  run "$CURVE" "$ITEMS" out/nested/deeper
  assert_success
  [ -d out/nested/deeper ]
}

@test "a trailing slash on the output directory does not double up" {
  run "$CURVE" "$ITEMS" out/
  assert_success
  [ -f out/00_fresh-roast-daily.png ]
  [ -f out/manifest.tsv ]
}

# --- --only -----------------------------------------------------------------

@test "--only renders exactly one item" {
  run "$CURVE" "$ITEMS" out --only 1
  assert_success
  assert_equal "$(out_png_count)" "1"
  [ -f out/01_cold-pressed.png ]
}

@test "--only 0 renders the first item, not all of them" {
  # "0" is falsy-looking and an easy off-by-one in the arg handling.
  run "$CURVE" "$ITEMS" out --only 0
  assert_success
  assert_equal "$(out_png_count)" "1"
  [ -f out/00_fresh-roast-daily.png ]
}

@test "--only keeps the array index in the filename and the manifest" {
  run "$CURVE" "$ITEMS" out --only 2
  assert_success
  [ -f out/02_loose-leaf-no-3.png ]
  assert_equal "$(manifest_rows)" "1"
  grep -q '^2[[:space:]]' out/manifest.tsv
}

@test "--only=N is accepted as well as --only N" {
  run "$CURVE" "$ITEMS" out --only=1
  assert_success
  assert_equal "$(out_png_count)" "1"
}

@test "--only out of range fails and says the valid range" {
  run "$CURVE" "$ITEMS" out --only 9
  assert_failure
  assert_output_contains "out of range"
  assert_output_contains "0..2"
}

@test "--only with a non-numeric value is rejected" {
  run "$CURVE" "$ITEMS" out --only last
  assert_failure
  assert_output_contains "numeric"
}

@test "--only with no value is rejected" {
  run "$CURVE" "$ITEMS" out --only
  assert_failure
  assert_output_contains "--only needs a number"
}

# --- --verbose --------------------------------------------------------------

@test "--verbose echoes the ImageMagick commands" {
  run "$CURVE" "$ITEMS" out --only 0 --verbose
  assert_success
  assert_output_contains "-distort Arc 42"
}

@test "--verbose output is pasteable, with each command on its own line" {
  run "$CURVE" "$ITEMS" out --only 0 --verbose
  assert_success
  assert_output_contains "+ "
  # The label render and the arc are separate commands, not one blob.
  [ "$(printf '%s\n' "$output" | grep -c '^+ ')" -ge 3 ]
}

@test "without --verbose the commands are not echoed" {
  run "$CURVE" "$ITEMS" out --only 0
  assert_success
  assert_output_not_contains "-distort"
}

@test "the per-item parameter line is printed with or without --verbose" {
  run "$CURVE" "$ITEMS" out --only 0
  assert_success
  assert_output_contains "[0] mode=arc"
  assert_output_contains "arc_degrees=42"
}

# --- --mode -----------------------------------------------------------------

@test "--mode overrides every item's mode" {
  # Item 1 is a displace item that also carries arc_degrees, so the override
  # has the fields it needs.
  run "$CURVE" "$ITEMS" out --mode arc --only 1
  assert_success
  grep -q '^1[[:space:]]arc[[:space:]]' out/manifest.tsv
  assert_output_contains "[1] mode=arc"
}

@test "--mode with an unknown value is rejected before anything renders" {
  run "$CURVE" "$ITEMS" out --mode wobble
  assert_failure
  assert_output_contains "unknown mode 'wobble'"
  [ ! -d out ] || assert_equal "$(out_png_count)" "0"
}

@test "--mode override still has to satisfy that mode's required fields" {
  # Item 0 is an arc item with no displace_map.
  run "$CURVE" "$ITEMS" out --mode displace --only 0
  assert_failure
  assert_output_contains ".displace_map"
}

# --- --keep-intermediates ---------------------------------------------------

@test "--keep-intermediates leaves the flat label and the bent label behind" {
  run "$CURVE" "$ITEMS" out --only 0 --keep-intermediates
  assert_success
  [ -f out/intermediates/0-label.png ]
  [ -f out/intermediates/0-bent.png ]
}

@test "without --keep-intermediates nothing is left next to the output" {
  run "$CURVE" "$ITEMS" out --only 0
  assert_success
  [ ! -d out/intermediates ]
  assert_equal "$(out_png_count)" "1"
}

# --- usage and bad invocations ----------------------------------------------

@test "no arguments prints usage and exits non-zero" {
  run "$CURVE"
  assert_failure
  assert_equal "$status" "2"
  assert_output_contains "usage: curve-text.sh"
}

@test "a missing output directory argument prints usage and exits non-zero" {
  run "$CURVE" "$ITEMS"
  assert_failure
  assert_equal "$status" "2"
  assert_output_contains "usage:"
}

@test "--help prints usage and exits zero" {
  run "$CURVE" --help
  assert_success
  assert_output_contains "usage:"
  assert_output_contains "--keep-intermediates"
}

@test "an unknown option prints usage and fails" {
  run "$CURVE" "$ITEMS" out --wobble
  assert_failure
  assert_output_contains "unknown option: --wobble"
}

@test "a third positional argument is rejected" {
  run "$CURVE" "$ITEMS" out extra
  assert_failure
  assert_output_contains "unexpected argument"
}

@test "a missing items file fails before creating anything" {
  run "$CURVE" nope.json out
  assert_failure
  assert_output_contains "items file not found"
}

@test "an empty items array fails with a clear message" {
  printf '[]' >empty.json
  run "$CURVE" empty.json out
  assert_failure
  assert_output_contains "empty array"
}

# --- external dependency ----------------------------------------------------

@test "a cylinderize item fails with install instructions when the script is absent" {
  local items
  items="$(write_items '{"mode":"cylinderize","text":"Loose Leaf","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","cyl_radius":190,"cyl_length":430,"cyl_wrap":150,"center_x":600,"center_y":640}')"
  run "$CURVE" "$items" out
  assert_failure
  assert_output_contains "cylinderize.sh"
  assert_output_contains "fmwconcepts.com"
}

@test "the other modes work with cylinderize.sh absent" {
  run "$CURVE" "$ITEMS" out
  assert_success
  assert_equal "$(out_png_count)" "3"
}

# --- text safety ------------------------------------------------------------

@test "text containing shell metacharacters is not evaluated" {
  local items
  items="$(write_items '{"mode":"arc","text":"$(touch pwned) `id`","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","arc_degrees":42,"center_x":10,"center_y":10}')"
  run "$CURVE" "$items" out
  assert_success
  [ ! -e pwned ]
}

@test "text with spaces and punctuation produces a safe filename" {
  local items
  items="$(write_items '{"mode":"arc","text":"Ready / Set: Go!","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","arc_degrees":42,"center_x":10,"center_y":10}')"
  run "$CURVE" "$items" out
  assert_success
  [ -f out/00_ready-set-go.png ]
}
