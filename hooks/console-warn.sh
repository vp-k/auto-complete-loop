#!/usr/bin/env bash
# PostToolUse:Edit|Write - 디버그 코드 경고
# 편집/생성된 파일에 console.log, debugger, print 등 디버그 코드가 있으면 경고
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: 경고 메시지 (있을 경우)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# 파일이 없거나 바이너리면 스킵
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# 테스트/설정 파일은 스킵
case "$FILE_PATH" in
  *.test.*|*.spec.*|*__tests__/*|*_test.go|*_test.py|*.config.*|*.json|*.md|*.sh|*.yml|*.yaml)
    exit 0
    ;;
esac

# 디버그 코드 패턴 검색
WARNINGS=""

# JavaScript/TypeScript
if echo "$FILE_PATH" | grep -qE '\.(js|ts|jsx|tsx)$'; then
  FOUND=$(grep -n 'console\.\(log\|debug\|warn\|error\|info\)\|debugger' "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    WARNINGS="⚠️ 디버그 코드 발견 (${FILE_PATH}):\n${FOUND}"
  fi
fi

# Python
if echo "$FILE_PATH" | grep -qE '\.py$'; then
  FOUND=$(grep -n 'print(\|breakpoint()\|pdb\.set_trace\|import pdb' "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    WARNINGS="⚠️ 디버그 코드 발견 (${FILE_PATH}):\n${FOUND}"
  fi
fi

# Dart/Flutter
if echo "$FILE_PATH" | grep -qE '\.dart$'; then
  FOUND=$(grep -n 'print(\|debugPrint(\|debugger(' "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    WARNINGS="⚠️ 디버그 코드 발견 (${FILE_PATH}):\n${FOUND}"
  fi
fi

# Go
if echo "$FILE_PATH" | grep -qE '\.go$'; then
  FOUND=$(grep -n 'fmt\.Print\|log\.Print' "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    WARNINGS="⚠️ 디버그 코드 발견 (${FILE_PATH}):\n${FOUND}"
  fi
fi

if [ -n "$WARNINGS" ]; then
  echo -e "$WARNINGS"
  echo "→ 의도적인 로깅이 아니라면 커밋 전에 제거하세요."
fi
