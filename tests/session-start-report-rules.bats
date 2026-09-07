#!/usr/bin/env bats
# session-start-report-rules.bats — 보고 작성 규칙(rules/report-writing-rules.md) 세션 주입 검증 (v4.23.0)
#
# 사용자 CLAUDE.md는 PC마다 다르므로 플러그인이 같은 규칙을 모든 환경에 주입해야 한다.
# 세 경로(progress 없음 / 완료 정리 / 복구) 모두에서 규칙이 additionalContext에 실려야 한다.

load test_helper

HOOK="$SCRIPT_DIR/../hooks/session-start.sh"
RULES="$SCRIPT_DIR/../rules/report-writing-rules.md"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

_ctx() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext'; }

@test "report-rules: 규칙 파일이 존재하고 양식·하드 규칙 섹션을 가진다" {
  [ -f "$RULES" ]
  grep -q '^## 양식' "$RULES"
  grep -q '^## 하드 규칙' "$RULES"
}

@test "report-rules: progress 없는 fresh 세션에서도 규칙이 주입된다" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(_ctx)
  [[ "$ctx" == *"[Report Rules]"* ]]
  [[ "$ctx" == *"## 하드 규칙"* ]]
}

@test "report-rules: 문서 힌트(overview.md)와 함께 주입되고 규칙이 뒤에 온다" {
  echo "# overview" > overview.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(_ctx)
  [[ "$ctx" == *"[Project Context]"* ]]
  [[ "$ctx" == *"[Report Rules]"* ]]
  # 프로젝트 컨텍스트가 먼저, 규칙이 나중
  _pc=$(printf '%s' "$ctx" | grep -n '\[Project Context\]' | head -1 | cut -d: -f1)
  _rr=$(printf '%s' "$ctx" | grep -n '\[Report Rules\]' | head -1 | cut -d: -f1)
  [ "$_pc" -lt "$_rr" ]
}

@test "report-rules: 복구(Auto-Recovery) 경로에서도 규칙이 덧붙는다" {
  mkdir -p .claude
  cat > .claude-full-auto-progress.json <<'EOF'
{"schemaVersion":7,"status":"in_progress","projectName":"t","currentPhase":2,
 "phases":{"phase_2":{"status":"in_progress","steps":{}}},
 "handoff":{"nextSteps":["continue"],"lastIteration":1}}
EOF
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(_ctx)
  [[ "$ctx" == *"[Auto-Recovery]"* ]]
  [[ "$ctx" == *"[Report Rules]"* ]]
}

@test "report-rules: 규칙 파일이 없으면 주입하지 않고 정상 종료한다" {
  # 플러그인 사본을 임시 디렉토리에 만들어 규칙 파일만 제거
  cp -r "$SCRIPT_DIR/.." "$TEST_DIR/plugin"
  rm -f "$TEST_DIR/plugin/rules/report-writing-rules.md"
  run bash "$TEST_DIR/plugin/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Report Rules]"* ]]
}
