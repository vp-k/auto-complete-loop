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
- PHASE_1_SKILL: `skills/doc-planning-solo/SKILL.md`
- PHASE_3_SKILL: `skills/code-review-solo/SKILL.md`
- 외부 AI(codex, gemini) 없이 Claude 단독 다관점 리뷰
