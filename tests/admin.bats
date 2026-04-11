#!/usr/bin/env bats

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

# ─── cmd_init tests ───

@test "init: creates full-auto progress file" {
  run run_gate init --template full-auto "test-proj" "test requirement"
  [ "$status" -eq 0 ]
  [ -f ".claude-full-auto-progress.json" ]
  # schemaVersion should be 7
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "7" ]
}

@test "init: creates review progress file" {
  run run_gate init --template review "test" "scope"
  [ "$status" -eq 0 ]
  [ -f ".claude-review-loop-progress.json" ]
}

@test "init: creates all 7 template types" {
  for tpl in full-auto plan implement review polish e2e doc-check; do
    run run_gate init --template "$tpl" "proj" "req"
    [ "$status" -eq 0 ]
  done
}

@test "init: skips if file already exists" {
  run run_gate init --template full-auto "test" "req"
  [ "$status" -eq 0 ]
  # run again
  run run_gate init --template full-auto "test" "req"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init: full-auto has all 5 phases in steps" {
  run_gate init --template full-auto "test" "req"
  result=$(jq '.steps | length' .claude-full-auto-progress.json)
  [ "$result" = "5" ]
}

@test "init: full-auto has 13 DoD items" {
  run_gate init --template full-auto "test" "req"
  result=$(jq '.dod | to_entries | length' .claude-full-auto-progress.json)
  [ "$result" = "13" ]
}

# ─── cmd_update_step tests ───

@test "update-step: transitions step status" {
  run_gate init --template full-auto "test" "req"
  run run_gate update-step phase_0 completed --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  result=$(jq -r '.steps[0].status' .claude-full-auto-progress.json)
  [ "$result" = "completed" ]
}

@test "update-step: rejects invalid status" {
  run_gate init --template full-auto "test" "req"
  run run_gate update-step phase_0 invalid_status --progress-file .claude-full-auto-progress.json
  [ "$status" -ne 0 ]
}

@test "update-step: rejects non-existent step" {
  run_gate init --template full-auto "test" "req"
  run run_gate update-step nonexistent completed --progress-file .claude-full-auto-progress.json
  [ "$status" -ne 0 ]
}

# ─── cmd_status tests ───

@test "status: displays progress info" {
  run_gate init --template full-auto "test" "req"
  run run_gate status --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"Progress Status"* ]]
  [[ "$output" == *"DoD:"* ]]
}

# ─── cmd_handoff_update tests ───

@test "handoff-update: batch updates all fields atomically" {
  run_gate init --template full-auto "test" "req"
  run run_gate handoff-update \
    --next-steps "Phase 1" \
    --phase "phase_1" \
    --completed "Phase 0 done" \
    --warnings "warn" \
    --decision "D1" \
    --decision "D2" \
    --iteration 5 \
    --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  # All fields should be set
  result=$(jq -r '.handoff.nextSteps' .claude-full-auto-progress.json)
  [ "$result" = "Phase 1" ]
  result=$(jq '.handoff.lastIteration' .claude-full-auto-progress.json)
  [ "$result" = "5" ]
  result=$(jq '.handoff.keyDecisions | length' .claude-full-auto-progress.json)
  [ "$result" = "2" ]
}

# ─── cmd_init_ralph tests ───

@test "init-ralph: creates ralph loop file" {
  run_gate init --template full-auto "test" "req"
  run run_gate init-ralph FULL_AUTO_COMPLETE .claude-full-auto-progress.json 20
  [ "$status" -eq 0 ]
  [ -f ".claude/ralph-loop.local.md" ]
}

@test "init-ralph: rejects invalid max_iter" {
  run run_gate init-ralph TEST .claude-full-auto-progress.json abc
  [ "$status" -ne 0 ]
}

@test "init-ralph: rejects path traversal" {
  run run_gate init-ralph TEST ../secret.json 10
  [ "$status" -ne 0 ]
}
