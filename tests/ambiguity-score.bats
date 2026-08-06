#!/usr/bin/env bats
# ambiguity-score.bats — 명확성 4차원 정량 선행 인터뷰 게이트
# 채점=AI, 산술·판정·기록=스크립트. pass/continue/escalated + floor 맹점 차단 검증.

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

@test "ambiguity: all-high scores PASS (exit 0, recorded)" {
  run run_gate ambiguity-score --goal 0.9 --sc 0.85 --constraints 0.8 --context 1.0 --round 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"AMBIGUITY SCORE: PASS"* ]]
  [ "$(jq -r '.ambiguityScore.result' .claude-verification.json)" = "pass" ]
}

@test "ambiguity: weak dimension below threshold CONTINUE (exit 1) with weakest surfaced" {
  run run_gate ambiguity-score --goal 0.9 --sc 0.4 --constraints 0.8 --context 0.9 --round 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"AMBIGUITY SCORE: CONTINUE"* ]]
  [[ "$output" == *"SuccessCriteria"* ]]
  [ "$(jq -r '.ambiguityScore.weakest.dimension' .claude-verification.json)" = "SuccessCriteria" ]
}

@test "ambiguity: floor breach blocks even when composite >= threshold" {
  # composite = .95*.30 + .95*.25 + .55*.25 + .95*.20 = 0.86 (>=0.8) 이지만 Constraints 0.55 < floor 0.6
  run run_gate ambiguity-score --goal 0.95 --sc 0.95 --constraints 0.55 --context 0.95 --round 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"BREACHED"* ]]
  [[ "$output" == *"AMBIGUITY SCORE: CONTINUE"* ]]
}

@test "ambiguity: still-weak at max-rounds ESCALATES (exit 0)" {
  run run_gate ambiguity-score --goal 0.9 --sc 0.4 --constraints 0.8 --context 0.9 --round 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"AMBIGUITY SCORE: ESCALATED"* ]]
  [ "$(jq -r '.ambiguityScore.result' .claude-verification.json)" = "escalated" ]
}

@test "ambiguity: --greenfield forces Context to 1.0" {
  run run_gate ambiguity-score --goal 0.85 --sc 0.85 --constraints 0.85 --greenfield --round 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ambiguityScore.dimensions.context' .claude-verification.json)" = "1.0" ]
  [ "$(jq -r '.ambiguityScore.greenfield' .claude-verification.json)" = "true" ]
}

@test "ambiguity: --greenfield forces Context=1.0 regardless of arg order (before --context)" {
  # greenfield 앞, context 뒤 — 순서 무관하게 greenfield가 1.0을 강제해야 한다
  run run_gate ambiguity-score --greenfield --goal 0.85 --sc 0.85 --constraints 0.85 --context 1.0 --round 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ambiguityScore.dimensions.context' .claude-verification.json)" = "1.0" ]
}

@test "ambiguity: --greenfield with conflicting non-1.0 --context is rejected (die)" {
  run run_gate ambiguity-score --goal 0.85 --sc 0.85 --constraints 0.85 --context 0.5 --greenfield --round 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"충돌"* ]]
}

@test "ambiguity: out-of-range score is rejected (die)" {
  run run_gate ambiguity-score --goal 1.5 --sc 0.8 --constraints 0.8 --context 0.8 --round 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"0.0~1.0"* ]]
}

@test "ambiguity: missing dimension score is rejected (die)" {
  run run_gate ambiguity-score --goal 0.8 --sc 0.8 --constraints 0.8 --round 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"점수 필수"* ]]
}
