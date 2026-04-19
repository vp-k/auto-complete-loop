# Security / Authentication / Authorization

보안·인증·인가 명세 문서. `projectScope.hasBackend=true`인 경우 필수로 작성한다.

이 문서는 SPEC.md의 API Contract보다 **우선순위 상위** (`rules/shared-rules.md` 문서 우선순위 표 참조) — 충돌 시 이 문서의 제약이 API 설계를 override한다.

## 1. 인증 (Authentication)

### 1.1 토큰 전략

| 항목 | 결정 | 근거 |
|------|------|------|
| 토큰 종류 | Access Token + Refresh Token | 짧은 Access 유효기간 + 안전한 갱신 |
| Access 형식 | JWT (signed, not encrypted) | stateless, 클레임 포함 |
| Access 유효기간 | 15분 | 탈취 피해 최소화 |
| Refresh 유효기간 | 14일 | 장기 로그인 경험 |
| Refresh 저장 | HttpOnly + Secure + SameSite=Lax 쿠키 | XSS 내성 |
| Access 저장 | 메모리 (JS 변수) 권장 | XSS 탈취 방지 |
| 회전(Rotation) | Refresh 사용 시 재발급 | 재사용 탐지로 탈취 감지 |

### 1.2 JWT 클레임 표준

```json
{
  "sub": "user_uuid",
  "iat": 1715000000,
  "exp": 1715000900,
  "iss": "api-auth",
  "aud": "api-gateway",
  "roles": ["user"],
  "scope": "profile read:orders write:orders"
}
```

**서명 알고리즘**: RS256 또는 EdDSA (HS256은 단일 서비스 + 키 관리 엄격 시에만)

**금지**:
- `none` 알고리즘
- 비밀번호/이메일 원문을 클레임에 포함
- 10KB 이상 클레임 (쿠키 크기 초과)

### 1.3 로그인 플로우

1. POST /auth/login { email, password }
2. 서버: 비밀번호 해시 검증 (bcrypt cost=12 또는 Argon2id)
3. 성공 시: Access + Refresh 발급 → 감사 로그 `audit.user.login.success`
4. 실패 시: 동일 응답 시간 유지 (타이밍 공격 방어) → `audit.user.login.failure`
5. 연속 실패 5회 → 15분 잠금 (브루트포스 방어), 429 응답

### 1.4 기타 인증 수단

| 수단 | 용도 | 비고 |
|------|------|------|
| OAuth 2.0 / OIDC | 소셜 로그인 | 사용 provider: [Google/Kakao 등] |
| Magic Link | 비밀번호 없는 로그인 | 15분 만료, 1회용 |
| MFA (TOTP) | 관리자 계정 필수 | RFC 6238 |
| API Key | 서비스 간 통신 | 장기 키, 스코프 제한 |

## 2. 인가 (Authorization)

### 2.1 권한 모델 선택

| 모델 | 적합 시점 | 복잡도 |
|------|----------|--------|
| RBAC (역할 기반) | 정적 역할, 권한이 역할에 고정 | Low |
| ABAC (속성 기반) | 리소스 소유권, 조건부 접근 | High |
| 혼합 | 대부분 실제 시스템 | Medium |

**이 프로젝트 선택**: [RBAC 또는 RBAC+ABAC 혼합]

### 2.2 역할 정의 (RBAC)

| 역할 | 설명 | 주요 권한 |
|------|------|----------|
| `guest` | 비로그인 | 공개 API 읽기 |
| `user` | 일반 사용자 | 본인 리소스 CRUD |
| `moderator` | 콘텐츠 관리 | 타 사용자 콘텐츠 제재 |
| `admin` | 시스템 관리자 | 모든 권한 (감사 대상) |

### 2.3 ABAC 규칙 (해당 시)

리소스 접근은 아래 조건 중 하나 충족:
- 리소스의 `owner_id == 현재 사용자 ID`
- `user.role` 이 `admin` 또는 `moderator`
- 리소스의 `visibility == "public"` + 읽기 전용

**구현**: 모든 쿼리에서 `owner_id` 필터를 **애플리케이션 레이어에서 자동 주입** (DB 레벨 RLS 추가 고려).

### 2.4 권한 체크 위치

1. **입력 검증** 이후, **비즈니스 로직** 이전
2. **프레임워크 중립 표현**: "인증 Guard" → 토큰 검증 + 사용자 주입. "권한 Guard" → 역할/속성 체크.
   - NestJS: `@UseGuards()` + CanActivate
   - Express: middleware chain
   - FastAPI: `Depends(get_current_user)` + 권한 함수
   - Spring: `@PreAuthorize`
   - Gin/Fiber: middleware
3. **컨트롤러 레벨**보다는 **서비스/유스케이스 레벨**에서 최종 체크 (이중 방어)

### 2.5 권한 누락 응답

- 인증 없음 → **401** `AUTH_REQUIRED`
- 역할 부족 → **403** `ROLE_INSUFFICIENT`
- 리소스 소유 아님 (민감 시) → **404** (존재 여부 숨김, 보안 우선)

## 3. 입력 검증

### 3.1 원칙

- 서버는 클라이언트를 신뢰하지 않는다. **모든 입력** 검증.
- 화이트리스트(허용 목록) > 블랙리스트
- 검증은 **경계** (컨트롤러/라우터)에서 수행. 내부 함수는 검증된 입력을 받는다고 가정.

### 3.2 검증 항목

| 항목 | 규칙 |
|------|------|
| 문자열 길이 | 최소·최대 (DB 컬럼과 일치) |
| 이메일 | RFC 5322 서브셋 정규식 + MX 검증 (선택) |
| URL | 스키마 제한 (`https://` only), 내부 IP 차단 (SSRF 방어) |
| 숫자 | 범위 (min/max), 정수/실수 명시 |
| 열거형 | 사전 정의 값 |
| 날짜 | ISO 8601 + 범위 |
| 배열 | 최대 길이 |
| 파일 업로드 | 확장자, MIME, 크기 상한, 바이러스 스캔 |

### 3.3 프레임워크 중립 구현 가이드

- 선언적 검증(class-validator, pydantic, zod, Joi 등) 우선 사용
- **ORM 레벨 제약**도 함께 정의 (DB 스키마에 NOT NULL, UNIQUE, CHECK)
- 커스텀 규칙은 별도 Validator 클래스로 분리

## 4. 비밀번호 정책

| 항목 | 요구사항 |
|------|---------|
| 최소 길이 | 10자 (NIST 권장) |
| 최대 길이 | 128자 (DoS 방지, bcrypt 72-byte 제한 고려) |
| 금지 | 공백만, 흔한 비밀번호 (Have I Been Pwned 리스트 참조) |
| 저장 | `bcrypt` cost=12 이상 또는 `Argon2id` (m=64MB, t=3, p=4) |
| 변경 주기 강제 | **하지 않음** (NIST SP 800-63B) — 유출 시에만 강제 재설정 |
| 재설정 링크 | 15분 유효, 1회용, 도메인 서명 |

**금지**:
- 평문 저장
- MD5/SHA-1 해시
- 2회 이상 해시 연쇄 (bcrypt 단독이 올바름)

## 5. 세션·쿠키 보안

| 속성 | 값 | 이유 |
|------|-----|------|
| `HttpOnly` | true | XSS의 쿠키 탈취 방지 |
| `Secure` | true (HTTPS 환경) | MITM 방지 |
| `SameSite` | `Lax` (기본) 또는 `Strict` | CSRF 방지 |
| `Path` | 제한적 (`/api` 등) | 스코프 최소화 |
| `Domain` | 명시적 | 서브도메인 누출 방지 |

**CSRF 방어**: SameSite=Lax + Double Submit Cookie 또는 Origin 헤더 검증.

## 6. 민감정보 처리

- **전송 중**: HTTPS 의무. HTTP 리다이렉트 금지 (HSTS 헤더 설정).
- **저장 시**: 대칭 암호화 (AES-256-GCM) 또는 KMS. 암호화 키는 환경변수/KMS에서 로드.
- **로깅**: `docs/logging-standard.md` §3 마스킹 규칙 준수.
- **백업·개발 환경**: 프로덕션 데이터 복사 시 마스킹 처리 필수.

## 7. 보안 헤더

HTTP 응답에 아래 헤더를 추가:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Content-Security-Policy: default-src 'self'; ...
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=()
```

## 8. 레이트 리밋

| 엔드포인트 종류 | 리밋 | 기준 |
|----------------|-----|------|
| 로그인/회원가입 | 5/분 | IP + 이메일 |
| 비밀번호 재설정 | 3/시간 | 이메일 |
| 일반 API | 100/분 | 사용자 |
| 검색/무거운 쿼리 | 20/분 | 사용자 |

초과 시 **429 `RATE_LIMITED`** + `Retry-After` 헤더 (`docs/error-policy.md` 참조).

## 9. 감사 대상 이벤트

`docs/logging-standard.md` §4 Audit Log 대상 이벤트 전체 준수 + 아래 추가:
- 역할/권한 변경: `audit.permission.change`
- API Key 발급/회수: `audit.apikey.create`, `audit.apikey.revoke`
- 비밀번호 실패 5회 잠금: `audit.user.lockout`

## 10. 보안 체크리스트 (구현 완료 전)

- [ ] 모든 보호 엔드포인트에 인증 Guard 적용
- [ ] 모든 권한 필요 엔드포인트에 인가 체크 적용
- [ ] 모든 입력이 경계에서 검증됨
- [ ] 비밀번호/토큰이 로그에 평문 출력되지 않음 (자동 테스트 포함)
- [ ] 보안 헤더 7종 모두 응답에 포함
- [ ] CORS 화이트리스트 명시 (와일드카드 금지)
- [ ] SQL Injection 방어 (ORM/parameterized query 강제)
- [ ] XSS 방어 (응답 인코딩, CSP)
- [ ] 의존성 취약점 스캔 통과 (`shared-gate.sh vuln-scan`)
- [ ] 시크릿 하드코딩 0건 (`shared-gate.sh secret-scan`)

## 11. 연관 문서

- `docs/SPEC.md` — API Contract (각 엔드포인트의 Auth 요구사항은 여기 문서와 일치해야 함)
- `docs/error-policy.md` — 401/403/429 응답 포맷
- `docs/logging-standard.md` — 감사 로그 이벤트
- `docs/adr/` — 토큰 전략 / 권한 모델 결정 근거
