---
description: "Planning doc refinement (solo multi-perspective). Claude debates as writer vs. critical reviewer without external AI"
argument-hint: <definition(overview.md)> <doclist(README.md)>
---

# 기획 문서 완성 (솔로 다관점 자기 토론형)

정의 문서(헌법)를 기준으로 문서 리스트의 각 문서를 검토/작성합니다.
외부 AI 없이 Claude가 **작성자 ↔ 비판적 검토자 역할 전환**으로 "추가 수정 불필요"에 도달할 때까지 반복합니다.

## 인수

- 정의 문서 경로: $1
- README 경로: $2

## Ralph Loop 자동 설정 (최우선 실행)

스킬 시작 시 스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "ALL_DOCS_REVIEWED" ".claude-plan-progress.json"
```

### Ralph Loop 완료 조건

`<promise>ALL_DOCS_REVIEWED</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-plan-progress.json`의 모든 문서 status가 `completed`
2. `.claude-plan-progress.json`의 `dod` 체크리스트가 모두 checked
3. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 한 iteration에서 **1~2개 문서**만 처리
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 진행 상태 파일 (`.claude-plan-progress.json`)

프로젝트 루트에 진행 상태 파일을 생성/관리하여 중단 시 복구 지원:

```json
{
  "project": "프로젝트명",
  "created": "2025-01-03T10:00:00Z",
  "status": "in_progress",
  "definitionDoc": "정의문서경로",
  "readmePath": "README경로",
  "documents": [
    {"name": "문서1.md", "status": "pending"},
    {"name": "문서2.md", "status": "completed"},
    {"name": "문서3.md", "status": "in_progress", "round": 2}
  ],
  "currentDocument": "문서3.md",
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {
    "user_story": { "checked": false, "evidence": null },
    "data_model": { "checked": false, "evidence": null },
    "api_contract": { "checked": false, "evidence": null },
    "error_scenarios": { "checked": false, "evidence": null },
    "no_definition_conflict": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
```

**상태 전이:**

- `pending` -> `in_progress`: 해당 문서 토론 시작 시
- `in_progress` -> `completed`: 자기 토론 수렴 완료 시

**파일 저장 시점:**

| 시점 | 업데이트 내용 |
| ---- | -------------- |
| 스킬 시작 | 파일 생성 또는 읽기 |
| 문서 시작 | status -> `in_progress` |
| 토론 라운드 완료 | round 값 업데이트 |
| `/compact` 실행 | turnCount, lastCompactAt |
| 문서 완료 | status -> `completed` |
| Iteration 종료 전 | `handoff` 필드 업데이트 |

## 0단계: 복구 감지

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 프로젝트 루트에서 `.claude-plan-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**

1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 -> 이전 iteration 맥락 복구
3. `definitionDoc`, `readmePath` 확인 (인수와 일치해야 함)
4. `in_progress` 상태인 문서 찾기 -> 해당 문서부터 재개
5. `in_progress`가 없으면 첫 번째 `pending` 문서부터 재개
6. 모든 문서가 `completed`면 -> 4단계(완료 보고)로 이동

**파일이 없는 경우 (파일 비교 복구 시도):**

> 이전에 실패한 작업도 복구 가능하도록 README와 실제 파일을 비교

1. README($2)에서 문서 목록 추출
2. 각 문서 파일이 실제로 존재하는지 확인 (Glob 사용)
3. **파일 비교 결과:**
   - 파일이 존재하고 내용이 있음 -> `completed`로 간주
   - 파일이 없거나 비어있음 -> `pending`으로 간주
4. `pending` 문서가 있으면:
   - AskUserQuestion으로 "이전 작업을 이어서 진행할까요?" 확인
   - "예" -> `.claude-plan-progress.json` 생성 후 첫 `pending` 문서부터 재개
   - "아니오" -> 새로 시작 (1단계부터)
5. 모든 문서가 `completed`면:
   - "모든 문서가 이미 작성되어 있습니다" 안내 후 종료

### DoD 로드

프로젝트 루트에서 `DONE.md` 확인:
- 파일 있음: "기획 문서 DoD" 섹션을 체크리스트로 사용
- 파일 없음: 내장 기획 문서 DoD 사용 (유저스토리/데이터모델/API계약/에러시나리오/정의문서충돌없음)

**완전 새로 시작:**

- 위 비교에서 모든 문서가 `pending`이고 사용자가 "새로 시작" 선택 시
- 1단계부터 정상 진행

## 1단계: 맥락 파악

정의 문서($1)를 읽고:

- 프로젝트의 핵심 원칙, 경계, 책임 파악
- 이 문서가 "헌법"으로서 모든 하위 문서의 기준임을 인지

### overview.md 구조 검증 (PM Planning 산출물)

정의 문서에 다음 섹션이 존재하는지 검증합니다:
- Problem Statement
- Target Users / 페르소나
- Core Jobs (JTBD)
- 핵심 가정 + 리스크
- 성공 기준

**누락 섹션 감지 시**: Claude가 1회 자동 보완 시도. 보완 후 경고 출력:
"overview.md에 [섹션명]이 누락되어 자동 보완했습니다. 확인해주세요."

이 검증은 **하드 실패가 아닌 자동 보완** — 기존 프로젝트(PM Planning 없이 직접 /plan-docs-auto-solo 실행) 호환성 유지.

## 2단계: 문서 목록 파악

README($2)에서:

- 작성할 문서 목록 추출
- 각 문서의 현재 상태 (완료/미작성) 확인
- AskUserQuestion으로 작업할 문서 범위 질문 (새로 시작할 때만)

**진행 상태 파일 생성** (새로 시작하는 경우):

```json
{
  "project": "프로젝트명 (README에서 추출)",
  "created": "현재시간",
  "status": "in_progress",
  "definitionDoc": "$1",
  "readmePath": "$2",
  "documents": [
    {"name": "선택된문서1.md", "status": "pending"},
    {"name": "선택된문서2.md", "status": "pending"}
  ],
  "currentDocument": null,
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {},
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
```

**복구 시**: 이 단계는 건너뛰고 `.claude-plan-progress.json`에서 문서 목록 사용

## 3단계: 솔로 자기 토론 루프

선택된 모든 문서에 대해 순차적으로 자기 토론 수행:

### 토론 프로세스

1. **문서 시작**
   - 문서 확인 (없으면 생성, 있으면 업데이트 대상)
   - `.claude-plan-progress.json` 업데이트: `currentDocument` 설정, 해당 문서 `status` -> `in_progress`

2. **자기 토론 루프 (Claude 솔로)**

   외부 AI 없이 Claude가 **역할 전환**으로 문서 품질을 검증합니다.

   각 문서에 대해:

   #### Step A [작성자 역할]
   문서를 작성하거나 수정합니다. 정의 문서(overview.md)를 기준으로 일관성을 유지합니다.

   #### Step B [비판적 검토자 역할]
   역할을 전환합니다. 지금부터 당신은 **비판적 기획 문서 검토 전문가**입니다.
   "이 문서대로 프로덕션에 들어갔을 때 실패하는 시나리오는 무엇인가?"를 자문합니다.

   검토 체크리스트:
   - [ ] 유저스토리가 충분하고 명확한가?
   - [ ] 에러/예외 시나리오가 포함되어 있는가?
   - [ ] 데이터 모델/API 스키마가 구체적인가?
   - [ ] 다른 문서와 교차 참조가 일치하는가?
   - [ ] 개발자가 이 문서만 보고 구현할 수 있는가?
   - [ ] 인증/인가 흐름이 명시되어 있는가?
   - [ ] 모니터링/로깅 고려가 있는가?

   피드백을 Critical/High/Medium/Low로 분류하여 기록합니다.

   #### Step C [작성자 역할로 복귀]
   검토 결과를 반영하여 문서를 수정합니다.

   #### Step D: 수렴 판단
   검토자가 "추가 수정 불필요"라고 판단하면 완료. 최대 3회 반복.
   "수정 불필요" 선언 시 반드시 검토한 항목과 근거를 명시해야 함 (단순 approve 금지).

3. **각 라운드 완료 시** `.claude-plan-progress.json`의 `round` 값 업데이트

4. **문서 품질 체크리스트 확인** (수렴 전 필수)

5. 수렴된 내용으로 최종 문서 확정

6. 확정된 문서를 검토자 역할로 다시 검토
   - 피드백 있으면 -> Step A로 복귀
   - 피드백 없음 -> 문서 완성

7. **문서 완료 처리**
   - `.claude-plan-progress.json` 업데이트: 해당 문서 `status` -> `completed`, `round` 삭제
   - `/compact` 실행 (다음 문서 시작 전 컨텍스트 정리)

8. 다음 문서로 자동 진행 (목록 끝까지 반복)

### 복구 시 토론 재개

복구로 인해 `in_progress` 문서부터 재시작하는 경우:

1. 해당 문서 다시 읽기
2. 정의 문서 핵심 원칙 다시 로드
3. `round` 값이 있으면 해당 라운드부터, 없으면 처음부터 토론 시작
4. 이전 토론 내용은 없으므로 새로 시작 (맥락은 파일로만 복구)

### 토론 규칙

**핵심 원칙: 비판적 시각**
- 검토자 역할 시 이전 작성 내용을 **비판적으로 검토**해야 함
- 자기 확인 편향(confirmation bias)을 의식적으로 경계
- "정말 필요한 수정인가?" 관점에서 과도한 피드백 필터링

**작성자 역할**: 정의 문서 기반으로 문서 작성/수정, 검토 피드백 반영
**검토자 역할**: 객관적 기준 기반 피드백, 우선순위별 분류, 구체적 개선안, "프로덕션 실패 시나리오" 관점

**수렴 기준**:
- 3회 자기 토론 후 검토자가 Critical/High 0건 판단 시 완료
- 또는 검토자가 근거 있는 "추가 수정 불필요" 선언 시 완료
- 최대 3회 반복 (3회 도달 시 Critical/High 피드백만 처리하고 마무리)

**단순 approve 금지**:
- "동의합니다", "좋습니다" 같은 단순 승인은 유효하지 않음
- "수정 불필요" 선언 시 반드시 **검토한 항목과 근거** 명시 필요
- 예: "정의 문서 원칙 X, Y 기준으로 검토 완료. 충돌 없음 확인."

### 기획 수준 원칙

**MVP 수준 금지 — 프로덕션 릴리즈 수준 기획:**
- "나중에 추가" 식의 미완성 기획은 토론에서 Critical 피드백으로 분류
- 모든 기능은 에러 처리, 유효성 검증, 보안을 포함한 완전한 형태로 기획
- "추후 구현", "Phase 2에서", "MVP에서는 제외" 같은 문구가 있으면 -> 해당 항목을 현재 기획에 포함시키거나, 명시적 Non-Goals로 정의 문서에서 제외했는지 확인

**백엔드 테스트 주도 개발 (TDD) 지원:**
- 백엔드 API/서비스 관련 기획 문서는 반드시 테스트 시나리오를 포함
- 각 엔드포인트마다: 정상 응답, 유효성 실패, 인증 실패, 권한 부족, 중복 요청 등의 테스트 케이스 명시
- 이 테스트 시나리오가 구현 시 TDD의 "실패하는 테스트 먼저 작성"의 기반이 됨

**예시 — API 문서에 포함해야 할 테스트 시나리오:**
```
### POST /api/auth/register
테스트 케이스:
- 정상 등록 -> 201 + 유저 객체
- 이메일 중복 -> 409 Conflict
- 비밀번호 8자 미만 -> 400 Bad Request
- 이메일 형식 오류 -> 400 Bad Request
- 필수 필드 누락 -> 400 Bad Request
- rate limit 초과 -> 429 Too Many Requests
```

### 문서 품질 체크리스트 (수렴 전 필수 확인)

토론 수렴 전, Claude가 검토자 역할로 다음을 확인:

**기본 품질:**
- [ ] 유저스토리 또는 목적이 명시되어 있는가?
- [ ] 구체적인 데이터 구조가 정의되어 있는가? (해당 시)
- [ ] 에러/예외 시나리오가 포함되어 있는가?
- [ ] 다른 문서와의 참조 관계가 올바른가?
- [ ] 개발자가 추가 질문 없이 구현 가능한 수준인가?

**릴리즈 수준 완성도 (MVP 수준 금지):**
- [ ] 에러 핸들링이 모든 경로에 정의되어 있는가? (happy path만 있으면 불합격)
- [ ] 인증/인가 요구사항이 명시되어 있는가? (해당 시)
- [ ] 입력 유효성 검증 규칙이 정의되어 있는가?
- [ ] 로깅/모니터링 요구사항이 포함되어 있는가?
- [ ] 배포/마이그레이션 고려사항이 있는가? (해당 시)
- [ ] 성능 제약(응답시간, 동시접속, 쿼리 제한)이 명시되어 있는가?

**백엔드 TDD 준비:**
- [ ] 백엔드 API/서비스 문서에 테스트 시나리오가 포함되어 있는가?
- [ ] 각 엔드포인트별 성공/실패 테스트 케이스가 명시되어 있는가?
- [ ] 경계값/예외 상황의 테스트 케이스가 포함되어 있는가?

미충족 항목이 있으면 수렴 불가. 해당 항목을 보완 후 재검토.

### 검토 기준

- 정의 문서의 원칙과 충돌하지 않는가?
- Non-Goals를 침범하지 않는가?
- 이미 작성된 문서들과 충돌하지 않는가?
- 데이터 구조/스키마가 일치하는가?
- 용어/명명 규칙이 통일되어 있는가?

### 피드백 우선순위

1. **Critical**: 정의 문서와 충돌, Non-Goals 침범
2. **High**: 다른 문서와 불일치, 누락된 필수 정보
3. **Medium**: 명확성 부족, 예시 부족
4. **Low**: 형식, 표현 개선

### Handoff (Iteration 종료 전 필수)

> `shared-rules.md`의 Handoff 업데이트 규칙을 따릅니다. progress 파일: `.claude-plan-progress.json`

## 컨텍스트 관리

> `shared-rules.md`의 컨텍스트 관리 규칙을 따릅니다.

### 3단계 종료 후: 문서 일관성 검사

모든 문서 토론 완료 후, 스크립트로 구조적 일관성을 검사합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/
```

스크립트가 발견한 구조적 불일치(모델 용어, API 엔드포인트, 네이밍 혼용, 상호참조 깨짐 등)를 Claude가 수정합니다.

## 4단계: 전체 완료 후 보고

모든 문서 작업 완료 시 **간결하게** 보고:

- 문서별 한 줄 요약 (생성/수정 여부 + 주요 변경점)
- 전체 토론 상세 내용은 포함하지 않음
- README 상태 업데이트

**Ralph Loop 완료:** 모든 조건 충족 시 `<promise>ALL_DOCS_REVIEWED</promise>` 출력

## 사용자 개입 시점 (이 시점에만 AskUserQuestion 허용)

**허용된 질문 시점:**
- 처음 실행 시 작업할 문서 범위 선택 (복구 시에는 생략)
- 토론이 교착 상태일 때 (3회 반복 후에도 Critical 미해결)

**금지된 질문 (절대 하지 않음):**
- "다음 문서로 진행할까요?"
- "이 문서 작업을 시작할까요?"
- "계속 진행해도 될까요?"
- 기타 확인성 질문

## 강제 규칙

> `shared-rules.md`의 공통 강제 규칙을 따릅니다.

**plan-docs-auto-solo 추가 규칙:**
- 막히면 -> 자기 토론 라운드 추가
- 3라운드 도달 시 -> Critical/High 피드백만 처리하고 마무리
- **원칙:** 문서 목록이 비워질 때까지 멈추지 않음
