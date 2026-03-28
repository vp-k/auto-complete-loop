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
- 성능: 응답시간 목표, 동시접속 제한, 쿼리 제한
- 보안: 입력 검증, 인증/인가, 민감정보 처리
- 관측성: 로깅 규칙, 에러 리포팅

## Non-Goals
- [명시적으로 이 프로젝트에서 하지 않는 것]
