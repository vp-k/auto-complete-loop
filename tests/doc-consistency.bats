#!/usr/bin/env bats
# doc-consistency.bats — [5] 수치 교차 일관성
#   [5a] 숫자만 다른 동일 문장 = BLOCKING
#   [5b] 단위별 값 스프레드     = INFO (issues 미계상)

load test_helper

PF=".claude-plan-progress.json"

setup() {
  setup_temp_dir
  run_gate init --template plan "test" "req" >/dev/null 2>&1 || true
  mkdir -p docs
}
teardown() { teardown_temp_dir; }

# ── [5b] 단위 스프레드는 모순이 아니다 ──

@test "numeric: 서로 다른 것을 세는 단위 스프레드는 issue가 아니다" {
  cat > overview.md <<'EOF'
# Overview
- 실패 사유 분류는 모두 11개다.
- 인수 테스트 러너는 스크립트 8개를 순회한다.
- 단위 테스트 상한은 10초다.
- 벤치 전체 상한은 30분이다.
EOF
  cat > docs/test-plan.md <<'EOF'
# Test Plan
- 픽스처 라우트는 15개를 제공한다.
- 인수 스위트 상한은 90초다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: multiple values for"* ]]
  [[ "$output" == *"=== Issues found: 0 ==="* ]]
}

@test "numeric: 스프레드는 INFO로만 보고되고 WARNING으로 계상되지 않는다" {
  cat > overview.md <<'EOF'
# Overview
- 업로드 상한은 10MB로 잡는다.
- 브라우저 티어 설치 용량은 400MB로 잡는다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO: multiple values for 'MB'"* ]]
  [[ "$output" != *"WARNING: Multiple values"* ]]
}

# ── [5a] 숫자만 다른 동일 문장은 모순이다 ──

@test "numeric: 두 문서에 숫자만 다른 동일 문장이 있으면 CONFLICT + exit 1" {
  cat > overview.md <<'EOF'
# Overview
- 단일 요청 전체 타임아웃 상한은 30초를 넘지 않는다.
EOF
  cat > docs/SPEC.md <<'EOF'
# Spec
- 단일 요청 전체 타임아웃 상한은 60초를 넘지 않는다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT: same statement, different numbers"* ]]
  [[ "$output" == *"=== Issues found: 1 ==="* ]]
}

@test "numeric: 같은 문장 + 같은 숫자 반복은 모순이 아니다" {
  cat > overview.md <<'EOF'
# Overview
- 단일 요청 전체 타임아웃 상한은 30초를 넘지 않는다.
EOF
  cat > docs/SPEC.md <<'EOF'
# Spec
- 단일 요청 전체 타임아웃 상한은 30초를 넘지 않는다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 0 ]
  [[ "$output" == *"No contradicting duplicate statements found"* ]]
}

@test "numeric: 짧은 문장(20자 미만)의 우연 충돌은 계상하지 않는다" {
  cat > overview.md <<'EOF'
# Overview
- 3개
EOF
  cat > docs/SPEC.md <<'EOF'
# Spec
- 7개
EOF
  run run_gate doc-consistency
  [ "$status" -eq 0 ]
  [[ "$output" != *"CONFLICT:"* ]]
}

@test "numeric: 같은 파일 안에서도 숫자만 다른 동일 문장을 잡는다" {
  cat > overview.md <<'EOF'
# Overview
- 호스트별 최소 요청 간격은 2초 이상으로 유지한다.
- 다른 내용 한 줄.
- 호스트별 최소 요청 간격은 5초 이상으로 유지한다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT: same statement, different numbers"* ]]
}

@test "numeric: 동일 키 다중 충돌도 한 번만 계상한다" {
  cat > overview.md <<'EOF'
# Overview
- 호스트별 최소 요청 간격은 2초 이상으로 유지한다.
- 호스트별 최소 요청 간격은 5초 이상으로 유지한다.
- 호스트별 최소 요청 간격은 9초 이상으로 유지한다.
EOF
  run run_gate doc-consistency
  [ "$status" -eq 1 ]
  [[ "$output" == *"=== Issues found: 1 ==="* ]]
}

# ── DoD / verification 기록 계약 ──

@test "numeric: PASS 시 dod.doc_consistency와 verification이 기록된다" {
  cat > overview.md <<'EOF'
# Overview
- 실패 사유 분류는 모두 11개다.
- 인수 스위트 상한은 90초다.
EOF
  jq '.dod.doc_consistency = {checked:false, evidence:null}' "$PF" > tmp.json && mv tmp.json "$PF"
  run run_gate doc-consistency --progress-file "$PF"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.dod.doc_consistency.checked' "$PF")" = "true" ]
  [ "$(jq -r '.docConsistency.result' .claude-verification.json)" = "pass" ]
}

@test "numeric: CONFLICT 시 verification이 fail로 기록된다" {
  cat > overview.md <<'EOF'
# Overview
- 단일 요청 전체 타임아웃 상한은 30초를 넘지 않는다.
- 단일 요청 전체 타임아웃 상한은 60초를 넘지 않는다.
EOF
  run run_gate doc-consistency --progress-file "$PF"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.docConsistency.result' .claude-verification.json)" = "fail" ]
}
