#!/usr/bin/env bats
# repo path: tests/validate.bats
# lib/validate.sh: per-mode required fields, and the pre-flight file checks
# that must reject a bad item BEFORE any render happens.

load test_helper

setup() {
  common_setup
  require_jq
  load_libs_with_stub json validate
  fixture_file "$TEST_TMP/mockups/mug.png"
  fixture_file "$TEST_TMP/mockups/mug-shading.png"
  fixture_file "$TEST_TMP/fonts/DejaVuSans-Bold.ttf"
  BASE='"text":"Fresh Roast Daily","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","center_x":640,"center_y":520'
}

teardown() { common_teardown; }

# --- mode ------------------------------------------------------------------

@test "validate_mode accepts the four known modes" {
  local m
  for m in arc perspective displace cylinderize; do
    validate_mode "$m" 0
  done
}

@test "validate_mode rejects an unknown mode and lists the valid ones" {
  run validate_mode "zigzag" 0
  assert_failure
  assert_output_contains "unknown mode 'zigzag'"
  assert_output_contains "arc perspective displace cylinderize"
}

@test "validate_mode rejects an empty mode" {
  run validate_mode "" 0
  assert_failure
}

@test "validate_mode is case sensitive" {
  run validate_mode "Arc" 0
  assert_failure
}

# --- common fields ----------------------------------------------------------

@test "a complete arc item validates" {
  run validate_item "{$BASE,\"arc_degrees\":42}" 0 arc
  assert_success
}

@test "missing text is rejected" {
  run validate_item '{"font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","center_x":1,"center_y":1,"arc_degrees":42}' 0 arc
  assert_failure
  assert_output_contains ".text"
}

@test "missing center_x is rejected" {
  run validate_item '{"text":"x","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/mug.png","center_y":1,"arc_degrees":42}' 0 arc
  assert_failure
  assert_output_contains ".center_x"
}

@test "a non-numeric pointsize is rejected" {
  run validate_item "{$BASE,\"pointsize\":\"large\",\"arc_degrees\":42}" 0 arc
  assert_failure
  assert_output_contains "pointsize must be numeric"
}

@test "an absent pointsize falls back to the default and passes" {
  run validate_item "{$BASE,\"arc_degrees\":42}" 0 arc
  assert_success
}

# --- mockup and font, before any render -------------------------------------

@test "a missing mockup file is rejected" {
  run validate_item '{"text":"x","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/absent.png","center_x":1,"center_y":1,"arc_degrees":42}' 4 arc
  assert_failure
  assert_output_contains "mockup not found"
  assert_output_contains "mockups/absent.png"
}

@test "a missing font file is rejected" {
  run validate_item '{"text":"x","font":"fonts/Absent.ttf","mockup":"mockups/mug.png","center_x":1,"center_y":1,"arc_degrees":42}' 0 arc
  assert_failure
  assert_output_contains "font file not found"
}

@test "a missing mockup is rejected before ImageMagick is invoked" {
  # The whole point of the pre-flight: a 30-item run must not die halfway
  # through having already written 12 files.
  run validate_item '{"text":"x","font":"fonts/DejaVuSans-Bold.ttf","mockup":"mockups/absent.png","center_x":1,"center_y":1,"arc_degrees":42}' 0 arc
  assert_failure
  assert_equal "$(im_call_count)" "0"
}

@test "a font family name is accepted when ImageMagick knows it" {
  STUB_IM_FONTS="DejaVu-Sans Inter-SemiBold"
  export STUB_IM_FONTS
  run validate_item '{"text":"x","font":"Inter-SemiBold","mockup":"mockups/mug.png","center_x":1,"center_y":1,"arc_degrees":42}' 0 arc
  assert_success
}

@test "a font family name ImageMagick does not know is rejected" {
  # The silent-fallback bug: without this check the item renders in the
  # default face and only looks wrong next to its neighbours.
  STUB_IM_FONTS="DejaVu-Sans"
  export STUB_IM_FONTS
  run validate_item '{"text":"x","font":"No-Such-Face","mockup":"mockups/mug.png","center_x":1,"center_y":1,"arc_degrees":42}' 0 arc
  assert_failure
  assert_output_contains "No-Such-Face"
}

@test "an empty path is rejected rather than passed to ImageMagick" {
  run validate_file "" "mockup" 0
  assert_failure
  assert_output_contains "empty mockup path"
}

# --- per-mode required fields -----------------------------------------------

@test "arc requires arc_degrees" {
  run validate_item "{$BASE}" 0 arc
  assert_failure
  assert_output_contains ".arc_degrees"
}

@test "arc rejects a non-numeric arc_degrees" {
  run validate_item "{$BASE,\"arc_degrees\":\"a lot\"}" 0 arc
  assert_failure
  assert_output_contains "arc_degrees must be numeric"
}

@test "perspective requires all four corners" {
  run validate_item "{$BASE,\"corners\":{\"tl\":[0,0],\"tr\":[10,0],\"br\":[10,10]}}" 0 perspective
  assert_failure
  assert_output_contains "corners.bl"
}

@test "perspective requires both coordinates of a corner" {
  run validate_item "{$BASE,\"corners\":{\"tl\":[0],\"tr\":[10,0],\"br\":[10,10],\"bl\":[0,10]}}" 0 perspective
  assert_failure
  assert_output_contains "corners.tl"
}

@test "a complete perspective item validates" {
  run validate_item "{$BASE,\"corners\":{\"tl\":[0,0],\"tr\":[10,0],\"br\":[10,10],\"bl\":[0,10]}}" 0 perspective
  assert_success
}

@test "displace requires displace_map" {
  run validate_item "{$BASE}" 0 displace
  assert_failure
  assert_output_contains ".displace_map"
}

@test "displace rejects a displace_map that does not exist" {
  run validate_item "{$BASE,\"displace_map\":\"mockups/absent-shading.png\"}" 0 displace
  assert_failure
  assert_output_contains "displacement map not found"
}

@test "displace accepts an existing map and defaults its amounts" {
  run validate_item "{$BASE,\"displace_map\":\"mockups/mug-shading.png\"}" 0 displace
  assert_success
}

@test "displace rejects a non-numeric displace_x" {
  run validate_item "{$BASE,\"displace_map\":\"mockups/mug-shading.png\",\"displace_x\":\"lots\"}" 0 displace
  assert_failure
  assert_output_contains "displace_x must be numeric"
}

@test "cylinderize requires radius, length and wrap" {
  run validate_item "{$BASE,\"cyl_radius\":190,\"cyl_length\":430}" 0 cylinderize
  assert_failure
  assert_output_contains "cyl_wrap"
}

@test "a complete cylinderize item validates without needing the external script" {
  # Field validation and tool availability are separate failures. Getting the
  # JSON right must not depend on having Fred Weinhaus' script installed.
  run validate_item "{$BASE,\"cyl_radius\":190,\"cyl_length\":430,\"cyl_wrap\":150}" 0 cylinderize
  assert_success
}

@test "the mode's own fields are only required for that mode" {
  # An arc item carrying no displace_map is fine; the previous run's leftover
  # fields must not become requirements.
  run validate_item "{$BASE,\"arc_degrees\":42}" 0 arc
  assert_success
}

# --- output dir -------------------------------------------------------------

@test "validate_outdir creates a missing directory" {
  run validate_outdir "$TEST_TMP/out/nested"
  assert_success
  [ -d "$TEST_TMP/out/nested" ]
}

@test "validate_outdir fails when the path is an existing file" {
  fixture_file "$TEST_TMP/notadir"
  run validate_outdir "$TEST_TMP/notadir"
  assert_failure
}

# --- numbers ----------------------------------------------------------------

@test "validate_number accepts integers, decimals and negatives" {
  validate_number "42" "n" 0
  validate_number "0.92" "n" 0
  validate_number "-6" "n" 0
}

@test "validate_number rejects text and empty values" {
  run validate_number "" "arc_degrees" 0
  assert_failure
  run validate_number "12deg" "arc_degrees" 0
  assert_failure
}
