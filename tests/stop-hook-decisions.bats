#!/usr/bin/env bats
# stop-hook-decisions.bats — 완주 시점 기록 3종 fail-closed
#   (a) handoff.lastIteration 갱신  (b) iteration별 결정 기록  (c) assumptionReview

load test_helper

HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

PROG=".claude-plan-docs-full-progress.json"

# iteration N에서 promise를 선언한 상태를 만든다.
# decision_log=true 면 v4.20.0 스키마(decisionLog.enabled), false 면 구버전 progress.
_fixture() {
  local iter="${1:-2}" decision_log="${2:-true}"
  mkdir -p .claude
  cat > .claude/ralph-loop.local.md <<EOF
---
iteration: $iter
max_iterations: 50
completion_promise: PLAN_DOCS_COMPLETE
progress_file: $PROG
---

작업 프롬프트 본문
EOF

  cat > "$PROG" <<EOF
{
  "schemaVersion": 8,
  "steps": [{"name": "s1", "status": "completed"}],
  "dod": {"k": {"checked": true, "evidence": "e"}},
  "handoff": {"lastIteration": 0, "nextSteps": "n", "keyDecisions": []}
}
EOF
  if [[ "$decision_log" == "true" ]]; then
    jq '.decisionLog = {"enabled": true}' "$PROG" > "$PROG.tmp" && mv "$PROG.tmp" "$PROG"
  fi

  echo '{}' > .claude-verification.json

  cat > transcript.jsonl <<'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"완료했습니다. <promise>PLAN_DOCS_COMPLETE</promise>"}]}}
EOF
  printf '{"transcript_path":"%s/transcript.jsonl"}' "$TEST_DIR" > hook-input.json
}

_run_hook() {
  run bash -c "cd '$TEST_DIR' && bash '$HOOK' < hook-input.json"
}

# ─── (a) handoff.lastIteration ───

@test "stop-hook: handoff.lastIteration이 이번 iteration과 다르면 차단" {
  _fixture 2 true
  _run_hook
  [[ "$output" == *"handoff.lastIteration=0 (이번 iteration=2)"* ]]
  [[ "$output" == *"handoff-update"* ]]
}

@test "stop-hook: handoff.lastIteration이 일치하면 그 사유는 사라진다" {
  _fixture 2 true
  jq '.handoff.lastIteration = 2' "$PROG" > t && mv t "$PROG"
  _run_hook
  [[ "$output" != *"handoff.lastIteration"* ]]
}

# ─── (b) iteration별 결정 기록 ───

@test "stop-hook: 이번 iteration의 결정 기록이 0건이면 차단" {
  _fixture 2 true
  _run_hook
  [[ "$output" == *"iteration 2의 결정 기록 없음"* ]]
  [[ "$output" == *"record-decision --none"* ]]
}

@test "stop-hook: 다른 iteration의 결정은 이번 iteration을 대신하지 못한다" {
  _fixture 2 true
  mkdir -p .claude
  printf '%s\n' '{"id":"D-0001","iteration":1,"kind":"decision","what":"w","why":"y"}' > .claude/acl-decisions.jsonl
  _run_hook
  [[ "$output" == *"iteration 2의 결정 기록 없음"* ]]
}

@test "stop-hook: 이번 iteration의 결정이 있으면 그 사유는 사라진다" {
  _fixture 2 true
  printf '%s\n' '{"id":"D-0001","iteration":2,"kind":"decision","what":"w","why":"y"}' > .claude/acl-decisions.jsonl
  _run_hook
  [[ "$output" != *"결정 기록 없음"* ]]
}

@test "stop-hook: kind=none도 이번 iteration의 기록으로 인정된다" {
  _fixture 3 true
  printf '%s\n' '{"id":"D-0001","iteration":3,"kind":"none","what":"w","why":"y"}' > .claude/acl-decisions.jsonl
  _run_hook
  [[ "$output" != *"결정 기록 없음"* ]]
}

# ─── (c) assumptionReview ───

@test "stop-hook: assumptionReview 키가 없으면 차단 (plan-docs-full)" {
  _fixture 2 true
  _run_hook
  [[ "$output" == *"assumptionReview 미기록"* ]]
}

@test "stop-hook: assumptionReview.status=confirmed면 통과" {
  _fixture 2 true
  jq '.assumptionReview = {"status":"confirmed","count":2}' "$PROG" > t && mv t "$PROG"
  _run_hook
  [[ "$output" != *"assumptionReview 미기록"* ]]
}

@test "stop-hook: assumptionReview.status=none / escalated도 허용" {
  _fixture 2 true
  jq '.assumptionReview = {"status":"none","count":0}' "$PROG" > t && mv t "$PROG"
  _run_hook
  [[ "$output" != *"assumptionReview 미기록"* ]]

  jq '.assumptionReview = {"status":"escalated","count":0}' "$PROG" > t && mv t "$PROG"
  _run_hook
  [[ "$output" != *"assumptionReview 미기록"* ]]
}

@test "stop-hook: 알 수 없는 assumptionReview.status는 차단 (임의 값 세탁 방지)" {
  _fixture 2 true
  jq '.assumptionReview = {"status":"ok","count":9}' "$PROG" > t && mv t "$PROG"
  _run_hook
  [[ "$output" == *"assumptionReview 미기록"* ]]
}

# ─── 하위호환: decisionLog.enabled 없는 progress ───

@test "stop-hook: decisionLog.enabled가 없으면 검사 대신 NOTE 1줄만 (구버전 progress)" {
  _fixture 2 false
  _run_hook
  [[ "$output" == *"decisionLog.enabled가 없어 결정 기록 검사를 건너뜁니다"* ]]
  [[ "$output" != *"결정 기록 없음"* ]]
  [[ "$output" != *"handoff.lastIteration"* ]]
  [[ "$output" != *"assumptionReview 미기록"* ]]
}

# ─── 무한 block 루프 방지: continue 경로는 차단하지 않고 리마인더만 ───

@test "stop-hook: promise 없는 iteration은 차단이 아니라 프롬프트 리마인더로 알린다" {
  _fixture 2 true
  cat > transcript.jsonl <<'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"아직 작업 중입니다."}]}}
EOF
  _run_hook
  # continue 경로: block JSON이지만 이유는 "다음 프롬프트"이며 실패 사유 문구가 아니다
  [[ "$output" != *"Promise detected but verification failed"* ]]
  reason=$(printf '%s' "$output" | jq -rs 'map(select(type == "object" and has("reason")))[-1].reason' 2>/dev/null || echo "")
  [[ "$reason" == *"직전 iteration(2) 마감 누락"* ]]
  [[ "$reason" == *"record-decision"* ]]
}

@test "stop-hook: 마감이 끝난 iteration이면 리마인더가 붙지 않는다" {
  _fixture 2 true
  jq '.handoff.lastIteration = 2 | .assumptionReview = {"status":"none","count":0}' "$PROG" > t && mv t "$PROG"
  printf '%s\n' '{"id":"D-0001","iteration":2,"kind":"decision","what":"w","why":"y"}' > .claude/acl-decisions.jsonl
  cat > transcript.jsonl <<'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"아직 작업 중입니다."}]}}
EOF
  _run_hook
  reason=$(printf '%s' "$output" | jq -rs 'map(select(type == "object" and has("reason")))[-1].reason' 2>/dev/null || echo "")
  [[ "$reason" != *"마감 누락"* ]]
}
