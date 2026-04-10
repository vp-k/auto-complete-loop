#!/usr/bin/env bash
# PreToolUse:Bash - --no-verify 플래그 차단 (fail-closed)
# git commit/push에서 --no-verify 및 -n 사용을 차단하여 pre-commit hook 보호
#
# 입력: stdin JSON { "tool_input": { "command": "..." } }
# 출력: {"decision": "block", "reason": "..."} 또는 {"decision": "approve"}

set -euo pipefail

BLOCK_MSG='{"decision": "block", "reason": "--no-verify는 사용할 수 없습니다. pre-commit hook을 우회하면 품질 게이트가 무력화됩니다. hook 실패 시 근본 원인을 해결하세요."}'

# jq 미설치 시 fail-closed
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 명령어를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

INPUT=$(cat)

# JSON 파싱 실패 시 fail-closed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 명령어를 검증할 수 없어 차단합니다."}'
  exit 0
}

# --no-verify 차단
if echo "$COMMAND" | grep -qE -- '--no-verify'; then
  echo "$BLOCK_MSG"
  exit 0
fi

# git commit의 -n (short form of --no-verify) 차단
# 주의: git push -n은 dry-run이므로 차단하지 않음
if echo "$COMMAND" | grep -qE 'git\s+commit'; then
  if echo "$COMMAND" | grep -qE '(^|\s)-[a-zA-Z]*n(\s|$)'; then
    echo "$BLOCK_MSG"
    exit 0
  fi
fi

echo '{"decision": "approve"}'
