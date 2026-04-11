---
description: "End-to-end project automation with Agent Teams. 3-way parallel code review + Live Testing"
argument-hint: <요구사항 (자연어)>
---

# Full Auto Teams (→ /full-auto --mode teams)

이 명령은 `/full-auto --mode teams`의 별칭입니다.

`$ARGUMENTS`를 `--mode teams`와 함께 `/full-auto`로 전달하여 실행합니다.

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/full-auto.md
```

위 파일의 지침을 `--mode teams`로 설정하여 따릅니다.
- PHASE_3_SKILL: `skills/team-code-review/SKILL.md`
- PROMISE_TAG: `FULL_AUTO_TEAMS_COMPLETE`
- PROGRESS_FILE: `.claude-full-auto-teams-progress.json`
- Agent Teams 3자 병렬 리뷰 + Live App Testing

## 전제 조건

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 설정 필요 (settings.json 또는 환경 변수)
- Claude Code v2.1.32 이상

## teams 모드 특화 규칙

### Phase 3 특화: Agent Teams 팀 리뷰

- 복구 감지 시: Agent Team은 세션 재개가 불가하므로 **새로 생성**
- 팀 cleanup 필수: Phase 3 완료 또는 iteration 종료 시 반드시 Agent Team cleanup
- 팀 리뷰어 독립성: 각 팀원은 독립적으로 리뷰, 리드가 결과를 조율
- 높은 severity 채택: 팀원간 severity 의견 불일치 시 높은 쪽 채택

### 포기 방지 규칙 추가

- Agent Teams 생성 실패 시 → 설정 확인 → 재시도
- Teammate 중단 시 → 리드가 해당 관점을 직접 리뷰하여 대체
- 팀 coordination 에러 시 → cleanup 후 재생성 (최대 2회)
- 3회 실패 시 → fallback으로 기존 `skills/code-review/SKILL.md` 사용
