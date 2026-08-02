#!/usr/bin/env bats
# spec-freeze.bats — SPEC 해시 동결/대조 (acceptance-freeze/gate v4.8.0 확장)

load test_helper

MANIFEST="tests/acceptance/.manifest.json"

setup() {
  setup_temp_dir
  # 기획 단계 progress (unapproved 동결 허용 조건)
  printf '{}\n' > .claude-plan-progress.json
  # 인수 테스트 픽스처 (러너 규약 준수, green)
  mkdir -p tests/acceptance
  cat > tests/acceptance/run.sh <<'EOF'
#!/bin/sh
echo "ACCEPTANCE_RESULT: total=1 passed=1 failed=0"
exit 0
EOF
  printf '# t1\n' > tests/acceptance/t1.sh
  # SPEC 픽스처
  cat > SPEC.md <<'EOF'
## Success Criteria
- SC-1: 기준

## API Contract
### GET /api/x
- Response 200: { }
EOF
}
teardown() { teardown_temp_dir; }

freeze() { run_gate acceptance-freeze --progress-file .claude-plan-progress.json; }

@test "spec-freeze: freeze records specFile path+hash in manifest" {
  freeze
  [ "$(jq -r '.specFile.path' "$MANIFEST")" = "SPEC.md" ]
  hash=$(jq -r '.specFile.hash' "$MANIFEST")
  [ -n "$hash" ] && [ "$hash" != "null" ]
}

@test "spec-freeze: gate passes when SPEC unchanged" {
  freeze
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPEC integrity OK"* ]]
  [ "$(jq -r '.acceptanceTests.result' .claude-verification.json)" = "pass" ]
}

@test "spec-freeze: gate fails when SPEC modified after freeze" {
  freeze
  printf -- '- Response 200: {"weakened": true}\n' >> SPEC.md
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"modified after freeze"* ]]
  [ "$(jq -r '.acceptanceTests.result' .claude-verification.json)" = "fail" ]
  [ "$(jq -r '.acceptanceTests.tamperedFiles[0]' .claude-verification.json)" = "SPEC.md" ]
}

@test "spec-freeze: gate fails when SPEC deleted after freeze" {
  freeze
  rm -f SPEC.md
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

@test "spec-freeze: gate re-run does not launder a modified SPEC" {
  freeze
  printf -- '- extra\n' >> SPEC.md
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  # 재실행해도 동일하게 차단 (해시 갱신은 승인 재동결로만)
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
}

@test "spec-freeze: approved re-freeze updates SPEC hash and gate passes again" {
  freeze
  printf -- '- approved change\n' >> SPEC.md
  run run_gate acceptance-gate
  [ "$status" -eq 1 ]
  run run_gate acceptance-freeze --approved-by-user --progress-file .claude-plan-progress.json
  [ "$status" -eq 0 ]
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
}

@test "spec-freeze: pre-4.8 manifest (no specFile) skips SPEC comparison" {
  freeze
  jq 'del(.specFile)' "$MANIFEST" > tmp.json && mv tmp.json "$MANIFEST"
  printf -- '- modified\n' >> SPEC.md
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-4.8"* ]]
}

@test "spec-freeze: freeze without SPEC file records specFile=null with warning" {
  rm -f SPEC.md
  freeze
  [ "$(jq '.specFile' "$MANIFEST")" = "null" ]
  run run_gate acceptance-gate
  [ "$status" -eq 0 ]
}
