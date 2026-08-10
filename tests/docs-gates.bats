#!/usr/bin/env bats
# docs-gates.bats — spec-completeness 명확성 4차원 (Goal/Constraints/SuccessCriteria/Context)

load test_helper

PF=".claude-full-auto-progress.json"

setup() {
  setup_temp_dir
  run_gate init --template full-auto "test" "req"
  jq '.phases.phase_0.outputs.projectScope = {"hasFrontend":false,"hasBackend":true}' \
    "$PF" > tmp.json && mv tmp.json "$PF"
  cat > overview.md <<'EOF'
## 문제 정의
사용자가 메모를 잃어버린다.

## 목표
메모 CRUD 제공.
EOF
  cat > SPEC.md <<'EOF'
# Specification

## Context & Existing System
- 해당 없음 — greenfield

## Success Criteria
- North Star Metric: 주간 활성 메모 수
- SC-1: 메모 생성 p95 < 200ms

## User Stories — Backend
- US-B-001: As a user, I want to create memos
  - AC: 인수 기준 — 201 반환

## Data Model
| memo | id | int | PK | 메모 |

## API Contract
### POST /api/memos
- Response 200: { }

## Error Response
- { code, message }

## Constraints
### 성능
- p95 < 200ms
### 보안
- 입력 검증 필수
EOF
  cat > docs_placeholder.md <<'EOF'
placeholder
EOF
  mkdir -p docs
  printf '# test plan\n- cases\n' > docs/test-plan.md
}
teardown() { teardown_temp_dir; }

@test "dimensions: complete spec passes with all dimensions ok" {
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.specCompleteness.dimensions.goal' .claude-verification.json)" = "ok" ]
  [ "$(jq -r '.specCompleteness.dimensions.successCriteria' .claude-verification.json)" = "ok" ]
  [ "$(jq -r '.specCompleteness.dimensions.constraints' .claude-verification.json)" = "ok" ]
  [ "$(jq -r '.specCompleteness.dimensions.context' .claude-verification.json)" = "ok" ]
}

@test "dimensions: zero SC-N items is CRITICAL (fail)" {
  sed 's/SC-1:.*/기준 없음/' SPEC.md | sed 's/SC-[0-9]*//g' > tmp.md && mv tmp.md SPEC.md
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[SuccessCriteria]"* ]]
  [ "$(jq -r '.specCompleteness.dimensions.successCriteria' .claude-verification.json)" = "missing" ]
}

@test "dimensions: missing 성능/보안 subsections are MAJOR (warn, non-blocking)" {
  sed 's/^### 성능/### 속도/; s/^### 보안/### 기타/' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Constraints]"* ]]
  [ "$(jq -r '.specCompleteness.dimensions.constraints' .claude-verification.json)" = "incomplete" ]
}

@test "dimensions: missing Context section is MAJOR (warn, non-blocking for pre-4.7 compat)" {
  grep -vE '^## Context|^- 해당 없음' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Context]"* ]]
  [ "$(jq -r '.specCompleteness.dimensions.context' .claude-verification.json)" = "missing" ]
}

@test "dimensions: overview without goal heading is MAJOR" {
  cat > overview.md <<'EOF'
## 배경
어떤 배경.
EOF
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Goal]"* ]]
  [ "$(jq -r '.specCompleteness.dimensions.goal' .claude-verification.json)" = "missing" ]
}

# ── 자기신고 세탁 감지 (ambiguity-score pass ↔ spec-completeness 약함 교차검증) ──

@test "laundering: ambiguity pass but spec finds weak dim (>=floor) emits mismatch event" {
  # ambiguity-score가 goal=0.9(신고 명확)로 pass였다고 시드
  echo '{"ambiguityScore":{"result":"pass","dimensions":{"goal":0.9,"successCriteria":0.9,"constraints":0.9,"context":0.9}}}' \
    > .claude-verification.json
  # 실제 문서에선 goal 헤딩 제거 → 재검증에서 goal=missing
  cat > overview.md <<'EOF'
## 배경
어떤 배경.
EOF
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"자기신고 세탁 신호"* ]]
  [[ "$output" == *"goal"* ]]
  # log_event로 mismatch 이벤트 기록됨
  run jq -r 'select(.event=="gate.ambiguity.mismatch") | .gate' .claude/acl-events.jsonl
  [[ "$output" == *"spec-completeness"* ]]
}

@test "laundering: dim below floor (0.6) is NOT flagged as laundering" {
  # goal 자기신고 0.5(<floor) → 실측이 약해도 세탁으로 보지 않음
  echo '{"ambiguityScore":{"result":"pass","dimensions":{"goal":0.5,"successCriteria":0.9,"constraints":0.9,"context":0.9}}}' \
    > .claude-verification.json
  cat > overview.md <<'EOF'
## 배경
어떤 배경.
EOF
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"자기신고 세탁 신호"* ]]
}

@test "laundering: no ambiguityScore recorded → no mismatch check (backward compat)" {
  # ambiguity 키 부재(pre-4.10 재개) → 세탁 검사 스킵, 경고 없음
  cat > overview.md <<'EOF'
## 배경
어떤 배경.
EOF
  run run_gate spec-completeness --progress-file "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"자기신고 세탁 신호"* ]]
}
