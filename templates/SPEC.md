# Specification

## Target Users (Personas Reference)
- 페르소나 1: [이름] — [역할], [핵심 니즈]
- 페르소나 2: [이름] — [역할], [핵심 니즈]

## Core Jobs (JTBD Reference)
- When [상황], I want to [행동], So I can [가치]

## Success Criteria
- North Star Metric: [지표]
- SC-1: [정성적/정량적 기준]
- SC-2: [기준]

## User Stories — Frontend
(projectScope.hasFrontend=true일 때 필수. false면 이 섹션을 "N/A — 프론트엔드 없음"으로 표기)

- US-F-001: As a [역할], I want to [UI 행동], so that [가치]
  - AC-F-001-1: [UI 수락 기준]
  - AC-F-001-2: [UX 예외 케이스]

## User Stories — Backend
(projectScope.hasBackend=true일 때 필수. false면 이 섹션을 "N/A — 백엔드 없음"으로 표기)

- US-B-001: As a [역할], I want to [API 행동], so that [가치]
  - AC-B-001-1: [API 수락 기준]
  - AC-B-001-2: [에러 시나리오]

## Frontend Pages & Components
(projectScope.hasFrontend=true일 때 필수)

| 페이지/컴포넌트 | 경로/위치 | 주요 기능 | 연관 US |
|---------------|----------|----------|--------|
| [PageName] | /path | [설명] | US-F-001 |

### UI States (화면별 상태 명세)
(projectScope.hasFrontend=true일 때 필수 — happy path만 명세하면 빈/로딩/에러 상태가
구현·인수 테스트에서 통째로 누락된다. 각 페이지에 대해 아래 상태를 정의할 것)

| 페이지 | 빈 상태 (데이터 0건) | 로딩 상태 | 에러 상태 (API 실패) | 입력 유효성 피드백 |
|--------|---------------------|----------|---------------------|-------------------|
| [PageName] | [안내 문구/일러스트] | [스피너/스켈레톤] | [에러 메시지+재시도] | [필드별 인라인 오류] |

- 위 상태 중 해당 US의 인수 기준(AC)에 포함되어야 하는 것을 명시한다
  (예: US-F-002 AC에 "메모 0건이면 '아직 메모가 없습니다' 표시" 포함)

## Data Model
| 엔티티 | 필드 | 타입 | 제약조건 | 설명 |
|--------|------|------|----------|------|

### 인덱스
| 테이블 | 인덱스 | 용도 |
|--------|--------|------|

## API Contract
### [METHOD] /api/[resource]
- Auth: [인증 방식]
- Request: { ... }
- Validation: [유효성 규칙]
- Response 200: { ... }
- Response 400: { code, message } — 유효성 실패
- Response 401: 인증 실패
- Response 403: 권한 부족
- Response 409: 중복/충돌
- Response 429: Rate limit 초과
- **테스트 케이스:**
  - 정상 요청 -> 기대 응답
  - 유효성 실패 -> 400
  - 인증 없음 -> 401
  - 경계값 -> [예상 동작]

## Constraints

> **hasBackend=true일 때 아래 3개 상세 문서 작성 필수** — 이 섹션은 요약만 두고 상세는 별도 문서 참조.

### 성능
- 응답시간: p95 < [N]ms, p99 < [N]ms
- 동시접속: [N] concurrent users
- 쿼리 제한: per-request [N] queries 이하

### 보안
- 상세: `docs/security-authn-authz.md` 참조 (인증·인가·입력검증·비밀번호·세션·민감정보·레이트리밋)
- 본 문서 엔드포인트의 `Auth:` 필드는 위 문서의 토큰 정책을 따름

### 에러 응답
- 상세: `docs/error-policy.md` 참조 (응답 포맷·HTTP 매핑·재시도·타임아웃)
- 본 문서 각 엔드포인트의 에러 응답은 위 정책 포맷 준수

### 관측성 (로깅)
- 상세: `docs/logging-standard.md` 참조 (레벨·JSON 포맷·마스킹·감사 로그)
- ERROR 이상 로그는 `request_id` + `error.code` 필수

## Non-Goals
- [명시적으로 이 프로젝트에서 하지 않는 것]
