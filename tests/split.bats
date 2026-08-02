#!/usr/bin/env bats
# split.bats — TOO_BIG 문서 분할 (record-error exit 4 + doc-split record)

load test_helper

PF=".claude-full-auto-progress.json"

setup() {
  setup_temp_dir
  run_gate init --template full-auto "test" "req"
  # in_progress 문서 1개 시드
  jq '.phases.phase_2.documents = [{"name":"auth.md","status":"in_progress","phase":"implementing","tickets":[]}]' \
    "$PF" > tmp.json && mv tmp.json "$PF"
}
teardown() { teardown_temp_dir; }

seed_l3_exhausted() {
  # L3 + 동일 에러 2회 누적 상태 시드 → 다음 record-error에서 예산(3) 소진
  jq '.errorHistory = {
        "currentError": {"type":"runtime","file":"src/a.ts","message":"same err","msgNormalized":"same err","count":2,"escalationLevel":"L3"},
        "attempts": [], "escalationLevel": "L3", "escalationBudget": 3, "levelHistory": ["L3"]
      }' "$PF" > tmp.json && mv tmp.json "$PF"
}

@test "split: L3 budget exhaustion with splittable doc returns exit 4 + pendingSplit" {
  seed_l3_exhausted
  run run_gate record-error --file "src/a.ts" --type "runtime" --msg "same err" --progress-file "$PF"
  [ "$status" -eq 4 ]
  [[ "$output" == *"SPLIT_REQUIRED"* ]]
  result=$(jq -r '.errorHistory.pendingSplit.doc' "$PF")
  [ "$result" = "auth.md" ]
}

@test "split: already-split doc (splitDepth=1) falls through to L4" {
  jq '.phases.phase_2.documents[0].splitDepth = 1' "$PF" > tmp.json && mv tmp.json "$PF"
  seed_l3_exhausted
  run run_gate record-error --file "src/a.ts" --type "runtime" --msg "same err" --progress-file "$PF"
  [ "$status" -eq 1 ]
  result=$(jq -r '.errorHistory.escalationLevel' "$PF")
  [ "$result" = "L4" ]
}

@test "split: no in_progress doc falls through to L4" {
  jq '.phases.phase_2.documents[0].status = "completed"' "$PF" > tmp.json && mv tmp.json "$PF"
  seed_l3_exhausted
  run run_gate record-error --file "src/a.ts" --type "runtime" --msg "same err" --progress-file "$PF"
  [ "$status" -eq 1 ]
}

@test "doc-split: refused without pendingSplit precondition" {
  mkdir -p docs
  printf '# p1\n' > docs/auth-part1.md
  printf '# p2\n' > docs/auth-part2.md
  run run_gate doc-split record --parent auth.md --children auth-part1.md,auth-part2.md --progress-file "$PF"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REFUSED"* ]]
}

do_pending_split() {
  seed_l3_exhausted
  run_gate record-error --file "src/a.ts" --type "runtime" --msg "same err" --progress-file "$PF" || true
}

@test "doc-split: happy path — parent split, children pending, escalation reset to L1" {
  do_pending_split
  mkdir -p docs
  printf '# p1\n' > docs/auth-part1.md
  printf '# p2\n' > docs/auth-part2.md
  run run_gate doc-split record --parent auth.md --children auth-part1.md,auth-part2.md --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.phases.phase_2.documents[] | select(.name=="auth.md") | .status' "$PF")" = "split" ]
  [ "$(jq '[.phases.phase_2.documents[] | select(.parentDoc=="auth.md")] | length' "$PF")" = "2" ]
  [ "$(jq -r '.phases.phase_2.documents[] | select(.name=="auth-part1.md") | .status' "$PF")" = "pending" ]
  [ "$(jq -r '.errorHistory.escalationLevel' "$PF")" = "L1" ]
  [ "$(jq '.errorHistory.currentError.count' "$PF")" = "0" ]
  [ "$(jq '.errorHistory | has("pendingSplit")' "$PF")" = "false" ]
  run jq -r 'select(.event=="doc.split") | .parent' .claude/acl-events.jsonl
  [[ "$output" == *"auth.md"* ]]
}

@test "doc-split: refused with fewer than 2 children" {
  do_pending_split
  mkdir -p docs
  printf '# p1\n' > docs/auth-part1.md
  run run_gate doc-split record --parent auth.md --children auth-part1.md --progress-file "$PF"
  [ "$status" -ne 0 ]
}

@test "doc-split: refused when child name does not derive from parent slug" {
  do_pending_split
  mkdir -p docs
  printf '# x\n' > docs/other.md
  printf '# p1\n' > docs/auth-part1.md
  run run_gate doc-split record --parent auth.md --children other.md,auth-part1.md --progress-file "$PF"
  [ "$status" -ne 0 ]
}

@test "doc-split: refused when child file missing" {
  do_pending_split
  run run_gate doc-split record --parent auth.md --children auth-part1.md,auth-part2.md --progress-file "$PF"
  [ "$status" -ne 0 ]
  [[ "$output" == *"존재하지 않음"* ]]
}

@test "stop-hook completion: split parent + completed children counts as complete" {
  result=$(jq -n '{documents:[{name:"auth.md",status:"split"},{name:"auth-part1.md",status:"completed"},{name:"auth-part2.md",status:"completed"}]}
    | [.documents[] | select(.status != "split")] | (length > 0) and all(.status == "completed")')
  [ "$result" = "true" ]
}

@test "stop-hook completion: split parent with pending child is incomplete" {
  result=$(jq -n '{documents:[{name:"auth.md",status:"split"},{name:"auth-part1.md",status:"pending"}]}
    | [.documents[] | select(.status != "split")] | (length > 0) and all(.status == "completed")')
  [ "$result" = "false" ]
}

@test "stop-hook completion: only split parents (no children) is incomplete" {
  result=$(jq -n '{documents:[{name:"auth.md",status:"split"}]}
    | [.documents[] | select(.status != "split")] | (length > 0) and all(.status == "completed")')
  [ "$result" = "false" ]
}
