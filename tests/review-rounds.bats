#!/usr/bin/env bats
# review-rounds.bats — v4.22.0
#   (M7) code-review-findings 인자 파서 fail-closed + --round-kind=값 형식
#   (M6) 게이트 자체 실패(리뷰 증거 없음 / sourceHash stale)는 라운드 예산을 쓰지 않는다
#   (H1) 문서의 게이트 호출 예시는 --round-kind를 반드시 동반한다

load test_helper

PF=".claude-review-loop-progress.json"
VF=".claude-verification.json"

setup() {
  setup_temp_dir
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  git init -q
  git config user.email t@t.t
  git config user.name tester
  echo a > f.txt
  git add f.txt
  git commit -qm init
}
teardown() { teardown_temp_dir; }

seed_progress() {
  jq -n --arg h "$1" '{
    findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{}}}]
  }' > "$PF"
}

# ─── M7: 인자 파서 ───

@test "round-kind: --round-kind=fix (등호 형식)도 수정 라운드로 계상" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF" --round-kind=fix
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewRounds.withFixes' "$VF")" = "1" ]
  [ "$(jq -r '.reviewRounds.lastKind' "$VF")" = "fix" ]
}

@test "round-kind: 알 수 없는 인자는 조용히 삼키지 않고 거부한다" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF" --round-knid fix
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
  # 거부됐으므로 라운드 카운터도 기록되지 않아야 한다
  if [ -f "$VF" ]; then
    [ "$(jq -r '.reviewRounds // "none"' "$VF")" = "none" ]
  fi
}

@test "round-kind: 잘못된 값은 여전히 거부" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF" --round-kind=nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"--round-kind must be one of"* ]]
}

# ─── M6: 게이트 자체 실패는 라운드 예산 비소모 ───

@test "round-counter: 리뷰 증거가 없으면 라운드를 계수하지 않는다" {
  jq -n '{findingHistory: [], roundResults: []}' > "$PF"
  run run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$status" -ne 0 ]
  [[ "$output" == *"no review evidence"* ]]
  [ "$(jq -r '.reviewRounds // "none"' "$VF")" = "none" ]
  [ "$(jq -r '.codeReviewFindings.result' "$VF")" = "fail" ]
}

@test "round-counter: sourceHash stale 재실행은 예산을 소모하지 않는다" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$(jq -r '.reviewRounds.withFixes' "$VF")" = "1" ]

  echo b >> f.txt
  git add f.txt
  git commit -qm change

  run run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$status" -ne 0 ]
  [[ "$output" == *"sourceHash=stale"* ]]
  [ "$(jq -r '.reviewRounds.withFixes' "$VF")" = "1" ]

  run run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$status" -ne 0 ]
  [ "$(jq -r '.reviewRounds.withFixes' "$VF")" = "1" ]
  [ "$(jq -r '.reviewRounds.total' "$VF")" = "1" ]
}

@test "round-counter: open C/H 실패는 성립한 라운드이므로 계수한다" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-CRIT-001",severity:"CRITICAL",status:"open"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$status" -ne 0 ]
  [ "$(jq -r '.reviewRounds.withFixes' "$VF")" = "1" ]
}

# ─── H1: 문서 회귀 방지 ───

@test "docs: 모든 code-review-findings 호출 예시가 --round-kind를 명시한다" {
  root="$SCRIPT_DIR/.."
  missing=""
  # CRLF 제거 + 백슬래시 줄이음 결합 후, 실제 실행 예시(`bash ...` 포함)만 검사한다
  # (게이트 이름을 언급만 하는 표 행은 호출부가 아니다)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" == *"--round-kind"* ]] || missing="${missing}${line}"$'\n'
  done < <(
    for f in $(grep -rl "shared-gate.sh code-review-findings" \
                 "$root/commands" "$root/skills" "$root/rules" "$root/templates" 2>/dev/null); do
      tr -d '\r' < "$f" \
        | sed -e :a -e '/\\$/N; s/\\\n/ /; ta' \
        | grep "shared-gate.sh code-review-findings" \
        | grep "bash " || true
    done
  )
  if [ -n "$missing" ]; then
    echo "--round-kind 누락 호출부:"
    echo "$missing"
    false
  fi
}

@test "docs: 문서에 jq_inplace(내부 함수) 사용 지시가 남아 있지 않다" {
  root="$SCRIPT_DIR/.."
  # 문서에서 jq_inplace를 "쓰라"고 지시하는 라인만 잡는다 (내부 함수임을 설명하는 문장은 허용)
  bad=$(grep -rhn "jq_inplace \"" "$root/commands" "$root/skills" "$root/rules" "$root/templates" 2>/dev/null || true)
  bad2=$(grep -rhn "jq_inplace {PROGRESS_FILE}" "$root/commands" "$root/skills" "$root/rules" "$root/templates" 2>/dev/null || true)
  [ -z "$bad" ] || { echo "$bad"; false; }
  [ -z "$bad2" ] || { echo "$bad2"; false; }
}
