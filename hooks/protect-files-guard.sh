#!/usr/bin/env bash
# PreToolUse:Write|Edit - 통합 파일 보호 가드
# 1. 진행 상태 파일 수정 경고 (warn)
# 2. 기획 문서 보호 (full-auto Phase 2+ block)
# 3. CLAUDE.md 보호 (full-auto Phase 2+ block)
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: {"decision": "block"|"approve", "reason": "..."} 또는 {"decision": "approve"}

# --- 공통 boilerplate (block-no-verify.sh 패턴 준수) ---

set -euo pipefail

# jq 미설치 시 fail-closed
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 파일 보호를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

INPUT=$(cat)

# JSON 파싱 실패 시 fail-closed
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 파일 보호를 검증할 수 없어 차단합니다."}'
  exit 0
}

# 파일 경로가 비어있으면 통과 (도구가 file_path를 사용하지 않는 경우)
if [[ -z "$FILE_PATH" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

FILENAME=$(basename "$FILE_PATH")

# --- Guard 1: 진행 상태 파일 보호 (warn) ---

case "$FILENAME" in
  .claude-quality-baseline.json|.claude-verification.json)
    echo "{\"decision\": \"approve\", \"reason\": \"WARNING: ${FILENAME}을 수정하려 합니다. 이 파일은 품질 게이트 상태를 추적합니다. shared-gate.sh를 통한 정당한 수정인지 확인하세요.\"}"
    exit 0
    ;;
esac

if [[ "$FILENAME" =~ ^\.claude-.*-progress\.json$ ]]; then
  echo "{\"decision\": \"approve\", \"reason\": \"WARNING: ${FILENAME}을 수정하려 합니다. 이 파일은 워크플로우 진행 상태를 추적합니다. shared-gate.sh를 통한 정당한 수정인지 확인하세요.\"}"
  exit 0
fi

# --- Guard 2 & 3: Phase 기반 보호 대상 판별 ---

PROTECTION_TYPE=""

# CLAUDE.md 보호
if [[ "$FILENAME" == "CLAUDE.md" ]]; then
  PROTECTION_TYPE="claude_md"
fi

# 기획 문서 보호
if [[ -z "$PROTECTION_TYPE" ]]; then
  case "$FILENAME" in
    overview.md|SPEC.md)
      PROTECTION_TYPE="spec_doc"
      ;;
  esac
fi

if [[ -z "$PROTECTION_TYPE" ]]; then
  if [[ "$FILE_PATH" == *"/docs/specs/"* ]] || [[ "$FILE_PATH" == *"/docs/plans/"* ]] \
  || [[ "$FILE_PATH" == *"docs/specs/"* ]] || [[ "$FILE_PATH" == *"docs/plans/"* ]] \
  || [[ "$FILE_PATH" == *"\\docs\\specs\\"* ]] || [[ "$FILE_PATH" == *"\\docs\\plans\\"* ]]; then
    PROTECTION_TYPE="spec_doc"
  fi
fi

# 보호 대상이 아니면 통과
if [[ -z "$PROTECTION_TYPE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# --- Phase 판별 (1회만 실행, 결과 공유) ---

PROGRESS_FILE=".claude-full-auto-progress.json"
if [[ ! -f "$PROGRESS_FILE" ]]; then
  # full-auto 워크플로우가 아님 → allow
  echo '{"decision": "approve"}'
  exit 0
fi

CURRENT_PHASE=$(jq -r '
  .phases // {} | to_entries[]
  | select(.value.status == "in_progress")
  | .key' "$PROGRESS_FILE" 2>/dev/null | head -1) || {
  # progress 파일 파싱 실패 시 fail-closed (보호 대상 파일이므로)
  echo "{\"decision\": \"block\", \"reason\": \"progress 파일 파싱 실패. ${FILENAME} 수정을 차단합니다.\"}"
  exit 0
}

# Phase 판별 실패 시 fail-closed (보호 대상 파일이므로)
if [[ -z "$CURRENT_PHASE" ]]; then
  echo "{\"decision\": \"block\", \"reason\": \"현재 Phase를 판별할 수 없습니다. 안전을 위해 ${FILENAME} 수정을 차단합니다.\"}"
  exit 0
fi

# --- Phase 2, 3, 4에서 보호 대상 수정 차단 ---

case "$CURRENT_PHASE" in
  phase_2|phase_3|phase_4)
    if [[ "$PROTECTION_TYPE" == "claude_md" ]]; then
      echo "{\"decision\": \"block\", \"reason\": \"자동화 단계(${CURRENT_PHASE})에서 CLAUDE.md 수정이 차단되었습니다. CLAUDE.md는 사용자가 명시적으로 요청한 경우에만 수정하세요.\"}"
    else
      echo "{\"decision\": \"block\", \"reason\": \"구현 단계(${CURRENT_PHASE})에서 기획 문서(${FILENAME}) 수정이 차단되었습니다. 기획 문서는 Phase 0~1에서만 수정할 수 있습니다. 스코프 변경이 필요하면 SCOPE_REDUCTIONS.md에 기록하세요.\"}"
    fi
    exit 0
    ;;
esac

echo '{"decision": "approve"}'
