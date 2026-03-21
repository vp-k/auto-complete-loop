#!/usr/bin/env bash
# PreCompact - 컴팩션 전 컨텍스트 요약 출력
# /compact 실행 직전에 progress 파일의 현재 상태를 stdout에 출력하여
# compact 요약에 포함되도록 함. 이를 통해 컴팩션 후 핵심 컨텍스트를 복구 가능.
# 주의: 이 훅은 progress 파일을 수정하지 않음. handoff 업데이트는 AI가 수동으로 수행해야 함.
#
# 출력: 컴팩션 요약에 포함될 텍스트

set -euo pipefail

# progress 파일 찾기 (shared-gate.sh detect_progress_file과 동일 순서)
PROGRESS_FILE=""
for f in .claude-full-auto-progress.json .claude-progress.json \
         .claude-plan-progress.json .claude-polish-progress.json \
         .claude-review-loop-progress.json .claude-e2e-progress.json \
         .claude-doc-check-progress.json; do
  if [ -f "$f" ]; then
    PROGRESS_FILE="$f"
    break
  fi
done

if [ -z "$PROGRESS_FILE" ]; then
  echo "PreCompact: progress 파일 없음 — 컨텍스트 출력 스킵"
  exit 0
fi

# jq 필요
if ! command -v jq &>/dev/null; then
  echo "PreCompact: jq 미설치 — 컨텍스트 출력 스킵"
  exit 0
fi

# 현재 단계 감지 (스키마별 분기)
CURRENT_PHASE=$(jq -r '.currentPhase // empty' "$PROGRESS_FILE" 2>/dev/null || true)
CURRENT_ROUND=$(jq -r '.currentRound // empty' "$PROGRESS_FILE" 2>/dev/null || true)
STATUS=$(jq -r '.status // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
NEXT_STEPS=$(jq -r '.handoff.nextSteps // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")
CURRENT_APPROACH=$(jq -r '.handoff.currentApproach // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")
WARNINGS=$(jq -r '.handoff.warnings // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")

# 현재 진행 단계 표시 (스키마별)
STAGE_INFO=""
if [ -n "$CURRENT_PHASE" ]; then
  STAGE_INFO="Phase: ${CURRENT_PHASE}"
elif [ -n "$CURRENT_ROUND" ]; then
  STAGE_INFO="Round: ${CURRENT_ROUND}"
else
  # steps 배열에서 현재 in_progress 단계 찾기
  ACTIVE_STEP=$(jq -r '[.steps[]? | select(.status == "in_progress") | .label // .name] | first // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")
  STAGE_INFO="Active Step: ${ACTIVE_STEP}"
fi

echo "=== PreCompact 컨텍스트 요약 ==="
echo "Progress: ${PROGRESS_FILE}"
echo "${STAGE_INFO} | Status: ${STATUS}"
echo "Next Steps: ${NEXT_STEPS}"
echo "Current Approach: ${CURRENT_APPROACH}"
if [ "$WARNINGS" != "없음" ] && [ "$WARNINGS" != "null" ] && [ -n "$WARNINGS" ]; then
  echo "Warnings: ${WARNINGS}"
fi
echo "=== 컴팩션 후 progress 파일을 먼저 읽어 컨텍스트를 복구하세요 ==="
