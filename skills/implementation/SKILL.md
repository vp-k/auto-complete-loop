# Phase 2: Implementation (순수 구현 로직)

이 스킬은 full-auto 오케스트레이터에서 Phase 2 진입 시 Read로 로드됩니다.
Ralph/progress/promise 코드 없음 — 오케스트레이터가 관리.

## 전제 조건

- Phase 1 완료 (기획 문서 완성)
- Pre-mortem 가드 통과 (blocking Tiger 모두 mitigation 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 2 절차

### Step 2-1: 맥락 파악

1. overview.md (정의 문서) 읽기 — 기술 스택, 아키텍처 파악
2. SPEC.md 확인 (없으면 기획 문서들로부터 자동 생성)
3. README.md에서 구현할 문서 목록 추출
4. 구현 순서 결정 (의존성 기반)

#### DoD 로드
프로젝트 루트에서 `DONE.md` 확인:
- 파일 있음: 해당 DoD를 완료 기준으로 사용
- 파일 없음: 내장 완료 기준 사용 (빌드/테스트/린트/리뷰 통과)

### Step 2-1.5: DRY 사전 분석

구현 시작 전 기존 코드베이스에서 재사용 가능한 패턴/유틸리티를 탐색합니다:

1. **유사 패턴 탐색**: 기존 코드에서 새 기능과 유사한 패턴, 헬퍼, 유틸리티 함수 검색
2. **공통 모듈 확인**: 프로젝트에 이미 존재하는 공통 모듈(utils, helpers, shared 등) 파악
3. **중복 방지 목록 작성**: 재사용할 수 있는 기존 코드 목록을 progress의 `context`에 기록
   ```json
   "context": {
     "reusablePatterns": ["기존 auth middleware 재사용", "shared/validators.ts 활용"]
   }
   ```
4. **위반 시**: 구현 중 기존 유틸리티와 동일 기능을 새로 작성하려 하면 기존 것을 사용

### Step 2-1.8: 구현 스코프 검증

progress 파일의 `phases.phase_0.outputs.projectScope`를 읽어 레이어별 구현 계획을 확인합니다.

1. `hasFrontend: true` → 구현 문서/티켓 목록에 프론트엔드 항목이 1개 이상 존재하는지 확인
2. `hasBackend: true` → 구현 문서/티켓 목록에 백엔드 항목이 1개 이상 존재하는지 확인
3. **누락 발견 시**: SPEC.md의 해당 레이어 User Stories를 기반으로 문서를 자동 생성하고 티켓 분할에 포함
4. `projectScope`가 null이면: **Phase 0 Step 0-2.5로 되돌아가 projectScope를 정의한 후 재시도** (Phase 1→2 게이트에서 이미 차단되어야 하지만 이중 안전장치)

**절대 금지**: 한 레이어만 구현하고 Phase 3으로 넘어가는 것. `hasFrontend: true`인데 프론트엔드 구현 없이 Phase 2를 완료할 수 없습니다.

---

### Step 2-2: 프로젝트 구조 설계

Claude가 직접 최적의 구조 설계:
1. 디렉토리 구조
2. 기술 스택 세부 결정 (버전, 라이브러리)
3. 설정 파일 구성
4. 프로젝트 스캐폴딩 생성

progress 파일에 아키텍처 맥락 저장 (크래시 복구용):
```json
"context": {
  "architecture": "기술 스택 + 핵심 결정",
  "patterns": "설계 패턴"
}
```

초기 커밋 (롤백 기준점):
```bash
git add -A && git commit -m "[auto] 프로젝트 스캐폴딩 완료"
```

### Step 2-2.7: E2E 인프라 셋업 (1회성)

프로젝트 스캐폴딩 완료 후, 티켓 분할 전에 E2E 테스트 인프라를 구성합니다.

#### 적용성 판단
- 순수 라이브러리/CLI 도구 → `phases.phase_2.e2e.applicable = false`, `dod.e2e_pass = {"checked": true, "evidence": "N/A: pure library"}`, 이후 E2E 스텝 전부 스킵
- 나머지(web/API/flutter/mobile) → 진행

#### E2E 스킬 로드 + 프로젝트 분석
```
Read ${CLAUDE_PLUGIN_ROOT}/skills/e2e-setup/SKILL.md
```
스킬의 섹션 1(프로젝트 분석)에 따라:
1. 프로젝트 유형 감지 (web/flutter_mobile/flutter_web/api/native_mobile)
2. 데이터 전략 결정 (real-server vs mock-server)
3. 플랫폼별 환경 검증 (에뮬레이터, 브라우저 등)
   - 환경 미충족 시: 스킬의 폴백 전략 적용

#### SPEC.md에서 E2E 시나리오 도출

SPEC.md에 E2E Scenarios 섹션이 있으면 해당 시나리오를 사용.
없으면 스킬의 섹션 4(시나리오 도출)에 따라 3-5개 도출:
- Web: 페이지 네비게이션 + 폼 제출 + API 연동 시나리오
- Flutter: 화면 이동 + 위젯 인터랙션 + 상태 변경 시나리오
- API: 엔드포인트 체인 시나리오 (인증 → CRUD → 권한 검증)

#### progress 파일에 E2E 정보 기록

```json
"phases": {
  "phase_2": {
    "e2e": {
      "applicable": true,
      "projectType": "web | flutter_mobile | flutter_web | api | native_mobile",
      "dataStrategy": "real-server | mock-server",
      "e2eFramework": "playwright | integration_test | supertest | pytest | maestro",
      "fallbackReason": null,
      "scenarios": [
        {"id": "E2E-001", "title": "회원가입→로그인→대시보드", "source": "SPEC.md US-001,US-002", "priority": "high", "status": "pending", "testFile": null}
      ]
    }
  }
}
```

#### 프레임워크 설치 + 데이터 인프라 구성

스킬의 섹션 2(플랫폼별 E2E 전략)에 따라 프레임워크 설치 및 데이터 인프라(seed/cleanup 또는 MSW) 구성.

설치 후 기존 빌드 확인:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

커밋:
```bash
git add -A && git commit -m "[auto] E2E 프레임워크 + 인프라 설정"
```

**Iteration 관점**: 이 스텝은 독립 iteration으로 분리 가능 (프레임워크 설치 + 시나리오 도출).

### Step 2-2.5: Acceptance Criteria 사전 합의 (문서별)

각 문서 구현 시작 전, codex에게 검증 포인트를 질의하여 Phase 3 리뷰 기준을 사전 확정:

```bash
codex exec --skip-git-repo-check '## Acceptance Criteria 도출

다음 기획 문서를 읽고, 이 문서의 구현이 완료되었다고 판단할 핵심 검증 포인트 5개를 제시하라.
각 포인트는 코드 리뷰 시 pass/fail로 판정할 수 있도록 구체적이어야 한다.

### 기획 문서
파일: [문서 경로] — 직접 읽고 분석하세요

### 출력 형식
1. [검증 포인트]: [pass 조건]
2. ...
'
```

결과를 progress 파일에 저장:
```json
"phases": {
  "phase_2": {
    "documents": [{
      "name": "auth.md",
      "acceptanceCriteria": [
        "JWT 토큰 발급/검증 로직이 미들웨어로 분리되어 있다",
        "리프레시 토큰 로테이션이 구현되어 있다",
        "..."
      ]
    }]
  }
}
```

Phase 3 코드 리뷰 시 이 기준을 codex 프롬프트에 포함하여 검증.

### Step 2-3: 문서별 티켓 분할

문서 구현 시작 전 해당 문서를 티켓으로 분할:
1. DB/스키마 변경 -> 별도 티켓
2. API 엔드포인트별 -> 별도 티켓
3. 프론트엔드 페이지/컴포넌트별 -> 별도 티켓
4. 각 티켓은 독립적으로 빌드/테스트 검증 가능

#### Scope Challenge Gate

티켓 분할 후 다음 기준으로 범위를 점검:
- **경고 조건**: 티켓당 예상 변경 파일 10개 초과 또는 신규 클래스/모듈 3개 이상
- **경고 발생 시**: 추가 분할을 시도하고, 분할 불가 시 사유를 progress에 기록
- **기록**: `phases.phase_2.scopeChallenges`에 경고 발생 티켓과 조치 결과 기록

### Step 2-4: 자동 구현 루프

모든 문서에 대해 순차적으로:

1. **문서 읽기 -> 구현 항목 추출**
   - progress: 해당 문서를 `in_progress`로 변경

2. **Claude가 구현 계획 수립 + 직접 코드 작성**
   - 백엔드: 테스트 우선 개발 (TDD)
     1. 실패하는 테스트 먼저 작성
     2. 테스트 통과하는 최소 코드 작성
     3. 리팩토링
   - 프론트엔드: 일반 구현 방식

3. **품질 게이트 통과 확인**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```
   - 실패 시 L0-L5 에스컬레이션 적용
   - L0 즉시 수정(3회) -> L1 다른 방법(3회) -> L2 codex 분석 -> L3 다른 접근법(3회) -> L4 범위 축소 -> L5 사용자 개입

4. **codex-cli에게 코드 리뷰 요청**
   ```bash
   codex exec --skip-git-repo-check '## 코드 리뷰
   ### 원본 문서 스펙
   [핵심 요구사항]
   ### 구현된 코드
   파일: [경로] — 직접 읽고 검토하세요
   ### 요청
   비판적 시각으로 문제점, 누락, 개선점을 제시해주세요.
   '
   ```
   - 리뷰 피드백 -> 수정 후 재리뷰
   - 권장사항 -> 즉시 구현 (사용자에게 묻지 않음)
   - 리뷰 사이클 최대 3회

5. **문서 완료 처리**
   - progress: 해당 문서 `completed`
   - `documentSummaries`에 핵심 결정 요약
   - 자동 커밋: `git add -A && git commit -m "[auto] {문서명} 구현 완료"`

#### Bisectable Commit 정책

모든 자동 커밋은 다음 규칙을 준수:
- **독립 빌드/테스트**: 각 커밋은 독립적으로 빌드 및 테스트를 통과해야 함. 커밋 전 `quality-gate` 실행 필수.
- **1 티켓 = 1 커밋**: 하나의 티켓은 하나의 커밋으로 완결. 중간 상태 커밋 금지.
- **마이그레이션/설정 분리**: DB 마이그레이션, 설정 파일 변경, 의존성 추가는 기능 코드와 별도 커밋으로 분리.
  - 예: `[auto] DB 마이그레이션: users 테이블 추가` → `[auto] 사용자 인증 API 구현`
- **목적**: `git bisect`로 문제 커밋을 추적할 수 있어야 함.

### Step 2-5: Fresh Context Verification (문서/티켓 완료 전 필수)

Self-check 후, Agent 도구로 검증 에이전트를 별도 생성하여 fresh context에서 검증:
- 빌드/타입체크/린트/테스트 실행
- SPEC.md 대비 요구사항 충족 확인
- 결과를 `.claude-verification.json`에 기록

### Step 2-6: 에러 자동 복구

`rules/error-escalation-rules.md` 참조.

에러 기록:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error \
  --file "src/auth.ts" --type "TypeError" --msg "..." \
  --level L2 --action "시도한 행동" \
  --progress-file .claude-full-auto-progress.json
```

Edit 도구 에러 처리:
1. 즉시 파일 다시 읽기
2. `old_string` 재확인 후 재시도 (최대 3회)
3. 3회 실패 -> Write 덮어쓰기 -> 빌드/테스트 검증 -> 실패 시 `git restore --source=HEAD -- {파일}`로 해당 파일만 롤백 (다른 변경에 영향 없음)

### Step 2-6.5: E2E 테스트 일괄 작성 (모든 문서 구현 완료 후)

`phases.phase_2.e2e.applicable == true`인 경우에만 수행.

**전제 조건**: 모든 문서 구현 + 유닛 테스트 통과. 앱이 기동 가능한 상태.
E2E는 앱이 완성된 상태에서만 실행 가능하므로, 문서별 즉시 작성이 아닌 **구현 완료 후 일괄 작성**.

1. 앱 기동 가능 확인:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check
   ```

2. `phases.phase_2.e2e.scenarios`의 모든 pending 시나리오를 high 우선순위부터 작성:
   - `Read ${CLAUDE_PLUGIN_ROOT}/skills/e2e-setup/SKILL.md` (섹션 5: 테스트 작성 규칙)
   - 각 시나리오: 테스트 작성 → 개별 실행 → 통과 확인
   - 실패 시 에러 에스컬레이션 (L0-L5) 적용
   - 시나리오 `status = "completed"`, `testFile` 기록

3. E2E 전체 실행:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json
   ```

4. 커밋:
   ```bash
   git add -A && git commit -m "[auto] E2E 테스트 작성 완료"
   ```

5. DoD 업데이트: `dod.e2e_pass.checked = true`, evidence에 "N개 시나리오 전체 통과"

**Flakiness 대응**: 실패 시 1회 자동 재실행. 2회 연속 실패 시 에러 에스컬레이션.

### Step 2-7: Phase 2 완료

모든 문서 구현 + 검증 완료 시:
1. 문서-코드 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/
   ```
2. E2E 최종 확인 (`e2e.applicable == true`인 경우):
   - 모든 시나리오 `status == "completed"` 확인
   - `dod.e2e_pass.checked == true` 확인
3. DoD 업데이트: `all_code_implemented.checked = true`
4. Phase 전이는 오케스트레이터가 수행

### Iteration 관리

- 문서 구현: 1개 문서 또는 3개 티켓 per iteration
- E2E 작성: Phase 2 마지막 1-2 iteration에 집중
  - Iteration N: 남은 문서 구현 완료
  - Iteration N+1: E2E 시나리오 2-3개 작성
  - Iteration N+2: 나머지 E2E 시나리오 + e2e-gate 전체 실행
- Step 2-2.7 (E2E 인프라 셋업)은 독립 iteration으로 분리 가능
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료

### 복구

progress 파일에서:
- `context`로 아키텍처/패턴 맥락 복구
- `documentSummaries`로 완료된 문서의 결정 사항 파악
- `completed` 문서 스킵
- `in_progress` 문서 -> 해당 문서 처음부터 다시 (맥락 있으므로 일관성 유지)
