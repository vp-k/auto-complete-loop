---
description: "코드 리뷰 반복 수행 (dual). codex#1(SEC/ERR/DATA) + codex#2(PERF/CODE) 분할 리뷰"
argument-hint: "[--rounds N | --goal \"조건\"] <scope>"
---

# Code Review Loop Dual → `/code-review-loop --mode dual`

이 명령은 `/code-review-loop --mode dual`의 별칭입니다.

`$ARGUMENTS`를 `--mode dual`과 함께 `/code-review-loop`으로 전달하여 실행합니다.

Read `${CLAUDE_PLUGIN_ROOT}/commands/code-review-loop.md`

위 파일의 지침을 `--mode dual`로 설정하여 따릅니다.
- codex-cli 1차(SEC/ERR/DATA) + codex-cli 2차(PERF/CODE) 분할 독립 리뷰
- codex 1차 → codex 2차 순차 호출, 서로 결과 참조 금지
