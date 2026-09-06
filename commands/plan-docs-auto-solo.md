---
description: "기획 문서 완성 (솔로형). Claude 작성 + fresh-context 검토 서브에이전트"
argument-hint: <definition(overview.md)> <doclist(README.md)>
---

# Plan Docs Auto Solo (→ /plan-docs-auto --mode solo)

이 명령은 `/plan-docs-auto --mode solo`의 별칭입니다.

`$ARGUMENTS`를 `--mode solo`와 함께 `/plan-docs-auto`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/plan-docs-auto.md
```

위 파일의 지침을 `--mode solo`로 설정하여 따릅니다.
- 검토는 Agent 툴로 호출한 **fresh-context 검토 서브에이전트**가 수행 (같은 컨텍스트의 역할극이 아님)
- 외부 AI 불필요 — Agent 툴 사용 불가 시에만 동일 기준의 자기검토로 폴백
