#!/usr/bin/env bats
# review-escalation.bats — 트리거 기반 리뷰 승격 판정/증거 검증

load test_helper

PF=".claude-full-auto-progress.json"

setup() {
  setup_temp_dir
  run_gate init --template full-auto "test" "req"
}
teardown() { teardown_temp_dir; }

@test "escalation-check: no triggers records skip" {
  run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "skip" ]
  [ "$(jq -r '.phases.phase_3.reviewEscalation.required' "$PF")" = "false" ]
}

@test "escalation-check: L1-only levelHistory still skips" {
  jq '.errorHistory.levelHistory = ["L0","L1","L1"]' "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "skip" ]
}

@test "escalation-check: L2 in levelHistory triggers pending" {
  jq '.errorHistory.levelHistory = ["L0","L2"]' "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDING"* ]]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "pending" ]
  [ "$(jq -r '.phases.phase_3.reviewEscalation.required' "$PF")" = "true" ]
  [ "$(jq -r '.reviewEscalation.triggers[0].type' .claude-verification.json)" = "escalation" ]
}

@test "escalation-check: scopeReductions triggers pending" {
  jq '.phases.phase_2.scopeReductions = [{"feature":"x"}]' "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "pending" ]
}

@test "escalation-check: acceptance refreezeHistory triggers pending" {
  mkdir -p tests/acceptance
  printf '{"refreezeHistory":[{"at":"t","approvedByUser":true}]}\n' > tests/acceptance/.manifest.json
  run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "pending" ]
}

@test "escalation-check: targetMode=dual when codex on PATH" {
  jq '.errorHistory.levelHistory = ["L2"]' "$PF" > tmp.json && mv tmp.json "$PF"
  mkdir -p fakebin
  printf '#!/bin/sh\nexit 0\n' > fakebin/codex
  chmod +x fakebin/codex
  PATH="$TEST_DIR/fakebin:$PATH" run run_gate review-escalation-check --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.phases.phase_3.reviewEscalation.targetMode' "$PF")" = "dual" ]
}

@test "mark-complete: fails without escalated round evidence" {
  jq '.errorHistory.levelHistory = ["L2"]' "$PF" > tmp.json && mv tmp.json "$PF"
  run_gate review-escalation-check --progress-file "$PF"
  run run_gate review-escalation-check --mark-complete --progress-file "$PF"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "fail" ]
}

@test "mark-complete: passes with matching escalated roundResults entry" {
  jq '.errorHistory.levelHistory = ["L2"]' "$PF" > tmp.json && mv tmp.json "$PF"
  run_gate review-escalation-check --progress-file "$PF"
  mode=$(jq -r '.phases.phase_3.reviewEscalation.targetMode' "$PF")
  jq --arg m "$mode" '.phases.phase_3.roundResults = [{"round":1,"escalated":true,"reviewMode":$m,"findings":{"bySeverity":{}}}]' \
    "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate review-escalation-check --mark-complete --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "pass" ]
  [ "$(jq -r '.reviewEscalation.mode' .claude-verification.json)" = "$mode" ]
}

@test "mark-complete: no triggers is idempotent skip" {
  run run_gate review-escalation-check --mark-complete --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewEscalation.result' .claude-verification.json)" = "skip" ]
}
