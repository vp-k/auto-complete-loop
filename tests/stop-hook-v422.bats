#!/usr/bin/env bats
# stop-hook-v422.bats — v4.22.0
#   (H2) implement 워크플로우 완주에 codeReviewFindings=pass 요구 (DoD 자기신고 차단)
#   (M8) jq 부재 시 fail-open(approve) → block (탈출구는 ACL_ALLOW_NO_JQ=1)
#   (M9) LESSON 추출이 실제 경로/타입(phases.phase_2.scopeReductions, handoff.warnings 문자열)을 읽는다
#   (M3) plan-docs-full 완료 조건이 실제 스키마(최상위 documents)를 가리킨다
#   (M12) session-start의 ACL_RUN_ID는 가장 최근 progress 파일에서 고른다

load test_helper

HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
SESSION_HOOK="$SCRIPT_DIR/../hooks/session-start.sh"
VF=".claude-verification.json"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

# $1=progress 파일명, $2=promise 태그
_ralph_state() {
  mkdir -p .claude
  cat > .claude/ralph-loop.local.md <<EOF
---
iteration: 1
max_iterations: 50
completion_promise: $2
progress_file: $1
---

작업 프롬프트 본문
EOF
  cat > transcript.jsonl <<EOF
{"role":"assistant","message":{"content":[{"type":"text","text":"완료 <promise>$2</promise>"}]}}
EOF
  printf '{"transcript_path":"%s/transcript.jsonl"}' "$TEST_DIR" > hook-input.json
}

_run_hook() {
  run bash -c "cd '$TEST_DIR' && bash '$HOOK' < hook-input.json"
}

# ─── H2: implement 워크플로우는 code-review-findings 게이트 증거를 요구 ───

@test "implement: dod.code_review_pass만 checked면 완주가 차단된다" {
  _ralph_state ".claude-progress.json" "IMPLEMENT_COMPLETE"
  cat > .claude-progress.json <<'EOF'
{
  "schemaVersion": 8,
  "steps": [{"name":"s1","status":"completed"}],
  "dod": {"code_review_pass": {"checked": true, "evidence": "모델이 직접 세팅한 값"}}
}
EOF
  printf '%s\n' '{"build":{"exitCode":0}}' > "$VF"
  _run_hook
  [[ "$output" == *"codeReviewFindings=missing"* ]]
  [[ "$output" == *"code-review-findings --round-kind"* ]]
}

@test "implement: codeReviewFindings=pass면 그 사유가 사라진다" {
  _ralph_state ".claude-progress.json" "IMPLEMENT_COMPLETE"
  cat > .claude-progress.json <<'EOF'
{
  "schemaVersion": 8,
  "steps": [{"name":"s1","status":"completed"}],
  "dod": {"code_review_pass": {"checked": true, "evidence": "gate"}}
}
EOF
  printf '%s\n' '{"build":{"exitCode":0},"codeReviewFindings":{"result":"pass","criticalOpen":0,"highOpen":0}}' > "$VF"
  _run_hook
  [[ "$output" != *"codeReviewFindings="* ]]
}

@test "implement: codeReviewFindings=fail도 차단된다" {
  _ralph_state ".claude-progress.json" "IMPLEMENT_COMPLETE"
  cat > .claude-progress.json <<'EOF'
{
  "schemaVersion": 8,
  "steps": [{"name":"s1","status":"completed"}],
  "dod": {"code_review_pass": {"checked": true, "evidence": "gate"}}
}
EOF
  printf '%s\n' '{"build":{"exitCode":0},"codeReviewFindings":{"result":"fail","criticalOpen":1,"highOpen":0}}' > "$VF"
  _run_hook
  [[ "$output" == *"codeReviewFindings=fail"* ]]
}

# ─── M8: jq 부재 ───

# jq를 담고 있는 PATH 디렉토리만 제거한다 (coreutils는 남긴다)
_path_without_jq() {
  local d out=""
  local IFS=":"
  for d in $PATH; do
    [[ -n "$d" ]] || continue
    if [[ -x "$d/jq" ]] || [[ -x "$d/jq.exe" ]]; then continue; fi
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}

@test "jq 부재: Ralph 루프가 활성이면 approve하지 않고 block한다" {
  local np
  np=$(_path_without_jq)
  PATH="$np" command -v date >/dev/null 2>&1 || skip "축소된 PATH에서 date를 찾을 수 없음"
  PATH="$np" command -v jq >/dev/null 2>&1 && skip "PATH에서 jq를 제거하지 못함"

  _ralph_state ".claude-progress.json" "IMPLEMENT_COMPLETE"
  run bash -c "cd '$TEST_DIR' && PATH='$np' bash '$HOOK' < hook-input.json"
  [[ "$output" == *'"decision": "block"'* ]]
  [[ "$output" != *'"decision": "approve"'* ]]
  [[ "$output" == *"jq"* ]]
  grep -q '"event":"jq_missing_block"' .claude/acl-events.jsonl
}

@test "jq 부재: ACL_ALLOW_NO_JQ=1 이면 명시적으로 승인한다" {
  local np
  np=$(_path_without_jq)
  PATH="$np" command -v date >/dev/null 2>&1 || skip "축소된 PATH에서 date를 찾을 수 없음"
  PATH="$np" command -v jq >/dev/null 2>&1 && skip "PATH에서 jq를 제거하지 못함"

  _ralph_state ".claude-progress.json" "IMPLEMENT_COMPLETE"
  run bash -c "cd '$TEST_DIR' && PATH='$np' ACL_ALLOW_NO_JQ=1 bash '$HOOK' < hook-input.json"
  [[ "$output" == *'"decision": "approve"'* ]]
  grep -q '"event":"jq_missing_bypass"' .claude/acl-events.jsonl
}

@test "jq 부재: Ralph 루프가 없으면 차단하지 않는다 (일반 세션 보호)" {
  local np
  np=$(_path_without_jq)
  PATH="$np" command -v date >/dev/null 2>&1 || skip "축소된 PATH에서 date를 찾을 수 없음"
  PATH="$np" command -v jq >/dev/null 2>&1 && skip "PATH에서 jq를 제거하지 못함"

  printf '{}' > hook-input.json
  run bash -c "cd '$TEST_DIR' && PATH='$np' bash '$HOOK' < hook-input.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision": "block"'* ]]
}

# ─── M9: LESSON 추출 경로/타입 ───

@test "LESSON: scopeReductions(phases.phase_2 객체 배열)와 warnings(문자열)가 실제로 실린다" {
  _ralph_state ".claude-plan-progress.json" "PLAN_COMPLETE"
  cat > .claude-plan-progress.json <<'EOF'
{
  "schemaVersion": 8,
  "documents": [{"name":"d1","status":"completed"}],
  "dod": {"k": {"checked": true, "evidence": "e"}},
  "phases": {"phase_2": {"scopeReductions": [
    {"feature":"실시간 알림","original":"WebSocket","reduced":"30초 폴링","reason":"연결 안정성 4회 실패","ticket":"POST_RELEASE_001"}
  ]}},
  "handoff": {"lastIteration": 1, "nextSteps": "n", "keyDecisions": ["JWT 채택"], "warnings": "부하 테스트 미수행"}
}
EOF
  printf '%s\n' '{}' > "$VF"
  _run_hook
  [[ "$output" == *"Promise verified"* ]]
  [ -f .claude/acl-learnings.local.md ]
  grep -q "Scope reductions: 실시간 알림 → 30초 폴링" .claude/acl-learnings.local.md
  grep -q "POST_RELEASE_001" .claude/acl-learnings.local.md
  grep -q "Warnings: 부하 테스트 미수행" .claude/acl-learnings.local.md
}

@test "LESSON: 범위 축소·경고가 없으면 결정만 실린다 (거짓 경고 없음)" {
  _ralph_state ".claude-plan-progress.json" "PLAN_COMPLETE"
  cat > .claude-plan-progress.json <<'EOF'
{
  "schemaVersion": 8,
  "documents": [{"name":"d1","status":"completed"}],
  "dod": {"k": {"checked": true, "evidence": "e"}},
  "handoff": {"lastIteration": 1, "nextSteps": "n", "keyDecisions": ["JWT 채택"], "warnings": ""}
}
EOF
  printf '%s\n' '{}' > "$VF"
  _run_hook
  [[ "$output" == *"Promise verified"* ]]
  grep -q "Decisions: JWT 채택" .claude/acl-learnings.local.md
  ! grep -q "Warnings:" .claude/acl-learnings.local.md
  ! grep -q "Scope reductions:" .claude/acl-learnings.local.md
}

# ─── M3: plan-docs-full 완료 조건이 실제 스키마를 가리킨다 ───

@test "docs: plan-docs-full 완료 조건이 최상위 documents를 요구한다" {
  local f="$SCRIPT_DIR/../commands/plan-docs-full.md"
  grep -q '최상위 `documents` 배열' "$f"
  # 검사되지 않는 구조(phases.phase_0/phase_1의 step 상태)를 완료 조건으로 요구하지 않는다
  ! grep -q '`phases.phase_0`.*`steps`.*completed' "$f"
}

# ─── M12: session-start ACL_RUN_ID는 최신 progress에서 ───

@test "session-start: runId는 가장 최근에 갱신된 progress 파일에서 고른다" {
  mkdir -p .claude
  printf '%s\n' '{"runId":"run-OLD"}' > .claude-full-auto-progress.json
  printf '%s\n' '{"runId":"run-NEW"}' > .claude-progress.json
  # 이름순이면 full-auto가 먼저다 — mtime으로 .claude-progress.json을 최신으로 만든다
  touch -d '2020-01-01 00:00:00' .claude-full-auto-progress.json 2>/dev/null || touch -t 202001010000 .claude-full-auto-progress.json
  touch .claude-progress.json

  cat > .claude/acl-decisions.jsonl <<'EOF'
{"id":"D-0001","runId":"run-OLD","what":"옛 실행의 결정","why":"이전 실행 기록"}
{"id":"D-0002","runId":"run-NEW","what":"이번 실행의 결정","why":"현재 실행 기록"}
EOF
  run bash "$SESSION_HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"D-0002"* ]]
  [[ "$ctx" != *"D-0001"* ]]
}
