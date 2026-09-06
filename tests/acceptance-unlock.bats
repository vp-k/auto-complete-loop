#!/usr/bin/env bats
# acceptance-unlock.bats — 승인 기반 동결 해제 토큰(v4.18.0) 계약 고정
#
# 배경: 동결 후 SPEC/인수 테스트는 protect-files-guard 가 영구 차단하는데,
# 스킬이 정한 정상 절차는 "사용자 승인 → SPEC 갱신 → 재동결"이었다(= 실행 불가한 모순).
# acceptance-unlock 토큰이 그 승인의 기계 판독 증거이며, 재동결이 토큰을 소비한다.
# 여기서 고정하는 계약:
#   (1) 승인/사유 없는 unlock 거부
#   (2) 토큰 존재 시 가드가 SPEC.md / tests/acceptance/** 허용 (overview.md 는 계속 차단)
#   (3) 재동결이 토큰을 소비하고 사유를 refreezeHistory 에 기록
#   (4) 토큰 잔존 시 acceptance-gate FAIL + stop-hook 완주 차단
#   (5) 러너 실패는 1회 재시도 — 2회차 green 이면 soft_fail(flaky) 로 기록, 재실행 1회차 green 이어야 pass
#   (6) 동결 후 파일 "추가"는 WARN(비차단), "변조"는 FAIL

load test_helper

PLUGIN_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
GUARD_HOOK="$PLUGIN_ROOT/hooks/protect-files-guard.sh"
STOP_HOOK="$PLUGIN_ROOT/hooks/stop-hook.sh"

MANIFEST="tests/acceptance/.manifest.json"
TOKEN=".claude/acceptance-unlock.json"
VERIF=".claude-verification.json"

setup() {
  setup_temp_dir
  # 기획 단계 progress → 무승인 최초 동결 허용
  printf '{}\n' > .claude-plan-progress.json
  mkdir -p tests/acceptance .claude
  cat > tests/acceptance/run.sh <<'EOF'
#!/bin/sh
echo "ACCEPTANCE_RESULT: total=1 passed=1 failed=0"
exit 0
EOF
  printf '# t1\n' > tests/acceptance/t1.sh
  cat > SPEC.md <<'EOF'
## Success Criteria
- SC-1: 기준
EOF
}
teardown() { teardown_temp_dir; }

freeze() { run_gate acceptance-freeze --progress-file .claude-plan-progress.json; }

# stdin JSON 을 protect-files-guard 로 흘려 BLOCK/WARN/PASS 판정
guard() {
  local out
  out=$(jq -n --arg p "$1" '{tool_input:{file_path:$p}}' | bash "$GUARD_HOOK" 2>/dev/null || true)
  if printf '%s' "$out" | grep -q '"decision": *"block"'; then
    echo "BLOCK"
  elif printf '%s' "$out" | grep -q 'systemMessage'; then
    echo "WARN"
  else
    echo "PASS"
  fi
}

# ─── (1) unlock 발급 조건 ───

@test "unlock: --approved-by-user 없으면 거부 (토큰 미생성)" {
  freeze
  run run_gate acceptance-unlock --reason "AC-B-001 오탈자"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  [ ! -f "$TOKEN" ]
}

@test "unlock: --reason 없으면 거부 (사유 기록 의무)" {
  freeze
  run run_gate acceptance-unlock --approved-by-user
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED"* ]]
  [ ! -f "$TOKEN" ]
}

@test "unlock: 승인+사유가 있으면 토큰 발급 (사유/SPEC 해시 기록)" {
  freeze
  run run_gate acceptance-unlock --approved-by-user --reason "AC-B-001 이 스펙과 모순"
  [ "$status" -eq 0 ]
  [ -f "$TOKEN" ]
  [ "$(jq -r '.reason' "$TOKEN")" = "AC-B-001 이 스펙과 모순" ]
  [ "$(jq -r '.approvedByUser' "$TOKEN")" = "true" ]
  [ "$(jq -r '.specPath' "$TOKEN")" = "SPEC.md" ]
  [ "$(jq -r '.specHashAtUnlock' "$TOKEN")" != "null" ]
}

# ─── (2) 가드 완화 범위 ───

@test "guard: 토큰 없으면 동결된 인수 테스트 편집 차단" {
  freeze
  [ "$(guard 'tests/acceptance/t1.sh')" = "BLOCK" ]
}

@test "guard: 토큰이 있으면 인수 테스트 편집 허용 (경고만)" {
  freeze
  run_gate acceptance-unlock --approved-by-user --reason "AC 수정"
  [ "$(guard 'tests/acceptance/t1.sh')" = "WARN" ]
}

@test "guard: 토큰이 있으면 SPEC.md 허용, overview.md 는 계속 차단" {
  freeze
  printf '{"currentPhase":"phase_2"}\n' > .claude-full-auto-progress.json
  [ "$(guard 'SPEC.md')" = "BLOCK" ]
  run_gate acceptance-unlock --approved-by-user --reason "스펙 모순 수정"
  [ "$(guard 'SPEC.md')" = "WARN" ]
  [ "$(guard 'docs/overview.md')" = "BLOCK" ]
  [ "$(guard 'CLAUDE.md')" = "BLOCK" ]
}

# ─── (3) 재동결이 토큰을 소비 ───

@test "freeze: --approved-by-user 재동결이 토큰을 소비하고 사유를 기록" {
  freeze
  run_gate acceptance-unlock --approved-by-user --reason "AC-B-001 재정의"
  [ -f "$TOKEN" ]
  printf '# t1 (스펙 변경 반영)\n' > tests/acceptance/t1.sh
  run run_gate acceptance-freeze --progress-file .claude-plan-progress.json --approved-by-user
  [ "$status" -eq 0 ]
  [ ! -f "$TOKEN" ]
  [ "$(jq -r '.refreezeHistory[-1].reason' "$MANIFEST")" = "AC-B-001 재정의" ]
  [ "$(jq -r '.refreezeHistory[-1].unlockConsumed' "$MANIFEST")" = "true" ]
}

@test "freeze: --approved-by 로 승인 출처를 기록 (--start-phase 무인 재개)" {
  run run_gate acceptance-freeze --progress-file .claude-plan-progress.json \
    --approved-by-user --reason "start-phase skip" --approved-by "--start-phase flag"
  [ "$status" -eq 0 ]
  run_gate acceptance-unlock --approved-by-user --reason "x"
  run run_gate acceptance-freeze --progress-file .claude-plan-progress.json \
    --approved-by-user --reason "start-phase skip" --approved-by "--start-phase flag"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.refreezeHistory[-1].approvedBy' "$MANIFEST")" = "--start-phase flag" ]
}

# ─── (4) 토큰 잔존 = 열린 문 → 게이트/훅 차단 ───

@test "gate: 토큰이 남아 있으면 FAIL (unlock pending — re-freeze first)" {
  freeze
  run_gate acceptance-unlock --approved-by-user --reason "AC 수정 중"
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"unlock pending"* ]]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "fail" ]
}

@test "gate: 재동결 후에는 다시 PASS" {
  freeze
  run_gate acceptance-unlock --approved-by-user --reason "AC 수정"
  run_gate acceptance-freeze --progress-file .claude-plan-progress.json --approved-by-user
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "pass" ]
}

@test "stop-hook: full-auto 완주 시 토큰 잔존이면 차단 사유에 포함" {
  cat > .claude/ralph-loop.local.md <<'EOF'
---
iteration: 1
max_iterations: 10
completion_promise: ALL_DONE
progress_file: .claude-full-auto-progress.json
---
body
EOF
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"<promise>ALL_DONE</promise>"}]}}\n' > transcript.jsonl
  printf '{"steps":[{"name":"phase_4","status":"completed"}],"dod":{"x":{"checked":true}}}\n' > .claude-full-auto-progress.json
  printf '{}\n' > "$VERIF"
  printf '{"reason":"AC 수정 중"}\n' > "$TOKEN"

  run bash -c "jq -n --arg t '$PWD/transcript.jsonl' '{transcript_path:\$t}' | bash '$STOP_HOOK' 2>&1"
  [[ "$output" == *"acceptance unlock 토큰 잔존"* ]]
  [[ "$output" == *"acceptance-freeze --approved-by-user"* ]]
}

@test "stop-hook: 토큰이 없으면 그 사유는 나오지 않는다 (오탐 회귀)" {
  cat > .claude/ralph-loop.local.md <<'EOF'
---
iteration: 1
max_iterations: 10
completion_promise: ALL_DONE
progress_file: .claude-full-auto-progress.json
---
body
EOF
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"<promise>ALL_DONE</promise>"}]}}\n' > transcript.jsonl
  printf '{"steps":[{"name":"phase_4","status":"completed"}],"dod":{"x":{"checked":true}}}\n' > .claude-full-auto-progress.json
  printf '{}\n' > "$VERIF"

  run bash -c "jq -n --arg t '$PWD/transcript.jsonl' '{transcript_path:\$t}' | bash '$STOP_HOOK' 2>&1"
  [[ "$output" != *"acceptance unlock 토큰 잔존"* ]]
}

# ─── (5) flaky 재시도 ───

@test "gate: 1회 실패 후 2회차 green 이면 soft_fail(flaky=true) — 완주 차단, 재실행 1회차 green 이면 pass" {
  cat > tests/acceptance/run.sh <<'EOF'
#!/bin/sh
C="$(dirname "$0")/../../.flaky-count"
n=0
[ -f "$C" ] && n=$(cat "$C")
n=$((n+1)); echo "$n" > "$C"
if [ "$n" -eq 1 ]; then
  echo "ACCEPTANCE_RESULT: total=1 passed=0 failed=1"
  exit 1
fi
echo "ACCEPTANCE_RESULT: total=1 passed=1 failed=0"
exit 0
EOF
  freeze
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"FLAKY"* ]]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "soft_fail" ]
  [ "$(jq -r '.acceptanceTests.flaky' "$VERIF")" = "true" ]
  [ "$(jq -r '.acceptanceTests.firstRun.failed' "$VERIF")" = "1" ]
  # dod.acceptance_pass 는 pass 에서만 기록된다
  [ "$(jq -r '.dod.acceptance_pass.checked // false' .claude-plan-progress.json)" != "true" ]
  # 비결정성 제거 후(카운터가 이미 1을 넘었으므로 이제 1회차부터 green) 재실행 → pass, flaky 표식 없음
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "pass" ]
  [ "$(jq -r '.acceptanceTests.flaky // "absent"' "$VERIF")" = "absent" ]
}

@test "gate: 2회 연속 실패는 FAIL (retried=true 기록)" {
  cat > tests/acceptance/run.sh <<'EOF'
#!/bin/sh
echo "ACCEPTANCE_RESULT: total=1 passed=0 failed=1"
exit 1
EOF
  freeze
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "fail" ]
  [ "$(jq -r '.acceptanceTests.retried' "$VERIF")" = "true" ]
}

# ─── (6) 추가 = WARN / 변조 = FAIL ───

@test "gate: 동결 후 파일 추가는 WARN (비차단, addedFiles 기록)" {
  freeze
  printf '# t2 (추가 어서션)\n' > tests/acceptance/t2.sh
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "pass" ]
  [ "$(jq -r '.acceptanceTests.addedFiles | index("tests/acceptance/t2.sh") != null' "$VERIF")" = "true" ]
}

@test "gate: 동결 후 파일 변조는 여전히 FAIL" {
  freeze
  printf '# t1 (어서션 약화)\n' > tests/acceptance/t1.sh
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "fail" ]
  [ "$(jq -r '.acceptanceTests.tamperedFiles[0]' "$VERIF")" = "tests/acceptance/t1.sh" ]
}

@test "gate: 동결된 파일 삭제는 FAIL (추가 WARN 완화가 삭제까지 열지 않는다)" {
  freeze
  rm -f tests/acceptance/t1.sh
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [ "$(jq -r '.acceptanceTests.result' "$VERIF")" = "fail" ]
}

# ─── (6) 토큰 위조 차단 ───

@test "guard: acceptance-unlock.json 직접 Write/Edit 는 토큰 유무와 무관하게 BLOCK" {
  freeze
  [ "$(guard "$PWD/.claude/acceptance-unlock.json")" = "BLOCK" ]
  run_gate acceptance-unlock --approved-by-user --reason "정당한 unlock"
  [ -f "$TOKEN" ]
  [ "$(guard "$PWD/.claude/acceptance-unlock.json")" = "BLOCK" ]
}

@test "stop-hook: plan-docs-full 워크플로우에서도 토큰 잔존이면 차단 (full-auto 전용이던 검사 공통화)" {
  cat > .claude/ralph-loop.local.md <<'EOF'
---
iteration: 1
max_iterations: 10
completion_promise: PLAN_DONE
progress_file: .claude-plan-docs-full-progress.json
---
body
EOF
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":"<promise>PLAN_DONE</promise>"}]}}\n' > transcript.jsonl
  printf '{"steps":[{"name":"phase_1","status":"completed"}],"dod":{"x":{"checked":true}}}\n' > .claude-plan-docs-full-progress.json
  printf '{}\n' > "$VERIF"
  printf '{"reason":"plan-docs-full 재동결 전"}\n' > "$TOKEN"

  run bash -c "jq -n --arg t '$PWD/transcript.jsonl' '{transcript_path:\$t}' | bash '$STOP_HOOK' 2>&1"
  [[ "$output" == *"acceptance unlock 토큰 잔존"* ]]
}
