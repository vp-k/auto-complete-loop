#!/usr/bin/env bash
# PreToolUse:Write - 불필요 문서 파일 생성 경고
# README.md, CHANGELOG.md 등 요청하지 않은 문서 파일 생성을 경고
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: {"decision": "block", "reason": "..."} 또는 {"decision": "allow"}

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# 파일명만 추출
FILENAME=$(basename "$FILE_PATH")

# 허용된 문서 파일 (프로젝트에서 의도적으로 사용하는 것들)
ALLOWED_DOCS="DONE.md|SPEC.md|SCOPE_REDUCTIONS.md|CLAUDE.md|SKILL.md|MEMORY.md"

# 경고 대상: 일반적인 문서 파일 패턴
case "$FILENAME" in
  README.md|CHANGELOG.md|CONTRIBUTING.md|LICENSE.md|AUTHORS.md|HISTORY.md|TODO.md)
    # 허용 목록에 없는 문서 파일
    if ! echo "$FILENAME" | grep -qE "^($ALLOWED_DOCS)$"; then
      echo "{\"decision\": \"block\", \"reason\": \"${FILENAME} 생성이 차단되었습니다. 명시적으로 요청된 경우에만 문서 파일을 생성하세요. 프로젝트에서 허용된 문서: ${ALLOWED_DOCS}\"}"
      exit 0
    fi
    ;;
esac

echo '{"decision": "allow"}'
