#!/usr/bin/env bats
# code-review-findings.bats — 리뷰 finding 게이트 + sourceHash 귀속 (v4.9.0)

load test_helper

PF=".claude-review-loop-progress.json"

setup() {
  setup_temp_dir
  # 사용자/시스템 git 설정 격리 (commit.gpgsign, hooksPath, init 템플릿 등으로 인한 flake 방지)
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

# $1=sourceHash (빈 값이면 필드 생략 — 레거시 형상)
seed_progress() {
  local sh="${1:-}"
  if [[ -n "$sh" ]]; then
    jq -n --arg h "$sh" '{
      findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
      roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{}}}]
    }' > "$PF"
  else
    jq -n '{
      findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
      roundResults: [{round:1, findings:{bySeverity:{}}}]
    }' > "$PF"
  fi
}

@test "source-hash: prints fingerprint in git repo, exit 0" {
  run run_gate source-hash
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]+- ]]
}

@test "source-hash: prints no-git outside a repo, exit 0" {
  cd "$(mktemp -d)"
  run run_gate source-hash
  [ "$status" -eq 0 ]
  [ "$output" = "no-git" ]
}

@test "gate: passes when last round sourceHash matches current fingerprint" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "pass" ]
}

@test "gate: stale fail when code edited after last recorded round (laundering case)" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  echo b >> f.txt   # 미커밋 편집 — 리뷰 이후 무리뷰 변경
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "stale" ]
}

@test "gate: stale fail even with zero open findings (stale 0-finding round)" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  echo b >> f.txt
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
}

@test "gate: missing fail for legacy round without sourceHash in a git repo" {
  seed_progress ""
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "missing" ]
}

@test "gate: skip hash check outside a git repo (backward compat)" {
  cd "$(mktemp -d)"
  seed_progress ""
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "skip" ]
}

@test "gate: open CRITICAL/HIGH still fails with matching hash" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-CRITICAL-001",severity:"CRITICAL",status:"open"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{CRITICAL:1}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"open CRITICAL/HIGH"* ]]
}

@test "gate: deferred CRITICAL counts as open — laundering via status blocked (v4.16.0)" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-CRITICAL-001",severity:"CRITICAL",status:"deferred"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{CRITICAL:1}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"open CRITICAL/HIGH"* ]]
}

@test "gate: regressed HIGH counts as open (v4.16.0)" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"ERR-HIGH-002",severity:"HIGH",status:"regressed"}],
    roundResults: [{round:2, sourceHash:$h, findings:{bySeverity:{HIGH:1}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"open CRITICAL/HIGH"* ]]
}

@test "gate: deferred MEDIUM/LOW does not block (convergence-round backlog)" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [
      {id:"PERF-MEDIUM-003",severity:"MEDIUM",status:"deferred"},
      {id:"CODE-LOW-004",severity:"LOW",status:"deferred"}
    ],
    roundResults: [{round:3, sourceHash:$h, findings:{bySeverity:{MEDIUM:1,LOW:1}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
}

@test "gate: dismissed CRITICAL still passes (rationale-recorded dismissal unaffected)" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-CRITICAL-005",severity:"CRITICAL",status:"dismissed"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{}}}]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
}

@test "gate: nested phases.phase_3 shape works with sourceHash" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    phases: {phase_3: {
      findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
      roundResults: [{round:1, sourceHash:$h, critical:0, high:0, medium:0, low:0}]
    }}
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "pass" ]
}

@test "gate: both arrays present — lastRound and hash check use the same (concatenated) last entry" {
  fp=$(run_gate source-hash)
  # top-level에 stale 라운드, phase_3에 현재 지문 라운드 → 연결 순서상 phase_3 마지막이 승자
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
    roundResults: [{round:1, sourceHash:"stale-old-hash", findings:{bySeverity:{}}}],
    phases: {phase_3: {roundResults: [{round:2, sourceHash:$h, critical:0, high:0, medium:0, low:0}]}}
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.codeReviewFindings.sourceHashCheck' .claude-verification.json)" = "pass" ]
}

@test "gate: only an earlier round matches current fingerprint — still stale-fail" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed"}],
    roundResults: [
      {round:1, sourceHash:$h, findings:{bySeverity:{}}},
      {round:2, sourceHash:"different-later-hash", findings:{bySeverity:{}}}
    ]
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "gate: escalated round followed by fresh recording round passes" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    phases: {phase_3: {
      findingHistory: [{id:"SEC-HIGH-001",severity:"HIGH",status:"fixed",escalated:true}],
      roundResults: [
        {round:1, escalated:true, reviewMode:"roundtable", sourceHash:"pre-fix-hash", critical:0, high:1, medium:0, low:0},
        {round:2, sourceHash:$h, critical:0, high:0, medium:0, low:0}
      ]
    }}
  }' > "$PF"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
}

@test "gate: recording progress/verification files does not perturb the fingerprint" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  # 게이트 실행이 .claude-verification.json을 썼지만 지문은 불변 (.claude* 제외)
  fp2=$(run_gate source-hash)
  [ "$fp" = "$fp2" ]
}

# ─── (M5) 리뷰 라운드 카운터: 게이트가 센다 (모델 자기 계수 아님) ───

@test "round-counter: --round-kind fix만 withFixes를 올리고 verify/rerecord는 total만 올린다" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "1" ]
  [ "$(jq -r '.reviewRounds.total' .claude-verification.json)" = "1" ]

  run_gate code-review-findings --progress-file "$PF" --round-kind verify
  run_gate code-review-findings --progress-file "$PF" --round-kind rerecord
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "1" ]
  [ "$(jq -r '.reviewRounds.total' .claude-verification.json)" = "3" ]
  [ "$(jq -r '.reviewRounds.cap' .claude-verification.json)" = "5" ]
  [ "$(jq -r '.reviewRounds.lastKind' .claude-verification.json)" = "rerecord" ]
}

@test "round-counter: 기본 round-kind는 verify (기존 호출부 동작 보존)" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "0" ]
  [ "$(jq -r '.reviewRounds.total' .claude-verification.json)" = "1" ]
  [[ "$output" == *"라운드 계수"* ]]
}

@test "round-counter: 소스가 바뀌었는데 verify로 신고하면 fix로 계상한다 (자기신고 세탁 차단)" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "1" ]
  [ "$(jq -r '.reviewRounds.sourceHash' .claude-verification.json)" = "$fp" ]

  # 코드를 고치고(지문 변경) 리뷰 라운드를 다시 기록한 뒤 '확인 전용'이라고 신고
  echo b >> f.txt
  fp2=$(run_gate source-hash)
  [ "$fp" != "$fp2" ]
  seed_progress "$fp2"
  run run_gate code-review-findings --progress-file "$PF" --round-kind verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"(fix)로 계상한다"* ]]
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "2" ]
  [ "$(jq -r '.reviewRounds.lastKind' .claude-verification.json)" = "fix" ]
  [ "$(jq -r '.reviewRounds.declaredKind' .claude-verification.json)" = "verify" ]

  # 소스 불변이면 신고대로 verify (계수 안 함)
  run run_gate code-review-findings --progress-file "$PF" --round-kind verify
  [ "$status" -eq 0 ]
  [[ "$output" != *"(fix)로 계상한다"* ]]
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "2" ]
  [ "$(jq -r '.reviewRounds.lastKind' .claude-verification.json)" = "verify" ]
}

@test "round-counter: 잘못된 --round-kind는 거부" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF" --round-kind nope
  [ "$status" -ne 0 ]
}

@test "round-counter: 수정 라운드 5회 후 open C/H가 남으면 REVIEW_ROUND_CAP 에스컬레이션을 요구" {
  fp=$(run_gate source-hash)
  jq -n --arg h "$fp" '{
    findingHistory: [{id:"SEC-CRIT-001",severity:"CRITICAL",status:"open"}],
    roundResults: [{round:1, sourceHash:$h, findings:{bySeverity:{}}}]
  }' > "$PF"

  local i
  for i in 1 2 3 4; do
    run_gate code-review-findings --progress-file "$PF" --round-kind fix || true
  done
  run run_gate code-review-findings --progress-file "$PF" --round-kind fix
  [ "$status" -ne 0 ]
  [[ "$output" == *"REVIEW_ROUND_CAP reached"* ]]
  [[ "$output" == *"--type REVIEW_ROUND_CAP --level L2"* ]]
  [ "$(jq -r '.reviewRounds.withFixes' .claude-verification.json)" = "5" ]
}
