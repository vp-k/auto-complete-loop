# Phase 4: Verification + Launch Readiness

Loaded by the full-auto orchestrator at Phase 4 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 3 완료 (코드 리뷰 통과)
- `shared-rules.md`가 이미 로드된 상태

## Phase 4 절차

Phase 4는 두 그룹으로 분할 가능:
- **Group A** (Step 4-1 ~ 4-4): 기술 검증 + 문서화
- **Group B** (Step 4-5 ~ 4-7): 폴리싱 + 최종 검증

### Step 4-1: 전체 빌드/테스트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --strict --progress-file .claude-full-auto-progress.json
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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh implementation-depth --progress-file .claude-full-auto-progress.json
```

- SOFT gate: 5건 미만이면 WARN (진행 가능), 5건 이상이면 FAIL (수정 필요)
- 수정 후 재실행하여 임계값 미만 확인

### Step 4-1.8: 기능 플로우 검증

프로젝트 유형별 smoke 스크립트를 실행하여 핵심 플로우가 실제로 작동하는지 확인합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh functional-flow --progress-file .claude-full-auto-progress.json
```

- tests/api-smoke.sh (백엔드) / tests/ui-smoke.sh (프론트엔드) / tests/lib-smoke.sh (라이브러리) 실행
- 스크립트가 없으면 SKIP
- 실패 시 수정 후 재실행

### Step 4-1.9: 테스트 품질 검증

테스트의 실질적 품질을 확인합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh test-quality --progress-file .claude-full-auto-progress.json
```

- assertion 비율 ≥ 70%, skip 비율 ≤ 20%
- US-* ID 기반 커버리지 확인 (SPEC.md에 US-* 존재 시)
- SOFT gate: 미달 시 WARN

### Step 4-1.10: 페이지 렌더링 검증 (hasFrontend=true 시)

프론트엔드가 있는 프로젝트에서 각 페이지가 실제로 렌더링되는지 확인합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh page-render-check --progress-file .claude-full-auto-progress.json
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

#### 수정 후 커밋 (수정 사항이 있는 경우)

```bash
git add -A && git commit -m "[auto] Phase 4 Live 테스트 이슈 수정 완료"
```

#### DoD 업데이트

```json
"live_testing": {
  "checked": true,
  "evidence": "Live 테스트 N건 수행, CRITICAL/HIGH A건 수정"
}
```

남은 open CRITICAL/HIGH가 있으면 evidence에 명시하고 Step 4-2로 계속 진행
(live testing 실패가 Phase 완료를 차단하지는 않으나, 최종 보고서에 포함).

### Step 4-2: 보안 검토

1. **시크릿 스캔**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan
   ```

2. **codex 보안 리뷰**
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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh design-polish-gate --strict --progress-file .claude-full-auto-progress.json
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

3. **결과 기록**
   `.claude-verification.json`의 `qualityDimensions`에 추가:
   ```json
   "visualRegression": {
     "result": "pass|warn|fail",
     "healthScore": 85,
     "scoreDiff": 5,
     "evidence": "Before/After 비교 완료, 레이아웃 정상"
   }
   ```
   - `warn`: 스코어 하락(-5 이상 -10 미만) 또는 경미한 시각적 차이
   - `fail`: 스코어 하락(-10 이상) 또는 명백한 레이아웃 깨짐
   - `pass`: 스코어 유지/개선 + 시각적 차이 없음

### Step 4-6: 아티팩트/스모크 체크

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check --strict --progress-file .claude-full-auto-progress.json
```

Phase 4에서는 `--strict` 모드로 실행:
- 서버 기동 실패(soft_fail) → **FAIL** (완주 차단)
- SPEC.md 기반 엔드포인트 검증: 5xx 응답이 있으면 **FAIL**
- 라이브러리/CLI 프로젝트(start 스크립트 없음)는 SKIP 유지

### Step 4-6.5: 통합 검증 게이트 (하드 게이트)

Phase 2에서 실행한 검증을 Phase 4에서 다시 확인합니다:

```bash
# Placeholder 잔존 검사
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh placeholder-check

# 외부 서비스 연동 검증
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh external-service-check

# 서비스 통합 테스트 존재 확인 (hasBackend=true 시)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh service-test-check --progress-file .claude-full-auto-progress.json

# 프론트↔백 연동 검증 (hasFrontend+hasBackend 시)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh integration-smoke --progress-file .claude-full-auto-progress.json
```

각 게이트가 FAIL이면 해당 문제를 수정 후 재실행. 모두 PASS해야 Step 4-7 진행.

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

progress 파일의 `phases.phase_0.outputs.projectScope`를 기반으로:

1. `hasFrontend: true` → 프론트엔드 파일 존재 확인:
   - 페이지/컴포넌트 파일 (*.tsx, *.jsx, *.vue, *.svelte, page.*, layout.* 등)
   - **0개면 → FAIL** ("프론트엔드 미구현 — projectScope에서 hasFrontend=true")
2. `hasBackend: true` → 백엔드 파일 존재 확인:
   - API 라우트/컨트롤러/서비스 파일 (route.*, controller.*, service.*, handler.* 등)
   - **0개면 → FAIL** ("백엔드 미구현 — projectScope에서 hasBackend=true")
3. `projectScope`가 null이면 → **FAIL** ("projectScope 미정의 — Phase 0 Step 0-2.5에서 정의 필요")

**FAIL 시**: Phase 2로 회귀하여 누락 레이어 구현. Phase 4를 통과할 수 없음.

각 차원의 결과를 `.claude-verification.json`에 기록:
```json
"qualityDimensions": {
  "featureCompleteness": { "result": "pass", "evidence": "12/12 features implemented" },
  "layerCoverage": { "result": "pass", "evidence": "frontend: 15 files, backend: 8 files" },
  "security": { "result": "pass", "evidence": "0 SEC CRITICAL/HIGH findings" },
  "performance": { "result": "pass", "evidence": "0 PERF CRITICAL/HIGH findings" },
  "codeQuality": { "result": "pass", "evidence": "85% test coverage on business logic" },
  "documentation": { "result": "pass", "evidence": "README + API docs + .env.example" },
  "e2eCoverage": { "result": "pass", "evidence": "5/5 E2E scenarios passed" }
}
```

소프트 차원에서 fail이 있으면 경고 출력하되 Phase 완료는 차단하지 않음 (정보 제공용).

#### 4-7c: 결과 기록
4. 결과를 `.claude-verification.json`에 기록 (기술 게이트 + 다차원 품질)
5. progress 파일의 dod 체크리스트 최종 업데이트

자동 커밋:
```bash
git add -A && git commit -m "[auto] 최종 검증 및 폴리싱 완료"
```

DoD 전체 checked 확인 후, Phase 전이는 오케스트레이터가 수행.

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
   ```bash
   # 변경 커밋
   git add -A && git commit -m "[auto] version bump to vX.Y.Z"

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

- Group A (Step 4-1~4-4), Group B (Step 4-5~4-7)로 분할 가능
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료
