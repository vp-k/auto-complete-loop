#!/usr/bin/env bats

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

# ─── Basic error recording ───

@test "record-error: records error in progress file" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --file "src/app.ts" --type "build" --msg "Cannot find module" --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  result=$(jq -r '.errorHistory.currentError.type' .claude-full-auto-progress.json)
  [ "$result" = "build" ]
  result=$(jq '.errorHistory.currentError.count' .claude-full-auto-progress.json)
  [ "$result" = "1" ]
}

@test "record-error: increments count for same error" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "src/app.ts" --type "build" --msg "Cannot find module" --progress-file .claude-full-auto-progress.json
  run_gate record-error --file "src/app.ts" --type "build" --msg "Cannot find module" --progress-file .claude-full-auto-progress.json
  result=$(jq '.errorHistory.currentError.count' .claude-full-auto-progress.json)
  [ "$result" = "2" ]
}

@test "record-error: resets count for different error" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "src/app.ts" --type "build" --msg "Cannot find module" --progress-file .claude-full-auto-progress.json
  run_gate record-error --file "src/app.ts" --type "runtime" --msg "TypeError" --progress-file .claude-full-auto-progress.json
  result=$(jq '.errorHistory.currentError.count' .claude-full-auto-progress.json)
  [ "$result" = "1" ]
  result=$(jq -r '.errorHistory.currentError.type' .claude-full-auto-progress.json)
  [ "$result" = "runtime" ]
}

# ─── Level and budget ───

@test "record-error: sets level and budget" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --file "f" --type "t" --msg "m" --level L1 --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  result=$(jq -r '.errorHistory.escalationLevel' .claude-full-auto-progress.json)
  [ "$result" = "L1" ]
  result=$(jq '.errorHistory.escalationBudget' .claude-full-auto-progress.json)
  [ "$result" = "3" ]
}

@test "record-error: rejects invalid level" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --file "f" --type "t" --msg "m" --level L9 --progress-file .claude-full-auto-progress.json
  [ "$status" -ne 0 ]
}

# ─── Budget exhaustion and escalation ───

@test "record-error: exit 1 when budget exhausted (L0 after 3 tries)" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json
  run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json
  run run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 1 ]
}

@test "record-error: auto-escalates to next level on budget exhaustion" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json
  run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json
  run run_gate record-error --file "f" --type "t" --msg "err" --level L0 --progress-file .claude-full-auto-progress.json || true
  result=$(jq -r '.errorHistory.escalationLevel' .claude-full-auto-progress.json)
  [ "$result" = "L1" ]
}

@test "record-error: exit 2 at L2 (codex needed)" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --file "f" --type "t" --msg "err" --level L2 --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 2 ]
}

@test "record-error: exit 3 at L5 (user intervention)" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --file "f" --type "t" --msg "err" --level L5 --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 3 ]
}

# ─── Reset count ───

@test "record-error: --reset-count resets counter" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "f" --type "t" --msg "err" --progress-file .claude-full-auto-progress.json
  run_gate record-error --file "f" --type "t" --msg "err" --progress-file .claude-full-auto-progress.json
  result=$(jq '.errorHistory.currentError.count' .claude-full-auto-progress.json)
  [ "$result" = "2" ]
  run_gate record-error --file "f" --type "t" --msg "err" --reset-count --progress-file .claude-full-auto-progress.json
  result=$(jq '.errorHistory.currentError.count' .claude-full-auto-progress.json)
  [ "$result" = "1" ]
}

# ─── Escalation log ───

@test "record-error: records escalation log with action/result" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "f" --type "t" --msg "err" --action "tried fix A" --result "fail" --progress-file .claude-full-auto-progress.json
  result=$(jq -r '.errorHistory.escalationLog[0].action' .claude-full-auto-progress.json)
  [ "$result" = "tried fix A" ]
  result=$(jq -r '.errorHistory.escalationLog[0].result' .claude-full-auto-progress.json)
  [ "$result" = "fail" ]
}

# ─── Validation ───

@test "record-error: requires --file, --type, --msg" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-error --type "t" --msg "m" --progress-file .claude-full-auto-progress.json
  [ "$status" -ne 0 ]
}
