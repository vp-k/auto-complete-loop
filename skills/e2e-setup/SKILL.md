# E2E Setup

Loaded by full-auto Phase 2 or add-e2e orchestrator via Read.
No Ralph/progress/promise code — managed by the caller.

## 1. 프로젝트 분석

### 1-1: 프로젝트 유형 감지

| 감지 파일 | 유형 |
|----------|------|
| `package.json` + React/Next/Vue | `web` |
| `package.json` + Express/Fastify/Nest (UI 없음) | `api` |
| `pubspec.yaml` + (`android/` or `ios/`) | `flutter_mobile` |
| `pubspec.yaml` + `web/` (모바일 디렉토리 없음) | `flutter_web` |
| `requirements.txt`/`pyproject.toml` + FastAPI/Django/Flask | `api` |
| `go.mod` + HTTP 서버 | `api` |
| 기타 | `unknown` (사용자 확인 요청) |

### 1-2: 데이터 전략 결정

| 조건 | 전략 | 설명 |
|------|------|------|
| 백엔드+DB가 같은 프로젝트 | `real-server` | 실제 서버 + ORM seed (정합성 최고, **우선 권장**) |
| 프론트엔드만 (외부 API) | `mock-server` | MSW/mock으로 API 모킹 |
| Flutter + 자체 백엔드 | `real-server` | 서버 기동 + seed |
| Flutter + 외부 API만 | `mock-server` | HTTP 클라이언트 DI 교체 |

풀스택 판별: `server/`, `api/`, `backend/` 디렉토리, ORM 파일(Prisma/TypeORM/Sequelize), docker-compose.yml 존재 여부.

### 1-3: 환경 검증

| 프레임워크 | 검증 명령 | 자동 설치 |
|-----------|----------|----------|
| Playwright | `npx playwright --version` | O (`npx playwright install`) |
| integration_test | `flutter devices` | X (에뮬레이터 필요) |
| Maestro | `maestro --version && adb devices` | 부분적 (`curl -Ls "https://get.maestro.mobile.dev" \| bash`) |
| supertest | `node --version` | O (`npm i -D supertest`) |
| pytest | `python --version` | O (`pip install pytest httpx`) |

### 1-4: 에뮬레이터 미감지 시 폴백

Flutter Mobile / Native Mobile에서 디바이스 없는 경우:
1. **위젯 통합 테스트** (`flutter test test/integration/` — 에뮬레이터 불필요, `testWidgets` 기반) — 1순위
2. 네이티브 플러그인 미사용 시: Playwright + `flutter build web`으로 전환
3. 모두 불가: `e2e.applicable = false` + 경고 기록

참고: 네이티브 플러그인(camera, bluetooth 등) 사용 시 `flutter build web` 자체가 실패하므로 위젯 통합 테스트를 1순위로 배치.

---

## 2. 플랫폼별 E2E 전략

### Web (Playwright)
- 설정: `npm init playwright@latest -- --yes --quiet`
- 셀렉터: `data-testid` > `getByRole` > `getByText` > 시맨틱 HTML
- 데이터(real): `globalSetup`/`globalTeardown`에 ORM seed/cleanup 통합
- 데이터(mock): MSW (`npm i -D msw`) + 스키마 기반 팩토리
- 실행: `npx playwright test`

### Flutter Mobile (integration_test)
- 설정: `flutter pub add 'dev:integration_test:{"sdk":"flutter"}'`
- 셀렉터: `find.byKey()` > `find.byType()` > `find.text()`
- 데이터: DI로 HTTP 클라이언트 교체 또는 실서버 seed
- 실행: `flutter test integration_test/`

### Flutter Web (Playwright 우선)
- `flutter build web` 후 Playwright로 테스트
- 또는 `flutter test --platform chrome integration_test/`

### API 서버 (supertest/pytest/httptest)
- 서버 기동 후 API 플로우 검증
- 인증: `POST /signup` -> `POST /login` -> `GET /me`
- CRUD: `POST` -> `GET` -> `PUT` -> `DELETE`
- Node: supertest, Python: pytest+httpx, Go: net/http/httptest

### Native Mobile (Maestro)
- `.maestro/` 디렉토리에 YAML flow 파일 생성
- 실행: `maestro test .maestro/`

---

## 3. Mock 데이터-DB 스키마 정합성

### 3단계 정합성 보장

**1단계 — 초기 정합성 (생성 시)**
스키마 소스 우선순위:
1. OpenAPI/Swagger 스펙 (최고)
2. GraphQL 스키마
3. TypeScript API 타입 (`types/`, `interfaces/`, `models/`)
4. API 클라이언트 코드 (Axios 래퍼의 response 타입)
5. Flutter 모델 클래스 (`fromJson`/`toJson`)
6. 기획 문서 (최저)

스키마 소스 없으면: E2E 범위를 UI 인터랙션으로 한정 (데이터 검증 제외).

**2단계 — 컴파일 타임 정합성 (드리프트 방지)**
팩토리가 프로젝트 실제 타입을 import하므로, 스키마 변경 시 빌드 에러 자동 발생:
- TS: `import { User } from '@/models/user'` -> 필드 불일치 시 tsc 에러
- Flutter: `import 'package:app/models/user.dart'` -> dart analyze 에러
- Python: Pydantic/dataclass 검증에서 실패
- Go: struct 필드 불일치 시 컴파일 에러
- JS(타입 없음): JSDoc `@type` 최소 힌트 추가, 불가 시 런타임 E2E 실행이 구조 불일치 감지

**3단계 — 런타임 정합성 (코드 리뷰에서 확인)**
Phase 3 리뷰 항목: "mock/seed 데이터가 실제 스키마에서 파생되었는가"

### 금지 규칙 (mock-server 전략)
1. 임의 JSON 리터럴로 mock 응답 생성 **금지** (타입 import 필수)
2. `as any`, `as unknown as T` 타입 우회 **금지**
3. 스키마에 없는 필드 추가 **금지**
4. 코드 패턴(`.data.id`)으로 스키마 역추론 **금지**
5. mock factory에 `// schema-source: [파일 경로]` 주석 **필수**

---

## 4. 시나리오 도출

### 소스 우선순위
1. SPEC.md의 E2E Scenarios 섹션 (Phase 1에서 정의된 경우)
2. SPEC.md User Stories + API Contract
3. 기획 문서 (docs/)
4. 코드 분석 (라우트/화면/API 구조)

### 도출 기준 (3-5개)
- 인증 플로우 (회원가입 -> 로그인 -> 인증 상태 확인)
- CRUD 플로우 (생성 -> 조회 -> 수정 -> 삭제)
- 네비게이션 플로우 (주요 페이지 이동 + 접근 제어)
- 에러 플로우 (잘못된 입력 -> 에러 메시지)
- 핵심 비즈니스 로직 (프로젝트 고유 기능)

### 시나리오 기록 형식
```json
{
  "id": "E2E-001",
  "title": "회원가입->로그인->대시보드",
  "priority": "high",
  "source": "SPEC.md US-001,US-002",
  "status": "pending",
  "testFile": null
}
```

---

## 5. 테스트 작성 규칙

### 작성 루프 (시나리오별)
1. 테스트 파일 생성 (시나리오별 독립 파일)
2. 데이터 전략에 따른 setup/teardown 코드 작성
3. 개별 실행 + 통과 확인
4. 실패 시: 최대 3회 수정 -> 3회 동일 에러 시 `record-error` + codex 요청

### 공통 원칙
- 핵심 플로우(happy path) 우선, 엣지 케이스는 후순위
- 헤드리스 실행 가능
- 테스트 간 상태 공유 금지, 각 테스트가 자체 데이터 관리
- 명시적 wait 사용 (하드코딩 sleep 지양)
- 기존 코드 동작 변경 금지 (`data-testid` 추가는 허용)

### 셀렉터 전략 (우선순위)
1. 기존 `data-testid`/`aria-label`/`role` 그대로 사용
2. 시맨틱 HTML (`button`, `input[name]`, heading) -> `getByRole`/`getByLabel`
3. 텍스트 기반 -> `getByText`
4. 위 3가지 불가 시만 -> 기존 코드에 `data-testid` 추가

### Flakiness 대응
- 실패 시 1회 자동 재실행 (retry)
- 2회 연속 실패 시 에러 에스컬레이션
- flaky 감지 시: `data-testid` + explicit wait로 안정화

### real-server 데이터 구조
```
e2e/
├── fixtures/
│   ├── global-setup.ts     # DB seed (ORM 모델 import)
│   ├── global-teardown.ts  # DB cleanup
│   └── test-data.ts        # seed 데이터 정의
└── *.spec.ts
```

### mock-server 데이터 구조
```
e2e/
├── mocks/
│   ├── factories.ts     # 프로젝트 타입 import 기반 팩토리
│   └── handlers.ts      # MSW 핸들러
└── *.spec.ts
```
