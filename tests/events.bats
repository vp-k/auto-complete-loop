#!/usr/bin/env bats
# events.bats — log_event(JSONL 이벤트 로그) + emit 지점 검증

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

@test "log_event: creates valid JSONL with ts/event + merged payload" {
  log_event "gate.result" '{"gate":"test-gate","result":"pass"}'
  [ -f .claude/acl-events.jsonl ]
  run jq -r '.event' .claude/acl-events.jsonl
  [ "$output" = "gate.result" ]
  run jq -r '.gate' .claude/acl-events.jsonl
  [ "$output" = "test-gate" ]
  run jq -r '.ts' .claude/acl-events.jsonl
  [[ "$output" =~ ^[0-9]{4}- ]]
}

@test "log_event: no payload defaults to bare event" {
  log_event "loop.exit"
  run jq -r '.event' .claude/acl-events.jsonl
  [ "$output" = "loop.exit" ]
}

@test "log_event: empty type is a silent no-op" {
  run log_event ""
  [ "$status" -eq 0 ]
  [ ! -f .claude/acl-events.jsonl ]
}

@test "log_event: invalid payload JSON is a silent no-op (never fails caller)" {
  run log_event "x.y" 'not-json'
  [ "$status" -eq 0 ]
  [ ! -f .claude/acl-events.jsonl ]
}

@test "log_event: truncates to 1000 lines when exceeding 2000" {
  mkdir -p .claude
  for i in $(seq 1 2001); do printf '{"ts":"t","event":"pad"}\n'; done > .claude/acl-events.jsonl
  log_event "cap.test" '{}'
  lines=$(wc -l < .claude/acl-events.jsonl | tr -d ' ')
  [ "$lines" -le 1001 ]
  run tail -1 .claude/acl-events.jsonl
  [[ "$output" == *'"cap.test"'* ]]
}

@test "append_gate_history: emits gate.result event even without progress file" {
  PROGRESS_FILE=""
  append_gate_history "some-gate" "fail" '{"n":1}'
  [ -f .claude/acl-events.jsonl ]
  run jq -r 'select(.event=="gate.result") | .gate' .claude/acl-events.jsonl
  [[ "$output" == *"some-gate"* ]]
}

@test "record-error: emits error.recorded event" {
  run_gate init --template full-auto "test" "req"
  run_gate record-error --file "f.ts" --type "build" --msg "boom" --progress-file .claude-full-auto-progress.json
  run jq -r 'select(.event=="error.recorded") | .type' .claude/acl-events.jsonl
  [[ "$output" == *"build"* ]]
}

@test "record-error: escalation transition emits escalation.level event" {
  run_gate init --template full-auto "test" "req"
  for i in 1 2; do
    run_gate record-error --file "f" --type "t" --msg "same err" --level L0 --progress-file .claude-full-auto-progress.json || true
  done
  run run_gate record-error --file "f" --type "t" --msg "same err" --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 1 ]
  run jq -r 'select(.event=="escalation.level") | .to' .claude/acl-events.jsonl
  [[ "$output" == *"L1"* ]]
}

@test "record-error: escalationLog capped at 200 entries" {
  run_gate init --template full-auto "test" "req"
  # 250개 엔트리 시드 후 1회 기록 → [-200:] 캡 적용 확인
  jq '.errorHistory.escalationLog = [range(250) | {ts:"t",level:"L0",attempt:1,error:"e",action:"",result:"fail"}]' \
    .claude-full-auto-progress.json > tmp.json && mv tmp.json .claude-full-auto-progress.json
  run_gate record-error --file "f" --type "t" --msg "m" --progress-file .claude-full-auto-progress.json
  count=$(jq '.errorHistory.escalationLog | length' .claude-full-auto-progress.json)
  [ "$count" -le 200 ]
}
