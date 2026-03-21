#!/usr/bin/env bash
# PreCompact - 컴팩션 전 컨텍스트 요약 출력
# /compact 실행 직전에 progress 파일의 현재 상태를 stdout에 출력하여
# compact 요약에 포함되도록 함. 이를 통해 컴팩션 후 핵심 컨텍스트를 복구 가능.
# 주의: 이 훅은 progress 파일을 수정하지 않음. handoff 업데이트는 AI가 수동으로 수행해야 함.
#
# 출력: 컴팩션 요약에 포함될 텍스트

set -euo pipefail

# progress 파일 찾기
PROGRESS_FILE=""
for f in .claude-progress.json .claude-review-loop-progress.json .claude-implement-progress.json .claude-plan-progress.json; do
  if [ -f "$f" ]; then
    PROGRESS_FILE="$f"
    break
  fi
done

if [ -z "$PROGRESS_FILE" ]; then
  echo "PreCompact: progress 파일 없음 — 컨텍스트 보존 스킵"
  exit 0
fi

# jq 필요
if ! command -v jq &>/dev/null; then
  echo "PreCompact: jq 미설치 — handoff 자동 저장 스킵"
  exit 0
fi

# 현재 상태 요약 출력 (compact 요약에 포함됨)
CURRENT_PHASE=$(jq -r '.currentPhase // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
STATUS=$(jq -r '.status // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
NEXT_STEPS=$(jq -r '.handoff.nextSteps // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")
CURRENT_APPROACH=$(jq -r '.handoff.currentApproach // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")
WARNINGS=$(jq -r '.handoff.warnings // "없음"' "$PROGRESS_FILE" 2>/dev/null || echo "없음")

echo "=== PreCompact 컨텍스트 보존 ==="
echo "Progress: ${PROGRESS_FILE}"
echo "Phase: ${CURRENT_PHASE} | Status: ${STATUS}"
echo "Next Steps: ${NEXT_STEPS}"
echo "Current Approach: ${CURRENT_APPROACH}"
if [ "$WARNINGS" != "없음" ] && [ "$WARNINGS" != "null" ]; then
  echo "Warnings: ${WARNINGS}"
fi
echo "=== 컴팩션 후 progress 파일을 먼저 읽어 컨텍스트를 복구하세요 ==="
