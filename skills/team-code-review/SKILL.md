# Phase 3: Team Code Review (Agent Teams)

Loaded by the full-auto-teams orchestrator at Phase 3 entry via Read.
Uses Agent Teams for 3-way parallel review + Live App Testing.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 2 완료 (모든 코드 구현 완료)
- `shared-rules.md`가 이미 로드된 상태
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 설정
- Claude Code v2.1.32 이상

## Phase 3 절차

### Step 3-0: Agent Teams 활성화 확인

1. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 환경 변수가 `1`인지 확인:
   ```bash
   echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-not_set}"
   ```
2. 미설정 시:
   - `~/.claude/settings.json`에 자동 추가:
     ```bash
     jq '. + {"env": ((.env // {}) + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"})}' ~/.claude/settings.json > /tmp/claude-settings.tmp && mv /tmp/claude-settings.tmp ~/.claude/settings.json
     ```
   - 사용자에게 안내: "Agent Teams 설정을 추가했습니다. 새 세션에서 다시 실행해주세요."
   - **중단** (새 세션 필요)
3. 설정됨 → Step 3-1로 진행

### Step 3-1: 리뷰 범위 + Acceptance Criteria 로드

1. 구현된 전체 코드를 리뷰 범위로 설정
2. progress 파일에서 `phases.phase_2.completedFiles` 확인
3. progress 파일에서 `phases.phase_2.documents[].acceptanceCriteria` 로드 (있으면 팀원 프롬프트에 포함)
4. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티

### Step 3-2: Agent Team 생성

리드(현재 Claude 세션)가 Agent Team을 생성합니다:

```
3명의 전문 코드 리뷰 팀을 생성하세요.

팀원 구성:
1. "sec-reviewer" — 보안/에러/데이터 전문 리뷰어 (Sonnet 사용)
2. "quality-reviewer" — 성능/코드 품질 전문 리뷰어 (Sonnet 사용)
3. "live-tester" — 실행 테스트 전문가 (Sonnet 사용)

각 팀원은 plan approval 없이 즉시 작업을 시작합니다.
```

### Step 3-3: 팀원별 태스크 할당

태스크 리스트에 다음 3개 태스크를 생성:

**태스크 1: Static Review — SEC/ERR/DATA** (sec-reviewer에게 할당)
```
당신은 보안/에러 처리/데이터 일관성 전문 코드 리뷰어입니다.

## 리뷰 원칙 (회의적 리뷰어 역할)
- 수정이 필요 없다고 판단하더라도, 최소 1개 이상의 개선점을 반드시 찾아라.
- 의심스러우면 severity를 한 단계 높게 판정하라.
- "이 정도면 괜찮다"는 판단을 경계하라.

## 전문 리뷰 관점
1. SEC (보안): SEC-INJ, SEC-XSS, SEC-AUTH, SEC-TOCTOU, SEC-LLM, SEC-CRYPTO, SEC-TYPE, SEC-RACE, SEC-TIME, SEC-SECRET
2. ERR (에러 처리): try-catch 누락, 에러 응답 불일치, 에지 케이스 미처리
3. DATA (데이터 무결성): 트랜잭션 누락, 스키마 불일치, race condition

## 심각도 판정 기준 (Few-shot)
CRITICAL 예시: db.query("SELECT * FROM users WHERE id = " + userId) → SEC-INJ
HIGH 예시: catch(e) {} 빈 catch 블록 → ERR

## 리뷰 대상
[파일 경로 목록]

[Acceptance Criteria가 있으면 여기에 포함]

## 출력 형식
### {CATEGORY}-{SEVERITY}-{번호}: {제목}
- 파일: {경로}
- 라인: {줄번호}
- 설명: {문제 상세}
- 권장: {수정안}

finding 없으면 "NO_FINDINGS".
마지막 줄: FINDING_COUNT: N

## 상호 도전
다른 팀원(quality-reviewer, live-tester)의 finding이 공유되면,
해당 finding에 동의/반론을 메시지로 보내세요.
```

**태스크 2: Static Review — PERF/CODE** (quality-reviewer에게 할당)
```
당신은 성능/코드 일관성 전문 코드 리뷰어입니다.

## 리뷰 원칙 (회의적 리뷰어 역할)
[sec-reviewer와 동일한 원칙]

## 전문 리뷰 관점
1. PERF (성능): N+1 쿼리, 불필요한 DB 호출, 대량 데이터 미처리, 메모리 누수
2. CODE (코드 품질): 컨벤션 위반, 패턴 불일치, 타입 안전성 부족, 미사용 코드

## 심각도 판정 기준 (Few-shot)
MEDIUM 예시: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF
LOW 예시: 함수명 getData가 구체적이지 않음 → CODE

## 리뷰 대상
[파일 경로 목록]

[Acceptance Criteria가 있으면 여기에 포함]

## 출력 형식
[sec-reviewer와 동일]

## 상호 도전
sec-reviewer가 보안 관점에서 발견한 이슈에 대해,
성능 영향이 있는지 교차 검증하여 메시지로 보내세요.
```

**태스크 3: Live App Testing** (live-tester에게 할당)
```
당신은 실행 테스트 전문가입니다. 코드를 읽는 것이 아니라 실제 앱을 실행하고 사용하여 버그를 찾습니다.

Read ${CLAUDE_PLUGIN_ROOT}/skills/live-testing/SKILL.md 를 읽고 지침을 따르세요.

## 리뷰 대상 프로젝트
[프로젝트 루트 경로]

## Acceptance Criteria (있으면)
[acceptance criteria 목록 — 각 항목을 실제로 검증]

## 출력 형식
### LIVE-{SEVERITY}-{번호}: {제목}
- 시나리오: {수행한 user flow}
- 기대 동작: {문서/상식 기반 기대}
- 실제 동작: {실제로 관찰된 결과}
- 파일 (추정): {원인으로 의심되는 파일/함수}
- 스크린샷/로그: {있으면 첨부}

## 상호 도전
sec-reviewer나 quality-reviewer가 "코드상 문제없음"이라 판정한 부분도,
실제로 실행해보면 동작하지 않을 수 있습니다.
발견한 런타임 버그를 다른 팀원에게 메시지로 알려주세요.

## E2E 테스트 검증 (추가 임무)
기존 E2E 테스트 스위트가 있으면 실행하여 결과를 보고하세요.
- E2E 테스트 전체 실행: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate`
- 시나리오 커버리지 갭을 finding으로 보고 (카테고리: E2E)
- E2E 테스트가 없으면 "E2E 테스트 미존재" finding 보고 (E2E-MEDIUM-001)
```

### Step 3-4: 팀원 결과 대기 + 상호 도전

1. 3개 팀원이 모두 작업 완료할 때까지 대기
2. 팀원간 메시지 교환 (상호 도전) 관찰
3. 수렴 시 (추가 메시지 없음) 리드가 결과 수집

### Step 3-5: Finding 종합 + 수정 (리드)

리드(Claude)가 3개 팀원의 결과를 종합:

1. **Finding 수집**: 각 팀원의 finding 파싱
2. **중복 제거**: 동일 파일 + 라인 범위(±5줄) + 유사 문제 유형 → 하나로 통합
   - 여러 팀원이 동일 이슈 발견 → 더 높은 severity 채택, 설명 병합
   - live-tester + static reviewer 동시 발견 → 신뢰도 높음으로 표시
3. **Severity 판정**:
   - 팀원간 severity 의견 불일치 → **높은 쪽 채택** (과소평가 방지)
   - live-tester가 발견한 런타임 버그 → 최소 HIGH
4. **수정**:
   - Critical/High: 즉시 수정
   - Medium: 즉시 수정 (스킵 금지)
   - Low: 합리적이면 수용, 과도하면 구체적 사유와 함께 스킵 (dismissedDetails에 기록)
5. **품질 게이트 재실행**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-teams-progress.json
   ```
6. **자동 커밋** (품질 게이트 통과 시):
   ```bash
   # 수정한 파일만 스테이징 (git add -A 금지 — 비의도 파일/시크릿 포함 방지)
   git add <수정한 파일 목록> && git commit -m "[auto] Phase 3 팀 코드 리뷰 Round N 수정: X건 finding 수정"
   ```

progress 파일에 라운드 결과 기록:
```json
"phase_3": {
  "reviewType": "agent-teams",
  "currentRound": 1,
  "roundResults": [
    {
      "round": 1,
      "reviewers": ["sec-reviewer", "quality-reviewer", "live-tester"],
      "findingsBySrc": {
        "sec-reviewer": { "total": 5, "confirmed": 4 },
        "quality-reviewer": { "total": 3, "confirmed": 3 },
        "live-tester": { "total": 2, "confirmed": 2 }
      },
      "merged": { "total": 8, "duplicatesRemoved": 2 },
      "critical": 0, "high": 2, "medium": 4, "low": 2,
      "fixed": 6,
      "dismissed": 1,
      "dismissedDetails": [
        { "id": "CODE-LOW-003", "reason": "테스트 헬퍼의 의도적 하드코딩" }
      ]
    }
  ]
}
```

### Step 3-5.5: Agent Team Cleanup

라운드 완료 후 반드시 팀을 정리:

1. 각 팀원에게 shutdown 요청
2. 모든 팀원 종료 확인
3. 리드가 team cleanup 실행

```
sec-reviewer, quality-reviewer, live-tester 팀원에게 shutdown을 요청하세요.
모든 팀원이 종료되면 팀을 cleanup하세요.
```

**주의**: iteration 종료 전 반드시 cleanup. 다음 라운드에서 새 팀을 생성.

### Step 3-6: 리뷰 완료 조건

- Critical/High/Medium 발견이 모두 0개 (라운드 제한 없음, 0개 될 때까지 반복)
- 품질 게이트 통과
- E2E 게이트 통과 (`phases.phase_2.e2e.applicable == true`인 경우에만, 최종 라운드에서 실행):
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-teams-progress.json
  ```
  applicable이 false/null이면 E2E 게이트 스킵.

### Step 3-7: Phase 3 완료

1. 코드 품질 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-teams-progress.json
   ```
2. DoD 업데이트: `code_review_pass.checked = true`, evidence에 "N라운드 팀 리뷰 완료, CRITICAL/HIGH/MEDIUM: 0"
3. Phase 전이는 오케스트레이터가 수행

### Iteration 관리

- 한 iteration에서 1 팀 리뷰 라운드만 처리 (Team 생성 → 리뷰 → 종합 → 수정 → Cleanup)
- 라운드 완료 후 handoff 업데이트하고 자연스럽게 종료
- **다음 iteration에서 새 Agent Team 생성** (세션 재개 불가 제약)

### Fallback

Agent Teams 관련 에러 발생 시:
1. Agent Team 생성 실패 → 설정 확인 후 1회 재시도
2. Teammate 중단 → 리드가 해당 관점 직접 리뷰
3. 3회 연속 팀 에러 → fallback으로 기존 `skills/code-review/SKILL.md` 사용 (단일 codex 리뷰)
