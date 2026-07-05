---
description: "기획 문서 완성 (3자 자동 토론형). codex 1차 + codex 2차 + Claude Code 3자 토론"
argument-hint: <기획 정의 문서 경로>
---

# Plan Docs Auto Dual (→ /plan-docs-auto --mode dual)

이 명령은 `/plan-docs-auto --mode dual`의 별칭입니다.

`$ARGUMENTS`를 `--mode dual`와 함께 `/plan-docs-auto`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/plan-docs-auto.md
```

위 파일의 지침을 `--mode dual`로 설정하여 따릅니다.
- codex 1차 + codex 2차 + Claude Code 3자 자동 토론 (codex-cli 두 번 독립 호출)
- codex 1차 → codex 2차 → Claude Code 순서로 순차 검토/반론
