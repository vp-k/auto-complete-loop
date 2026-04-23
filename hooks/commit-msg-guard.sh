#!/usr/bin/env bash
# PreToolUse:Bash - [auto] 커밋 메시지의 US-ID suffix 의무화 검증 (fail-closed)
# RTM(Requirements Traceability) 유지를 위해 자동화 커밋에 User Story ID 부착 강제
#
# 규칙:
# - git commit -m "[auto] ..."  메시지에서 US-F-### 또는 US-B-### suffix 필수
# - 면제 키워드 포함 시 통과 (스캐폴딩/infrastructure/최종 검증/폴리싱/E2E 프레임워크)
# - Directive: / Rejected: / Consensus: / Scope-risk: 트레일러 포함 시 면제
# - [auto] prefix가 없는 커밋은 모두 통과 (사용자 수동 커밋은 본 훅 관여 X)
#
# 입력: stdin JSON { "tool_input": { "command": "..." } }
# 출력: {"decision": "block", "reason": "..."} 또는 {"decision": "approve"}

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 커밋 메시지를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 커밋 메시지를 검증할 수 없어 차단합니다."}'
  exit 0
}

# git commit 커맨드가 아니면 즉시 통과
# git global option(-C, -c, --git-dir, --work-tree)이 앞에 있어도 commit을 포함하면 검사
if ! echo "$COMMAND" | grep -qE 'git([[:space:]]+(-C[[:space:]]+\S+|-c[[:space:]]+\S+=\S+|--git-dir[[:space:]]+\S+|--work-tree[[:space:]]+\S+))*[[:space:]]+commit'; then
  echo '{"decision": "approve"}'
  exit 0
fi

# -m / --message 플래그가 없으면 (에디터 사용) 본 훅은 검증하지 않음
if ! echo "$COMMAND" | grep -qE -- '(-m.|--message[[:space:]=])'; then
  echo '{"decision": "approve"}'
  exit 0
fi

# [auto] 표식이 없으면 통과 (수동 커밋)
if ! echo "$COMMAND" | grep -qE '\[auto\]'; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 면제 키워드 (스코프 전역 커밋은 US-ID 불필요)
EXEMPT_PATTERN='스캐폴딩|scaffolding|infrastructure|E2E 프레임워크|E2E framework|최종 검증|폴리싱|polishing|Directive:|Rejected:|Consensus:|Scope-risk:'
if echo "$COMMAND" | grep -qE "$EXEMPT_PATTERN"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# US-F-### 또는 US-B-### 존재 체크
if echo "$COMMAND" | grep -qE 'US-[FB]-[0-9]+'; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 차단
REASON='[auto] 커밋 메시지에 User Story ID suffix가 누락되었습니다. 형식: `[auto] <내용> [US-F-###]` 또는 `[auto] <내용> [US-B-###]`. 여러 US 관련 시 쉼표 구분: [US-F-001,US-B-002]. 면제 대상(스캐폴딩/인프라/최종 검증/폴리싱/Directive 등)이면 해당 키워드를 메시지에 포함하세요.'
printf '{"decision": "block", "reason": %s}' "$(echo "$REASON" | jq -Rs .)"
exit 0
