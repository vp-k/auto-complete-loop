---
description: "코드 리뷰 반복 수행 (gemini). codex(SEC/ERR/DATA) + gemini(PERF/CODE) 분할 리뷰"
argument-hint: "[--rounds N | --goal \"조건\"] <scope>"
---

# Code Review Loop Gemini → `/code-review-loop --mode gemini`

이 명령은 `/code-review-loop --mode gemini`의 별칭입니다.

`$ARGUMENTS`를 `--mode gemini`와 함께 `/code-review-loop`으로 전달하여 실행합니다.

Read `${CLAUDE_PLUGIN_ROOT}/commands/code-review-loop.md`

위 파일의 지침을 `--mode gemini`로 설정하여 따릅니다.
- codex-cli(SEC/ERR/DATA) + gemini-cli(PERF/CODE) 분할 독립 리뷰
- codex → gemini 순차 호출, 서로 결과 참조 금지
