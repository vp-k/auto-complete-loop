#!/usr/bin/env bats
# code-review-findings.bats — 리뷰 finding 게이트 + sourceHash 귀속 (v4.9.0)

load test_helper

PF=".claude-review-loop-progress.json"

setup() {
  setup_temp_dir
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

@test "gate: recording progress/verification files does not perturb the fingerprint" {
  fp=$(run_gate source-hash)
  seed_progress "$fp"
  run run_gate code-review-findings --progress-file "$PF"
  [ "$status" -eq 0 ]
  # 게이트 실행이 .claude-verification.json을 썼지만 지문은 불변 (.claude* 제외)
  fp2=$(run_gate source-hash)
  [ "$fp" = "$fp2" ]
}
