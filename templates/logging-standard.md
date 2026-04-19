# Logging Standard

프로젝트 로깅 표준 문서. Phase 1 Doc Planning에서 `projectScope.hasBackend=true`인 경우 필수로 작성한다.

이 문서는 **언어 중립** 기준을 정의하고, 프로젝트 기술 스택에 맞는 구현 도구를 선택하여 "구현 스택" 섹션을 채운다.

## 1. 로그 레벨 기준

| 레벨 | 용도 | 프로덕션 사용 | 예시 |
|------|------|--------------|------|
| TRACE | 세밀한 진입/탈출 추적 | No | 함수 호출 체인 |
| DEBUG | 개발 중 변수 상태 확인 | No (또는 샘플링) | SQL 파라미터, 중간 계산값 |
| INFO | 정상 업무 흐름 + 감사 | Yes | 사용자 로그인 성공, 주문 생성 |
| WARN | 복구 가능한 이상 | Yes | 외부 API 재시도, 캐시 미스 폭주 |
| ERROR | 요청/작업 실패 | Yes | DB 연결 실패, 검증 통과 후 내부 오류 |
| FATAL | 프로세스 지속 불가 | Yes | OOM, 헬스체크 치명 실패 |

**원칙**:
- WARN 이상은 반드시 프로덕션에 기록
- DEBUG는 프로덕션에서 샘플링(예: 1%) 또는 비활성
- TRACE는 로컬/개발 환경 전용

## 2. 로그 포맷 (JSON 구조화)

모든 로그는 **단일 라인 JSON**으로 출력한다. 수동 파싱 금지, 집계 도구(ELK/Datadog/CloudWatch) 입력 가능 형태.

**필수 필드**:

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `timestamp` | ISO 8601 UTC | 이벤트 발생 시각 | `2026-04-19T12:34:56.789Z` |
| `level` | string | 로그 레벨 | `INFO` |
| `service` | string | 서비스명 | `api-auth` |
| `env` | string | 실행 환경 | `production`|`staging`|`dev` |
| `request_id` | string\|null | 요청 단위 상관 ID | `req_abc123` |
| `trace_id` | string\|null | 분산 추적 ID (OpenTelemetry) | `7f3a1b...` |
| `user_id` | string\|null | 인증된 사용자 ID (UUID 등) | `user_456` |
| `event` | string | 이벤트 코드 (snake_case) | `user.login.success` |
| `message` | string | 사람 읽는 요약 | `Login succeeded` |
| `context` | object | 추가 필드 (자유) | `{"ip": "1.2.3.4"}` |

**선택 필드**:
- `duration_ms` (요청 처리 시간)
- `error.type`, `error.message`, `error.stack` (ERROR 이상)
- `http.method`, `http.path`, `http.status` (HTTP 요청)

**예시**:
```json
{"timestamp":"2026-04-19T12:34:56.789Z","level":"INFO","service":"api-auth","env":"production","request_id":"req_abc","trace_id":null,"user_id":"user_456","event":"user.login.success","message":"Login succeeded","context":{"ip":"1.2.3.4"},"duration_ms":42}
```

## 3. 마스킹 (절대 출력 금지)

**대상 데이터**:
- 비밀번호 (평문/해시 불문)
- 인증 토큰 (JWT, Refresh Token, API Key, Session ID)
- 주민번호·신용카드·계좌번호
- 개인 연락처 (휴대폰, 이메일 전체 — 필요 시 `u***@e***.com` 형태로 부분 마스킹)
- 위치 정보 (정밀 좌표)
- 의료/결제 상세 데이터

**구현 원칙**:
1. 로거 레이어에서 **중앙 마스킹 필터** 적용 (코드 호출부 개별 처리 금지)
2. 정규식 기반 필터 + 필드명 기반 필터 조합
3. 중첩 객체/배열도 재귀 처리

**정규식 예시** (참고):
```
password["']?\s*[:=]\s*["']?[^"',}\s]+   → password: "***"
(bearer|token|apikey)["']?\s*[:=]\s*[^"',}\s]+  → bearer "***"
\b\d{3}-?\d{2}-?\d{4}\b                 → SSN 마스킹
\b(?:\d[ -]*?){13,16}\b                 → 카드번호 마스킹
```

**필드명 기반 블랙리스트 예시**:
`password`, `passwd`, `pwd`, `secret`, `token`, `access_token`, `refresh_token`, `api_key`, `apiKey`, `authorization`, `cookie`, `ssn`, `rrn`, `credit_card`, `card_number`

## 4. 감사 로그 (Audit Log) 대상 이벤트

보안·규정 준수를 위해 **반드시** 기록해야 하는 이벤트. 별도 수집 파이프라인/보관 정책 권장 (장기 보관).

| 이벤트 | 레벨 | 필수 context |
|--------|------|-------------|
| 로그인 성공/실패 | INFO/WARN | `ip`, `user_agent`, `method` (password/oauth/sso) |
| 비밀번호/이메일 변경 | INFO | `user_id`, `changed_fields` |
| 권한 변경 (역할 부여/회수) | INFO | `target_user_id`, `before_role`, `after_role`, `actor_id` |
| 민감 데이터 조회 | INFO | `resource_type`, `resource_id`, `reason?` |
| 민감 데이터 수정/삭제 | INFO | `resource_type`, `resource_id`, `diff_summary` |
| 관리자 행위 | INFO | `admin_action`, `affected_entity` |
| 결제/환불 | INFO | `payment_id`, `amount`, `currency`, `status` |
| 토큰 발급/폐기 | INFO | `token_type`, `expires_at` |

**감사 로그는 `event` 값에 `audit.` prefix 권장**:
- `audit.user.login.success`
- `audit.permission.change`
- `audit.payment.refund`

## 5. 예외 로깅 규칙

- **ERROR 이상**: 반드시 스택트레이스 포함 (`error.stack` 필드)
- **사용자 식별정보 PII 금지**: `user_id`만 기록, 이메일·이름 등 원본 금지
- **중복 억제**: 동일 에러 burst 발생 시 샘플링 또는 dedup 카운터 사용
- **Throw vs Log**: "예외를 던지고 상위에서 잡을 때만 log" 원칙 — 중복 로그 방지. 잡지 않을 예외는 현장에서 로그

## 6. 성능·운영

- **비동기 로거 권장**: stdout blocking 방지, 드롭 정책 명시 (backpressure 발생 시)
- **DEBUG 샘플링**: 프로덕션 DEBUG는 `sampler: 0.01` 수준
- **라이브러리 로그 제어**: ORM/HTTP 클라이언트 자체 로그는 WARN 이상만 통과
- **민감 필드 auto-redact 검증**: CI에서 로그 스냅샷 테스트로 비밀번호 필드 누출 회귀 감지

## 7. 구현 스택 (프로젝트 선택)

> 아래는 참고. 프로젝트 기술 스택에 맞춰 1개를 선택하여 채운다.

| 언어/런타임 | 권장 라이브러리 | 비고 |
|------------|----------------|------|
| Node.js | `pino` (고성능) 또는 `winston` | NestJS: `nestjs-pino` |
| Python | `structlog` 또는 `loguru` | FastAPI: middleware 통합 |
| Go | `zap` 또는 `slog` (1.21+) | structured by default |
| Java/Kotlin | `Logback` + `logstash-logback-encoder` | Spring: `logback-spring.xml` |
| Flutter/Dart | `logger` 패키지 | 모바일: 클라우드 로깅 전송 |
| Rust | `tracing` + `tracing-subscriber` | JSON fmt layer |

**이 프로젝트 선택**: [라이브러리명 + 버전]
**설정 파일 위치**: [파일 경로]
**마스킹 필터 위치**: [파일 경로]

## 8. 연관 문서

- `docs/error-policy.md` — 에러 코드 체계 (ERROR 레벨 로그의 `error.code` 필드와 매핑)
- `docs/security-authn-authz.md` — 감사 로그 대상 이벤트의 세부 정책
- `docs/SPEC.md` Constraints — 서비스별 로그 보존 기간
