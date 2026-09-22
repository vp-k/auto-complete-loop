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

# ─── v4.25.0: 컨텍스트 채움 관측 이벤트 집계 ───

@test "cross-run: context.read.large >=3 surfaced with top files; run.uncapped >=3 surfaced" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"context.read.large","tool":"Read","file":"/p/docs/SPEC.md","lines":900,"bytes":1,"offset":0,"threshold":300,"iteration":1}
{"ts":"t2","event":"context.read.large","tool":"Read","file":"/p/docs/SPEC.md","lines":900,"bytes":1,"offset":0,"threshold":300,"iteration":2}
{"ts":"t3","event":"context.read.large","tool":"Bash","file":"test.log","lines":500,"bytes":1,"offset":0,"threshold":300,"iteration":2}
{"ts":"t4","event":"context.run.uncapped","cmd":"npm test","iteration":1}
{"ts":"t5","event":"context.run.uncapped","cmd":"npm test","iteration":2}
{"ts":"t6","event":"context.run.uncapped","cmd":"pytest","iteration":3}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"교차 실행 반복 경고"* ]]
  [[ "$ctx" == *"긴 파일 통째 읽기 ×3회"* ]]
  [[ "$ctx" == *"SPEC.md×2"* ]]
  [[ "$ctx" == *"상한 없는 테스트 실행 ×3회"* ]]
  [[ "$ctx" == *"run-capped"* ]]
}

@test "cross-run: fewer than 3 context events → not surfaced" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"context.read.large","tool":"Read","file":"a.md","lines":900,"bytes":1,"offset":0,"threshold":300,"iteration":1}
{"ts":"t2","event":"context.read.large","tool":"Read","file":"a.md","lines":900,"bytes":1,"offset":0,"threshold":300,"iteration":2}
{"ts":"t3","event":"context.run.uncapped","cmd":"npm test","iteration":1}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"긴 파일 통째 읽기"* ]]
  [[ "$output" != *"상한 없는 테스트 실행"* ]]
}

@test "cross-run: a context event with non-string file does not kill the whole warning [review M2]" {
  mkdir -p .claude
  cat > .claude/acl-events.jsonl <<'EOF'
{"ts":"t1","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L0","count":1}
{"ts":"t2","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L1","count":2}
{"ts":"t3","event":"error.recorded","type":"BUILD_FAIL","file":"a","level":"L1","count":3}
{"ts":"t4","event":"context.read.large","file":42,"lines":900}
{"ts":"t5","event":"context.read.large","file":null,"lines":900}
{"ts":"t6","event":"context.read.large","file":"C:\\p\\docs\\SPEC.md","lines":900}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"BUILD_FAIL"* ]]
  [[ "$ctx" == *"긴 파일 통째 읽기 ×3회"* ]]
  [[ "$ctx" == *"SPEC.md×1"* ]]
}
