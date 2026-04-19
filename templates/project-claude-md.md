# Project Guardrails for Claude Code

이 파일은 Claude Code가 자동 로드하는 프로젝트 진입점이다. 작업 시작 전 반드시 읽고 따른다.

## 1. Project Snapshot

- Stack: [프레임워크/버전/언어]
- Test: [테스트 프레임워크]
- Lint / Formatter: [ESLint, Prettier, Ruff 등]
- Package Manager: [npm / pnpm / pip / go mod / flutter pub]

## 2. 작업 시작 전 필수 읽기

아래 순서로 읽고 이해한 뒤에만 코드 생성 시작한다.

1. `docs/overview.md` (프로젝트 헌법)
2. `docs/<해당 기능>.md` (작업할 기능 명세)
3. `docs/SPEC.md` (API Contract, User Stories, Data Model)
4. `docs/security-authn-authz.md` (보안 정책 — hasBackend=true인 경우)
5. `docs/error-policy.md` (에러 응답 포맷 — hasBackend=true인 경우)
6. `docs/logging-standard.md` (로깅 표준 — hasBackend=true인 경우)
7. `docs/adr/*.md` (관련 아키텍처 결정)
8. `tests/` (기존 테스트 패턴)

## 3. 불변 규칙 (위반 시 작업 중단)

- **문서에 없는 기능/엔드포인트/필드 추가 금지** — 필요 시 문서를 먼저 수정
- **DB 스키마 임의 변경 금지** — 마이그레이션은 별도 커밋 + 롤백 계획 명시
- **신규 라이브러리 도입 금지** — 필요 시 `docs/adr/` 에 결정 근거 작성 후 도입
- **로깅 표준 위반 금지** — 마스킹 대상 출력·필수 필드 누락 금지
- **에러 응답 포맷/코드 임의 변경 금지** — `docs/error-policy.md` 카탈로그 준수
- **커밋 메시지 형식 준수** — `[auto] <내용> [US-X-###]` (자동화), `<type>(<scope>): <subject> [US-X-###]` (수동)

## 4. 3대 안전장치

### 4.1 문서 우선순위 (충돌 시 상위가 우선)

```
ADR > 보안 > SPEC API > 기능 문서 > 에러 정책 > 로깅 > UI/UX > 기타
```

### 4.2 [NEEDS-CLARIFICATION] 질의 프로토콜

문서에 근거 없는 판단 필요 시:
1. 코드 생성 즉시 중단
2. 다음 형식으로 질의 출력:
   ```
   [NEEDS-CLARIFICATION]
   상황: <무엇을 하려 했는가>
   충돌/공백: <어떤 문서의 어떤 부분이 빠졌는가>
   옵션: A) ... B) ... C) ...
   추천: <추천안과 근거>
   ```
3. 사용자 승인 전까지 코드 생성 재개 금지

### 4.3 예시 우선 원칙

추상 규칙과 구체 예시가 모두 있으면 **구체 예시의 해석을 우선 적용**.

## 5. TDD 강제 규칙 (백엔드)

순서: **Red → Green → Refactor** (커밋 분리 권장)

1. 실패 테스트 먼저 작성. describe/it에 User Story ID 태깅:
   ```ts
   describe('[US-B-001] AuthController.login', () => {
     it('[US-B-001] 유효한 자격증명으로 200 응답', async () => { ... });
   });
   ```
2. 통과시키는 **최소 코드**만 구현
3. 그린 유지하며 리팩터
4. 외부 의존(DB·HTTP·시간·랜덤)은 포트/어댑터로 격리 후 모킹
5. 테스트 레이어 비중 목표: 단위 70 / 통합 20 / E2E 10

## 6. 프로젝트 구조 규칙

- 레이어: [Controller/Route → Service → Domain → Repository]
- 모듈 경계: 도메인 단위 (예: `auth`, `order`, `user`)
- 도메인 로직은 Service/Domain 레이어에 배치. Controller는 입출력·검증만.
- 입력 검증은 경계(컨트롤러/라우터)에서 선언적 방식 (class-validator, pydantic, zod 등)
- 인증/인가: Guard/Middleware로 통일 (`docs/security-authn-authz.md` §2.4 참조)
- 에러: 공통 예외 필터 사용. 응답 포맷은 `docs/error-policy.md` 강제
- 로깅: 전역 인터셉터/미들웨어로 `request_id`, `trace_id`, `user_id` 자동 주입

## 7. PR 전 자가 점검 체크리스트

- [ ] 테스트 선행 증거(커밋 히스토리 Red → Green) 확인
- [ ] User Story ID로 코드 역추적 가능
- [ ] 해당 User Story 외 파일 변경 없음 (스코프 크리프 없음)
- [ ] 린트·포매터·타입체크 통과
- [ ] 커버리지 목표 달성
- [ ] 로깅 표준 준수 (필수 필드·마스킹·감사 로그)
- [ ] 에러 응답 포맷·코드 카탈로그 준수
- [ ] 보안 체크리스트 (`docs/security-authn-authz.md` §10) 통과
- [ ] 관련 문서 동기화(SPEC/ERD/ADR) 완료

## 8. Iteration 복귀 프로토콜

DoD 미충족 또는 문서-코드 불일치 발견 시:
1. 즉시 작업 중단
2. §9 Iteration Log에 기록
3. 해당 Phase 문서로 복귀 → 수정 → 재리뷰 → 재개

## 9. Iteration Log

| 날짜 | 사유 | 복귀 지점 | 재개 조건 | 상태 |
|------|------|----------|-----------|------|
|      |      |          |           |      |

## 10. 플러그인 참조

본 프로젝트는 `auto-complete-loop` 플러그인을 사용한다. 자동화 명령:
- `/full-auto <요구사항>` — PM → Doc → Implement → Review → Polish 전체 루프
- `/code-review-loop` — 독립 코드 리뷰
- `/plan-docs-auto` — 기획 문서 전용 자동화

품질 게이트:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate docs/
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh spec-completeness
```
