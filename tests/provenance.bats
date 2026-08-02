#!/usr/bin/env bats
# provenance.bats — SPEC 핵심 섹션 출처 마커 게이트

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

write_valid_spec() {
  cat > SPEC.md <<'EOF'
# Specification

## Context & Existing System
<!-- provenance: user-fact -->
- 해당 없음 — greenfield

## Success Criteria
<!-- provenance: user-fact -->
- SC-1: 기준

## User Stories — Backend
<!-- provenance: user-fact -->
- US-B-001: As a user, I want X

## Data Model
<!-- provenance: assumption: SQLite가 로컬 앱 관례이고 마이그레이션 가능 -->
| memo | id | int | PK | 메모 |

## API Contract
<!-- provenance: repo-fact:src/routes.ts -->
### GET /api/memos
- Response 200: { }

## Constraints
<!-- provenance: user-fact -->
### 성능
- p95 < 200ms
### 보안
- 입력 검증 필수
EOF
}

@test "provenance: valid markers on all present core sections pass" {
  write_valid_spec
  run run_gate provenance-gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [ "$(jq -r '.provenanceGate.result' .claude-verification.json)" = "pass" ]
}

@test "provenance: missing marker on a core section fails" {
  write_valid_spec
  # Data Model 마커 제거
  grep -v 'SQLite가 로컬 앱 관례' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Data Model"* ]]
  [ "$(jq -r '.provenanceGate.result' .claude-verification.json)" = "fail" ]
}

@test "provenance: assumption without rationale is malformed" {
  write_valid_spec
  sed 's|<!-- provenance: assumption: SQLite가 로컬 앱 관례이고 마이그레이션 가능 -->|<!-- provenance: assumption: -->|' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
}

@test "provenance: blocker marker fails with NEEDS-CLARIFICATION guidance" {
  write_valid_spec
  sed 's|<!-- provenance: repo-fact:src/routes.ts -->|<!-- provenance: blocker -->|' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"NEEDS-CLARIFICATION"* ]]
  [ "$(jq '.provenanceGate.blockers' .claude-verification.json)" = "1" ]
}

@test "provenance: unsafe domain term + assumption marker fails" {
  write_valid_spec
  # unsafe 용어를 assumption 섹션(Data Model) 본문에 삽입
  awk '1; /provenance: assumption/ {print "| user | password | text | NOT NULL | 계정 비밀번호 |"}' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"assumption 금지"* ]]
}

@test "provenance: unsafe domain term + user-fact marker passes" {
  write_valid_spec
  # Constraints(user-fact, 파일 마지막 섹션) 본문에 unsafe 용어 삽입
  printf -- '- 비밀번호는 bcrypt 해싱\n' >> SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 0 ]
}

@test "provenance: unsafe term inside code block is ignored" {
  write_valid_spec
  # Data Model(assumption) 섹션에 코드블록으로 unsafe 용어 삽입
  awk '1; /provenance: assumption/ {print "```"; print "password TEXT"; print "```"}' SPEC.md > tmp.md && mv tmp.md SPEC.md
  run run_gate provenance-gate
  [ "$status" -eq 0 ]
}

@test "provenance: no spec file fails" {
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
}

@test "provenance: marker-less SPEC + phase-1-skipped progress records skip" {
  cat > SPEC.md <<'EOF'
## Success Criteria
- SC-1: 기준
EOF
  printf '{"dod":{"all_docs_complete":{"checked":true,"evidence":"skipped by user (--start-phase 2)"}}}\n' > .claude-progress.json
  run run_gate provenance-gate --progress-file .claude-progress.json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenanceGate.result' .claude-verification.json)" = "skip" ]
}

@test "provenance: marker-less SPEC without skip evidence fails (fail-closed)" {
  cat > SPEC.md <<'EOF'
## Success Criteria
- SC-1: 기준
EOF
  run run_gate provenance-gate
  [ "$status" -eq 1 ]
}

@test "provenance: PASS records dod.provenance_recorded when key exists" {
  write_valid_spec
  printf '{"dod":{"provenance_recorded":{"checked":false,"evidence":null}}}\n' > .claude-progress.json
  run run_gate provenance-gate --progress-file .claude-progress.json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.dod.provenance_recorded.checked' .claude-progress.json)" = "true" ]
}
