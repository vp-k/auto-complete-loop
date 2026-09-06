---
description: "End-to-end project automation (solo). No external AI dependency, Claude multi-perspective review"
argument-hint: <요구사항 (자연어)>
---

# Full Auto Solo (→ /full-auto --mode solo)

이 명령은 `/full-auto --mode solo`의 별칭입니다.

`$ARGUMENTS`를 `--mode solo`과 함께 `/full-auto`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/full-auto.md
```

위 파일의 지침을 `--mode solo`로 설정하여 따릅니다.
- PHASE_1_SKILL: `skills/doc-planning/SKILL.md` (`{REVIEW_MODE}` = `solo`로 치환 — 통합 스킬의 Step 1-2/1-6 분기가 solo 경로를 선택)
- PHASE_3_SKILL: `skills/code-review-solo/SKILL.md`
- 외부 AI(codex) 없이 Claude 단독 다관점 리뷰 — Phase 1 문서 검토는 **fresh-context 검토 서브에이전트**(Agent 툴)가 수행
