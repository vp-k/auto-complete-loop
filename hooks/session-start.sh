#!/usr/bin/env bash
# SessionStart - Ralph Loop 자동 복구
# 세션 시작 시 progress 파일이 있으면 recover 정보를 컨텍스트에 주입
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_GATE="${PLUGIN_ROOT}/scripts/shared-gate.sh"

# shared-gate.sh 존재 확인
if [[ ! -f "$SHARED_GATE" ]]; then
  exit 0
fi

# progress 파일 탐지 (shared-gate.sh detect_progress_file와 동일 목록)
PROGRESS_FILE=""
for f in .claude-full-auto-progress.json .claude-full-auto-teams-progress.json \
         .claude-progress.json \
         .claude-plan-progress.json .claude-polish-progress.json \
         .claude-review-loop-progress.json .claude-e2e-progress.json \
         .claude-doc-check-progress.json; do
  if [[ -f "$f" ]]; then
    PROGRESS_FILE="$f"
    break
  fi
done

# progress 파일 없으면 복구 불필요
if [[ -z "$PROGRESS_FILE" ]]; then
  exit 0
fi

# jq 필요
if ! command -v jq &>/dev/null; then
  exit 0
fi

# completed 상태 progress 파일 정리
PROGRESS_STATUS=$(jq -r '.status // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
if [[ "$PROGRESS_STATUS" == "completed" ]]; then
  rm -f "$PROGRESS_FILE"
  rm -f ".claude-verification.json"
  exit 0
fi

# recover 실행하여 컨텍스트 수집
RECOVER_OUTPUT=$(bash "$SHARED_GATE" recover --progress-file "$PROGRESS_FILE" 2>/dev/null || true)

if [[ -z "$RECOVER_OUTPUT" ]]; then
  exit 0
fi

# Ralph Loop 상태 파일 확인
HAS_RALPH=false
[[ -f ".claude/ralph-loop.local.md" ]] && HAS_RALPH=true

# 모든 동적 값을 jq로 안전하게 JSON 생성
RALPH_RAW=""
if [[ "$HAS_RALPH" == "true" ]]; then
  # RALPH_INFO는 \\n prefix가 포함된 문자열이므로 실제 개행으로 변환
  RALPH_RAW=$(printf '\n[Ralph Loop] iteration=%s/%s, promise=%s' \
    "$(sed -n 's/^iteration: *\([0-9]*\)/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")" \
    "$(sed -n 's/^max_iterations: *\([0-9]*\)/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")" \
    "$(sed -n 's/^completion_promise: *"\(.*\)"/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")")
fi

ACTION_LINE=$(printf '\n\n[Action] Read %s → handoff.nextSteps 확인 → 이어서 진행' "$PROGRESS_FILE")

FULL_CONTEXT=$(printf '[Auto-Recovery] 진행 중인 작업이 감지되었습니다. progress 파일을 먼저 읽고 handoff.nextSteps를 따르세요.\n\n%s%s%s' \
  "$RECOVER_OUTPUT" "$RALPH_RAW" "$ACTION_LINE")

# jq로 안전하게 JSON 생성 (모든 특수문자 자동 이스케이프)
jq -n --arg ctx "$FULL_CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
