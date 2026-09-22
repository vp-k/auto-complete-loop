#!/usr/bin/env bats
# read-guard.bats — PreToolUse:Read 긴 파일 통째 읽기 관측 훅 (비차단) 검증 (v4.25.0)
#   - 임계 초과 + limit 없음 + ACL 활성 → context.read.large 이벤트 + additionalContext 안내
#   - 차단 출력(decision:block / permissionDecision)은 어떤 경우에도 내지 않는다
#   - ACL 비활성 프로젝트에는 흔적(.claude/acl-events.jsonl)을 남기지 않는다

load test_helper

HOOK="$SCRIPT_DIR/../hooks/read-guard.sh"

setup() {
  setup_temp_dir
  seq 1 400 > big.log
  seq 1 400 | sed 's/^/# H /' > big.md
  seq 1 50 > small.md
}
teardown() { teardown_temp_dir; }

activate_acl() {
  mkdir -p .claude
  printf -- '---\niteration: 7\n---\n' > .claude/ralph-loop.local.md
}

run_hook() {
  printf '%s' "$1" | bash "$HOOK"
}

@test "large file without limit (ACL active) → additionalContext note + context.read.large event with iteration" {
  activate_acl
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.log\"}}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PreToolUse" ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"[read-guard] big.log"* ]]
  [[ "$ctx" == *"400줄"* ]]
  [[ "$output" != *"permissionDecision"* ]]
  [[ "$output" != *'"decision"'* ]]
  ev=$(grep '"event":"context.read.large"' .claude/acl-events.jsonl | tail -1)
  [ "$(printf '%s' "$ev" | jq -r '.tool')" = "Read" ]
  [ "$(printf '%s' "$ev" | jq -r '.lines')" = "400" ]
  [ "$(printf '%s' "$ev" | jq -r '.iteration')" = "7" ]
  [ "$(printf '%s' "$ev" | jq -r '.threshold')" = "300" ]
}

@test "with limit → silent pass, no event" {
  activate_acl
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.log\",\"limit\":50}}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -q 'context.read.large' .claude/acl-events.jsonl 2>/dev/null
}

@test "file under threshold → silent pass" {
  activate_acl
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/small.md\"}}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ACL not active → silent pass and no .claude/acl-events.jsonl created" {
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.log\"}}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f .claude/acl-events.jsonl ]
}

@test "progress file alone activates observation" {
  echo '{}' > .claude-progress.json
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.md\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[read-guard] big.md"* ]]
  ev=$(grep '"event":"context.read.large"' .claude/acl-events.jsonl | tail -1)
  [ "$(printf '%s' "$ev" | jq -r '.iteration')" = "0" ]
}

@test "Windows backslash path is normalized" {
  activate_acl
  win=$(printf '%s' "$PWD" | sed 's#/#\\\\#g')
  run run_hook "{\"tool_input\":{\"file_path\":\"${win}\\\\big.md\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[read-guard] big.md"* ]]
}

@test "alternative hint depends on file kind (md → doc-section, log → grep/run-capped, progress → status)" {
  activate_acl
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.md\"}}"
  [[ "$output" == *"doc-section"* ]]
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/big.log\"}}"
  [[ "$output" == *"run-capped"* ]]
  seq 1 400 > .claude-progress.json
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/.claude-progress.json\"}}"
  [[ "$output" == *"shared-gate.sh status"* ]]
}

@test "ACL_LARGE_READ_LINES overrides the threshold" {
  activate_acl
  ACL_LARGE_READ_LINES=10 run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/small.md\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"임계 10"* ]]
}

@test "missing file / empty input / no file_path → silent pass" {
  activate_acl
  run run_hook "{\"tool_input\":{\"file_path\":\"$PWD/nope.md\"}}"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run run_hook ""
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run run_hook '{"tool_input":{}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "non-ACL project: hook exits before parsing (no jq needed, malformed input tolerated)" {
  run run_hook 'not json at all'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "ACL active + malformed JSON / numeric file_path → silent pass" {
  activate_acl
  run run_hook 'not json at all'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run run_hook '{"tool_input":{"file_path":42}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
