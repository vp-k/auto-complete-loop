# Phase 4: Verification + Launch Readiness

Loaded by the full-auto orchestrator at Phase 4 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

> `{PROGRESS_FILE}`은 오케스트레이터(full-auto.md "파라미터" 표)가 정한 값으로 치환한다
> (codex/solo: `.claude-full-auto-progress.json`, teams: `.claude-full-auto-teams-progress.json`).

## 전제 조건

- Phase 3 완료 (코드 리뷰 통과)
- `shared-rules.md`가 이미 로드된 상태

## Phase 4 절차

Phase 4는 두 그룹으로 분할 가능:
- **Group A** (Step 4-1 ~ 4-4): 기술 검증 + 문서화
- **Group B** (Step 4-5 ~ 4-7.5): 폴리싱 + 최종 검증 + 교차 감사

### Step 4-1: 전체 빌드/테스트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file {PROGRESS_FILE}
```

1. 전체 빌드 재실행 — 모든 모듈 빌드 성공 확인
2. 전체 테스트 재실행 — 모든 테스트 통과 확인
3. 린트/포맷 전체 검사 — 코드 스타일 일관성 확인

### Step 4-1.5: E2E 테스트 검증 (하드 게이트)

#### 적용성 확인
1. progress 파일의 `phases.phase_2.e2e.applicable` 확인
   - `false` → SKIP (`dod.e2e_pass = {"checked": true, "evidence": "N/A: not applicable"}`, 실패 아님)
   - `true` → **필수 (MANDATORY)**, 아래 진행
   - `null` (이전 버전 progress) → Phase 2에서 미설정. e2e-setup 스킬 로드하여 적용성 판단 후 진행

#### E2E 게이트 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --strict --progress-file {PROGRESS_FILE}
```

- **PASS (exit 0)** → `dod.e2e_pass` 업데이트
- **FAIL (exit 1)** → 실패한 테스트 수정 (에러 에스컬레이션 L0-L5 적용)
  - Flakiness 대응: 1회 자동 재실행, 2회 연속 실패 시 에스컬레이션
- **SKIP (exit 2)** → 프레임워크 없음. `--strict` 모드에서는 FAIL(exit 1)로 승격됨 = Phase 2에서 설정했어야 하는 에러 상태
  - Last-resort: `Read ${CLAUDE_PLUGIN_ROOT}/skills/e2e-setup/SKILL.md` → 설정 + 작성 + 실행
  - 이후 e2e-gate 재실행

#### 시나리오 커버리지 확인
- `phases.phase_2.e2e.scenarios`에서 모든 시나리오의 `status == "completed"` 확인
- pending 시나리오가 있으면: 작성 후 재실행

### Step 4-1.7: 구현 깊이 검증

stub/빈 함수/placeholder 응답을 탐지합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh implementation-depth --progress-file {PROGRESS_FILE}
```

- SOFT gate: 5건 미만이면 WARN (진행 가능), 5건 이상이면 FAIL (수정 필요)
- **SOFT→HARD 승격**: 연속 2회 실패(직전 fail/warn 포함) 시 HARD로 자동 승격되어 exit 1 — pass가 나오면 warn 등급으로 복귀
- 수정 후 재실행하여 임계값 미만 확인

### Step 4-1.8: 기능 플로우 검증

프로젝트 유형별 smoke 검증(functional-flow)은 Step 4-6의 `runtime-gate`가 서버 1회 기동으로 통합 실행합니다 (smoke-check + integration-smoke + functional-flow 3종). 이 단계에서 별도로 서버를 기동하지 않습니다.

- 폴백 (runtime-gate 사용 불가 환경 한정): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh functional-flow --progress-file {PROGRESS_FILE}` 개별 실행

### Step 4-1.9: 테스트 품질 검증

테스트의 실질적 품질을 확인합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh test-quality --progress-file {PROGRESS_FILE}
```

- assertion 비율 ≥ 70%, skip 비율 ≤ 20%
- US-* ID 기반 커버리지 확인 (SPEC.md에 US-* 존재 시)
- SOFT gate: 미달 시 WARN
- **SOFT→HARD 승격**: 연속 2회 실패(직전 fail/warn 포함) 시 HARD로 자동 승격되어 exit 1 — pass가 나오면 warn 등급으로 복귀

### Step 4-1.10: 페이지 렌더링 검증 (hasFrontend=true 시)

프론트엔드가 있는 프로젝트에서 각 페이지가 실제로 렌더링되는지 확인합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh page-render-check --progress-file {PROGRESS_FILE}
```

- Playwright로 각 페이지 방문 → 빈 페이지, console.error, JS 에러, 404 탐지
- hasFrontend=false이면 자동 SKIP
- SOFT gate: 문제 페이지 수 보고, --strict 시 FAIL
- 실패 시 해당 페이지 수정 후 재실행

### Step 4-1.11: Live App Testing

코드 리뷰와 자동화 E2E가 잡지 못하는 런타임 버그를 사용자 관점에서 검증합니다.

#### 실행 조건

progress 파일에서 다음 중 하나를 확인:
- `phases.phase_0.outputs.projectScope.hasFrontend == true`
- `phases.phase_0.outputs.projectScope.isMobileApp == true`
- 또는 `pubspec.yaml` / `package.json` + `src/` 존재로 앱 실행 가능 판단

해당 없으면: `dod.live_testing = {checked: true, evidence: "N/A: no frontend or mobile app"}` 후 SKIP.

#### 실행

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/live-testing/SKILL.md
```

위 스킬의 절차를 순서대로 따릅니다:
1. Step 1: 프로젝트 타입 감지 → 도구 선택 (Playwright MCP / Maestro / curl)
2. Step 2: 앱 기동
3. Step 3: User flow 테스트 (progress 파일의 acceptance criteria 포함)
4. Step 4: Finding 보고
5. Step 4.5: LIVE-CRITICAL/HIGH finding 수정 루프 → quality-gate 재실행
6. Step 5: 앱 종료 + 정리
7. Step 6: Live Testing Gate 실행 (아래 하드 게이트와 동일 — 중복 실행해도 무해)

#### 수정 후 커밋 (수정 사항이 있는 경우)

```bash
git add -A && git commit -m "[auto] Phase 4 Live 테스트 이슈 수정 완료"
```

#### Live Testing Gate (하드 게이트 — 필수)

live-testing 완료 후 반드시 실행:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh live-testing-gate --progress-file {PROGRESS_FILE}
```

- progress의 open LIVE-CRITICAL/HIGH finding을 집계하여 **1건이라도 있으면 FAIL → Phase 완료 차단**
- FAIL 시: Step 4.5 수정 루프로 돌아가 해당 finding 해결 → 게이트 재실행. PASS 전에는 Step 4-2로 진행할 수 없음.
- **skip 허용 범위**: `hasFrontend` 또는 `hasBackend`가 true인 프로젝트에서는 live 테스트를 반드시 수행해야 하며(게이트가 skip으로 기록되는 상태 = live 테스트 미수행 = 허용 안 됨), skip은 라이브러리/CLI 프로젝트에만 허용된다.
- `dod.live_testing.checked`는 **모델이 직접 기록하지 않는다** — 이 게이트의 PASS 결과로만 세팅된다. 결과는 verification.json의 `liveTesting`에 기록되며, stop-hook이 fail-closed로 확인한다.

### Step 4-2: 보안 검토

1. **시크릿 스캔**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan
   ```

2. **의존성 취약점 스캔** (조건 없이 항상 — codex 리뷰가 스킵되어도 이 검사가 의존성 취약점을 커버한다)
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh vuln-scan
   ```

3. **codex 보안 리뷰 (조건부 — SEC finding 이력이 있을 때만)**

   Phase 3 리뷰가 이미 SEC 관점을 포함하므로, 무조건 3중 검토하는 것은 중복이다. Phase 3 `findingHistory`에 `SEC-*` finding이 **1건이라도 있었던 경우에만** 실행한다 (보안 취약 신호가 있었던 코드베이스 → 수정 후 재확인 가치 있음). 0건이면 스킵하고 `security_review` evidence에 "Phase 3 SEC finding 0건 — codex 재검토 스킵, secret-scan·vuln-scan pass" 기록:
   ```bash
   codex exec --skip-git-repo-check '## 보안 검토
   ### 프로젝트 구조
   [주요 파일 목록 — 직접 읽고 검토]
   ### 요청
   비판적 시각으로 보안 문제점을 탐색해주세요.
   - .env 파일 .gitignore 포함 여부
   - 하드코딩된 API 키, 비밀번호
   - 로그 민감 정보 출력
   - 의존성 취약점
   '
   ```

   (secret-scan·vuln-scan은 조건 없이 **항상** 실행 — 위 1·2번)

DoD 업데이트: `security_review`, `secret_scan`

### Step 4-3: Cleanup Pass (De-Sloppify)

구현 중 "~하지 마" 지시보다 구현 후 정리 패스가 더 신뢰성 높음.
이 단계는 코드 리뷰(Phase 3)와 독립적인 **코드 정리 전용** 패스.

**4-3a: 디버그 코드 제거**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh find-debug-code
```
- console.log, print, debugger, breakpoint 등 제거
- 테스트 파일의 의도적 로깅은 유지

**4-3b: AI 슬롭 정리 (Code Simplifier Agent)**

Agent tool로 `code-simplifier` 에이전트를 호출하여 AI 생성 코드 안티패턴을 탐지:
- 불필요한 추상화 레이어 (단일 사용 래퍼, 단일 구현 팩토리 등)
- 과잉 에러 핸들링 (도달 불가능한 에러 경로, 재throw만 하는 catch)
- 코드를 반복하는 주석 (// increment counter 위의 counter++)
- 과잉 일반화 타입 (1회 사용 제네릭, 1-필드 인터페이스)
- 조기 설정화 (변하지 않는 값의 환경변수화)

에이전트 프롬프트에 프로젝트의 src/ 또는 주요 소스 디렉토리 경로를 포함.
결과의 HIGH 항목은 즉시 수정, MEDIUM은 판단 후 수정.

**4-3c: 코드 위생 정리**
- 주석 처리된 코드 블록 제거 (TODO 주석은 유지)
- 미사용 import/require 제거
- 빈 파일, 빈 함수 정리
- 불필요한 타입 캐스팅 제거

**4-3d: 일관성 정리**
- 네이밍 일관성 확인 (camelCase/snake_case 혼용)
- 에러 메시지 포맷 일관성
- 로깅 레벨 적절성 (info/warn/error)

**4-3e: 정리 후 품질 재검증**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file {PROGRESS_FILE}
```
정리 작업이 기존 기능을 깨뜨리지 않았는지 확인.

### Step 4-4: 문서화 확인 + Launch Readiness

#### 기본 문서화
1. **README 완성도**: 프로젝트 설명, 설치/실행 방법, 환경 변수 설명
2. **.env.example** 존재 여부 + 필수 환경 변수 목록
3. **API 문서** (해당 시)

#### 릴리즈 노트 자동 생성

git log 기반으로 릴리즈 노트를 생성합니다:

**`[auto]` 커밋 필터링 규칙:**
- `[auto]` prefix 커밋은 사용자용 changelog에서 제외
- `feat:`, `fix:`, `breaking:` 등 semantic commit만 포함
- `[auto]` 커밋은 "내부 자동화 N건" 1줄 요약으로 축약

**Fallback:**
- semantic commit이 0개인 경우, 파일 변경 기반 요약으로 fallback
- 디렉토리별 변경 파일 수 + 주요 변경 내용 AI 요약

릴리즈 노트 파일: `CHANGELOG.md` 또는 `RELEASE_NOTES.md`

#### (Flutter) 앱 스토어 메타데이터 템플릿

Flutter 프로젝트인 경우:
```markdown
## App Store Metadata
- 앱 이름: [프로젝트명]
- 한줄 설명: [80자 이내]
- 상세 설명: [4000자 이내]
- 카테고리: [App Store 카테고리]
- 키워드: [최대 100자]
- 스크린샷 가이드: [필요한 스크린샷 목록과 설명]
```

#### 배포 체크리스트

```markdown
## 배포 체크리스트
- [ ] 환경 변수 설정 완료
- [ ] 시크릿 관리 (vault/secrets manager)
- [ ] DNS/도메인 설정 (해당 시)
- [ ] SSL 인증서 (해당 시)
- [ ] 모니터링/알림 설정
- [ ] 백업 정책
- [ ] 롤백 계획
```

DoD 업데이트: `launch_ready.checked = true`, evidence에 "릴리즈 노트 + 배포 체크리스트 완료"

### Step 4-5: 디자인 폴리싱

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh design-polish-gate --strict --progress-file {PROGRESS_FILE}
```

WCAG 체크 + 스크린샷 캡처 (design-polish 플러그인 미설치 시 SKIP).
`--strict` 모드: WCAG 위반 시 FAIL (하드 게이트). 플러그인 미설치 시에는 SKIP 유지.

디자인 수정 + 품질 게이트 통과 후:
```bash
git add -A && git commit -m "[auto] Phase 4 디자인 폴리싱 완료"
```

### Step 4-5b: 시각적 리그레션 체크

design-polish-gate 실행 후, Before/After 비교를 수행합니다.

1. **Health Score 리그레션 확인**
   `.design-polish/health-score.json`의 `regression` 필드를 읽고:
   - `status == "regression"` && `diff < -10` → **경고 출력** (UI 품질 하락 가능성)
   - `status == "improved"` → 개선 확인
   - `status == "unknown"` → 첫 실행, 기준선 수립

2. **Before/After 스크린샷 시각 비교** (존재하는 경우)
   `.claude-verification.json`의 `designPolish.screenshots` 필드를 확인하여:
   - `before` 경로가 존재하면 `Read(".design-polish/screenshots/before-main.png")` 실행
   - `Read(".design-polish/screenshots/current-main.png")` 실행
   - Claude 비전으로 두 이미지를 비교:
     - 레이아웃 깨짐 여부
     - 색상/폰트 의도치 않은 변경
     - 요소 누락/추가 확인
   - `before`가 없으면 (첫 실행) 시각 비교 건너뜀

3. **디자인 계약 위반 확인** (계약이 설정된 프로젝트)
   `.claude-verification.json`의 `designPolish.tokenDrift`를 읽고:
   - `tokenDrift`가 없거나(게이트 skip/구버전 기록) `enabled == false` → 계약 미설정. 이 항목 건너뜀 (heuristic 모드)
   - `newViolationCount > 0` → **합의된 결정을 코드가 배신한 것**. 스코어가 올랐더라도 완료로 보지 않는다.
     위반 토큰을 `docs/DESIGN.md`의 결정 표와 대조해 (a) 코드를 계약에 맞추거나 (b) 사용자 승인 후
     계약을 갱신한다. 임의로 계약을 넓혀 위반을 지우는 것은 금지.
   - `totalViolations > 0` && `newViolationCount == 0` → 래칫으로 동결된 기존 부채. 차단하지 않되 리포트에 명시.

4. **결과 기록**
   `record-dimension` 서브커맨드로 `qualityDimensions.visualRegression`에 기록 (verification.json 직접 편집은 가드가 차단함):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension visualRegression pass "healthScore 85 (diff +5), Before/After 비교 완료, 레이아웃 정상"
   ```
   - `warn`: 스코어 하락(-5 이상 -10 미만) 또는 경미한 시각적 차이
   - `fail`: 스코어 하락(-10 이상) 또는 명백한 레이아웃 깨짐
   - `pass`: 스코어 유지/개선 + 시각적 차이 없음
   - evidence 문자열에 healthScore/scoreDiff와 비교 근거를 포함한다

### Step 4-6: 아티팩트/런타임 체크

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file {PROGRESS_FILE}
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh runtime-gate --progress-file {PROGRESS_FILE}
```

`runtime-gate`는 서버를 **1회만 기동**하여 smoke 3종(smoke-check + integration-smoke + functional-flow)을 통합 실행합니다:
- 서버 기동 실패(soft_fail) → **FAIL** (완주 차단 — stop-hook이 smokeCheck의 soft_fail을 fail로 처리)
- SPEC.md 기반 엔드포인트 검증: 5xx 응답이 있으면 **FAIL**
- 라이브러리/CLI 프로젝트(start 스크립트 없음)는 SKIP 유지
- 폴백 (runtime-gate 사용 불가 환경 한정): `smoke-check --strict` / `integration-smoke` / `functional-flow` 개별 실행

### Step 4-6.5: 통합 검증 게이트 (하드 게이트)

Phase 2에서 실행한 검증을 Phase 4에서 다시 확인합니다:

```bash
# Placeholder 잔존 검사
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh placeholder-check

# 외부 서비스 연동 검증
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh external-service-check

# 서비스 통합 테스트 존재 확인 (hasBackend=true 시)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh service-test-check --progress-file {PROGRESS_FILE}
```

프론트↔백 연동 검증(integration-smoke)은 Step 4-6의 `runtime-gate`에 통합되어 이미 실행되었습니다 (별도 재실행 불필요).

각 게이트가 FAIL이면 해당 문제를 수정 후 재실행. 모두 PASS해야 Step 4-7 진행.

### Step 4-6.7: 인수 테스트 게이트 (하드 게이트 — 필수 실행)

Phase 1에서 동결된 인수 테스트의 무결성 검사 + 실행을 수행합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh acceptance-gate --progress-file {PROGRESS_FILE}
```

> 인수 테스트 스위트가 오래 걸리는 프로젝트(서버 기동 포함)는 Bash 툴 기본 타임아웃(2분)을
> 넘길 수 있다 — 호출 시 timeout을 상향(최대 10분)하여 실행할 것. 타임아웃으로 끊기면
> 결과가 기록되지 않아 재실행이 필요하다.

- 무결성(변조/추가/삭제 감지) + `bash tests/acceptance/run.sh` 실행. 결과는 verification.json의 `acceptanceTests`(`{result, total, passed, failed, tamperedFiles?}`)에 기록됨.
- **FAIL 시**:
  - **(a) tamper** (`tamperedFiles` 존재): 동결 이후 변조/추가/삭제된 파일 → `git restore` 등으로 동결 시점 상태로 **원복**하거나, 정당한 스펙 변경이었다면 사용자 승인 → SPEC 갱신 → `acceptance-freeze --approved-by-user` 재동결 후 재실행.
  - **(b) red** (테스트 실패): **구현을 수정**한다 (에러 에스컬레이션 L0-L5 적용). **테스트 수정 금지** — implementation SKILL Step 2-1.10 참조.
- `dod.acceptance_pass`는 이 게이트가 pass 시 **자동 기록**한다 — 모델이 직접 세팅하지 않는다.
- stop-hook이 full-auto 계열 완주 조건으로 `acceptanceTests=pass`를 **fail-closed**로 요구한다 (기록 없음 = 미실행 = 완주 불가).

### Step 4-6.8: 최종 델타 리뷰 (조건부 — Phase 4 소스 변경 시)

**배경**: 소스 지문(`source-hash`)은 HEAD 커밋을 포함한다. Phase 4의 코드 변이 스텝(4-1.11 live 수정, 4-3 정리, 4-5 폴리싱)에서 커밋이 하나라도 생겼으면 마지막 리뷰 라운드의 `sourceHash`와 지문이 달라져 Step 4-7c의 `code-review-findings` 게이트가 **stale FAIL**한다. 이 스텝이 그 재기록 라운드의 공식 위치다 — 게이트에서 stale을 만난 뒤 즉흥 대응하지 말고 여기서 선제 처리한다.

절차 (Step 4-7 진입 전 필수):

1. **잔여 변경 전부 커밋** — 이 스텝 이후 4-7 진행 중 소스 커밋이 새로 생기지 않도록 한다. **순서 원칙: 커밋이 먼저, 리뷰가 마지막** (리뷰 후 커밋하면 지문이 다시 달라져 라운드 귀속이 깨진다).
2. **지문 대조**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh source-hash
   ```
   출력이 마지막 리뷰 라운드(roundResults 마지막 항목)의 `sourceHash`와 **같으면** → Phase 4에서 소스 변경 없음. 이 스텝 스킵, Step 4-7로 진행.
3. **다르면 델타 리뷰 라운드 1회 실행**: Phase 3 스킬의 라운드 절차(지문 캡처 → 리뷰어 실제 호출 → 검증 → roundResults/findingHistory 기록)를 재사용하되, **리뷰 범위는 마지막 라운드 이후의 diff만**으로 한정한다 (`git diff <마지막 라운드 시점 커밋>..HEAD`). 이 라운드는 재기록 라운드이므로:
   - 수렴 라운드 규칙 적용 대상 — 신규 finding이 Medium/Low뿐이면 수정 없이 `deferred` 기록 (소스 불변 → 지문 정합 자동 충족)
   - 수정 라운드 상한(5회) 계상에서 제외 (v4.16.0 규칙과 동일)
4. **신규 Critical/High가 나오면**: 수정 → 커밋 → 3을 반복 (Phase 3 리뷰 루프 규칙 동일 적용 — C/H는 deferred 불가). 수정 커밋이 발생했으면 이미 통과한 게이트가 옛 코드 기준이 되므로 **acceptance-gate를 재실행**하고, 런타임 코드(서버 기동 경로)가 변경됐으면 **runtime-gate도 재실행**한다.
5. **순서 불변식**: 이 스텝 이후(4-7, 4-7.5 포함) 어떤 경로로든 소스 수정이 발생하면 **반드시 이 스텝으로 돌아와** 커밋 → 델타 리뷰 → 게이트 재실행 순서를 다시 밟는다. "소스 변경 → 델타 리뷰 → 게이트"는 어떤 경로에서도 뒤집히지 않는다. **명시적 예외 1건**: Step 4-8의 version bump 커밋 — 모든 게이트 통과 후 버전 파일만 변경하는 릴리즈 메타데이터 커밋으로, 리뷰 대상 소스 변경이 아니므로 델타 리뷰를 트리거하지 않는다 (단, 커밋 범위가 버전 파일을 벗어나면 예외가 아니다 — Step 4-8의 커밋 범위 규칙 참조).

### Step 4-7: 최종 검증 (다차원 체크리스트)

모든 정리/폴리싱 완료 후, 기술 게이트 + 다차원 품질 평가를 수행:

#### 4-7a: 기술 게이트 (하드 임계값 — 하나라도 실패 시 차단)
1. 빌드 재실행 → 성공
2. 테스트 재실행 → 전체 통과
3. 린트 재실행 → 경고 없음

#### 4-7b: 다차원 품질 평가 (소프트 — 각 차원별 pass/fail 기록)

| 차원 | 평가 기준 | pass 조건 |
|------|----------|----------|
| 기능 완성도 | SPEC.md/기획 문서 대비 구현 비율 | 100% 구현 (scope reduction 제외) |
| **레이어 커버리지** | **projectScope 대비 아티팩트 존재** | **필수 레이어 파일 모두 존재 (아래 상세)** |
| 보안 | Phase 3 리뷰 + Phase 4 시크릿 스캔 결과 | CRITICAL/HIGH SEC finding 0개 |
| 성능 | N+1 쿼리, 메모리 누수, 대량 데이터 처리 | CRITICAL/HIGH PERF finding 0개 |
| 코드 품질 | 중복, 복잡도, 테스트 커버리지 | 주요 비즈니스 로직 테스트 존재 |
| 문서화 | README, API 문서, 환경 변수 설명 | 필수 문서 존재 |
| E2E 커버리지 | E2E 시나리오 vs SPEC.md 유저스토리 | high/medium 시나리오 전체 통과 (applicable=false 시 N/A) |

**US-* 기반 기능 완성도 자동 검증** (SPEC.md에 US-* ID 존재 시):
- SPEC.md에서 US-F-*, US-B-* ID 추출
- 각 ID가 소스 코드에 구현되었는지 확인 (해당 라우트/컴포넌트 존재)
- 각 ID가 테스트에서 커버되는지 확인
- 미구현 US 목록 출력

#### 레이어 커버리지 검증 (하드 게이트)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh layer-coverage --progress-file {PROGRESS_FILE}
```

스크립트가 `phases.phase_0.outputs.projectScope`와 파일시스템을 자동 대조합니다:
- `hasFrontend: true`인데 프론트엔드 파일(페이지/컴포넌트) 0개 → **FAIL**
- `hasBackend: true`인데 백엔드 파일(라우트/컨트롤러/서비스) 0개 → **FAIL**
- `projectScope`가 null → **FAIL** ("projectScope 미정의 — Phase 0 Step 0-2.5에서 정의 필요")

결과는 스크립트가 verification.json의 `layerCoverage`에 기록합니다. **모델이 `layerCoverage`를 직접 기록하는 것 금지** — 이 서브커맨드 실행 결과로만 세팅되며, stop-hook이 fail-closed로 확인한다.

**FAIL 시**: Phase 2로 회귀하여 누락 레이어 구현. Phase 4를 통과할 수 없음.

각 소프트 차원의 결과는 `record-dimension` 서브커맨드로 기록한다 (`layerCoverage`는 위 서브커맨드가 기록하므로 제외 — record-dimension이 거부한다). verification.json 직접 편집은 가드가 차단함:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension featureCompleteness pass "12/12 features implemented"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension security pass "0 SEC CRITICAL/HIGH findings"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension performance pass "0 PERF CRITICAL/HIGH findings"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension codeQuality pass "85% test coverage on business logic"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension documentation pass "README + API docs + .env.example"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension e2eCoverage pass "5/5 E2E scenarios passed"
```

소프트 차원에서 fail이 있으면 경고 출력하되 Phase 완료는 차단하지 않음 (정보 제공용).

#### 4-7c: 결과 기록
4. 결과 기록 — 기술 게이트(build/test/lint)는 `quality-gate` 등 각 서브커맨드가 verification.json에 자동 기록하고, 다차원 품질은 위 `record-dimension`으로 기록한다 (직접 편집은 가드가 차단함)
5. progress 파일의 dod 체크리스트 최종 업데이트
   - `dod.code_review_pass`는 **모델이 직접 세팅하지 않는다** — 아래 서브커맨드의 PASS 결과로만 세팅:
     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh code-review-findings --progress-file {PROGRESS_FILE}
     ```
     open CRITICAL/HIGH finding이 1건 이상이면 FAIL → 해당 finding 수정 후 Step 4-6.8로 복귀(커밋 → 델타 리뷰) 후 재실행. **stale FAIL**이면 Step 4-6.8 수행 누락이다 — 4-6.8로 돌아가 커밋+델타 리뷰를 수행한다. 결과는 verification.json의 `codeReviewFindings`에 기록된다.

**커밋 가드 (지문 보호)**: 잔여 변경은 Step 4-6.8에서 이미 전부 커밋했으므로, 이 시점에 새 커밋이 필요한 상태 자체가 이상 신호다 — 커밋은 HEAD를 바꿔 지문을 다시 stale로 만든다:
```bash
git status --porcelain | grep -vE '\.claude[-/]'
```
- 출력에 소스/문서 변경이 있으면 → **Step 4-6.8로 복귀** (커밋 → 델타 리뷰 → 게이트 재실행)
- 출력이 비어 있으면(런타임 산출물 `.claude-*`뿐) → 커밋 없이 진행 (`.claude-*`는 지문에서 제외되는 런타임 파일 — 최종 라운드 이후 소스 커밋 금지)

DoD 전체 checked 확인 후, Phase 전이는 오케스트레이터가 수행.

### Step 4-7.5: Fresh-Context 교차 검증 (verification-auditor)

구현 세션의 자기검증 편향을 제거하기 위해, Agent tool로 `verification-auditor` 에이전트를 호출하여 **fresh context에서 독립 감사**를 수행합니다. 이 에이전트는 코드를 수정하지 않으며 감사·보고만 합니다 (evidence 기반 — 주장을 신뢰하지 않고 직접 재확인).

**감사 범위 (모델 기록분에 한정)**: 스크립트가 기록하고 쓰기 가드로 보호되는 fail-closed 키(`acceptanceTests`, `layerCoverage`, `smokeCheck`, `codeReviewFindings`, `liveTesting`, 기획 게이트 3종 등)는 게이트 실행 결과로만 기록되어 조작이 이미 차단돼 있으므로 **재검증하지 않는다** — 키의 존재 여부(미실행 감지)만 확인한다. 감사의 실질 대상은 **모델이 기록한 항목**이다:
- (a) `record-dimension`으로 기록된 소프트 차원의 evidence vs 실제 상태
- (b) DoD 항목별 evidence 텍스트 vs 실제 상태
- (c) SPEC 대비 기능 실재 spot-check (US 2~3개 샘플 — 라우트/컴포넌트/테스트 실존 확인)
- (d) Test Plan 계약 spot-check (`docs/test-plan.md` 존재 시 — P0 케이스 전수 테스트 실존, P1 2~3개 샘플)

에이전트 프롬프트에 다음 경로를 반드시 포함:
- progress 파일 경로: `{PROGRESS_FILE}` (실제 값으로 치환)
- verification 파일 경로: `.claude-verification.json`
- SPEC 경로: `SPEC.md` (또는 `docs/api-spec.md`)
- 요청: 위 감사 범위 (a)(b)(c)(d) + fail-closed 키 존재 확인. 불일치 발견 목록을 Verification Audit Report 형식으로 보고

감사 보고서 처리:
1. **Blockers 또는 불일치 발견 시**: 해당 항목 수정 → **소스 수정이 있었으면 Step 4-6.8로 복귀** (커밋 → 델타 리뷰) → 관련 게이트 재실행 (quality-gate / runtime-gate / layer-coverage / code-review-findings / live-testing-gate 중 해당 게이트) → 에이전트 재호출로 재감사
2. **발견 없음 (Release Ready: Yes)**: Step 4-8 진행

### Step 4-8: Version Bump + PR 생성 (Opt-in)

Phase 4 완료 후, 사용자에게 버전 업 + PR 생성을 제안합니다.

#### Version Bump 규칙

diff 크기 기반 자동 결정:
- **patch** (0.0.x): 변경 50줄 미만 (버그 수정, 소규모 변경)
- **minor** (0.x.0): 변경 50줄 이상 (새 기능, 개선)
- **major** (x.0.0): breaking change 감지 시 (API 변경, 삭제 등)

```bash
# diff 크기 측정 (POSIX 호환)
local base_branch="${BASE_BRANCH:-main}"
local diff_lines
diff_lines=$(git diff --stat "HEAD~$(git rev-list --count HEAD --not "$base_branch")" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /insertion/) print $i}' || echo "0")

# breaking change 감지
local has_breaking
has_breaking=$(git log --oneline "$base_branch"..HEAD | grep -ciE 'breaking|BREAKING' || echo "0")
```

**Version 파일 업데이트** (프로젝트 유형별):
- `package.json`: `npm version <patch|minor|major> --no-git-tag-version`
- `pubspec.yaml`: `version:` 필드 직접 수정
- `Cargo.toml`: `version =` 필드 직접 수정
- `pyproject.toml`: `version =` 필드 직접 수정

#### PR 생성 (사용자 확인 후)

1. **사용자 확인**: "PR을 생성하시겠습니까?" (AskUserQuestion)
2. **승인 시**:

   **커밋 범위 규칙**: 이 커밋은 4-6.8 순서 불변식의 예외로 인정되는 대신 **버전 파일만** 포함해야 한다 (`git add -A` 금지). 스테이징 전 `git status --porcelain | grep -vE '\.claude[-/]'`로 버전 파일 외 변경이 없는지 확인 — 다른 소스 변경이 섞여 있으면 Step 4-6.8로 복귀한다.
   ```bash
   # 버전 파일 한정 커밋 (예: package.json — 프로젝트 유형에 맞는 버전 파일만 지정)
   git add package.json && git commit -m "[auto] version bump to vX.Y.Z"

   # PR 생성 (gh CLI)
   gh pr create \
     --title "Release vX.Y.Z: [주요 변경 요약]" \
     --body "## Summary
   - [자동 생성된 변경 요약]

   ## Quality
   - Health Score: [점수]/100
   - Code Review: [라운드] rounds, CRITICAL/HIGH: 0
   - Tests: All passing

   ## Changelog
   [릴리즈 노트에서 발췌]"
   ```
3. **거부 시**: 버전 업만 로컬에 커밋, PR 생성 건너뜀

### Iteration 관리

- Group A (Step 4-1~4-4), Group B (Step 4-5~4-7.5)로 분할 가능
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료
