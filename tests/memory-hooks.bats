#!/usr/bin/env bats
# memory-hooks.bats — 결정 로그의 컨텍스트 주입 (pre-compact / session-start)

load test_helper

PRE_COMPACT="$SCRIPT_DIR/../hooks/pre-compact.sh"
SESSION_START="$SCRIPT_DIR/../hooks/session-start.sh"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

_seed_decisions() {
  mkdir -p .claude
  local i
  for i in 1 2 3 4 5 6; do
    printf '{"id":"D-000%s","ts":"t","phase":"","iteration":1,"kind":"decision","what":"결정 %s","why":"사유 %s","alternatives":[],"reversible":"yes","scope":"planning","source":"adr"}\n' "$i" "$i" "$i"
  done > .claude/acl-decisions.jsonl
}

# ─── pre-compact ───

@test "pre-compact: 최근 결정 5건을 요약 보존 지시와 함께 출력한다" {
  run_gate init --template full-auto "test" "req"
  _seed_decisions
  run bash "$PRE_COMPACT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent Decisions (최근 5건"* ]]
  [[ "$output" == *"요약에 반드시 보존할 것"* ]]
  # 6건 중 마지막 5건만 (D-0001은 잘려나간다)
  [[ "$output" == *"D-0006"* ]]
  [[ "$output" == *"D-0002"* ]]
  [[ "$output" != *"D-0001 "* ]]
  [[ "$output" == *"acl-decisions.jsonl을 먼저 읽어"* ]]
}

@test "pre-compact: 결정 로그가 없으면 섹션을 출력하지 않고 정상 종료" {
  run_gate init --template full-auto "test" "req"
  run bash "$PRE_COMPACT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Recent Decisions"* ]]
}

@test "pre-compact: 손상된 결정 로그에도 죽지 않는다" {
  run_gate init --template full-auto "test" "req"
  mkdir -p .claude
  printf 'not json\n' > .claude/acl-decisions.jsonl
  run bash "$PRE_COMPACT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PreCompact 컨텍스트 요약"* ]]
}

# ─── session-start ───

@test "session-start: 최근 결정 건수와 마지막 결정을 관찰 라인으로 주입한다" {
  _seed_decisions
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"최근 결정 6건"* ]]
  [[ "$ctx" == *"D-0006"* ]]
  [[ "$ctx" == *"record-decision --list"* ]]
}

@test "session-start: 결정 로그가 없으면 결정 라인을 주입하지 않는다" {
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
  [[ "$ctx" != *"최근 결정"* ]]
}

@test "session-start: 손상된 결정 로그에도 죽지 않는다" {
  mkdir -p .claude
  printf 'not json\n' > .claude/acl-decisions.jsonl
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
}
