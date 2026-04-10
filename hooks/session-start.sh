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

# progress 파일 없으면 복구 불필요 — 단, 프로젝트 컨텍스트 주입 (A5)
if [[ -z "$PROGRESS_FILE" ]]; then
  CONTEXT_HINTS=""
  [[ -f ".claude/acl-learnings.local.md" ]] && CONTEXT_HINTS="${CONTEXT_HINTS}\n- .claude/acl-learnings.local.md (이전 워크플로우 학습 내역)"
  [[ -f "overview.md" ]] && CONTEXT_HINTS="${CONTEXT_HINTS}\n- overview.md (프로젝트 정의 문서)"
  for _spec in SPEC.md docs/SPEC.md; do
    [[ -f "$_spec" ]] && { CONTEXT_HINTS="${CONTEXT_HINTS}\n- ${_spec} (기술 사양)"; break; }
  done

  if [[ -n "$CONTEXT_HINTS" ]]; then
    CTX_MSG=$(printf '[Project Context] 이전 작업 컨텍스트가 감지되었습니다. 참고할 문서:%b' "$CONTEXT_HINTS")
    jq -n --arg ctx "$CTX_MSG" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }'
  fi
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
RECOVER_STDERR=$(mktemp 2>/dev/null || echo "/tmp/acl-recover-$$")
RECOVER_OUTPUT=$(bash "$SHARED_GATE" recover --progress-file "$PROGRESS_FILE" 2>"$RECOVER_STDERR" || true)
if [[ -s "$RECOVER_STDERR" ]]; then
  RECOVER_OUTPUT="${RECOVER_OUTPUT}\n[recover warning] $(head -3 "$RECOVER_STDERR")"
fi
rm -f "$RECOVER_STDERR"

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
