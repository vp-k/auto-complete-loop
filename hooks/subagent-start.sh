#!/usr/bin/env bash
# subagent-start.sh — SubagentStart 훅: 서브에이전트 착수 규칙 주입 (v4.27.0)
#
# 서브에이전트는 세션의 규칙 파일을 읽지 않고, 공식 문서상 SessionStart 주입도 받는다는 보장이 없다.
# 그래서 rules/subagent-briefing.md 를 서브에이전트 컨텍스트에 직접 넣는다.
#
# - 범위: ACL 실행 중인 프로젝트만 (ralph-loop 파일 또는 progress 파일). 다른 프로젝트의 서브에이전트는 건드리지 않는다.
# - stdin 을 읽지 않는다. Windows 에서 stdin 대기가 서브에이전트 생성마다 멈춤을 만들 수 있다.
#   판단에 필요한 것은 작업 디렉토리의 파일뿐이다.
# - 보고 작성 규칙은 넣지 않는다. 리뷰 서브에이전트의 finding 형식과 충돌한다.
# - 출력 계약: {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}
#   SubagentStart 는 평문 stdout 을 컨텍스트로 쓴다는 문서가 없으므로 JSON 만 쓴다.
# - 어떤 경우에도 exit 0. 이 훅은 서브에이전트 생성을 막지 않는다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEFING_FILE="${PLUGIN_ROOT}/rules/subagent-briefing.md"

_acl_active="false"
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  _acl_active="true"
else
  for _p in .claude-*progress*.json; do
    if [[ -f "$_p" ]]; then _acl_active="true"; break; fi
  done
fi
[[ "$_acl_active" == "true" ]] || exit 0
[[ -f "$BRIEFING_FILE" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

_ctx=$(cat "$BRIEFING_FILE" 2>/dev/null) || exit 0
[[ -n "$_ctx" ]] || exit 0

jq -n --arg ctx "$_ctx" \
  '{ "hookSpecificOutput": { "hookEventName": "SubagentStart", "additionalContext": $ctx } }' \
  </dev/null 2>/dev/null || true
exit 0
