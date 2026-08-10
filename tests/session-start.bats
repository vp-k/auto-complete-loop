#!/usr/bin/env bats
# session-start.bats — 교차 실행 반복 감지(acl-events 소비) 주입 검증 (Fix 2)

load test_helper

HOOK="$SCRIPT_DIR/../hooks/session-start.sh"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

@test "cross-run: recurring error type (>=3) injected as 반복 경고 without progress file" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L0","count":1}
{"ts":"t2","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L1","count":2}
{"ts":"t3","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L1","count":3}
{"ts":"t4","event":"gate.result","gate":"g","result":"pass"}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"교차 실행 반복 경고"* ]]
  [[ "$ctx" == *"BUILD_FAIL"* ]]
}

@test "cross-run: ambiguity mismatch + deep escalation surfaced" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"gate.ambiguity.mismatch","gate":"spec-completeness","mismatch":"goal"}
{"ts":"t2","event":"escalation.level","from":"L3","to":"L4","reason":"budget_exhausted"}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"명확성 세탁"* ]]
  [[ "$ctx" == *"심층 에스컬레이션"* ]]
}

@test "cross-run: single error occurrence (<3) is NOT flagged" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"error.recorded","type":"ONEOFF","file":"a","level":"L0","count":1}
{"ts":"t2","event":"gate.result","gate":"g","result":"pass"}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  # 반복 경고 섹션 자체가 없어야 함 (일회성 오류는 노이즈)
  [[ "$output" != *"교차 실행 반복 경고"* ]]
}

@test "cross-run: no events file → no injection, clean exit" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"교차 실행 반복 경고"* ]]
}

@test "cross-run: malformed JSONL line degrades to no-op (never crashes)" {
  mkdir -p .claude
  printf 'this is not json\n' > .claude/acl-events.jsonl
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"교차 실행 반복 경고"* ]]
}
