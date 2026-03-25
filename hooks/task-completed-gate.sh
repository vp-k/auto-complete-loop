#!/usr/bin/env bash
# Agent Teams TaskCompleted Hook
# Phase 3 팀 리뷰에서 태스크 완료 시 최소 품질 기준 확인
#
# 동작:
# - 태스크 완료 시 finding 보고 형식 검증
# - FINDING_COUNT가 0이면 통과 (정상 완료)
# - finding이 있으면 형식 검증 후 통과
# - 형식 오류 시 exit code 2 반환 → 태스크 완료 거부 + 피드백
#
# Exit codes:
# 0 = 태스크 완료 허용
# 2 = 태스크 완료 거부 (피드백과 함께 재작업 요청)

# set -e 사용하지 않음: grep 매칭 실패 시 exit 1로 스크립트가 비정상 종료되는 것을 방지
set -uo pipefail

# Agent Teams 리뷰 태스크인지 확인
# CLAUDE_TEAM_NAME이 설정되어 있지 않으면 Agent Teams 컨텍스트가 아님 → 즉시 통과
if [[ -z "${CLAUDE_TEAM_NAME:-}" ]]; then
  exit 0
fi

# 태스크 완료 시 전달되는 환경 변수 확인
# 주의: CLAUDE_TASK_OUTPUT이 실제로 전달되지 않을 수 있음
# 환경변수가 없으면 검증을 스킵하고 리드에게 위임
TASK_OUTPUT="${CLAUDE_TASK_OUTPUT:-}"

if [[ -z "$TASK_OUTPUT" ]]; then
  # 환경변수가 전달되지 않는 경우 리드가 직접 검증하도록 통과
  exit 0
fi

# NO_FINDINGS는 즉시 통과
if echo "$TASK_OUTPUT" | grep -q "NO_FINDINGS"; then
  exit 0
fi

# FINDING_COUNT 확인
if ! echo "$TASK_OUTPUT" | grep -qE "FINDING_COUNT:[[:space:]]*[0-9]+"; then
  echo "FINDING_COUNT가 누락되었습니다. 보고서 마지막에 'FINDING_COUNT: N'을 추가해주세요."
  exit 2
fi

# finding 형식 검증 (최소 1개의 finding이 올바른 형식인지)
if ! echo "$TASK_OUTPUT" | grep -qE "###[[:space:]]+(SEC|ERR|DATA|PERF|CODE|LIVE)-(CRITICAL|HIGH|MEDIUM|LOW)-[0-9]+"; then
  FINDING_COUNT=$(echo "$TASK_OUTPUT" | grep -oE "[0-9]+" | tail -1) || FINDING_COUNT="0"
  if [[ "${FINDING_COUNT:-0}" -gt 0 ]]; then
    echo "finding이 있지만 올바른 형식이 아닙니다."
    echo "형식: ### {CATEGORY}-{SEVERITY}-{번호}: {제목}"
    echo "카테고리: SEC, ERR, DATA, PERF, CODE, LIVE"
    echo "심각도: CRITICAL, HIGH, MEDIUM, LOW"
    exit 2
  fi
fi

# 모든 검증 통과
exit 0
