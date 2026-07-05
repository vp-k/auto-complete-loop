---
description: "프로덕션 릴리즈 전 폴리싱 (dual). codex-cli 1차 + codex-cli 2차 + Claude 3자 리뷰"
argument-hint: [기획 정의 문서 경로]
---

# Polish for Release Dual (→ /polish-for-release --mode dual)

이 명령은 `/polish-for-release --mode dual`의 별칭입니다.

`$ARGUMENTS`를 `--mode dual`와 함께 `/polish-for-release`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/polish-for-release.md
```

위 파일의 지침을 `--mode dual`로 설정하여 따릅니다.
- codex-cli 1차(리뷰) + codex-cli 2차(리뷰) + Claude Code(실행) 3자 리뷰
- codex 1·2차 모두 피드백만 제공, Claude Code가 실제 수정 수행
