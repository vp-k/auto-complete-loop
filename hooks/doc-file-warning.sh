#!/usr/bin/env bash
# PreToolUse:Write - 불필요 문서 파일 생성 차단
# README.md, CHANGELOG.md 등 요청하지 않은 문서 파일 생성을 차단
#
# 게이팅: 플러그인 워크플로우 활성 시(.claude-*progress*.json 존재)에만 동작.
# 비플러그인 프로젝트에서는 무출력 통과 (오탐 방지).
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: 차단 시 {"decision": "block", "reason": "..."} / 통과 시 무출력 (approve 금지)

set -euo pipefail

# 훅 입력: stdin 우선, 비어 있으면 CLAUDE_HOOK_INPUT 폴백
# (stdin은 게이팅 판정 전에 소비 — 파이프 writer의 EPIPE 방지)
INPUT=$(cat 2>/dev/null || true)
if [[ -z "$INPUT" ]]; then
  INPUT="${CLAUDE_HOOK_INPUT:-}"
fi

# ─── 워크플로우 활성 게이팅 ───
_ACTIVE=0
for _pf in .claude-*progress*.json; do
  if [[ -f "$_pf" ]]; then
    _ACTIVE=1
    break
  fi
done
if [[ "$_ACTIVE" -ne 1 ]]; then
  exit 0
fi
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# 파일명만 추출
FILENAME=$(basename "$FILE_PATH")

# 허용된 문서 파일 (프로젝트에서 의도적으로 사용하는 것들)
ALLOWED_DOCS="DONE.md|SPEC.md|SCOPE_REDUCTIONS.md|CLAUDE.md|SKILL.md|MEMORY.md"

# 경고 대상: 일반적인 문서 파일 패턴 (ALLOWED_DOCS와 disjoint)
case "$FILENAME" in
  README.md|CHANGELOG.md|CONTRIBUTING.md|LICENSE.md|AUTHORS.md|HISTORY.md|TODO.md)
    echo "{\"decision\": \"block\", \"reason\": \"${FILENAME} 생성이 차단되었습니다. 명시적으로 요청된 경우에만 문서 파일을 생성하세요. 프로젝트에서 허용된 문서: ${ALLOWED_DOCS}\"}"
    exit 0
    ;;
esac

# 통과 → 무출력 (권한 판정 유보)
exit 0
