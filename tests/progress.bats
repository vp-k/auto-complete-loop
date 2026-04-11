#!/usr/bin/env bats

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

# ─── Schema migration tests ───

@test "migrate v2: adds assumptions and premortem fields" {
  # Create v1 schema manually
  run_gate init --template full-auto "test" "req"
  # Downgrade to v1 to test migration
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 1 | del(.phases.phase_0.outputs.assumptions, .phases.phase_0.outputs.premortem, .dod.assumptions_documented, .dod.premortem_done, .dod.launch_ready)'

  migrate_schema_v2 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "2" ]
  # premortem should exist
  result=$(jq '.phases.phase_0.outputs.premortem | has("tigers")' .claude-full-auto-progress.json)
  [ "$result" = "true" ]
}

@test "migrate v2: idempotent - safe to run multiple times" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 1'
  migrate_schema_v2 .claude-full-auto-progress.json
  migrate_schema_v2 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "2" ]
}

@test "migrate v3: adds E2E support" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 2 | del(.phases.phase_2.e2e)'
  migrate_schema_v3 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "3" ]
  result=$(jq '.phases.phase_2.e2e | has("applicable")' .claude-full-auto-progress.json)
  [ "$result" = "true" ]
}

@test "migrate v4: adds projectScope" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 3 | del(.phases.phase_0.outputs.projectScope)'
  migrate_schema_v4 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "4" ]
}

@test "migrate v5: adds gateHistory" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 4 | del(.gateHistory)'
  migrate_schema_v5 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "5" ]
  result=$(jq '.gateHistory | type' .claude-full-auto-progress.json)
  [ "$result" = "\"array\"" ]
}

@test "migrate v6: adds implementationOrder" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 5 | del(.phases.phase_0.outputs.implementationOrder)'
  migrate_schema_v6 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "6" ]
}

@test "migrate v7: adds conditionalGoItems" {
  run_gate init --template full-auto "test" "req"
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 6 | del(.conditionalGoItems)'
  migrate_schema_v7 .claude-full-auto-progress.json
  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "7" ]
  result=$(jq '.conditionalGoItems | type' .claude-full-auto-progress.json)
  [ "$result" = "\"array\"" ]
}

@test "migrate: full chain v1→v7 produces valid schema" {
  run_gate init --template full-auto "test" "req"
  # Downgrade to v1
  jq_inplace .claude-full-auto-progress.json '.schemaVersion = 1 | del(.gateHistory, .phases.phase_2.e2e, .phases.phase_0.outputs.projectScope, .phases.phase_0.outputs.implementationOrder, .conditionalGoItems)'

  # Run full chain
  migrate_schema_v2 .claude-full-auto-progress.json
  migrate_schema_v3 .claude-full-auto-progress.json
  migrate_schema_v4 .claude-full-auto-progress.json
  migrate_schema_v5 .claude-full-auto-progress.json
  migrate_schema_v6 .claude-full-auto-progress.json
  migrate_schema_v7 .claude-full-auto-progress.json

  result=$(jq '.schemaVersion' .claude-full-auto-progress.json)
  [ "$result" = "7" ]
  # Validate JSON integrity
  jq empty .claude-full-auto-progress.json
  # conditionalGoItems should exist
  result=$(jq 'has("conditionalGoItems")' .claude-full-auto-progress.json)
  [ "$result" = "true" ]
}

@test "migrate: skips non-full-auto files" {
  run_gate init --template review "test" "scope"
  migrate_schema_v2 .claude-review-loop-progress.json
  # Should not crash and version should not change (no schemaVersion field)
  result=$(jq '.schemaVersion // "none"' .claude-review-loop-progress.json)
  [ "$result" = "\"none\"" ]
}

# ─── append_gate_history tests ───

@test "append_gate_history: adds entry to history" {
  run_gate init --template full-auto "test" "req"
  PROGRESS_FILE=".claude-full-auto-progress.json"
  append_gate_history "quality-gate" "pass" '{"exitCode":0}'

  result=$(jq '.gateHistory | length' .claude-full-auto-progress.json)
  [ "$result" = "1" ]
  result=$(jq -r '.gateHistory[0].gate' .claude-full-auto-progress.json)
  [ "$result" = "quality-gate" ]
}

@test "append_gate_history: limits to 100 entries" {
  run_gate init --template full-auto "test" "req"
  PROGRESS_FILE=".claude-full-auto-progress.json"

  # Add 105 entries
  for i in $(seq 1 105); do
    append_gate_history "gate-$i" "pass" '{}' 2>/dev/null
  done

  result=$(jq '.gateHistory | length' .claude-full-auto-progress.json)
  [ "$result" = "100" ]
}

@test "append_gate_history: detects 3 consecutive failures" {
  run_gate init --template full-auto "test" "req"
  PROGRESS_FILE=".claude-full-auto-progress.json"

  run append_gate_history "quality-gate" "fail" '{}'
  run append_gate_history "quality-gate" "fail" '{}'
  run append_gate_history "quality-gate" "fail" '{}'

  [[ "$output" == *"CIRCULAR FAILURE"* ]]
}

@test "append_gate_history: no alert for mixed results" {
  run_gate init --template full-auto "test" "req"
  PROGRESS_FILE=".claude-full-auto-progress.json"

  append_gate_history "quality-gate" "fail" '{}'
  append_gate_history "quality-gate" "pass" '{}'
  run append_gate_history "quality-gate" "fail" '{}'

  [[ "$output" != *"CIRCULAR FAILURE"* ]]
}
