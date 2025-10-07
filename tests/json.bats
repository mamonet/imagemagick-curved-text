#!/usr/bin/env bats
# repo path: tests/json.bats
# lib/json.sh: accessor defaults, required-field failure, slugify.

load test_helper

setup() {
  common_setup
  load_libs_with_stub json
  require_jq
  OBJ='{"mode":"arc","text":"Fresh Roast Daily","pointsize":96,"arc_degrees":42,"nulled":null,"blank":""}'
}

teardown() { common_teardown; }

# --- json_opt ---------------------------------------------------------------

@test "json_opt returns the value when the field is present" {
  run json_opt "$OBJ" '.pointsize' '96'
  assert_success
  assert_equal "$output" "96"
}

@test "json_opt returns the default when the field is absent" {
  run json_opt "$OBJ" '.label_width' '1200'
  assert_success
  assert_equal "$output" "1200"
}

@test "json_opt treats an explicit null as absent" {
  run json_opt "$OBJ" '.nulled' 'fallback'
  assert_success
  assert_equal "$output" "fallback"
}

@test "json_opt treats an empty string as absent" {
  # Deliberate: an empty fill or font is never what the author meant, and
  # passing "" through to ImageMagick fails much further downstream.
  run json_opt "$OBJ" '.blank' '#222222'
  assert_success
  assert_equal "$output" "#222222"
}

@test "json_opt on a missing optional field is not an error" {
  run json_opt "$OBJ" '.no_such_field' ''
  assert_success
  assert_equal "$output" ""
}

@test "json_opt reads a nested path" {
  run json_opt '{"corners":{"tl":[10,20]}}' '.corners.tl[1]' '0'
  assert_success
  assert_equal "$output" "20"
}

# --- json_req ---------------------------------------------------------------

@test "json_req returns the value when present" {
  run json_req "$OBJ" '.text' 0
  assert_success
  assert_equal "$output" "Fresh Roast Daily"
}

@test "json_req fails when a required field is missing" {
  run json_req "$OBJ" '.mockup' 3
  assert_failure
  assert_output_contains "missing required field"
  assert_output_contains ".mockup"
}

@test "json_req names the item index in the failure" {
  # A 30-item run needs to say WHICH item, not just that something is missing.
  run json_req "$OBJ" '.mockup' 17
  assert_failure
  assert_output_contains "[17]"
}

@test "json_req fails on an explicit null" {
  run json_req "$OBJ" '.nulled' 0
  assert_failure
  assert_output_contains "missing required field"
}

@test "json_req fails on an empty string" {
  run json_req "$OBJ" '.blank' 0
  assert_failure
}

# --- json_has ---------------------------------------------------------------

@test "json_has is true for a present field and false for a missing one" {
  json_has "$OBJ" '.arc_degrees'
  run json_has "$OBJ" '.displace_map'
  assert_failure
}

@test "json_has is false for an explicit null" {
  run json_has "$OBJ" '.nulled'
  assert_failure
}

# --- json_load / json_count / json_item -------------------------------------

@test "json_load accepts an array of objects" {
  local f
  f="$(write_items "$(fixture_item_arc)")"
  run json_load "$f"
  assert_success
}

@test "json_load rejects a missing file" {
  run json_load "$TEST_TMP/nope.json"
  assert_failure
  assert_output_contains "items file not found"
}

@test "json_load rejects a top-level object" {
  printf '{"mode":"arc"}' >"$TEST_TMP/obj.json"
  run json_load "$TEST_TMP/obj.json"
  assert_failure
  assert_output_contains "must be a JSON array"
}

@test "json_load rejects an empty array" {
  printf '[]' >"$TEST_TMP/empty.json"
  run json_load "$TEST_TMP/empty.json"
  assert_failure
  assert_output_contains "empty array"
}

@test "json_load rejects malformed JSON" {
  printf '[{"mode": }]' >"$TEST_TMP/bad.json"
  run json_load "$TEST_TMP/bad.json"
  assert_failure
}

@test "json_count counts the items" {
  local f
  f="$(write_items "$(fixture_item_arc)" "$(fixture_item_arc)")"
  run json_count "$f"
  assert_success
  assert_equal "$output" "2"
}

@test "json_item returns the object at an index" {
  local f
  f="$(write_items '{"mode":"arc","text":"first"}' '{"mode":"displace","text":"second"}')"
  run json_item "$f" 1
  assert_success
  assert_output_contains '"second"'
  assert_output_not_contains '"first"'
}

# --- slugify ----------------------------------------------------------------

@test "slugify lowercases and replaces spaces with dashes" {
  run slugify "Fresh Roast Daily"
  assert_success
  assert_equal "$output" "fresh-roast-daily"
}

@test "slugify collapses punctuation runs into a single dash" {
  run slugify "Loose Leaf No. 3"
  assert_success
  assert_equal "$output" "loose-leaf-no-3"
}

@test "slugify strips characters that would break a path or a shell" {
  # The output goes straight into a filename, so a slash or a quote getting
  # through here is a path-traversal bug, not a cosmetic one.
  run slugify 'a/b "c" $(d) ../e'
  assert_success
  assert_equal "$output" "a-b-c-d-e"
}

@test "slugify trims leading and trailing dashes" {
  run slugify "  -- Cold Pressed --  "
  assert_success
  assert_equal "$output" "cold-pressed"
}

@test "slugify falls back to 'item' when nothing survives" {
  run slugify "!!! ??? ---"
  assert_success
  assert_equal "$output" "item"
}

@test "slugify handles an empty string" {
  run slugify ""
  assert_success
  assert_equal "$output" "item"
}

@test "slugify caps the length so paths stay sane" {
  run slugify "the quick brown fox jumps over the lazy dog and keeps on going well past any reasonable filename"
  assert_success
  [ "${#output}" -le 48 ]
}

@test "slugify reduces non-ASCII to dashes rather than passing bytes through" {
  # LC_ALL=C means each non-ASCII byte becomes a dash, and the run collapses.
  # Not pretty, but a filename that is guaranteed portable beats a pretty one.
  run slugify "Café Noir"
  assert_success
  assert_equal "$output" "caf-noir"
}
