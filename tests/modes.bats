#!/usr/bin/env bats
# repo path: tests/modes.bats
# The mode libraries build the right ImageMagick command line.
#
# These assert on argv, not on pixels. That is deliberate: the bugs that matter
# here (a missing -virtual-pixel, a displacement amount on the wrong axis, a
# flag and its value fused into one word) all produce a plausible image, so a
# visual check would pass and the command line would still be wrong.

load test_helper

setup() {
  common_setup
  load_libs_with_stub label arc perspective displace cylinderize validate
  fixture_file "$TEST_TMP/label.png"
  fixture_file "$TEST_TMP/map.png"
}

teardown() { common_teardown; }

# --- arc --------------------------------------------------------------------

@test "arc builds -distort Arc with the item's degrees" {
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42
  assert_im_called_with "-distort Arc 42"
  assert_im_argv_adjacent "-distort" "Arc"
  assert_im_argv_adjacent "Arc" "42"
}

@test "arc passes the degrees as one argument, not fused to the operator" {
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 120
  assert_im_not_called_with "Arc120"
}

@test "arc sets a transparent background and virtual-pixel none" {
  # Without both, Arc fills the expanded canvas with smeared edge pixels and
  # the composite lands a solid plate on the product.
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42
  assert_im_called_with "-background none"
  assert_im_called_with "-virtual-pixel none"
  assert_im_argv_adjacent "-virtual-pixel" "none"
}

@test "arc puts the background settings before the distort" {
  # Order is load-bearing: ImageMagick settings only apply to operators that
  # follow them.
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42
  local bg distort
  bg="$(grep -n -x -F -- '-background' "$IM_ARGV" | head -n1 | cut -d: -f1)"
  distort="$(grep -n -x -F -- '-distort' "$IM_ARGV" | head -n1 | cut -d: -f1)"
  [ "$bg" -lt "$distort" ]
}

@test "arc appends the rotate argument when one is given" {
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42 180
  assert_im_argv_adjacent "Arc" "42 180"
}

@test "arc omits the rotate argument when it is empty" {
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42 ""
  assert_im_argv_adjacent "Arc" "42"
}

@test "arc_apply_below flips the curve with a 180 rotate" {
  arc_apply_below "$TEST_TMP/label.png" "$TEST_TMP/out.png" 60
  assert_im_argv_adjacent "Arc" "60 180"
}

@test "arc writes png32 so the alpha channel survives" {
  arc_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 42
  assert_im_called_with "png32:$TEST_TMP/out.png"
}

# --- displace ---------------------------------------------------------------

@test "displace builds -compose displace with the item's amounts" {
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  assert_im_called_with "-compose displace"
  assert_im_called_with "compose:args=14x4"
  assert_im_argv_adjacent "-define" "compose:args=14x4"
}

@test "displace keeps the two axes separate" {
  # displace_x on its own must not leak into the vertical axis; a shared value
  # is the diagonal-smear bug.
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 20 0 "$TEST_TMP"
  assert_im_called_with "compose:args=20x0"
  assert_im_not_called_with "compose:args=20x20"
}

@test "displace normalises the map to a single grey channel" {
  # Red drives X and green drives Y. A colour map makes them disagree and the
  # baseline jitters.
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  assert_im_called_with "-colorspace Gray"
  assert_im_called_with "-auto-level"
}

@test "displace resizes the map to the label's exact dimensions" {
  # The '!' is the whole point: without it aspect ratio is preserved and the
  # map no longer lines up with the text it is supposed to bend.
  STUB_IM_W=640 STUB_IM_H=180
  export STUB_IM_W STUB_IM_H
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  assert_im_called_with "resize 640x180!"
}

@test "displace blurs the map before using it" {
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  assert_im_called_with "-blur 0x6"
}

@test "displace passes the label first and the map second" {
  # Order decides which image is displaced. Swapped, ImageMagick bends the map.
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  local line
  line="$(im_call_matching 'compose:args')"
  case "$line" in
    *"$TEST_TMP/label.png"*dmap-*) : ;;
    *) printf 'label and map are in the wrong order: %s\n' "$line" >&2; return 1 ;;
  esac
}

@test "displace keeps the label's transparency" {
  displace_apply "$TEST_TMP/label.png" "$TEST_TMP/map.png" "$TEST_TMP/out.png" 14 4 "$TEST_TMP"
  assert_im_called_with "-alpha set"
}

# --- perspective ------------------------------------------------------------

@test "perspective builds four source,destination pairs" {
  STUB_IM_W=800 STUB_IM_H=200
  export STUB_IM_W STUB_IM_H
  perspective_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" \
    10 20  700 40  690 180  20 160
  assert_im_called_with "-distort Perspective"
  assert_im_argv_adjacent "-distort" "Perspective"
  assert_im_called_with "0,0 10,20"
  assert_im_called_with "0,200 20,160"
}

@test "perspective sources its corners from the label's own dimensions" {
  STUB_IM_W=640 STUB_IM_H=160
  export STUB_IM_W STUB_IM_H
  perspective_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" \
    0 0  10 0  10 10  0 10
  assert_im_called_with "640,0"
  assert_im_called_with "640,160"
}

@test "perspective passes the whole point list as one argument" {
  perspective_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" \
    10 20  700 40  690 180  20 160
  grep -c -x -F -- 'Perspective' "$IM_ARGV" >/dev/null
  grep -q -F -- '0,0 10,20' "$IM_ARGV"
}

# --- cylinderize ------------------------------------------------------------

@test "cylinderize fails clearly when the external script is absent" {
  run cylinderize_require
  assert_failure
  assert_output_contains "cylinderize.sh"
  assert_output_contains "fmwconcepts.com"
}

@test "cylinderize does not invoke ImageMagick when the script is absent" {
  run cylinderize_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 190 430 150
  assert_failure
  assert_equal "$(im_call_count)" "0"
}

@test "cylinderize passes radius, length and wrap as separate flags" {
  # Stand in for Fred Weinhaus' script, which is not bundled and may not be
  # installed. We only assert on the argv we hand it.
  cat >"$STUB_BIN/cylinderize.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$IM_LOG"
printf '%s\n' "$@" >>"$IM_ARGV"
printf -- '--\n' >>"$IM_ARGV"
exit 0
STUB
  chmod +x "$STUB_BIN/cylinderize.sh"

  cylinderize_apply "$TEST_TMP/label.png" "$TEST_TMP/out.png" 190 430 150 8 0 0 0 0
  assert_im_argv_adjacent "-r" "190"
  assert_im_argv_adjacent "-l" "430"
  assert_im_argv_adjacent "-w" "150"
  assert_im_argv_adjacent "-p" "8"
  assert_im_argv_adjacent "-m" "cylinder"
  assert_im_argv_adjacent "-b" "none"
  assert_im_argv_adjacent "-o" "0,0"
}

@test "cylinderize is resolved through CYLINDERIZE_BIN when set" {
  cat >"$TEST_TMP/elsewhere.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$TEST_TMP/elsewhere.sh"
  CYLINDERIZE_BIN="$TEST_TMP/elsewhere.sh"
  run cylinderize_require
  assert_success
}

# --- label ------------------------------------------------------------------

@test "the label is rendered before any distortion, transparent and flat" {
  label_render "Fresh Roast" "fonts/X.ttf" 96 "#2b2b2b" 1100 "$TEST_TMP/label.png"
  assert_im_called_with "-background none"
  assert_im_called_with "caption:@-"
  assert_im_argv_adjacent "-pointsize" "96"
}

@test "the label size constrains width only, so pointsize is honoured" {
  # -size WxH makes caption: shrink text to fit and the set renders at
  # inconsistent sizes with no error anywhere.
  label_render "Fresh Roast" "fonts/X.ttf" 96 "#2b2b2b" 1100 "$TEST_TMP/label.png"
  assert_im_argv_adjacent "-size" "1100x"
  assert_im_not_called_with "-size 1100x1100"
}

@test "the label text is passed on stdin, never as an argument" {
  # Text is untrusted input. A leading @ would otherwise make ImageMagick read
  # a file, and nothing here is ever eval'd.
  label_render 'Fresh @Roast $(whoami)' "fonts/X.ttf" 96 "#2b2b2b" 1100 "$TEST_TMP/label.png"
  assert_im_not_called_with 'whoami'
}

# --- dispatch ---------------------------------------------------------------

@test "an unknown mode is rejected" {
  run validate_mode "wobble" 0
  assert_failure
  assert_output_contains "unknown mode 'wobble'"
}

@test "an unknown mode renders nothing" {
  run validate_mode "wobble" 0
  assert_failure
  assert_equal "$(im_call_count)" "0"
}
