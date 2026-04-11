---
description: "프로덕션 릴리즈 전 폴리싱 (gemini). codex-cli + gemini-cli + Claude 3자 리뷰"
argument-hint: [기획 정의 문서 경로]
---

# Polish for Release Gemini (→ /polish-for-release --mode gemini)

이 명령은 `/polish-for-release --mode gemini`의 별칭입니다.

`$ARGUMENTS`를 `--mode gemini`와 함께 `/polish-for-release`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/polish-for-release.md
```

위 파일의 지침을 `--mode gemini`로 설정하여 따릅니다.
- codex-cli(리뷰) + gemini-cli(리뷰) + Claude Code(실행) 3자 리뷰
- codex와 gemini는 피드백만 제공, Claude Code가 실제 수정 수행
