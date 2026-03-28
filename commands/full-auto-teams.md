---
description: "기획→구현→팀 리뷰→검수 올인원. Agent Teams로 3자 병렬 코드 리뷰 + Live Testing"
argument-hint: <요구사항 (자연어)>
---

# Full Auto Teams: Agent Teams 기반 팀 리뷰 (오케스트레이터)

한 줄 요구사항으로 **기획 문서 작성 → 코드 구현 → Agent Teams 팀 코드 리뷰 → 최종 검증**까지 자동 완주합니다.

**full-auto와의 차이**: Phase 3에서 Agent Teams를 활용한 3자 병렬 리뷰 + Live App Testing.
**역할 분담**: Claude(리드) = PM + 구현 + 리뷰 조율, Teammates = 독립 리뷰 + 상호 도전
**비용 참고**: Phase 3에서 3개 독립 Claude 인스턴스 → full-auto 대비 토큰 비용 높음

## 전제 조건

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 설정 필요 (settings.json 또는 환경 변수)
- Claude Code v2.1.32 이상

## 파라미터

- PROMISE_TAG: `FULL_AUTO_TEAMS_COMPLETE`
- PROGRESS_FILE: `.claude-full-auto-teams-progress.json`
- PHASE_3_SKILL: `skills/team-code-review/SKILL.md`
- PHASE_3_STEPS: Step 3-1 ~ 3-7

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "커뮤니티 사이트를 만들어줘")

## Step 0: Agent Teams 사전 확인 (Phase 0 전에 반드시 실행)

**이 단계는 Phase 0보다 먼저 실행해야 합니다.**

1. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 환경 변수 확인:
   ```bash
   echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-not_set}"
   ```
2. **설정되어 있지 않으면** (`not_set` 또는 빈 값):
   - `~/.claude/settings.json`을 읽고, `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 키가 없으면 자동 추가:
     ```bash
     jq '. + {"env": ((.env // {}) + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"})}' ~/.claude/settings.json > /tmp/claude-settings.tmp && mv /tmp/claude-settings.tmp ~/.claude/settings.json
     ```
   - 사용자에게 안내:
     > Agent Teams 설정을 `~/.claude/settings.json`에 추가했습니다.
     > 새 세션에서 `/full-auto-teams <요구사항>`을 다시 실행해주세요.
   - **여기서 중단** (settings.json의 env는 새 세션에서 적용됨)
3. **설정되어 있으면** (`1`) → Phase 0으로 진행

## 아키텍처: full-auto 확장 + Phase 3 팀 리뷰

```
이 파일 (오케스트레이터) — Phase 3만 차별화, 나머지는 공유 규칙 파일 참조
    ↓ Read로 Phase별 스킬 로드
    ├── skills/pm-planning/SKILL.md     (Phase 0)
    ├── skills/doc-planning/SKILL.md    (Phase 1)
    ├── skills/implementation/SKILL.md  (Phase 2)
    ├── skills/team-code-review/SKILL.md (Phase 3 — ★ Agent Teams 팀 리뷰 ★)
    └── skills/verification/SKILL.md    (Phase 4)
```

## 5-Phase 워크플로우

```
Phase 0: PM Planning ─── 사용자 승인 (유일한 상호작용)
    ↓
Phase 1: Planning ───── codex 토론으로 기획 문서 완성
    ↓ [일관성 검사 #1: doc↔doc]
    ↓ [Pre-mortem 가드: blocking Tiger 미해결 시 Phase 2 진입 금지]
Phase 2: Implementation ── Claude 직접 구현 + TDD + Acceptance Criteria
    ↓ [일관성 검사 #2: doc↔code]
Phase 3: ★ Team Code Review ★ ── Agent Teams 3자 병렬 리뷰 + Live Testing
    ↓ [일관성 검사 #3: code quality]
Phase 4: Verification ─── 최종 검증 + 폴리싱 + Launch Readiness
    ↓
<promise>FULL_AUTO_TEAMS_COMPLETE</promise>
```

## 공통 규칙 로드

```
Read ${CLAUDE_PLUGIN_ROOT}/rules/orchestration-rules.md
Read ${CLAUDE_PLUGIN_ROOT}/rules/phase-transition-rules.md
```

위 두 파일에 정의된 파라미터(`{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`)는
이 파일 상단의 "파라미터" 섹션 값으로 치환하여 적용합니다.

---

## Phase 3 특화: Agent Teams 팀 리뷰

### 복구 감지 시 Phase 3 특화 처리

Phase 3 재개 시: Agent Team은 세션 재개가 불가하므로 **새로 생성**해야 합니다.

### Handoff Phase 3 추가 필드

```json
"handoff": {
  "lastIteration": 5,
  "currentPhase": "phase_3",
  "completedInThisIteration": "Phase 3: Team Review Round 1 완료, 5건 수정",
  "nextSteps": "Phase 3: Round 2 팀 리뷰 (Agent Team 재생성 필요)",
  "keyDecisions": ["SEC-HIGH-001 수정: parameterized query 적용"],
  "warnings": "live-tester가 로그인 flow에서 실패 감지",
  "currentApproach": "Agent Teams Phase 3"
}
```

## 강제 규칙 추가 (공통 규칙 위에 적용)

11. **팀 cleanup 필수**: Phase 3 완료 또는 iteration 종료 시 반드시 Agent Team cleanup
12. **팀 리뷰어 독립성**: 각 팀원은 독립적으로 리뷰, 리드가 결과를 조율
13. **높은 severity 채택**: 팀원간 severity 의견 불일치 시 높은 쪽 채택

## 포기 방지 규칙 추가 (공통 규칙 위에 적용)

- Agent Teams 생성 실패 시 → `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 설정 확인 → 설정 후 재시도
- Teammate 중단 시 → 리드가 해당 관점을 직접 리뷰하여 대체
- 팀 coordination 에러 시 → Agent Team cleanup 후 재생성 (최대 2회)
- 3회 실패 시 → fallback으로 기존 `skills/code-review/SKILL.md` (단일 codex 리뷰) 사용
