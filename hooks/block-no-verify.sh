#!/usr/bin/env bash
# PreToolUse:Bash - --no-verify 플래그 차단 (fail-closed)
# git commit/push에서 --no-verify 및 -n 사용을 차단하여 pre-commit hook 보호
#
# NOTE: hooks.json에는 통합 디스패처(bash-guards.sh)만 등록된다. 이 파일은 잔존 유지본.
#
# 입력: stdin JSON { "tool_input": { "command": "..." } }
# 출력: 차단 시 {"decision": "block", "reason": "..."} / 통과 시 무출력 (approve 금지)

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

# git global option(-C, -c, --git-dir, --work-tree)이 앞에 있어도 서브커맨드를 검사
GIT_OPTS='([[:space:]]+(-C[[:space:]]+\S+|-c[[:space:]]+\S+=\S+|--git-dir[[:space:]]+\S+|--work-tree[[:space:]]+\S+))*'
GIT_COMMIT_RE="git${GIT_OPTS}[[:space:]]+commit"
GIT_PUSH_RE="git${GIT_OPTS}[[:space:]]+push"

# --no-verify 차단: git commit/push에 한정 + 워드 경계
# (오탐 방지: '--no-verify-tls' 같은 더 긴 플래그의 부분 문자열이나
#  git과 무관한 명령의 --no-verify를 잘못 차단하지 않음)
if echo "$COMMAND" | grep -qE "$GIT_COMMIT_RE|$GIT_PUSH_RE"; then
  if echo "$COMMAND" | grep -qE -- '--no-verify([^-a-zA-Z0-9]|$)'; then
    echo "$BLOCK_MSG"
    exit 0
  fi
fi

# git commit의 -n (short form of --no-verify) 차단
# 주의: git push -n은 dry-run이므로 차단하지 않음
if echo "$COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
  if echo "$COMMAND" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n([[:space:]]|$)'; then
    echo "$BLOCK_MSG"
    exit 0
  fi
fi

# 통과 → 무출력 (권한 판정 유보)
exit 0
