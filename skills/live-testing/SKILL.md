# Live App Testing (적응형)

실제 앱을 실행하고 사용자 관점에서 user flow를 검증합니다.
코드 리뷰(static analysis)로는 발견할 수 없는 런타임 버그를 찾습니다.

## 핵심 원칙

- **코드를 읽지 말고 앱을 사용하라**: 코드 리뷰가 아닌 실행 테스트
- **사용자처럼 행동하라**: 실제 user flow를 따라가며 기대 동작과 비교
- **엣지 케이스를 시도하라**: 빈 입력, 특수문자, 대량 데이터, 빠른 연속 클릭

## Step 1: 프로젝트 타입 감지

프로젝트 루트에서 다음을 확인하여 타입 결정:

| 감지 파일 | 프로젝트 타입 | 테스트 도구 |
|----------|-------------|-----------|
| `pubspec.yaml` + (`android/` or `ios/`) + 에뮬레이터 사용 가능 | Flutter Mobile | Maestro / Flutter Integration Test |
| `pubspec.yaml` + `web/` 폴더 존재 + 에뮬레이터 미사용 | Flutter Web | Playwright MCP |
| `package.json` + React/Next/Vue | 웹앱 | Playwright MCP |
| `package.json` + Express/Fastify/Nest | API 서버 | curl + DB 조회 |
| `requirements.txt` or `pyproject.toml` + FastAPI/Django/Flask | API 서버 | curl + DB 조회 |
| `go.mod` | Go 서버 | curl + DB 조회 |
| 기타 | 범용 | 가능한 도구로 대체 |

## Step 2: 앱 기동

프로젝트 타입에 따라 앱을 기동:

### 웹앱 / API 서버
```bash
# 의존성 설치 (필요시)
# npm install / pip install -r requirements.txt 등

# 개발 서버 시작 (백그라운드) — PID를 기록하여 종료 시 사용
# npm run dev & APP_PID=$!
# python manage.py runserver & APP_PID=$!
# go run main.go & APP_PID=$!

# 서버 준비 대기 (최대 30초)
# curl로 health check 반복
```

**중요**: 앱 기동 시 `& APP_PID=$!`로 PID를 반드시 기록. Step 5에서 `kill $APP_PID`로 종료.

### Flutter Mobile
```bash
# Flutter 의존성
flutter pub get

# 에뮬레이터/시뮬레이터 확인
flutter devices

# 앱 빌드 + 실행
flutter run -d <device_id>
```

### Flutter Web
```bash
flutter pub get
flutter run -d chrome --web-port=3000
```

**앱 기동 실패 시**: 에러 로그 수집 → LIVE-CRITICAL finding으로 보고 → 추가 테스트 불가

## Step 3: User Flow 테스트

### 3a: 프로젝트 타입별 테스트 실행

#### Playwright MCP (웹앱 / Flutter Web)

Playwright MCP를 사용하여 브라우저에서 직접 상호작용:

1. 페이지 네비게이션 (각 라우트 방문)
2. 폼 입력 + 제출
3. 버튼 클릭 + 결과 확인
4. 에러 상태 유발 (잘못된 입력)
5. 반응형 확인 (뷰포트 변경)

#### Maestro (Flutter Mobile)

Maestro flow 파일 생성 후 실행:

```yaml
# flow.yaml 예시
appId: com.example.app
---
- launchApp
- tapOn: "로그인"
- inputText:
    id: "email"
    text: "test@example.com"
- inputText:
    id: "password"
    text: "password123"
- tapOn: "로그인 버튼"
- assertVisible: "홈"
```

```bash
maestro test flow.yaml
```

**Maestro 미설치 시**: Flutter Integration Test로 fallback
```bash
flutter test integration_test/
```

#### curl (API 서버)

주요 API 엔드포인트를 순차적으로 호출:

```bash
# 1. 헬스 체크
curl -s http://localhost:3000/health

# 2. 인증 플로우
curl -s -X POST http://localhost:3000/api/auth/register -H "Content-Type: application/json" -d '{"email":"test@test.com","password":"test1234"}'

# 3. CRUD 작업
curl -s -X POST http://localhost:3000/api/posts -H "Authorization: Bearer $TOKEN" -d '{"title":"test","content":"test"}'
curl -s http://localhost:3000/api/posts
curl -s http://localhost:3000/api/posts/1

# 4. 에러 케이스
curl -s http://localhost:3000/api/posts/999999  # 존재하지 않는 리소스
curl -s -X POST http://localhost:3000/api/posts -d '{}'  # 잘못된 입력
```

### 3b: 공통 검증 항목

모든 프로젝트 타입에서 확인:

1. **핵심 기능 동작**: 주요 user story가 실제로 동작하는가?
2. **에러 처리**: 잘못된 입력, 미인증 접근 시 적절한 에러 응답?
3. **데이터 일관성**: 생성한 데이터가 조회 시 정확히 반환되는가?
4. **네비게이션**: 모든 경로가 접근 가능한가? 404 페이지?
5. **상태 유지**: 새로고침 후 상태가 유지되는가? (해당 시)

### 3c: Acceptance Criteria 검증

progress 파일에서 로드한 acceptance criteria 각 항목을 실제로 검증:
- 각 기준에 대해 pass/fail 판정
- fail인 항목은 LIVE finding으로 보고

## Step 4: Finding 보고

### 출력 형식

```
### LIVE-{SEVERITY}-{번호}: {제목}
- 시나리오: {수행한 user flow 단계별 설명}
- 기대 동작: {문서/상식 기반 기대}
- 실제 동작: {실제로 관찰된 결과}
- 파일 (추정): {원인으로 의심되는 파일/함수 — 코드를 읽어서 추정}
- 재현 방법: {다른 사람이 재현할 수 있는 구체적 단계}
```

### Severity 기준

- **CRITICAL**: 앱이 크래시, 데이터 손실, 핵심 기능 완전 불능
- **HIGH**: 주요 기능 부분 동작 불능, 심각한 UX 문제
- **MEDIUM**: 부수 기능 이상, 경미한 UX 문제
- **LOW**: 미세한 동작 차이, 개선 제안

## Step 5: 앱 종료 + 정리

테스트 완료 후:
1. 앱 프로세스 종료: `kill $APP_PID` (Step 2에서 기록한 PID 사용). 포트가 해제되었는지 확인.
2. 테스트 데이터 정리 (해당 시)
3. 임시 파일 삭제 (flow.yaml 등)

## 제한사항

- **외부 서비스 의존**: OAuth, 결제 등 외부 API가 필요한 기능은 테스트 불가 → SKIP으로 표시
- **시뮬레이터 필요**: Flutter Mobile은 에뮬레이터/시뮬레이터 필요 → 미설치 시 SKIP
- **Playwright MCP 필요**: 웹앱 테스트에 Playwright MCP 서버 필요 → 미설치 시 curl fallback
- **Maestro 필요**: Flutter Mobile 테스트에 Maestro 필요 → 미설치 시 flutter test fallback
