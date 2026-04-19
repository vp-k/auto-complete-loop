# Error Policy

API 에러 응답 포맷·코드 체계·재시도·타임아웃 정책 문서. `projectScope.hasBackend=true`인 경우 필수로 작성한다.

## 1. 공통 에러 응답 포맷

모든 에러 응답은 아래 JSON 스키마를 따른다. 일관된 포맷이 클라이언트 에러 핸들링을 단순화한다.

```json
{
  "code": "AUTH_INVALID_CREDENTIALS",
  "message": "이메일 또는 비밀번호가 올바르지 않습니다.",
  "details": {
    "field": "password",
    "reason": "mismatch"
  },
  "request_id": "req_abc123",
  "timestamp": "2026-04-19T12:34:56.789Z"
}
```

**필드 규칙**:

| 필드 | 필수 | 설명 |
|------|------|------|
| `code` | Yes | 내부 에러 코드 (SCREAMING_SNAKE_CASE). 클라이언트 분기용. |
| `message` | Yes | 사용자 노출 가능한 설명 (다국어 처리 가능). 내부 스택/SQL 노출 금지. |
| `details` | No | 구조화된 부가 정보 (검증 실패 필드 등) |
| `request_id` | Yes (가능 시) | 로그 상관 ID. 고객 지원 시 역추적. |
| `timestamp` | Yes | 에러 발생 시각 ISO 8601 |

**금지 사항**:
- 스택트레이스 노출
- 내부 경로·SQL·환경 변수 노출
- 다른 사용자 정보 노출 (에러 메시지에 타 유저 이메일 등)
- `password` 같은 원본 입력값 echo

## 2. HTTP 상태코드 매핑

| HTTP | 의미 | 사용 시점 | 내부 코드 예시 |
|------|------|----------|---------------|
| 400 | Bad Request | 클라이언트 입력 형식/유효성 위반 | `VALIDATION_FAILED` |
| 401 | Unauthorized | 인증 정보 없음/만료/무효 | `AUTH_REQUIRED`, `TOKEN_EXPIRED` |
| 403 | Forbidden | 인증은 됐으나 권한 부족 | `FORBIDDEN`, `ROLE_INSUFFICIENT` |
| 404 | Not Found | 리소스 없음 | `RESOURCE_NOT_FOUND` |
| 409 | Conflict | 중복/상태 충돌 | `ALREADY_EXISTS`, `STATE_CONFLICT` |
| 410 | Gone | 리소스 영구 삭제됨 | `RESOURCE_GONE` |
| 422 | Unprocessable Entity | 비즈니스 규칙 위반 (형식은 통과) | `BUSINESS_RULE_VIOLATED` |
| 429 | Too Many Requests | 레이트 리밋 초과 | `RATE_LIMITED` |
| 500 | Internal Server Error | 내부 예기치 못한 오류 | `INTERNAL_ERROR` |
| 502 | Bad Gateway | 외부 업스트림 실패 | `UPSTREAM_ERROR` |
| 503 | Service Unavailable | 일시적 부하/점검 | `SERVICE_UNAVAILABLE` |
| 504 | Gateway Timeout | 업스트림 타임아웃 | `UPSTREAM_TIMEOUT` |

**원칙**:
- 401과 403 구분: 인증 실패 vs 권한 부족
- 404와 403 구분: 보안상 민감하면 403 대신 404로 숨김 가능 (문서화 필수)
- 5xx는 재시도 가능성 검토, 4xx는 원칙적으로 클라이언트가 수정

## 3. 에러 코드 명명 규칙

- **패턴**: `<DOMAIN>_<ERROR_KIND>` 또는 `<DOMAIN>_<ACTION>_<ERROR_KIND>`
- **예시**: `AUTH_INVALID_CREDENTIALS`, `ORDER_PAYMENT_FAILED`, `USER_EMAIL_ALREADY_EXISTS`
- **금지**: 숫자만 사용 (`E001`), 장황한 문장, 공백/하이픈 포함

**도메인 목록** (프로젝트별 채우기):
- `AUTH` — 인증/인가
- `USER` — 사용자 관리
- `ORDER` — 주문
- `PAYMENT` — 결제
- `VALIDATION` — 입력 검증
- `INTERNAL` — 시스템 내부

## 4. 에러 코드 카탈로그

> 프로젝트 에러 코드를 아래 표로 관리한다. 새 엔드포인트 추가 시 이 표도 함께 갱신한다.

| 코드 | HTTP | 설명 | 발생 엔드포인트 | 사용자 메시지 | 재시도 권장 |
|------|------|------|----------------|---------------|------------|
| `AUTH_REQUIRED` | 401 | 인증 토큰 없음 | 모든 보호 엔드포인트 | "로그인이 필요합니다" | No |
| `TOKEN_EXPIRED` | 401 | 토큰 만료 | 동일 | "다시 로그인해주세요" | Yes (refresh 후) |
| `AUTH_INVALID_CREDENTIALS` | 401 | 비밀번호/이메일 불일치 | POST /auth/login | "이메일 또는 비밀번호가 올바르지 않습니다" | No |
| `FORBIDDEN` | 403 | 권한 부족 | 여러 곳 | "권한이 없습니다" | No |
| `VALIDATION_FAILED` | 400 | 입력 검증 실패 | 여러 곳 | "입력값을 확인해주세요" | No (수정 후) |
| `RATE_LIMITED` | 429 | 레이트 리밋 | 여러 곳 | "잠시 후 다시 시도해주세요" | Yes (백오프) |
| `INTERNAL_ERROR` | 500 | 예기치 못한 오류 | 모든 곳 | "일시적 오류가 발생했습니다" | Yes (idempotent) |
| ... | ... | ... | ... | ... | ... |

## 5. 재시도·타임아웃 정책

### 5.1 클라이언트 측

| 상황 | 재시도 | 백오프 | 최대 시도 |
|------|--------|--------|----------|
| 네트워크 실패 | Yes | exponential, jitter 포함 | 3 |
| 5xx (idempotent) | Yes | exponential | 3 |
| 429 | Yes | Retry-After 헤더 존중 | 3 |
| 401/403/4xx | No | — | — |

**Idempotency-Key**: POST 요청에서 재시도 안전하려면 `Idempotency-Key` 헤더 전송 (서버 중복 처리 방지).

### 5.2 서버 측 (외부 API 호출)

| 외부 호출 | 타임아웃 | 재시도 | Circuit Breaker |
|----------|---------|--------|-----------------|
| 내부 마이크로서비스 | 3s | 2회 (exp) | 50% 실패율 + 5s 반개방 |
| 외부 결제 API | 10s | 2회 (exp, idempotent만) | 필수 |
| 외부 OAuth provider | 5s | 1회 | 권장 |
| DB 쿼리 | 2s | 0회 | — |

**원칙**:
- 타임아웃 없는 외부 호출 금지 (반드시 명시적 timeout)
- 재시도 중 동일 장애 시 Circuit Breaker로 차단 → 503 반환
- 재시도 로그는 `event: "upstream.retry"` 로 WARN 레벨 기록

## 6. 로깅 연계

- **ERROR 이상 로그**: `error.code` 필드에 위 에러 코드 포함 (`docs/logging-standard.md` 참조)
- **400~422**: INFO 또는 WARN (사용자 실수는 ERROR가 아님)
- **5xx**: ERROR 레벨 + 스택트레이스 + `request_id` 필수

## 7. 클라이언트 가이드

클라이언트는 다음 순서로 에러 처리:
1. HTTP 상태코드로 1차 분기 (4xx vs 5xx)
2. `code` 필드로 2차 분기 (도메인별 UI 처리)
3. `message` 필드는 UI에 그대로 노출 가능 (이미 사용자 친화 문구)
4. `details`는 폼 검증 실패 필드 표시 등에 활용

## 8. 검증

PR 전 체크리스트:
- [ ] 새 에러가 카탈로그(§4)에 등록되었는가?
- [ ] HTTP 상태코드 매핑이 §2 표와 일치하는가?
- [ ] `message`에 내부 정보(SQL/경로/타 유저 정보) 노출 없는가?
- [ ] 재시도 가능 에러는 `Retry-After` 또는 idempotent한가?
- [ ] ERROR 로그에 `request_id`, `error.code`, 스택이 포함되는가?
