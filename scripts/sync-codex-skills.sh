#!/usr/bin/env bash
# Codex Skill 미러링 스크립트
# auto-complete-loop의 리뷰/기획 스킬을 대상 프로젝트의 .agents/skills/에 미러링
# Codex CLI 공식 디스커버리 경로: .agents/skills/*/SKILL.md
# 참고: https://developers.openai.com/codex/skills
#
# 사용법: bash sync-codex-skills.sh [대상_프로젝트_루트]
# 기본값: 현재 디렉토리

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-.}"

# 미러링 대상 스킬 (Codex가 실제 사용하는 리뷰/기획 스킬만)
MIRROR_SKILLS=(
  "code-review"
  "code-review-solo"
  "team-code-review"
  "pm-planning"
)

echo "=== Codex Skill Mirroring ==="
echo "Source: ${PLUGIN_ROOT}/skills/"
echo "Target: ${TARGET_ROOT}/.agents/skills/"
echo ""

MIRRORED=0
SKIPPED=0

for SKILL_NAME in "${MIRROR_SKILLS[@]}"; do
  SRC="${PLUGIN_ROOT}/skills/${SKILL_NAME}/SKILL.md"
  DST_DIR="${TARGET_ROOT}/.agents/skills/${SKILL_NAME}"
  DST="${DST_DIR}/SKILL.md"

  if [[ ! -f "$SRC" ]]; then
    echo "SKIP: ${SKILL_NAME} — source not found"
    ((SKIPPED++))
    continue
  fi

  mkdir -p "$DST_DIR"

  # SKILL.md 정제: CLAUDE_PLUGIN_ROOT 참조 처리 (구체적 패턴 우선, catch-all 마지막)
  sed \
    -e 's|\${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate\.sh|# [Claude Code only] shared-gate.sh|g' \
    -e 's|bash \${CLAUDE_PLUGIN_ROOT}|# [Claude Code only] bash|g' \
    -e 's|Read \${CLAUDE_PLUGIN_ROOT}|# [Claude Code only] Read|g' \
    -e 's|\${CLAUDE_PLUGIN_ROOT}|# [Claude Code only path]|g' \
    "$SRC" > "$DST"

  echo "OK:   ${SKILL_NAME} → .agents/skills/${SKILL_NAME}/SKILL.md"
  ((MIRRORED++))
done

echo ""
echo "Mirrored: ${MIRRORED}, Skipped: ${SKIPPED}"

# AGENTS.md 생성 (Codex CLI 프로젝트 지침 파일)
AGENTS_MD="${TARGET_ROOT}/AGENTS.md"

if [[ -f "$AGENTS_MD" ]]; then
  echo ""
  echo "AGENTS.md already exists — skipping (manual merge required)"
else
  cat > "$AGENTS_MD" << 'AGENTS_EOF'
# AGENTS.md

## Role

You are a code reviewer. When asked to review code, analyze it across 5 categories with severity-based findings.

## Review Categories

- **SEC** (Security): Injection, XSS, auth bypass, SSRF, deserialization, LLM output trust
- **ERR** (Error Handling): Missing error handling, swallowed exceptions, incorrect propagation
- **DATA** (Data Integrity): Input validation, schema mismatches, missing constraints
- **PERF** (Performance): N+1 queries, missing pagination, memory leaks
- **CODE** (Code Quality): Dead code, logic errors, god objects, feature envy

## Finding Format

```
### {CATEGORY}-{SEVERITY}-{NUMBER}

**File**: `path/to/file.ext:line`
**Issue**: One-line description
**Evidence**: Code snippet or explanation
**Fix suggestion**: Brief fix description
```

Severity: CRITICAL, HIGH, MEDIUM, LOW

## Rules

1. Only report confident findings with specific file:line references
2. No style/formatting suggestions
3. Focus on production-impacting issues
4. End with `FINDING_COUNT: N`

## Available Skills

Skills in `.agents/skills/` provide additional context for specific review types.
AGENTS_EOF

  echo ""
  echo "Created: AGENTS.md"
fi

echo ""
echo "Done. Run 'codex' in ${TARGET_ROOT} to verify skill discovery."
