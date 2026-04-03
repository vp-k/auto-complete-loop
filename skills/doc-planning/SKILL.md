# Phase 1: Doc Planning

Loaded by the full-auto orchestrator at Phase 1 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 0 완료 (overview.md, README.md 존재)
- progress 파일에 Phase 0 outputs 기록 완료
- `shared-rules.md`가 이미 로드된 상태

## Phase 1 절차

### Step 1-0: 맥락 파악

1. overview.md (정의 문서) 읽기 — 프로젝트 핵심 원칙, 경계, 책임 파악
2. README.md에서 작성할 문서 목록 추출
3. 각 문서의 현재 상태 확인 (완료/미작성)

#### overview.md 구조 검증 (PM Planning 산출물)

정의 문서에 다음 섹션이 존재하는지 검증:
- Problem Statement
- Target Users / 페르소나
- Core Jobs (JTBD)
- 핵심 가정 + 리스크
- 성공 기준

**누락 섹션 감지 시**: Claude가 1회 자동 보완 시도. 보완 후 경고 출력:
"overview.md에 [섹션명]이 누락되어 자동 보완했습니다. 확인해주세요."

자동 보완은 하드 실패가 아님 — 기존 프로젝트(PM Planning 없이 직접 실행) 호환성 유지.

### Step 1-1: 문서 목록 등록

progress 파일의 `phases.phase_1.documents`에 문서 목록 등록:
```json
[
  {"name": "auth.md", "status": "pending"},
  {"name": "user-profile.md", "status": "pending"}
]
```

### Step 1-2: 2자 자동 토론 루프

선택된 모든 문서에 대해 순차적으로 2자 토론 수행:

#### 토론 프로세스

1. **문서 시작**
   - 문서 확인 (없으면 생성, 있으면 업데이트 대상)
   - progress 파일 업데이트: `currentDocument` 설정, 해당 문서 `status` -> `in_progress`

2. **codex-cli에게 피드백 요청**
   ```bash
   codex exec --skip-git-repo-check '## 역할
   당신은 기획 문서 품질 검토 전문가입니다.
   아래 파일들을 직접 읽고 검토하세요.

   ## 검토 대상
   - 정의 문서 (헌법): [overview.md 경로] — 직접 읽고 핵심 원칙과 Non-Goals를 파악하세요
   - 검토할 문서: [문서 경로] — 직접 읽고 정의 문서 기준으로 검토하세요

   ## 요청
   피드백을 Critical/High/Medium/Low 우선순위로 분류해서 제공해주세요.

   ## E2E 시나리오 관점
   SPEC.md 작성 시 핵심 E2E 시나리오 3-5개를 도출하세요.
   - 인증 플로우, CRUD 플로우, 네비게이션 플로우 우선
   - 각 시나리오에 관련 User Story ID를 매핑
   - 여러 문서에 걸치는 크로스커팅 시나리오를 명시적으로 표시
   '
   ```

3. **Claude Code가 codex 피드백 분석/반론**
   - 각 피드백의 타당성 검토
   - 수용할 피드백과 반론할 피드백 구분
   - 반론 시 근거와 대안 제시
   - 수용한 피드백으로 문서 수정

4. codex-cli에게 재검토 요청 (이전 토론 요약 포함)

5. 참여 중인 AI 모두 "수정 없음" 합의까지 3-4 반복
   - 각 라운드 완료 시 progress의 `round` 값 업데이트

6. **문서 품질 체크리스트 확인** (합의 전 필수)

7. 합의된 내용으로 최종 문서 확정

8. 확정된 문서 다시 검토
   - 피드백 있으면 -> 2로 복귀
   - 피드백 없음 -> 문서 완성

9. **문서 완료 처리**
   - progress 업데이트: 해당 문서 `status` -> `completed`, `round` 삭제
   - `/compact` 실행 (다음 문서 시작 전 컨텍스트 정리)

10. 다음 문서로 자동 진행 (목록 끝까지 반복)

#### 토론 규칙

**핵심 원칙: 비판적 시각**
- 모든 참여자는 이전 피드백을 비판적으로 검토
- 단순 동의보다 반론/보완/대안 제시 우선
- "정말 필요한 수정인가?" 관점에서 과도한 피드백 필터링

**codex-cli 역할**: 객관적 기준 기반 피드백, 우선순위별 분류, 구체적 개선안
**Claude Code 역할**: codex 피드백 비판적 분석, 실제 필요한 수정만 선별, 최종 문서 수정

**AI 제외 규칙**:
- codex 동일 피드백 3회 반복 -> codex 제외, Claude Code 단독 결정
- codex 근거 없는 approve 3회 -> codex 제외, Claude Code 단독 결정

**합의 기준**:
- 참여 중인 AI 모두 근거 있는 "수정 없음" 선언
- 또는 5회 이상 토론 후 주요 쟁점 해결

#### 기획 수준 원칙

**MVP 수준 금지 — 프로덕션 릴리즈 수준 기획:**
- "나중에 추가" 식의 미완성 기획은 Critical 피드백으로 분류
- 모든 기능은 에러 처리, 유효성 검증, 보안 포함 완전한 형태
- "추후 구현", "Phase 2에서" 같은 문구 -> 현재 기획에 포함 또는 Non-Goals로 확인

**백엔드 TDD 지원:**
- 백엔드 API/서비스 기획 문서는 반드시 테스트 시나리오 포함
- 각 엔드포인트마다: 정상/유효성실패/인증실패/권한부족/중복 테스트 케이스 명시

**E2E Scenarios (SPEC.md 포함 필수 — Phase 2에서 테스트로 구현):**
- SPEC.md에 다음 형식의 E2E 시나리오 섹션을 포함할 것:

| ID | Scenario | Source (User Story) | Priority | Steps |
|----|----------|-------------------|----------|-------|
| E2E-001 | [시나리오명] | US-001, US-002 | high | 1. [step] 2. [step] ... |

- 핵심 E2E 시나리오 3-5개 도출 (인증 플로우, CRUD 플로우, 네비게이션 플로우 우선)
- 각 시나리오에 관련 User Story ID를 매핑
- 여러 문서에 걸치는 크로스커팅 시나리오를 명시적으로 표시

#### 문서 품질 체크리스트 (합의 전 필수)

**기본 품질:**
- [ ] 유저스토리 또는 목적이 명시되어 있는가?
- [ ] 구체적인 데이터 구조가 정의되어 있는가? (해당 시)
- [ ] 에러/예외 시나리오가 포함되어 있는가?
- [ ] 다른 문서와의 참조 관계가 올바른가?
- [ ] 개발자가 추가 질문 없이 구현 가능한 수준인가?

**릴리즈 수준 완성도:**
- [ ] 에러 핸들링이 모든 경로에 정의되어 있는가?
- [ ] 인증/인가 요구사항이 명시되어 있는가? (해당 시)
- [ ] 입력 유효성 검증 규칙이 정의되어 있는가?
- [ ] 성능 제약이 명시되어 있는가?

**백엔드 TDD 준비:**
- [ ] API/서비스 문서에 테스트 시나리오가 포함되어 있는가?
- [ ] 각 엔드포인트별 성공/실패 테스트 케이스가 명시되어 있는가?

#### 검토 기준

- 정의 문서 원칙과 충돌하지 않는가?
- Non-Goals를 침범하지 않는가?
- 이미 작성된 문서들과 충돌하지 않는가?
- 데이터 구조/스키마가 일치하는가?
- 용어/명명 규칙이 통일되어 있는가?

#### 피드백 우선순위

1. **Critical**: 정의 문서와 충돌, Non-Goals 침범
2. **High**: 다른 문서와 불일치, 누락된 필수 정보
3. **Medium**: 명확성 부족, 예시 부족
4. **Low**: 형식, 표현 개선

### Step 1-3: Iteration 관리

- 한 iteration에서 1~2개 문서만 처리
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료
- Stop Hook이 다음 iteration 자동 시작

### Step 1-4: 복구 시 토론 재개

복구로 `in_progress` 문서부터 재시작:
1. 해당 문서 다시 읽기
2. 정의 문서 핵심 원칙 다시 로드
3. `round` 값이 있으면 해당 라운드부터, 없으면 처음부터 토론 시작

### Step 1-5: 문서 일관성 검사

모든 문서 토론 완료 후:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/
```

스크립트가 발견한 구조적 불일치를 Claude가 수정합니다.

### Step 1-6: 스펙 깊이 검증 + Architect Agent

Phase 0의 API/모델/플로우 테이블이 Phase 1에서 충분히 상세화되었는지 검증합니다.

**Architect Agent**를 병렬로 호출하여 아키텍처 리뷰를 수행합니다:
- Agent tool로 `architect` 에이전트 호출
- 기술 스택 적합성, 의존성 분석, API 설계 일관성, 데이터 모델, NFR 커버리지 검증
- overview.md + SPEC.md 경로를 프롬프트에 포함
- 결과: Architecture Review Report (ARCHITECTURE_SCORE 포함)
- ARCHITECTURE_SCORE < 5 또는 블로커 존재 시 Phase 2 진행 전 반드시 해결

Claude가 직접 수행하는 검증:

- **API 엔드포인트**: SPEC.md에 각 엔드포인트의 Request/Response 상세가 기술되어 있는지 확인 (단순 목록이 아닌 필드/타입/예시 수준)
- **User Story ID**: 모든 User Story에 `US-F-*` (프론트엔드) 또는 `US-B-*` (백엔드) 형식의 ID가 부여되었는지 확인
- **상세 부족 시 경고**: 검증 실패 항목은 경고를 출력하고, Claude가 1회 자동 보완 시도

### Step 1-7: 검증 스크립트 생성 (Phase 1 산출물)

Phase 1 완료 시 SPEC.md의 핵심 플로우를 기반으로 실행 가능한 검증 스크립트를 생성합니다:

- **hasBackend=true**: `tests/api-smoke.sh` 생성
  - SPEC.md의 핵심 플로우를 curl 명령으로 변환
  - 각 단계에서 응답의 필수 필드를 jq로 검증
  - exit 0 = 모든 플로우 통과, exit 1 = 실패
  - 서버 URL은 인수로 받음: `$BASE_URL` (기본값: http://localhost:3000)

- **hasFrontend=true**: `tests/ui-smoke.sh` 또는 `tests/ui-smoke.spec.ts` 생성
  - 핵심 1-2개 유저 플로우를 Playwright 또는 간단한 curl로 검증

- **library/CLI**: `tests/lib-smoke.sh` 생성
  - 주요 export/CLI 명령 호출 + 예상 출력 확인

US-* ID 필수화 규칙:
- SPEC.md의 모든 User Story에 US-F-001, US-B-001 형식 ID를 반드시 부여
- 이 ID가 테스트 커버리지 측정의 기준이 됨

### Step 1-8: Test Strategist Agent

Phase 1 완료 직전, **Test Strategist Agent**를 호출하여 테스트 전략을 수립합니다:

- Agent tool로 `test-strategist` 에이전트 호출
- overview.md + SPEC.md + Architecture Review Report를 입력으로 제공
- 결과: Test Plan (테스트 피라미드 배분, 기능별 에지케이스, 실패 경로, 테스트 데이터 설계)
- Test Plan은 `docs/test-plan.md`에 저장
- Phase 2 구현자가 이 Test Plan을 따라 테스트 작성
- Phase 4 verification-auditor가 Test Plan 대비 커버리지 교차 검증

### Step 1-9: Phase 1 완료 검증

모든 문서 토론 완료 및 검증 스크립트 생성 후, Phase 전이 전 최종 검증을 수행합니다:

```bash
# 스펙 깊이 검증
api_detail=$(grep -c 'Request\|Response\|필드\|Field\|Body' SPEC.md 2>/dev/null || echo 0)
if [[ $api_detail -lt 3 ]]; then
  echo "WARN: SPEC.md에 API 상세 부족"
fi

# 검증 스크립트 존재 체크
if [[ ! -f tests/api-smoke.sh ]] && [[ ! -f tests/ui-smoke.sh ]] && [[ ! -f tests/ui-smoke.spec.ts ]] && [[ ! -f tests/ui-smoke.spec.js ]] && [[ ! -f tests/lib-smoke.sh ]]; then
  echo "FAIL: 검증 스크립트(tests/*-smoke.sh 또는 tests/ui-smoke.spec.ts) 미생성"
fi

# US-* ID 존재 체크
us_count=$(grep -coE 'US-[A-Z]-[0-9]+' SPEC.md 2>/dev/null || echo 0)
if [[ $us_count -eq 0 ]]; then
  echo "WARN: SPEC.md에 US-* ID 없음"
fi
```

WARN은 경고만 출력하고 진행, FAIL은 해당 단계를 재수행합니다.

### Step 1-10: Phase 1 완료

모든 문서 `completed` 시:
1. DoD 업데이트: `all_docs_complete.checked = true`
2. Phase 전이는 오케스트레이터가 수행 (이 스킬에서 하지 않음)
