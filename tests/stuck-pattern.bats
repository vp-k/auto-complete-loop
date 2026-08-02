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
  # 상이한 게이트 집합(부분집합 관계 아님) → 수렴 예외 미적용 → DR 발동
  printf 'hash-one\tgateA\nhash-two\tgateB\nhash-three\tgateC\nhash-four\tgateD\nhash-five\tgateE\n' > "$HISTORY"
  run_hook                                # 6번째 append → 상이 서명 >= 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIMINISHING_RETURNS"* ]]
  [ ! -f "$STATE" ]
  grep -q "stop-hook-diminishing-returns" "$LEARNINGS"
}

@test "stuck: DR skipped when failing-gate set monotonically shrinks (converging run)" {
  # full-auto 픽스처: _require_vgate missing 사유가 'key=missing' 게이트 토큰을 생성
  cat > "$STATE" <<'EOF'
---
iteration: 1
max_iterations: 30
completion_promise: "DONE"
progress_file: .claude-full-auto-progress.json
---
loop prompt
EOF
  rm -f .claude-progress.json
  printf '{"steps":[{"name":"phase_0","status":"completed"}],"dod":{"k":{"checked":true,"evidence":"e"}}}\n' > .claude-full-auto-progress.json
  printf '{}\n' > .claude-verification.json
  run_hook
  [ -f "$HISTORY" ]
  G=$(tail -1 "$HISTORY" | cut -f2)
  [ -n "$G" ]
  # 시드 5개: 상이 해시 + 현재 게이트 집합의 상위집합(+zzzExtra) → 단조 축소 형상
  { for i in 1 2 3 4 5; do printf 'seedhash-%s\t%s,zzzExtra\n' "$i" "$G"; done; } > "$HISTORY"
  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"converging"* ]]
  [ -f "$STATE" ]                         # DR 미발동 — 루프 계속
}

@test "stuck: legacy bare-hash lines (no tab) are excluded from detection" {
  # 구 포맷 5줄 시드 — 감지에서 제외되므로 가짜 DIMINISHING_RETURNS가 발동하면 안 됨
  printf 'legacy-a\nlegacy-b\nlegacy-c\nlegacy-d\nlegacy-e\n' > "$HISTORY"
  run_hook
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  lines=$(wc -l < "$HISTORY" | tr -d ' ')
  [ "$lines" -eq 6 ]
}

@test "stuck: verify_failed event emitted on each failed verification" {
  run_hook
  run jq -r 'select(.event=="loop.verify_failed") | .event' .claude/acl-events.jsonl
  [[ "$output" == *"loop.verify_failed"* ]]
}
