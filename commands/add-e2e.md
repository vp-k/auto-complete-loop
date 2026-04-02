---
description: "Add E2E tests to existing projects. Auto-generate scenarios from docs or code analysis"
argument-hint: "[docs_dir]"
---

# Add E2E: 기존 프로젝트에 E2E 테스트 추가

기존 프로젝트에 **E2E 테스트를 사후적으로 추가**합니다. 문서가 있으면 문서 기반으로, 없으면 코드 분석으로 핵심 시나리오를 도출합니다.

**두 가지 경로:**
- **문서 모드**: 문서 분석 → 문서↔코드 정합성 체크 → 문서 기반 시나리오 도출 → E2E 작성
- **코드 분석 모드**: 코드 탐색(라우트/화면/API) → 핵심 플로우 추론 → 회귀 방지 E2E 작성

**핵심 원칙**: 스크립트로 토큰 절약 | 시나리오 1개씩 작성→실행→통과 확인 | 기존 코드 동작 변경 금지

## 인수

- `$ARGUMENTS`: 문서 디렉토리 경로 (선택, 예: `docs/`). 미지정 시 코드 분석 모드.

## 5-Phase 워크플로우

```
Phase 0: 프로젝트 분석 ─── 유형 감지 + 모드 결정
    ↓
Phase 1: 시나리오 도출 ─── 문서 또는 코드에서 핵심 플로우 추출
    ↓
Phase 2: 프레임워크 설정 ── 자동 감지/설치 + quality-gate 확인
    ↓
Phase 3: E2E 테스트 작성 ── 시나리오별 작성→실행→통과
    ↓
Phase 4: 테스트 검증 ───── e2e-gate + quality-gate 최종 확인
    ↓
<promise>E2E_TESTS_COMPLETE</promise>
```

## Ralph Loop 자동 설정 (최우선 실행)

스킬 시작 시 스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "E2E_TESTS_COMPLETE" ".claude-e2e-progress.json"
```

### Ralph Loop 완료 조건

`<promise>E2E_TESTS_COMPLETE</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-e2e-progress.json`의 모든 steps status가 `completed`
2. `.claude-e2e-progress.json`의 `dod` 체크리스트가 모두 checked
3. `.claude-verification.json`의 e2e 검증 항목 exitCode가 0
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- Phase 0+1: 분석 + 시나리오 도출 (1 iteration)
- Phase 2: 프레임워크 설정 (1 iteration)
- Phase 3: 테스트 작성 (2-3개 시나리오/iteration)
- Phase 4: 검증 (1 iteration)
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 토큰 절약 스크립트 활용

반복적/기계적 작업은 `shared-gate.sh`로 대체하여 토큰을 절약합니다.

```bash
# Progress 초기화
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template e2e "프로젝트명"

# 현재 상태 확인
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status

# 단계 전이
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step analyze_project completed

# 품질 게이트 일괄 실행
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate

# E2E 테스트 실행 (프레임워크 자동 감지)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate

# 문서↔코드 일관성 검사
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/
```

**원칙**: 스크립트 = 구조적/기계적 검사, AI = 의미적 판단. 스크립트로 먼저 거르고, AI는 스크립트가 못 잡는 의미적 문제만 처리.

## 공유 스킬 참조

이 커맨드의 E2E 순수 로직(프로젝트 분석, 시나리오 도출, 프레임워크 설정, 테스트 작성 규칙, 정합성 전략)은
`skills/e2e-setup/SKILL.md`에 정의되어 있습니다. 아래 Phase별 상세 지침과 함께 참조하세요:

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/e2e-setup/SKILL.md
```

## 복구 감지 (0단계 전 실행)

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 `.claude-e2e-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**
1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 → 이전 iteration 맥락 복구
3. 현재 단계의 진행 상태에 따라 재개
4. 모든 steps가 `completed`면 → Phase 4(테스트 검증)로 이동

**파일이 없는 경우 (신규):**
- Phase 0부터 정상 시작

---

## Phase 0: 프로젝트 분석 (`analyze_project`)

**출력**: 프로젝트 유형, 모드 결정, 데이터 전략, 기존 E2E 현황 파악

### Step 0-1: Progress 초기화

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template e2e "프로젝트명"
```

### Step 0-2: 프로젝트 유형 감지

프로젝트 루트 파일을 기준으로 유형 결정:
- `package.json` → **web**
- `pubspec.yaml` → **flutter**
- 기타 → **unknown** (사용자에게 유형 확인 요청)

progress 파일에 `projectType` 업데이트.

### Step 0-3: 모드 결정

1. `$ARGUMENTS`가 있으면 → **docs 모드** (`docsDir` = `$ARGUMENTS`)
2. `$ARGUMENTS`가 없어도 다음을 자동 탐지:
   - `docs/` 디렉토리 존재
   - `SPEC.md` 파일 존재
   - 발견되면 → **docs 모드**
3. 위 모두 없으면 → **code 모드**

progress 파일에 `mode`, `docsDir` 업데이트.

### Step 0-4: 기존 E2E 존재 여부 확인

- `playwright.config.*`, `cypress.config.*` 존재 → 기존 프레임워크 감지
- `integration_test/` 디렉토리 존재 → Flutter integration test 감지
- `.maestro/` 디렉토리 존재 → Maestro 감지

**기존 E2E 없음**: 전체 설정 모드 (프레임워크 설치부터 시작)

**기존 E2E 있음**: 보완 모드 — 다음을 분석합니다:
1. **기존 테스트 파일 목록 수집**: 어떤 시나리오가 이미 커버되는지 파악
2. **기존 fixtures/helpers 파악**: seed, mock, auth helper 등 재사용 가능한 인프라 식별
3. **기존 설정 파일 분석**: `playwright.config.ts`의 baseURL, `webServer`, `globalSetup` 등 기존 설정 존중
4. Phase 1(시나리오 도출)에서 기존 테스트가 커버하는 시나리오는 **제외**
5. Phase 2(프레임워크 설정)는 스킵, Phase 3에서 기존 구조/패턴을 따라 새 테스트 작성

progress 파일에 `e2eFramework` 업데이트.

### Step 0-5: 데이터 전략 자동 판단

프로젝트 구조를 분석하여 E2E 테스트의 데이터 전략을 자동 결정합니다.

**풀스택 판별 기준 (같은 프로젝트에 백엔드 존재):**
- `server/`, `api/`, `backend/` 디렉토리 존재
- `prisma/`, `drizzle/`, `typeorm`, `sequelize` 등 ORM 설정 존재
- Express/Fastify/NestJS 등 서버 프레임워크 감지
- `docker-compose.yml`에 DB 서비스 정의

**전략 결정:**

| 조건 | 전략 | 설명 |
|------|------|------|
| 백엔드+DB가 같은 프로젝트 | `real-server` | 실제 서버 기동 + seed 데이터로 E2E |
| 프론트엔드만 (외부 API 호출) | `mock-server` | MSW/mock으로 API 응답 모킹 |
| Flutter + 자체 백엔드 | `real-server` | 서버 기동 + seed |
| Flutter + 외부 API만 | `mock-server` | HTTP 클라이언트 모킹 |

progress 파일에 `dataStrategy` 업데이트.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step analyze_project completed
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step derive_scenarios in_progress
```

---

## Phase 1: 시나리오 도출 (`derive_scenarios`)

**출력**: 핵심 E2E 시나리오 3-5개 (progress 파일의 `scenarios` 배열)

### 문서 모드 (mode: "docs")

#### Step 1-1: 문서 분석

`docsDir` 내 문서를 읽고 핵심 사용자 플로우를 추출합니다.

#### Step 1-2: 문서↔코드 정합성 체크

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check ${docsDir}
```

미구현 항목은 시나리오에서 **제외** (구현되지 않은 기능은 테스트 불가).

#### Step 1-3: 시나리오 도출

문서에서 핵심 시나리오 3-5개 도출:
- 인증 플로우 (회원가입 → 로그인 → 인증 상태 확인)
- CRUD 플로우 (생성 → 조회 → 수정 → 삭제)
- 네비게이션 플로우 (주요 페이지 이동 + 접근 제어)
- 에러 플로우 (잘못된 입력 → 에러 메시지 확인)
- 핵심 비즈니스 로직 (프로젝트 고유 기능)

### 코드 분석 모드 (mode: "code")

#### Step 1-1: 코드 탐색

프로젝트 유형별로 핵심 구조를 탐색합니다:

**Web:**
- 라우트 설정: Next.js `pages/`/`app/`, React Router, Vue Router, Express 라우트
- 인증 패턴: `auth`, `login`, `jwt`, `passport`, `session` 키워드
- 폼/입력: `<form>`, `onSubmit`, `handleSubmit` 패턴
- API 엔드포인트: `app.get/post/put/delete`, `router.*`, API route 파일

**Flutter:**
- 화면 클래스: `Screen`, `Page`, `View` 접미사 클래스
- 라우터 설정: `GoRouter`, `Navigator`, `MaterialPageRoute`
- 인증 패턴: `firebase_auth`, `SharedPreferences`, `token` 관련
- API 호출: `Dio`, `http.get/post`, `ApiClient`

#### Step 1-2: 공통 패턴 식별

코드에서 다음 패턴을 식별합니다:
- **인증/세션**: 로그인/로그아웃 로직, 토큰 관리
- **CRUD**: 데이터 생성/조회/수정/삭제 패턴
- **네비게이션**: 라우트 구조, 접근 제어(guard/middleware)
- **폼 제출**: 입력 검증, 제출 처리
- **외부 연동**: API 호출, 결제, 소셜 로그인 (모킹 대상 식별)

#### Step 1-3: 시나리오 도출

코드에서 핵심 시나리오 3-5개 도출 (high/medium 우선순위):
- 가장 많은 코드가 관여하는 사용자 플로우 우선
- 외부 서비스 의존 시나리오는 모킹 계획 포함

### 시나리오 기록

시나리오를 progress 파일의 `scenarios` 배열에 기록:

```json
{
  "id": "E2E-001",
  "title": "회원가입→로그인→대시보드",
  "priority": "high",
  "source": "docs/auth.md 또는 code:src/routes/index.ts",
  "status": "pending",
  "testFile": null
}
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step derive_scenarios completed
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step setup_framework in_progress
```

DoD 업데이트:
```json
"dod.scenarios_documented": { "checked": true, "evidence": "N개 시나리오 도출 완료" }
```

---

## Phase 2: E2E 프레임워크 + 데이터 설정 (`setup_framework`)

**출력**: E2E 프레임워크 설치/설정 + 데이터 전략 구성 완료

### Step 2-1: 기존 프레임워크 확인

Phase 0에서 감지한 `e2eFramework`가 있으면 프레임워크 설정은 **스킵**.

### Step 2-2: 프레임워크 자동 설정

프레임워크가 없으면 프로젝트 유형에 따라 자동 설정:

**Web → Playwright:**
```bash
npm init playwright@latest -- --yes --quiet
```
- `playwright.config.ts` 설정 (headless, baseURL 등)
- `e2e/` 또는 `tests/` 디렉토리 생성

**Flutter → integration_test:**
- `integration_test/` 디렉토리 생성
- 의존성 설치:
  ```bash
  flutter pub add 'dev:integration_test:{"sdk":"flutter"}'
  flutter pub add 'dev:flutter_test:{"sdk":"flutter"}'
  ```
- `integration_test/app_test.dart` 기본 파일 생성

**Mobile → Maestro:**
- `.maestro/` 디렉토리 생성
- 기본 YAML 플로우 파일 생성

### Step 2-3: 데이터 전략 구성

Phase 0에서 결정한 `dataStrategy`에 따라 데이터 인프라를 구성합니다.

#### `real-server` 전략: 환경 확인 + Seed 구성

백엔드가 같은 프로젝트에 있으므로 **실제 DB 스키마가 곧 정합성의 소스**입니다.

**Step A: 환경 전제조건 확인**

서버+DB를 로컬에서 기동할 수 있는지 순서대로 확인합니다:

1. **DB 접속 확인**:
   - `docker-compose.yml` 존재 → `docker compose up -d` (테스트 DB 서비스 기동)
   - Docker 없으면 → `.env`/`.env.local`에서 DB 연결 문자열 확인
   - DB 연결 불가 → `warnings`에 기록 + `mock-server`로 **폴백** (무리하게 DB 설정 시도 금지)
2. **마이그레이션 실행**: Prisma → `npx prisma migrate deploy`, TypeORM → `npx typeorm migration:run` 등
3. **환경변수 확인**: `.env.example`이 있으면 `.env.test` 또는 `.env.local` 존재 확인. 없으면 `.env.example`을 복사하여 `.env.test` 생성 (비밀값은 placeholder)
4. **서버 기동 테스트**: `npm run dev` 또는 해당 start 명령이 에러 없이 뜨는지 확인

**Step B: Seed/Cleanup 구성**

seed/cleanup을 Playwright `globalSetup`/`globalTeardown`에 통합하여 **`e2e-gate`가 별도 처리 없이 자동으로 seed→test→cleanup을 실행**하도록 합니다.

1. **DB 스키마 분석**: Prisma schema, TypeORM entities, Sequelize models 등에서 데이터 구조 파악
2. **seed/cleanup 모듈 생성** (`e2e/fixtures/`):
   - ORM의 실제 모델을 import하여 생성 → **스키마 정합성 자동 보장**
   - 고유 prefix로 테스트 데이터 식별 (예: `e2e-user-{uuid}`)
   - E2E 시나리오에 필요한 최소 데이터만 (테스트 사용자, 기본 레코드)
3. **globalSetup/globalTeardown에 연결**:
   ```typescript
   // playwright.config.ts
   export default defineConfig({
     globalSetup: './e2e/fixtures/global-setup.ts',   // DB seed
     globalTeardown: './e2e/fixtures/global-teardown.ts', // DB cleanup
     webServer: { command: 'npm run dev', ... },
   });
   ```
   이렇게 하면 `npx playwright test`(= `e2e-gate`) 한 번으로 서버기동→seed→테스트→cleanup 전체가 동작합니다.

```
e2e/
├── fixtures/
│   ├── global-setup.ts     # DB seed (ORM 모델 import → e2e-gate 호환)
│   ├── global-teardown.ts  # DB cleanup
│   └── test-data.ts        # seed 데이터 정의 (모델 기반)
└── *.spec.ts
```

**Flutter `real-server`의 경우:**
- `integration_test/fixtures/` 에 seed/cleanup 스크립트
- 테스트 실행 전 `dart run e2e/seed.dart`, 실행 후 `dart run e2e/cleanup.dart`를 `scripts/run-e2e.sh`에 래핑

#### `mock-server` 전략: 스키마 기반 Mock 구성

프론트엔드만 있는 프로젝트에서 mock 데이터는 **반드시 실제 스키마에서 파생**해야 합니다.
임의로 만든 mock 데이터는 실제 API와 구조가 달라질 수 있어 테스트의 신뢰성이 없습니다.

**Step A: MSW 설치 (Web 프로젝트)**

```bash
npm i -D msw
npx msw init public/ --save   # SPA의 경우 public 디렉토리에 service worker 배치
```

Flutter의 경우 MSW 대신 HTTP 클라이언트를 DI로 교체하는 방식을 사용합니다.

**Step B: 스키마 소스 탐지 (우선순위순)**

| 우선순위 | 소스 | 탐지 방법 | 신뢰도 |
|---------|------|----------|--------|
| 1 | OpenAPI/Swagger 스펙 | `openapi.json`, `swagger.json`, `*.yaml` API 스펙 파일 | 최고 |
| 2 | GraphQL 스키마 | `schema.graphql`, `*.gql`, codegen 설정 | 최고 |
| 3 | TypeScript API 타입 | `types/`, `interfaces/`, `models/` 내 response type 정의 | 높음 |
| 4 | API 클라이언트 코드 | Axios/fetch 래퍼의 response 타입, React Query 훅의 제네릭 타입 | 높음 |
| 5 | Flutter 모델 클래스 | `fromJson`/`toJson` 메서드가 있는 모델 클래스 | 높음 |
| 6 | 기획 문서 | docs 모드에서 문서의 데이터 모델 섹션 | 중간 |

**스키마 소스를 찾은 경우:**
1. 소스에서 엔티티별 필드/타입 추출
2. 추출한 스키마로 mock 데이터 팩토리 생성 (`e2e/mocks/factories.ts`)
3. **팩토리는 프로젝트의 기존 타입을 직접 import** (재정의 금지)
4. MSW 핸들러에서 팩토리를 사용하여 응답 생성
5. progress 파일에 `mockSchemaSource` 기록

**스키마 소스를 찾지 못한 경우 (역추론 금지):**

코드에서 `.data.id` 같은 접근 패턴으로 스키마를 역추론하는 것은 **비현실적**입니다 (optional 필드, 중첩 구조, 배열 등 누락 불가피). 대신:

1. progress 파일의 `warnings`에 "신뢰할 수 있는 스키마 소스 없음" 기록
2. **E2E 범위를 UI 인터랙션으로 한정**: API 응답에 의존하는 데이터 검증은 제외하고, 네비게이션/폼 제출/에러 표시 등 UI 동작만 테스트
3. mock 데이터는 **시나리오별 최소 인라인 정의** (팩토리 패턴 대신 각 테스트 파일에 필요한 응답만 직접 정의)
4. `e2e/mocks/README.md`에 "이 mock 데이터는 실제 API 스펙에서 파생되지 않음. API 변경 시 수동 업데이트 필요" 경고 명시

**Mock 데이터 구조 (스키마 소스 있는 경우):**
```
e2e/
├── mocks/
│   ├── factories.ts     # 프로젝트 타입 import 기반 mock 팩토리
│   └── handlers.ts      # MSW 핸들러 (팩토리 사용)
└── *.spec.ts
```

**Mock 데이터 구조 (스키마 소스 없는 경우):**
```
e2e/
├── mocks/
│   ├── handlers.ts      # MSW 핸들러 (시나리오별 인라인 응답)
│   └── README.md        # 스키마 미파생 경고
└── *.spec.ts
```

**Flutter mock 구조:**
```
integration_test/
├── mocks/
│   ├── mock_api_client.dart  # HTTP 클라이언트 모킹 (모델 클래스 기반)
│   └── test_data.dart        # 프로젝트 모델 클래스의 인스턴스
└── *_test.dart
```

**핵심 규칙:**
- 스키마 소스가 있으면: 프로젝트 타입을 직접 import. `as any` 우회 금지, 스키마에 없는 필드 추가 금지
- 스키마 소스가 없으면: 역추론으로 가짜 정합성을 만들지 않음. 범위를 줄이고 한계를 명시

### Step 2-4: 기존 빌드 확인

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate
```

프레임워크/데이터 설정이 기존 빌드를 깨뜨리지 않는지 확인. 실패 시 즉시 수정.

progress 파일에 `e2eFramework`, `dataStrategy`, `mockSchemaSource` 업데이트.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step setup_framework completed
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step write_tests in_progress
```

DoD 업데이트:
```json
"dod.framework_setup": { "checked": true, "evidence": "Playwright/integration_test/Maestro 설정 + 데이터 전략 구성 완료 + quality-gate 통과" }
```

---

## Phase 3: E2E 테스트 작성 (`write_tests`)

**출력**: 모든 시나리오의 E2E 테스트 작성 + 개별 통과

### 보완 모드 시 기존 패턴 준수

기존 E2E가 있는 보완 모드에서는:
- 기존 테스트의 **파일 네이밍 규칙** 따르기 (예: `*.spec.ts`, `*.e2e-spec.ts`)
- 기존 **auth helper/fixture** 재사용 (새로 만들지 않음)
- 기존 **mock 구조** 재사용 (MSW handlers가 있으면 거기에 추가)
- 기존 **디렉토리 구조** 유지 (새 디렉토리 생성 최소화)

### 작성 순서

**high** 우선순위 시나리오부터 작성합니다.

### 작성 루프

각 시나리오에 대해:

1. **테스트 파일 생성**: 시나리오별 독립 파일
2. **데이터 전략별 테스트 코드 작성**:

   **`real-server` 전략:**
   - `beforeAll`: seed 스크립트로 테스트 데이터 주입 (ORM 모델 사용 → DB 정합성 자동 보장)
   - `afterAll`: cleanup 스크립트로 테스트 데이터 삭제
   - 서버는 `webServer` 설정 또는 `globalSetup`에서 자동 기동
   - 외부 서비스(결제, 소셜 로그인)만 모킹

   **`mock-server` 전략:**
   - `beforeAll`: MSW 서버 시작 + 스키마 기반 핸들러 등록
   - mock 데이터는 `factories.ts`에서 생성 (프로젝트 타입 정의 기반)
   - **금지**: `as any` 타입 캐스팅, 스키마에 없는 임의 필드, 하드코딩된 JSON 리터럴
   - **필수**: mock 응답의 타입이 프로젝트의 API response 타입과 일치

3. **공통 작성 규칙**:
   - 헤드리스 실행 가능
   - 다른 테스트와 독립 실행 가능
   - 테스트 간 상태 공유 금지
4. **개별 실행 + 통과 확인**:
   - Playwright: `npx playwright test <파일>`
   - Flutter: `flutter test integration_test/<파일>`
   - Maestro: `maestro test .maestro/<파일>`
5. **실패 시 수정**:
   - Claude 직접 수정 (최대 3회)
   - 동일 에러 3회 반복:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error --file <f> --type <t> --msg <m>
     ```
     exit 2 → codex 해결 요청
   - 동일 에러 5회 반복 → exit 3 → 사용자 개입 요청
6. **progress 업데이트**: 시나리오 `status` → `completed`, `testFile` 기록

### 작성 원칙

- **핵심 플로우만**: 엣지 케이스보다 happy path 우선
- **셀렉터 전략** (우선순위순):
  1. 기존 `data-testid`/`aria-label`/`role` → 그대로 사용
  2. 시맨틱 HTML (`button`, `input[name]`, `heading`) → Playwright `getByRole`/`getByLabel`
  3. 텍스트 기반 → `getByText` (안정적이면 OK)
  4. 위 3가지로 불가능한 경우만 → 기존 코드에 `data-testid` 추가 (동작 변경 아니므로 허용)
- **적절한 대기**: 명시적 wait (하드코딩된 sleep 지양)
- **독립성**: 테스트 간 상태 공유 금지, 각 테스트가 자체 데이터 관리
- **데이터 정합성**: mock/seed 데이터는 반드시 프로젝트의 실제 타입/스키마에서 파생. 임의 JSON 금지
- **외부 서비스만 모킹**: `real-server`에서는 자체 백엔드는 실제 사용, 외부(결제/소셜)만 모킹

**Iteration 단위**: 2-3개 시나리오/iteration

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step write_tests completed
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step verify_tests in_progress
```

DoD 업데이트:
```json
"dod.tests_written": { "checked": true, "evidence": "N개 시나리오 테스트 작성 완료" }
```

---

## Phase 4: 테스트 검증 (`verify_tests`)

**출력**: 전체 E2E 통과 + 기존 코드 영향 없음 확인

### Step 4-1: E2E 전체 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate
```

### Step 4-2: 실패 시 수정 루프

실패한 테스트가 있으면:
1. 에러 분석 + 수정
2. `record-error` 활용 (3회 반복 시 codex 요청)
3. 재실행
4. 모든 테스트 통과까지 반복

### Step 4-3: 기존 코드 영향 확인

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate
```

E2E 추가가 기존 빌드/테스트에 영향을 주지 않는지 확인.

### Step 4-4: DoD 최종 업데이트

모든 DoD 항목 최종 확인:
```json
{
  "framework_setup": { "checked": true },
  "scenarios_documented": { "checked": true },
  "tests_written": { "checked": true },
  "e2e_pass": { "checked": true },
  "build_pass": { "checked": true }
}
```

### Step 4-5: 완료 보고

```
## E2E 테스트 추가 완료 보고

### 프로젝트
- 유형: [web/flutter/mobile]
- 모드: [docs/code]
- 프레임워크: [playwright/integration_test/maestro]

### 시나리오 결과
| ID | 시나리오 | 우선순위 | 테스트 파일 | 결과 |
|----|---------|---------|-----------|------|
| E2E-001 | 회원가입→로그인 | high | e2e/auth.spec.ts | PASS |
| ... | ... | ... | ... | ... |

### 검증 결과
- E2E Gate: PASS
- Quality Gate: PASS (기존 빌드 영향 없음)
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step verify_tests completed
```

모든 steps completed + DoD 전체 checked + verification 통과 확인 후:

`<promise>E2E_TESTS_COMPLETE</promise>`

---

## 진행 상태 파일 (`.claude-e2e-progress.json`)

```json
{
  "project": "프로젝트명",
  "created": "ISO timestamp",
  "status": "in_progress",
  "mode": "docs | code",
  "docsDir": "docs/ | null",
  "projectType": "web | flutter | mobile | unknown",
  "e2eFramework": "playwright | cypress | flutter_integration_test | maestro | null",
  "dataStrategy": "real-server | mock-server | null",
  "mockSchemaSource": "openapi | typescript-types | graphql | api-client | flutter-models | docs | inferred | null",
  "steps": [
    {"name": "analyze_project", "label": "프로젝트 분석", "status": "pending"},
    {"name": "derive_scenarios", "label": "시나리오 도출", "status": "pending"},
    {"name": "setup_framework", "label": "E2E 프레임워크 설정", "status": "pending"},
    {"name": "write_tests", "label": "E2E 테스트 작성", "status": "pending"},
    {"name": "verify_tests", "label": "테스트 검증", "status": "pending"}
  ],
  "scenarios": [],
  "errorHistory": {"currentError": null, "attempts": []},
  "dod": {
    "framework_setup": {"checked": false, "evidence": null},
    "scenarios_documented": {"checked": false, "evidence": null},
    "tests_written": {"checked": false, "evidence": null},
    "e2e_pass": {"checked": false, "evidence": null},
    "build_pass": {"checked": false, "evidence": null}
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

---

## Handoff (Iteration 종료 전 필수)

세션을 종료하기 전에 `.claude-e2e-progress.json`의 `handoff` 필드를 반드시 업데이트합니다:

```json
"handoff": {
  "lastIteration": 2,
  "completedInThisIteration": "Phase 2: Playwright 설정 완료, Phase 3: E2E-001, E2E-002 작성 완료",
  "nextSteps": "Phase 3: E2E-003 작성 시작. 인증 모킹은 playwright fixtures 사용",
  "keyDecisions": [
    "Playwright 선택 (기존 Node.js 프로젝트)",
    "data-testid 셀렉터 전략 채택"
  ],
  "warnings": "소셜 로그인 모킹 필요 - bypass 전략 검토 중",
  "currentApproach": "시나리오별 독립 spec 파일, 공통 fixtures로 인증 처리"
}
```

---

## 강제 규칙 (절대 위반 금지)

1. **자동 진행**: Phase 간 사용자 확인 없이 자동 진행
2. **단일 in_progress**: 동시에 하나의 단계만 `in_progress` 상태
3. **완료 전 진행 금지**: `in_progress` 작업이 `completed` 되기 전 다음 작업 시작 금지
4. **스킵 금지**: 어떤 이유로도 `pending` 작업을 건너뛰지 않음
5. **중간 종료 금지**: 모든 단계가 `completed` 될 때까지 종료하지 않음
6. **상태 파일 동기화**: 상태 변경 시 반드시 progress 파일 업데이트
7. **질문 금지**: 프로젝트 유형 unknown 예외 외에는 AskUserQuestion 사용 금지
8. **자동 전환**: 단계 완료 → 다음으로 확인 없이 자동 진행
9. **기존 코드 보호**: E2E 추가로 기존 빌드/테스트가 깨지면 안 됨. `data-testid` 추가는 동작 변경이 아니므로 허용
10. **handoff 필수**: 매 iteration 종료 시 handoff 필드 업데이트
11. **스크립트 우선**: 구조적/기계적 검사는 `shared-gate.sh`로 먼저 실행

## 포기 방지 규칙 (강제)

**절대 금지:**
- "E2E를 작성할 수 없습니다"
- "사용자가 직접 확인해주세요"
- 모든 단계 완료 전 종료

**강제 행동:**
- 막히면 → 다른 셀렉터/접근법 시도
- 3회 실패 → codex-cli 해결 요청
- 5회 실패 → 사용자 개입 요청
- 컨텍스트 부족 → `/compact` 실행 후 계속 진행
- 모든 단계 완료까지 계속 진행

**원칙:** 5회 실패 전까지 스스로 해결. 모든 단계가 완료될 때까지 멈추지 않음.
