#!/usr/bin/env bash
# PostToolUse:Edit|Write - 디버그 코드 경고
# 편집/생성된 파일에 console.log, debugger, print 등 디버그 코드가 있으면 경고
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: 경고 메시지 (있을 경우)

set -euo pipefail

# 훅 입력: stdin 우선, 비어 있으면 CLAUDE_HOOK_INPUT 폴백
# (stdin은 게이팅 판정 전에 소비 — 파이프 writer의 EPIPE 방지)
INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
  INPUT="${CLAUDE_HOOK_INPUT:-}"
fi

# ─── 워크플로우 활성 게이팅 ───
# 플러그인 워크플로우 활성 시(.claude-*progress*.json 존재)에만 경고.
# 비플러그인 프로젝트에서는 침묵 (오탐/노이즈 방지).
_ACTIVE=0
for _pf in .claude-*progress*.json; do
  if [ -f "$_pf" ]; then
    _ACTIVE=1
    break
  fi
done
if [ "$_ACTIVE" -ne 1 ]; then
  exit 0
fi
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

# Rust
if echo "$FILE_PATH" | grep -qE '\.rs$'; then
  FOUND=$(grep -n 'dbg!\|println!\|eprintln!' "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FOUND" ]; then
    WARNINGS="⚠️ 디버그 코드 발견 (${FILE_PATH}):\n${FOUND}"
  fi
fi

if [ -n "$WARNINGS" ]; then
  echo -e "$WARNINGS"
  echo "→ 의도적인 로깅이 아니라면 커밋 전에 제거하세요."
fi
