#!/usr/bin/env bats
# design-contract.bats — hasFrontend 프로젝트의 DESIGN.md 계약 + UI States AC 반영 검사

load test_helper

PF=".claude-full-auto-progress.json"

setup() {
  setup_temp_dir
  run_gate init --template full-auto "test" "req"
  jq '.phases.phase_0.outputs.projectScope = {"hasFrontend":true,"hasBackend":false}' \
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
- SC-1: 첫 화면 LCP < 2.5s

## User Stories — Frontend
- US-F-001: As a user, I want to see my memos
  - AC-F-001-1: 메모 목록이 최신순으로 표시된다
  - AC-F-001-2: 메모가 0건이면 "아직 메모가 없습니다" 빈 상태를 표시한다

## Frontend Pages & Components
| 페이지 | 경로 | 기능 | 연관 US |
| List | / | 목록 | US-F-001 |

### UI States (화면별 상태 명세)
| 페이지 | 빈 상태 | 로딩 상태 | 에러 상태 | 유효성 |
| List | 안내 문구 | 스켈레톤 | 재시도 버튼 | 인라인 |

## Data Model
| memo | id | int | PK | 메모 |

## API Contract
### GET /api/memos
- Response 200: { }

## Error Response
- { code, message }

## Constraints
### 성능
- LCP < 2.5s
### 보안
- XSS 방지
EOF
  mkdir -p docs
  printf '# test plan\n- cases\n' > docs/test-plan.md
  cp "${SCRIPT_DIR%/scripts}/templates/DESIGN.md" docs/DESIGN.md
  # 템플릿 플레이스홀더 채우기 (작성 완료 상태로 만든다)
  sed -i 's|<이 제품은 ___한 사람에게 ___한 인상을 주어야 한다>|바쁜 실무자에게 군더더기 없는 인상을 준다|' docs/DESIGN.md
}
teardown() { teardown_temp_dir; }

@test "design: 완성된 DESIGN.md가 있으면 디자인 관련 MAJOR 없음" {
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" != *"no docs/DESIGN.md"* ]]
  [[ "$output" != *"템플릿 상태"* ]]
  [[ "$output" != *"assumption 마커"* ]]
}

@test "design: hasFrontend=true인데 DESIGN.md 없으면 MAJOR" {
  rm -f docs/DESIGN.md
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" == *"no docs/DESIGN.md"* ]]
}

@test "design: hasFrontend=false면 DESIGN.md 없어도 무관" {
  rm -f docs/DESIGN.md
  jq '.phases.phase_0.outputs.projectScope = {"hasFrontend":false,"hasBackend":true}' \
    "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" != *"no docs/DESIGN.md"* ]]
}

@test "design: 템플릿 플레이스홀더가 남아 있으면 MAJOR" {
  cp "${SCRIPT_DIR%/scripts}/templates/DESIGN.md" docs/DESIGN.md
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" == *"템플릿 상태"* ]]
}

@test "design: 제품 성격 섹션의 assumption 마커는 MAJOR" {
  sed -i '/^## 1. 제품 성격/,/^## 2./ s|<!-- provenance: blocker -->|<!-- provenance: assumption: 아마 이런 느낌 -->|' docs/DESIGN.md
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" == *"assumption 마커"* ]]
}

@test "design: 3절 이하의 assumption 마커는 허용" {
  run run_gate spec-completeness --progress-file "$PF"
  # 템플릿 3·4·6·7절은 assumption을 쓰고 있으나 성격/브랜드 섹션이 아니므로 통과
  [[ "$output" != *"assumption 마커"* ]]
}

@test "ui-states: UI States 표가 있고 AC-F에 상태가 반영되면 통과" {
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" != *"하나도 반영되지 않음"* ]]
}

@test "ui-states: UI States 표만 있고 AC-F가 happy path뿐이면 MAJOR" {
  sed -i 's|  - AC-F-001-2: 메모가 0건이면 "아직 메모가 없습니다" 빈 상태를 표시한다|  - AC-F-001-2: 메모 제목이 굵게 표시된다|' SPEC.md
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" == *"하나도 반영되지 않음"* ]]
}

@test "ui-states: AC 서술이 ID 다음 줄에 있어도 상태 반영으로 인식 (오탐 방지)" {
  # AC ID 줄과 서술 줄이 분리된 표기
  cat > SPEC.md <<'EOF'
# Specification

## Context & Existing System
- 해당 없음

## Success Criteria
- North Star Metric: 주간 활성 메모 수

## User Stories — Frontend
- US-F-001: 메모 목록
  - AC-F-001-1
    목록이 최신순으로 표시된다
  - AC-F-001-2
    메모가 0건이면 빈 상태 안내를 표시한다

## Frontend Pages & Components
| 페이지 | 경로 | 기능 | 연관 US |
| List | / | 목록 | US-F-001 |

### UI States (화면별 상태 명세)
| 페이지 | 빈 상태 | 로딩 상태 | 에러 상태 | 유효성 |
| List | 안내 문구 | 스켈레톤 | 재시도 버튼 | - |
EOF
  run run_gate spec-completeness
  [[ "$output" != *"AC-F-*에 빈/로딩/에러/유효성 상태가 하나도 반영되지 않음"* ]]
}

@test "ui-states: UI States 섹션 자체가 없으면 기존 MAJOR 유지" {
  grep -v 'UI States' SPEC.md | grep -v '빈 상태' > tmp.md && mv tmp.md SPEC.md
  run run_gate spec-completeness --progress-file "$PF"
  [[ "$output" == *"no UI States section"* ]]
}

# ── design-polish-gate SOFT→HARD 승격 판정 (순수 함수) ──

@test "escalation: 신규 계약 위반 soft_fail은 승격 후보" {
  run _dp_escalation_candidate "soft_fail" "true" "3"
  [ "$status" -eq 0 ]
}

@test "escalation: WCAG만으로 인한 soft_fail은 승격 후보 아님 (브라운필드 데드락 방지)" {
  run _dp_escalation_candidate "soft_fail" "true" "0"
  [ "$status" -eq 1 ]
}

@test "escalation: 계약 미설정(heuristic) 프로젝트는 승격 후보 아님" {
  run _dp_escalation_candidate "soft_fail" "false" "3"
  [ "$status" -eq 1 ]
}

@test "escalation: pass/fail 결과는 승격 후보 아님" {
  run _dp_escalation_candidate "pass" "true" "3"
  [ "$status" -eq 1 ]
  run _dp_escalation_candidate "fail" "true" "3"
  [ "$status" -eq 1 ]
}

@test "escalation: 비정상 카운트는 승격 후보 아님 (fail-safe)" {
  run _dp_escalation_candidate "soft_fail" "true" "null"
  [ "$status" -eq 1 ]
  run _dp_escalation_candidate "soft_fail" "true" ""
  [ "$status" -eq 1 ]
}

@test "escalation: gateHistory 연속성 — 직전 warn이면 승격, 직전 pass면 미승격" {
  PROGRESS_FILE="$PF"
  append_gate_history "design-polish-contract" "warn" '{}'
  run soft_gate_escalation "design-polish-contract" "warn"
  [ "$status" -eq 0 ]
  append_gate_history "design-polish-contract" "pass" '{}'
  run soft_gate_escalation "design-polish-contract" "warn"
  [ "$status" -eq 1 ]
}

@test "escalation: WCAG 부채로 게이트가 매번 warn이어도 계약 이력은 오염되지 않는다" {
  PROGRESS_FILE="$PF"
  # 게이트 전체는 WCAG 때문에 계속 warn — 그러나 계약 위반은 이번이 처음
  append_gate_history "design-polish-gate" "warn" '{}'
  append_gate_history "design-polish-gate" "warn" '{}'
  run soft_gate_escalation "design-polish-contract" "warn"
  [ "$status" -eq 1 ]
}
