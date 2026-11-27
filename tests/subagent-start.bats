#!/usr/bin/env bats
# subagent-start.bats — 서브에이전트 착수 규칙 주입 훅 검증 (v4.27.0)
#
# 서브에이전트는 세션의 규칙 파일도 SessionStart 주입도 받지 않는다.
# SubagentStart 훅이 ACL 활성 프로젝트에서만 착수 규칙을 서브에이전트 컨텍스트에 넣는다.
# 출력 계약(공식 문서): {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}

load test_helper

PLUGIN="$SCRIPT_DIR/.."
HOOK="$PLUGIN/hooks/subagent-start.sh"
BRIEFING="$PLUGIN/rules/subagent-briefing.md"

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

_ctx() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext'; }

_activate() {
  echo '{"status":"in_progress"}' > .claude-full-auto-progress.json
}

@test "subagent-start: 비 ACL 프로젝트에서는 아무것도 출력하지 않는다" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "subagent-start: progress 파일이 있으면 SubagentStart 형식으로 주입한다" {
  _activate
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "SubagentStart" ]
  ctx=$(_ctx)
  [[ "$ctx" == *"[Subagent Rules]"* ]]
  [[ "$ctx" == *"기준은 지시문에 적힌 것이 전부다"* ]]
  [[ "$ctx" == *"사용자에게 묻지 않는다"* ]]
  [[ "$ctx" == *"증거는 명령과 그 출력이다"* ]]
}

@test "subagent-start: ralph-loop 파일만 있어도 활성으로 본다" {
  mkdir -p .claude
  echo "---" > .claude/ralph-loop.local.md
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$(_ctx)" == *"[Subagent Rules]"* ]]
}

@test "subagent-start: 지시문의 출력 형식이 이 규칙보다 우선한다고 명시한다" {
  _activate
  run bash "$HOOK"
  [[ "$(_ctx)" == *"출력 형식"*"우선"* ]]
}

@test "subagent-start: 보고 작성 규칙은 주입하지 않는다" {
  # 리뷰 서브에이전트의 finding 형식과 충돌하고 다른 플러그인 에이전트의 반환 형식까지 바꾼다
  _activate
  run bash "$HOOK"
  [[ "$(_ctx)" == *"[Subagent Rules]"* ]]
  [[ "$(_ctx)" != *"## 하드 규칙"* ]]
  [[ "$(_ctx)" != *"[Report Rules]"* ]]
}

@test "subagent-start: stdin이 닫히지 않아도 기다리지 않고 끝난다" {
  # stdin은 15초 동안 열려 있다. stdin을 읽는 훅은 10초에 강제 종료되어 124가 된다.
  # 그래서 종료 코드 0이 "기다리지 않았다"의 판별이다. 경과 초는 검사하지 않는다.
  # Idle 우선순위와 코어 1개로 돌리면 다른 부하에 밀려 8초를 넘긴 실행이 실제로 있었다.
  _activate
  run timeout 10 bash "$HOOK" < <(sleep 15 2>/dev/null 3>&-)
  [ "$status" -eq 0 ]
  [[ "$(_ctx)" == *"[Subagent Rules]"* ]]
}

@test "subagent-start: 규칙 파일이 없으면 주입하지 않고 정상 종료한다" {
  mkdir -p "$TEST_DIR/plugin/hooks" "$TEST_DIR/plugin/rules"
  cp "$HOOK" "$TEST_DIR/plugin/hooks/"
  _activate
  run bash "$TEST_DIR/plugin/hooks/subagent-start.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "subagent-start: hooks.json에 SubagentStart로 등록되고 timeout이 있다" {
  cmd=$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$PLUGIN/hooks/hooks.json")
  [[ "$cmd" == *"run-hook.cmd"*"subagent-start.sh"* ]]
  t=$(jq -r '.hooks.SubagentStart[0].hooks[0].timeout' "$PLUGIN/hooks/hooks.json")
  [[ "$t" =~ ^[0-9]+$ ]]
  [ "$t" -le 30 ]
}

@test "subagent-start: shared-rules 착수 지시 세 항목이 주입 파일과 같다" {
  # 오케스트레이터용 설명(shared-rules)과 서브에이전트용 본문(briefing)이 갈라지지 않게 한다
  for title in "기준은 지시문에 적힌 것이 전부다." "사용자에게 묻지 않는다." "증거는 명령과 그 출력이다."; do
    grep -qF "**${title}**" "$PLUGIN/rules/shared-rules.md"
    grep -qF "**${title}**" "$BRIEFING"
  done
}
