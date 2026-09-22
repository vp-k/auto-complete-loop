#!/usr/bin/env bash
# PreToolUse:Read — 긴 파일 통째 읽기 관측 (비차단)
#
# 문제: 진행 중 SPEC·설계 문서·테스트 로그를 통째로 읽어 컨텍스트를 채우고, compact 뒤에 같은
#       파일을 다시 읽는 순환이 반복된다. v4.24.0 계측은 총량(사용률)만 재고 "무엇이" 채웠는지는 모른다.
# 이 훅: Read 가 임계(ACL_LARGE_READ_LINES, 기본 300줄)를 넘는 파일을 limit 없이 읽으려 할 때
#   1) `context.read.large` 이벤트를 .claude/acl-events.jsonl 에 남기고 (무엇이 채우는지의 사실)
#   2) 대안(doc-section / offset+limit / status / run-capped)을 한 줄 안내로 덧붙인다.
#   차단하지 않는다 — 차단은 토큰을 줄이지 못하고(200줄씩 두 번 읽는다) 대안 탐색 턴만 더한다.
#   안내 주입(additionalContext)은 Claude Code 버전에 따라 모델에 보이지 않을 수 있다. 이벤트 기록이
#   확실한 채널이고, session-start 가 누적치를 다음 세션 경고로 주입한다.
# 범위: auto-complete-loop 실행 중인 프로젝트에서만 동작한다(ralph-loop 파일 또는 progress 파일 존재).
#   그 밖의 프로젝트에 .claude/acl-events.jsonl 을 만들지 않는다.
# 입력: stdin JSON { "tool_input": { "file_path": "...", "offset": N, "limit": N } }
# 출력: 관측 대상이면 {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"..."}}
#       (permissionDecision 은 넣지 않는다 — 권한 프롬프트를 우회하지 않는다), 아니면 무출력.

set -euo pipefail

# 관측 전용: jq 없으면 조용히 통과 (보호 가드와 달리 fail-closed 가 아니다 — 막을 것이 없다)
command -v jq >/dev/null 2>&1 || exit 0

# ACL 실행 중인 프로젝트에서만 (다른 프로젝트에 흔적을 남기지 않는다).
# Read 는 가장 잦은 도구이므로 jq 를 띄우기 전에 파일 존재만으로 먼저 빠진다 (비 ACL 프로젝트 고정 비용 0).
_acl_active="false"
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  _acl_active="true"
else
  for _p in .claude-*progress*.json; do
    if [[ -f "$_p" ]]; then _acl_active="true"; break; fi
  done
fi
[[ "$_acl_active" == "true" ]] || { cat >/dev/null 2>&1 || true; exit 0; }

INPUT=$(cat 2>/dev/null || true)
[[ -n "$INPUT" ]] || exit 0

# jq 1회: file_path / limit / offset 을 세 줄로 (@tsv 는 백슬래시를 이스케이프해 Windows 경로를 깨뜨리므로 쓰지 않는다)
PARSED=$(printf '%s' "$INPUT" \
  | jq -r '.tool_input | [(.file_path // ""), (.limit // ""), (.offset // "")] | map(tostring) | .[]' 2>/dev/null || true)
[[ -n "$PARSED" ]] || exit 0
FILE_PATH=""; LIMIT=""; OFFSET=""
{ IFS= read -r FILE_PATH; IFS= read -r LIMIT; IFS= read -r OFFSET; } <<< "$PARSED" || true
[[ -n "$FILE_PATH" ]] || exit 0

# limit 이 있으면 부분 읽기 — 관측 대상이 아니다
if [[ "$LIMIT" =~ ^[0-9]+$ ]] && [[ "$LIMIT" -gt 0 ]]; then
  exit 0
fi

# Windows 경로(C:\...) → bash 가 읽을 수 있게 구분자 정규화
FILE_PATH="${FILE_PATH//\\//}"
[[ -f "$FILE_PATH" ]] || exit 0

THRESHOLD="${ACL_LARGE_READ_LINES:-300}"
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -lt 1 ]]; then
  THRESHOLD=300
fi

LINES=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ' || echo 0)
[[ "$LINES" =~ ^[0-9]+$ ]] || exit 0
[[ "$LINES" -gt "$THRESHOLD" ]] || exit 0
BYTES=$(wc -c < "$FILE_PATH" 2>/dev/null | tr -d ' ' || echo 0)
[[ "$BYTES" =~ ^[0-9]+$ ]] || BYTES=0

# iteration (있으면) — 어느 iteration 이 채웠는지 사후 집계용
ITERATION=0
if [[ -f ".claude/ralph-loop.local.md" ]]; then
  ITERATION=$(sed -n 's/^iteration:[[:space:]]*\([0-9]\+\).*/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null | head -1 || true)
  [[ "$ITERATION" =~ ^[0-9]+$ ]] || ITERATION=0
fi
[[ "$OFFSET" =~ ^[0-9]+$ ]] || OFFSET=0

# 이벤트 기록 — scripts/lib/utils.sh 의 log_event 를 단일 출처로 재사용 (크기 캡 포함)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${PLUGIN_ROOT}/scripts/lib/utils.sh" ]]; then
  # shellcheck source=../scripts/lib/utils.sh
  . "${PLUGIN_ROOT}/scripts/lib/utils.sh"
  log_event "context.read.large" "$(jq -cn \
    --arg tool "Read" --arg f "$FILE_PATH" --argjson l "$LINES" --argjson b "$BYTES" \
    --argjson off "$OFFSET" --argjson th "$THRESHOLD" --argjson it "$ITERATION" \
    '{tool:$tool, file:$f, lines:$l, bytes:$b, offset:$off, threshold:$th, iteration:$it}' 2>/dev/null || echo '{}')" || true
fi

# 비차단 안내 — 파일 성격별 대안
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  .claude-*progress*.json|.claude-verification.json)
    ALT="이 파일은 shared-gate.sh status 로 요약만 본다 (전문 읽기 불필요)." ;;
  acl-decisions.jsonl)
    ALT="결정 로그는 shared-gate.sh record-decision --list [--last N] 으로 본다." ;;
  *.log|*.txt|*.jsonl)
    ALT="로그는 실패 줄만: grep -n -E 'FAIL|Error' <파일> | head -40, 또는 실행 자체를 shared-gate.sh run-capped -- <cmd> 로 바꾼다." ;;
  *.md)
    ALT="문서는 섹션만: shared-gate.sh doc-section --file <파일> --list 로 제목 좌표를 잡고 doc-section <US-ID|제목> 또는 Read offset/limit 로 읽는다." ;;
  *)
    ALT="필요한 부분만: Grep 으로 위치를 찾고 Read offset/limit 로 그 구간만 읽는다." ;;
esac
NOTE="[read-guard] ${BASENAME}: ${LINES}줄(임계 ${THRESHOLD}) 을 limit 없이 읽는다 — 컨텍스트를 채워 compact 를 부른다. ${ALT}"

jq -cn --arg n "$NOTE" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $n}}'
exit 0
