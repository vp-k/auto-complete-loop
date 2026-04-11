---
description: "코드 리뷰 반복 수행 (solo). Claude 다관점 3-pass 순차 리뷰"
argument-hint: "[--rounds N | --goal \"조건\"] <scope>"
---

# Code Review Loop Solo → `/code-review-loop --mode solo`

이 명령은 `/code-review-loop --mode solo`의 별칭입니다.

`$ARGUMENTS`를 `--mode solo`와 함께 `/code-review-loop`으로 전달하여 실행합니다.

Read `${CLAUDE_PLUGIN_ROOT}/commands/code-review-loop.md`

위 파일의 지침을 `--mode solo`로 설정하여 따릅니다.
- Claude 단독 3-pass 순차 리뷰 (SEC+ERR → DATA+PERF → CODE+IMPL)
- 외부 AI 불필요
