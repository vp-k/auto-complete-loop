#!/usr/bin/env bats
# stuck-pattern.bats — stop-hook 막힘 패턴 감지 (3-strike / OSCILLATION / DIMINISHING_RETURNS)

load test_helper

HOOK="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)/hooks/stop-hook.sh"
HISTORY=".claude/ralph-loop-failure-history.local"
STATE=".claude/ralph-loop.local.md"
LEARNINGS=".claude/acl-learnings.local.md"

setup() {
  setup_temp_dir
  mkdir -p .claude
  cat > "$STATE" <<'EOF'
---
iteration: 1
max_iterations: 30
completion_promise: "DONE"
progress_file: .claude-progress.json
---
loop prompt
EOF
  # 미완료 문서 → promise 검증 실패 (실패 사유는 숫자 없는 고정 문자열)
  printf '{"documents":[{"name":"a.md","status":"pending"}]}\n' > .claude-progress.json
  printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"<promise>DONE</promise>"}]}}' > transcript.jsonl
}
teardown() { teardown_temp_dir; }

run_hook() {
  # 상태 파일이 트리거로 삭제된 뒤 재생성이 필요한 테스트를 위해 함수화
  run bash -c "printf '{\"transcript_path\":\"%s\"}' '$TEST_DIR/transcript.jsonl' | bash '$HOOK'"
}

@test "stuck: single failure appends hash+gates line and continues loop" {
  run_hook
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  [ -f "$HISTORY" ]
  lines=$(wc -l < "$HISTORY" | tr -d ' ')
  [ "$lines" -eq 1 ]
  [[ "$output" == *'"decision"'* ]]
}

@test "stuck: 3 identical consecutive failures trigger 3-strike exit" {
  run_hook; run_hook; run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Breaking loop"* ]]
  [ ! -f "$STATE" ]
  [ ! -f "$HISTORY" ]
  grep -q "stop-hook-3strike" "$LEARNINGS"
  run jq -r 'select(.event=="loop.exit") | .reason' .claude/acl-events.jsonl
  [[ "$output" == *"3strike"* ]]
}

@test "stuck: AABA does NOT trigger (cumulative-count bug fixed)" {
  run_hook; run_hook                      # H, H
  printf 'otherhash\tgateX\n' >> "$HISTORY"  # H, H, OTHER
  run_hook                                # H, H, OTHER, H
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]                         # 루프 계속 (탈출 아님)
  [[ "$output" == *'"decision"'* ]]
}

@test "stuck: ABAB alternation triggers OSCILLATION exit" {
  run_hook                                # H
  printf 'otherhash\tgateX\n' >> "$HISTORY"  # H, OTHER
  run_hook                                # H, OTHER, H
  [ -f "$STATE" ]
  printf 'otherhash\tgateX\n' >> "$HISTORY"  # H, OTHER, H, OTHER
  run_hook                                # H, OTHER, H, OTHER, H → last4 = OTHER,H,OTHER,H
  [ "$status" -eq 0 ]
  [[ "$output" == *"OSCILLATION"* ]]
  [ ! -f "$STATE" ]
  grep -q "stop-hook-oscillation" "$LEARNINGS"
  run jq -r 'select(.event=="loop.exit") | .reason' .claude/acl-events.jsonl
  [[ "$output" == *"oscillation"* ]]
}

@test "stuck: 6 consecutive failures with >=3 distinct signatures trigger DIMINISHING_RETURNS" {
  printf 'hash-one\nhash-two\nhash-three\nhash-four\nhash-five\n' > "$HISTORY"
  run_hook                                # 6번째 append → 상이 서명 >= 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIMINISHING_RETURNS"* ]]
  [ ! -f "$STATE" ]
  grep -q "stop-hook-diminishing-returns" "$LEARNINGS"
}

@test "stuck: legacy bare-hash lines (no tab) parse without error" {
  printf 'legacyhashnotab\n' > "$HISTORY"
  run_hook
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  lines=$(wc -l < "$HISTORY" | tr -d ' ')
  [ "$lines" -eq 2 ]
}

@test "stuck: verify_failed event emitted on each failed verification" {
  run_hook
  run jq -r 'select(.event=="loop.verify_failed") | .event' .claude/acl-events.jsonl
  [[ "$output" == *"loop.verify_failed"* ]]
}
