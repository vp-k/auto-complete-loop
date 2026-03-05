---
description: 기획 문서 구현 (완전 자동화). Claude가 직접 구현하고 codex-cli는 리뷰/오류해결만. 프로젝트 생성부터 완료까지 사용자 개입 최소화
argument-hint: <definition(overview.md)> <doclist(README.md)>
---

# 기획 문서 구현 (완전 자동화)

정의 문서(헌법)를 기준으로 문서 리스트의 각 문서를 **실제 코드로 구현**합니다.
**Claude가 직접 구현**하고, codex-cli는 **리뷰와 오류 해결**에만 사용합니다.

**핵심 원칙**:
- Claude가 계획 수립부터 코드 작성까지 직접 수행
- codex-cli는 리뷰 시점과 L2 에스컬레이션(근본 원인 분석) 시에만 호출
- 사용자에게 "진행할래?" 묻지 않음

## 인수

- 정의 문서 경로: $1
- README 경로: $2

## Ralph Loop 자동 설정 (최우선 실행)

스킬 시작 시 스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "ALL_DOCS_VERIFIED" ".claude-progress.json"
```

### Ralph Loop 완료 조건

`<promise>ALL_DOCS_VERIFIED</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-progress.json`의 모든 문서 status가 `completed`
2. `.claude-verification.json`의 모든 검증 항목 exitCode가 0
3. `.claude-progress.json`의 `dod` 체크리스트가 모두 checked
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 한 iteration에서 **1~2개 문서(또는 3~5개 티켓)**만 처리
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 0단계: 맥락 파악

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

정의 문서($1)를 읽고:

- 프로젝트의 핵심 원칙, 기술 스택, 아키텍처 파악
- 이 문서가 "헌법"으로서 모든 구현의 기준임을 인지

### DoD 로드

프로젝트 루트에서 `DONE.md` 확인:
- 파일 있음: 해당 DoD를 완료 기준으로 사용
- 파일 없음: 내장 완료 기준 사용 (빌드/테스트/린트/리뷰 통과)

DoD를 `.claude-progress.json`의 `dod` 필드에 기록:
```json
"dod": {
  "build_success": { "checked": false, "evidence": null },
  "type_check": { "checked": false, "evidence": null },
  "lint_pass": { "checked": false, "evidence": null },
  "test_pass": { "checked": false, "evidence": null },
  "code_review": { "checked": false, "evidence": null },
  "e2e_pass": { "checked": false, "evidence": null }
}
```
각 항목의 `evidence`는 실제 실행 결과를 기록. evidence가 null이면 checked를 true로 설정 불가.

## 1단계: 문서 목록 파악

README($2)에서:

- 구현할 문서 목록 추출
- 각 문서의 유형 자동 감지 (DB, API, 프론트엔드, 인증, 인덱싱 등)
- 백엔드/프론트엔드 구분하여 구현 방식 결정
- 구현 순서 결정 (README에 명시된 순서 또는 의존성 기반)

## 1.5단계: SPEC 확인

프로젝트 루트에서 `SPEC.md` 확인:
- 파일 있음: 이를 구현 기준으로 사용
- 파일 없음: 기획 문서들로부터 SPEC.md 자동 생성
  1. 각 기획 문서에서 유저스토리 추출
  2. 데이터 모델 정리
  3. API 계약 정리
  4. 제약 조건 명시
  5. codex-cli에게 SPEC 검토 요청:
     ```bash
     codex exec --skip-git-repo-check '## SPEC 검토
     [생성된 SPEC.md 내용]
     기획 문서 대비 누락된 항목이 있는지 검토해주세요.'
     ```
  6. 검토 통과 후 SPEC.md 저장

## 2단계: 프로젝트 구조 설계

맥락 파악 후 Claude가 직접 최적의 구조 설계:

1. **구조 설계**
   - 디렉토리 구조
   - 기술 스택 세부 결정 (버전, 라이브러리)
   - 설정 파일 구성

2. **프로젝트 스캐폴딩 생성**

3. **진행 상황 파일 생성** (`.claude-progress.json`)

4. **아키텍처 맥락 저장** (크래시 복구용)
   - `.claude-progress.json`의 `context` 필드에 기록
   - `architecture`: 기술 스택 + 핵심 결정 (예: "Next.js 14 + Prisma + PostgreSQL, JWT 인증 (세션 서버 불필요)")
   - `patterns`: 설계 패턴 (예: "Repository 패턴, Controller-Service 구조")

5. **초기 커밋** (롤백 기준점)
   - `git commit -am "[auto] 프로젝트 스캐폴딩 완료"`
   - `lastCommitSha` 설정 (이후 롤백의 기준점)

## 3단계: 자동 구현 루프

모든 문서에 대해 순차적으로 구현 수행:

### 티켓 분할 (문서별 구현 전 필수)

문서 구현 시작 전 해당 문서를 티켓으로 분할:

1. DB/스키마 변경 -> 별도 티켓
2. API 엔드포인트별 -> 별도 티켓
3. 프론트엔드 페이지/컴포넌트별 -> 별도 티켓
4. 각 티켓은 독립적으로 빌드/테스트 검증 가능해야 함

티켓 목록을 `.claude-progress.json`의 해당 문서 `tickets` 배열에 기록:
```json
"tickets": [
  { "id": "T-001", "title": "users 테이블 마이그레이션", "status": "pending" },
  { "id": "T-002", "title": "POST /api/auth/register", "status": "pending" }
]
```

### 구현 프로세스

1. **문서 읽기 -> 구현 항목 추출**
   - `.claude-progress.json`에서 해당 문서를 `in_progress`로 변경

2. **Claude가 구현 계획 수립 및 직접 코드 작성**
   - **백엔드**: 테스트 우선 개발 방식 적용
   - **프론트엔드**: 일반 구현 방식

3. **품질 게이트 통과 확인** (빌드/타입/린트/테스트)
   - 실패 시 L0-L5 에스컬레이션 적용 (에러 자동 복구 섹션 참조)
   - L0 즉시 수정 → L1 다른 방법 → L2 codex 분석 → L3 다른 접근법 → L4 범위 축소 → L5 사용자 개입

4. **codex-cli에게 코드 리뷰 요청**
   - 리뷰 피드백 있으면 -> 수정 후 다시 리뷰
   - 권장사항 있으면 -> 즉시 구현 (사용자에게 묻지 않음)
   - 리뷰 통과 + 권장사항 모두 처리 -> 구현 완료

5. **다음 문서로 자동 진행**
   - `.claude-progress.json`에서 해당 문서를 `completed`로 변경
   - `documentSummaries`에 해당 문서의 핵심 결정 요약 추가
     - 예: `"auth.md": "JWT 인증 (세션 서버 불필요), refresh token 7일, bcrypt 해싱"`
     - 결정 사항 + 간단한 이유 포함 (읽고 이해 가능한 수준)
   - **자동 커밋**: `git commit -am "[auto] {문서명} 구현 완료"`
   - `lastCommitSha` 업데이트
   - 목록 끝까지 반복

### 백엔드 테스트 우선 개발 (백엔드만 적용)

API, 서비스 로직, DB 관련 코드에 적용:

1. **테스트 먼저 작성** - 실패하는 테스트 코드 작성
2. **최소 구현** - 테스트 통과하는 최소한의 코드 작성
3. **리팩토링** - 코드 정리 및 최적화

codex 리뷰 시 테스트 우선 개발 준수 여부도 확인:

- 테스트 커버리지
- 테스트 품질 (경계 조건, 에러 케이스)
- 테스트와 구현의 일관성

### 프론트엔드 테스트 전략

**단위 테스트 (필수):** 비즈니스 로직 단위 테스트 (상태 관리, 유틸 함수)

**E2E 테스트 (필수):** 핵심 사용자 플로우를 커버하는 E2E 테스트 작성
- Web: Playwright (헤드리스) — `npm init playwright@latest`로 설정
- Flutter: integration_test/ — `flutter test integration_test/`
- Mobile: Maestro — `.maestro/` 디렉토리에 YAML 플로우

**작성 원칙:**
- 핵심 시나리오 3-5개 (가입→로그인→핵심기능→결과확인)
- 헤드리스 CLI 실행 가능해야 함
- 테스트 데이터 셋업/클린업 자체 포함

**언어별 특화 지침:** codex 토론에서 결정 (아키텍처, 테스트 전략 등)

### 문서별 품질 게이트

각 문서 구현 완료 후 codex 리뷰 전에 자동 검증:

**검증 항목:**

1. **빌드 성공** - 언어별 빌드 명령 실행
2. **타입 체크 통과** - TypeScript: `tsc --noEmit`, Go: `go vet`, Dart: `dart analyze`
3. **린트 통과** - ESLint, gofmt, dart format 등
4. **테스트 통과** - 해당 문서 관련 테스트 실행

**품질 게이트 실패 처리 흐름 (L0-L5 에스컬레이션):**

```
빌드/타입/린트/테스트 실패
        |
  [L0] Claude 즉시 수정 (3회)
        | (예산 소진)
  [L1] 다른 방법 시도 (3회)
        | (예산 소진)
  [L2] codex-cli 근본 원인 분석 (1회) + git stash 안전 지점
        |
  [L3] 완전히 다른 접근법 (3회, codex 분석 기반)
        | (예산 소진)
  [L4] 범위 축소 (1회, 핵심 경로 제외)
        | (예산 소진)
  [L5] 사용자 개입 요청
```

- **L0~L1**: "에러 자동 복구" 섹션의 규칙 적용
- **L2**: codex-cli 근본 원인 분석 + `git stash`로 안전 지점 확보
- **L3~L4**: codex 분석 기반 접근법 전환 + 범위 축소
- **phase 변화**: `testing` -> (실패) -> `implementing` -> (수정) -> `testing`
- **레벨 전환 시**: `record-error --reset-count`로 카운터 리셋

**codex 품질 게이트 해결 요청:**

```bash
codex exec --skip-git-repo-check '## 품질 게이트 실패 해결

### 실패 항목
[빌드/타입/린트/테스트]

### 에러 메시지
[에러 내용]

### 관련 코드
[문제 코드 스니펫]

### 요청
비판적 시각으로 근본 원인과 해결책을 제시해주세요.
'
```

### 검증 결과 기록 (강제)

스크립트로 품질 게이트를 일괄 실행하고 결과를 기록합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-progress.json
```

스크립트가 자동으로:
1. 프로젝트 유형을 감지하고 빌드/타입/린트/테스트 명령을 결정
2. 각 명령을 실행하고 결과를 `.claude-verification.json`에 기록 (stop-hook 호환 포맷)
3. progress 파일의 DoD를 업데이트

**규칙:**
- 코드 변경 후 반드시 재실행 및 재기록
- timestamp가 마지막 git commit보다 이전이면 재실행 필요
- exitCode가 0이 아닌 항목이 있으면 문서/티켓 완료 불가

### codex-cli 호출 방법

**코드 리뷰 (구현 완료 후):**

```bash
codex exec --skip-git-repo-check '## 코드 리뷰

### 원본 문서 스펙
[문서 핵심 요구사항]

### 구현된 코드
파일: [파일 경로]
[코드 내용 - 핵심 부분만]

### 요청
비판적 시각으로 문제점, 누락, 개선점을 탐색하고 우선순위별로 제시해주세요.
권장사항이 있으면 함께 제시해주세요.
'
```

### 리뷰 피드백 처리

**codex-cli 리뷰 피드백 수신 시:**

1. 피드백 우선순위 확인 (Critical > High > Medium > Low)
2. Critical/High는 즉시 수정
3. Medium/Low는 판단하여 수용 또는 사유와 함께 스킵
4. 수정 후 재리뷰 요청
5. 피드백 없을 때까지 반복

**권장사항 처리:**

- 권장사항도 즉시 구현 (사용자에게 묻지 않음)
- 구현 후 재리뷰
- **리뷰 사이클 최대 3회** - 3회 후에도 새 권장사항이 있으면 Low 우선순위로 기록만 하고 진행

### Fresh Context Verification (문서/티켓 완료 전 필수)

Self-check 통과 후, **Task 도구로 검증 에이전트를 별도 생성**하여 fresh context에서 검증:

```
Task(subagent_type="general-purpose", prompt="
## Fresh Context 검증 요청

### 검증 대상
[변경된 파일 목록]

### 검증 항목
1. 빌드: [빌드 명령어] 실행 -> exit code 0 확인
2. 타입체크: [타입체크 명령어] 실행 -> 에러 없음 확인
3. 린트: [린트 명령어] 실행 -> 경고 없음 확인
4. 테스트: [테스트 명령어] 실행 -> 전체 통과 확인

### 요구사항 대조
[SPEC.md 또는 기획 문서의 해당 항목]

구현이 요구사항을 충족하는지 확인하고,
결과를 .claude-verification.json에 기록해주세요.
")
```

**왜 Task 도구인가:**
- 서브에이전트는 fresh context로 시작 -> 구현 AI의 편향 없음
- 부모 세션의 컨텍스트를 소비하지 않음
- codex-cli보다 더 깊은 검증 가능 (실제 빌드/테스트 실행)

**기존 codex-cli 리뷰와의 관계:**
- codex-cli 리뷰: 코드 품질/설계 관점 (유지)
- Fresh Context Verification: 빌드/테스트/요구사항 충족 관점 (신규)
- 둘 다 통과해야 완료

### 피드백 우선순위

1. **Critical**: 정의 문서와 충돌, 보안 취약점, 치명적 버그
2. **High**: 성능 심각한 저하, 주요 기능 누락
3. **Medium**: 최적화 기회, UX 개선 가능
4. **Low**: 코드 스타일, 사소한 개선

## 에러 자동 복구

> 이 섹션은 "문서별 품질 게이트"의 L0-L5 에스컬레이션에 해당합니다.

### 에러 분류 (Error Classification)

에러 발생 시 레벨 분류 (`shared-rules.md`의 Error Classification & Escalation 참조):

| 레벨 | 분류 | 예시 |
|------|------|------|
| L0 | environment | 패키지 미설치, PATH, 권한 |
| L1 | build | 컴파일 에러, 번들 실패 |
| L2 | type | 타입 불일치, 인터페이스 누락 |
| L3 | runtime | 테스트 실패, 런타임 에러 |
| L4 | quality | 린트, 코드 스타일, 경고 |

**방향 판별**: L0→L1→...→L4 = 진행(forward), 역방향 = 회귀(backward)
회귀 2회 연속 시 현재 접근법을 재검토 (codex 호출 또는 다른 접근법)

### 동일 에러 판별 기준

**다음 조건이 모두 일치하면 "동일 에러"로 판단:**

- 에러 유형 (TypeError, BuildError, SyntaxError 등)
- 에러 발생 파일
- 에러 메시지의 핵심 부분 (줄 번호는 무시)

**에러 발생 시 스크립트로 에러 기록 및 에스컬레이션 판별:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error \
  --file "src/auth.ts" --type "TypeError" --msg "Property 'user' does not exist" \
  --level L2 --action "타입 가드 추가 시도" \
  --progress-file .claude-progress.json
```

레벨 전환 시 카운터 리셋:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error \
  --file "src/auth.ts" --type "TypeError" --msg "Property 'user' does not exist" \
  --level L2 --reset-count \
  --progress-file .claude-progress.json
```

스크립트 exit code로 다음 액션 결정:
- `0`: 현재 레벨 예산 내 → 계속 시도
- `1`: 현재 레벨 예산 소진 → 다음 레벨로 에스컬레이트
- `2`: L2 도달 → codex 분석 필요
- `3`: L5 도달 → 사용자 개입 필요

### 빌드/테스트 실패 처리 (레벨별 에스컬레이션)

**L0: 즉시 수정 (3회)**

1. 에러 분석 → 원인 파악 → 수정
2. 품질 게이트 재실행
3. 통과 시 다음 단계, 실패 시 재시도
4. 3회 소진 시 → L1로 에스컬레이트 (`record-error --reset-count`)

**L1: 다른 방법 시도 (3회)**

같은 설계, 다른 구현으로 시도:
- 라이브러리 교체, 패턴 변경, API 변경
- 3회 소진 시 → L2로 에스컬레이트

**L2: codex 분석 (1회)**

1. **안전 지점 확보**: `git stash`로 현재 상태 저장
2. **codex-cli 호출**:

```bash
codex exec --skip-git-repo-check '## 근본 원인 분석 요청

### 에러 내용 (L0-L1 총 6회 시도 후)
[에러 메시지 핵심]

### 시도한 해결책
[이전 시도 목록]

### 요청
근본 원인을 분석하고 완전히 다른 접근법을 제시해주세요.
'
```

3. codex 분석 결과 확보 → L3로 진행

**L3: 완전히 다른 접근법 (3회, codex 분석 기반)**

설계/아키텍처 수준 전환 (REST→GraphQL, CSR→SSR, WebSocket→폴링 등):
1. **롤백**: `git reset --hard {lastCommitSha}` (마지막 성공 커밋으로)
2. codex 분석 결과 기반으로 다시 구현
3. `phase` → `implementing` (처음부터 다시 구현)
4. 3회 소진 시 → L4로 에스컬레이트

**L4: 범위 축소 (1회)**

`shared-rules.md`의 Scope Reduction 절차 참조:
1. 기능을 최소 동작 버전으로 구현
2. `scopeReductions` 배열에 기록
3. `SCOPE_REDUCTIONS.md` 생성/업데이트
4. **핵심 경로(인증, CRUD 기본, 빌드)는 범위 축소 불가**
5. 범위 축소 후에도 실패 시 → L5로 에스컬레이트

**L5: 사용자 개입 요청**

선택지를 제시하여 사용자에게 개입 요청

**errorHistory 초기화 시점:**

- 품질 게이트 통과 시 → 전체 초기화
- 레벨 전환 시 → `record-error --reset-count`로 카운터 리셋
- codex 해결책으로 다른 에러 발생 시 → `currentError` 갱신

### Edit 도구 에러 처리

**Edit 실패 시 (old_string 불일치 등):**

1. 즉시 파일 다시 읽기 (`Read` 도구)
2. `old_string` 재확인 후 재시도
3. 최대 3회 재시도
4. 3회 실패 시 -> **안전한 Write 덮어쓰기**:
   - git이 있으므로 별도 백업 불필요 (`git diff`로 복구 가능)
   - `Write` 도구로 전체 파일 덮어쓰기
   - 즉시 빌드/테스트로 검증
   - 실패 시 `git checkout -- {파일}`로 복구

**원칙:** Edit 실패는 즉시 해결 (다음 작업 진행 금지)

### 세션 중단 대비

**상태는 `.claude-progress.json`에 자동 저장됨:**

- 현재 진행 중인 문서명 (`currentDocument`)
- 완료된 문서 목록 (`documents[].status`)
- 현재 단계 (`phase`: implementing/testing/reviewing)

**재개 방법 (정상 중단):**

- `claude -c` 또는 `claude -r`로 세션 재개
- `.claude-progress.json` 파일 읽어서 마지막 작업 지점부터 계속

### 프로세스 완전 종료 후 복구

**정전, 크래시 등으로 프로세스가 완전 종료된 경우:**

**`.claude-progress.json`으로 복구 가능:**
- `context`로 아키텍처/패턴 맥락 복구
- `documentSummaries`로 완료된 문서의 결정 사항 파악
- `completed` 문서들 스킵 (다시 구현 안 함)
- 생성된 파일 목록 확인 (`completedFiles`)
- `handoff`로 이전 iteration의 맥락 복구

**복구 불가능한 것:**
- `in_progress` 문서의 진행 중이던 작업 (처음부터 다시)
- codex 리뷰 상세 내용 (요약만 있음)

**재시작 방법:**

1. 새 Claude Code 세션 시작
2. `/implement-docs-auto <정의문서> <README>` 실행
3. Claude가 `.claude-progress.json` 파일 감지

**Claude 동작 규칙 (0단계에서):**

프로젝트 루트에 `.claude-progress.json` 파일이 존재하면:

1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 -> 이전 iteration 맥락 복구
3. `context.architecture`, `context.patterns`로 아키텍처 맥락 주입
4. `documentSummaries`로 각 완료 문서의 결정 사항 파악
5. `completed` 문서들 -> 스킵
6. `in_progress` 문서 -> **해당 문서 처음부터 다시** (맥락 있으므로 일관성 유지)

## TODO 완료 강제 (파일 기반)

### 진행 상황 파일

프로젝트 시작 시 `.claude-progress.json` 파일 생성:

```json
{
  "project": "프로젝트명",
  "created": "2025-01-02T10:00:00Z",
  "status": "in_progress",
  "documents": [
    {"name": "문서1.md", "status": "pending", "phase": null, "tickets": []},
    {"name": "문서2.md", "status": "pending", "phase": null, "tickets": []}
  ],
  "dod": {},
  "currentDocument": null,
  "lastCommitSha": null,
  "errorHistory": {
    "currentError": null,
    "attempts": []
  },
  "completedFiles": [],
  "context": {
    "architecture": null,
    "patterns": null
  },
  "documentSummaries": {},
  "lastVerifiedAt": null,
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

**상태 전이:**

- `pending` -> `in_progress`: 해당 문서 구현 시작 시
- `in_progress` -> `completed`: 품질 게이트 + codex 리뷰 통과 시

**phase 값 (3단계):**

- `implementing`: 계획 수립 + 코드 작성 중
- `testing`: 품질 게이트 검증 중
- `reviewing`: codex 리뷰 중

**phase 전이 시점:**

- `implementing` -> `testing`: 코드 작성 완료 후
- `testing` -> `reviewing`: 품질 게이트 통과 후
- `testing` -> `implementing`: 품질 게이트 실패 시 (수정 필요)
- `reviewing` -> `completed`: 리뷰 통과 + 권장사항 처리 완료

### 강제 규칙

> `shared-rules.md`의 공통 강제 규칙 + 증거 기반 완료 선언 규칙을 따릅니다.

### 파일 저장 시점 (최소화)

**`.claude-progress.json` 업데이트 시점:**

| 시점 | 업데이트 내용 |
|------|--------------|
| 2단계 완료 | `context.architecture`, `context.patterns` (1회) |
| 문서 시작 | status -> `in_progress`, phase 설정 |
| phase 변경 | phase 값만 |
| 에러 발생 | errorHistory (3회 이상 반복 시만) |
| `/compact` 실행 | turnCount, lastCompactAt |
| 문서 완료 | status -> `completed`, completedFiles, `documentSummaries` 추가 |
| Iteration 종료 전 | `handoff` 필드 업데이트 |

**저장하지 않는 것:**
- 매 턴의 turnCount (메모리로만 관리)
- 1~2회차 에러 (L0 예산 소진 전까지는 저장 안 함)

### 체크포인트 (문서 완료 조건)

각 문서가 completed가 되려면 **모두 충족**:

1. 품질 게이트 통과 (빌드/타입/린트/테스트)
2. codex 리뷰 통과
3. 권장사항 처리 (Critical/High 전부, Medium/Low는 리뷰 3회 이내만)
4. `.claude-progress.json` 파일 업데이트

### Self-check (문서/티켓 완료 전 필수)

완료 선언 전 다음을 **순서대로** 실행:

1. 원래 요구사항(SPEC.md 또는 기획 문서) 다시 읽기
2. 구현이 요구사항을 충족하는지 항목별 대조
3. 빌드/테스트를 **지금** 실행 (이전 결과 재사용 금지)
4. 실행 결과를 `.claude-verification.json`에 기록
5. `.claude-progress.json`의 dod 체크리스트 업데이트 (evidence 포함)

**5개 중 하나라도 미완료면 완료 불가. 미충족 항목부터 해결.**

### Handoff (Iteration 종료 전 필수)

> `shared-rules.md`의 Handoff 업데이트 규칙을 따릅니다. progress 파일: `.claude-progress.json`

### 증거 기반 완료 선언

> `shared-rules.md`의 증거 기반 완료 선언 규칙을 따릅니다. 추가: Fresh Context Verification도 통과해야 완료.

## 컨텍스트 관리

> `shared-rules.md`의 컨텍스트 관리 + 외부 AI 자체 탐색 규칙을 따릅니다.

### 대용량 작업 시

문서가 10개 이상이거나 복잡한 프로젝트인 경우:

- `sonnet[1m]` 모델 사용 권장 (1백만 토큰 컨텍스트)
- 또는 모듈별로 새 세션에서 진행

## 4단계: 전체 검증

모든 문서 구현 완료 후 릴리즈 품질 검증 수행:

### 4.1 전체 빌드/테스트

1. **전체 빌드 재실행** - 모든 모듈 빌드 성공 확인
2. **전체 테스트 재실행** - 모든 테스트 통과 확인
3. **린트/포맷 전체 검사** - 코드 스타일 일관성 확인

### 4.1.5 E2E 테스트 검증

1. 기존 E2E 테스트 점검:
   - 누락된 핵심 시나리오 확인 → 추가
   - 실패 테스트 원인 분석 → 수정

2. E2E 실행:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate
```

3. 프레임워크 미감지 시: 이 시점에서 E2E 설정 + 테스트 작성 후 재실행.

### 4.2 보안 검토

1. **민감 정보 노출 확인**
   - .env 파일이 .gitignore에 포함되어 있는지
   - 하드코딩된 API 키, 비밀번호 없는지
   - 로그에 민감 정보 출력하지 않는지

2. **의존성 취약점 스캔**
   - `npm audit`, `go mod verify`, `pub outdated` 등

```bash
codex exec --skip-git-repo-check '## 보안 검토

### 프로젝트 구조
[주요 파일 목록]

### 환경 변수 처리
[.env 파일, 환경 변수 사용 패턴]

### 요청
비판적 시각으로 보안 문제점을 탐색해주세요.
'
```

### 4.3 문서화 확인

1. **README 완성도**
   - 프로젝트 설명, 설치 방법, 실행 방법
   - 환경 변수 설명

2. **환경 설정 가이드**
   - .env.example 존재 여부
   - 필수 환경 변수 목록

3. **API 문서** (해당시)

```bash
codex exec --skip-git-repo-check '## 문서화 검토

### 현재 README
[README 내용 요약]

### 프로젝트 구조
[주요 기능, 파일 구조]

### 요청
README에 추가해야 할 내용을 제시해주세요.
'
```

### 4.4 코드 정리

1. **디버그 코드 제거** - console.log, print 등
2. **주석 처리된 코드 정리**
3. **미사용 import 제거**
4. **불필요한 파일 정리**

```bash
codex exec --skip-git-repo-check '## 릴리즈 전 정리

### 코드 상태
[주요 파일 목록, 코드 스니펫]

### 요청
릴리즈 전 정리해야 할 항목을 비판적 시각으로 제시해주세요.
'
```

### 4.5 최종 검증

모든 정리 완료 후:

1. 빌드 재실행 -> 성공
2. 테스트 재실행 -> 전체 통과
3. 린트 재실행 -> 경고 없음
4. 결과를 `.claude-verification.json`에 기록
5. `.claude-progress.json`의 dod 체크리스트 최종 업데이트

## 5단계: 완료 보고

**완료 조건**: 모든 문서 구현 + 전체 검증 통과 + codex 리뷰 통과 + dod 체크리스트 전체 checked

모든 작업 완료 시 **간결하게** 보고:

- 문서별 한 줄 요약 (생성된 파일 + 주요 결정사항)
- 전체 검증 결과 요약
- 처리된 권장사항 요약
- 외부 서비스 설정 안내 (API 키 등)

**Ralph Loop 완료:** 모든 조건 충족 시 `<promise>ALL_DOCS_VERIFIED</promise>` 출력

## 포기 방지 규칙 (강제)

**절대 금지:**

- "이 문제는 해결할 수 없습니다"
- "사용자가 직접 확인해주세요"
- "다른 접근법을 시도해보세요" (본인이 시도하지 않고)
- 중간에 사용자에게 넘기기

**강제 행동 (레벨별 에스컬레이션):**
- L0 즉시 수정 (3회) → L1 다른 방법 (3회) → L2 codex 분석 → L3 다른 접근법 (3회) → L4 범위 축소 → L5 사용자 개입
- 각 레벨에서 예산만큼 시도 후 다음 레벨로 자동 에스컬레이트
- 레벨 전환 시 `record-error --reset-count`로 카운터 리셋
- 범위 축소는 핵심 경로(인증, CRUD 기본, 빌드) 제외

**원칙:** L5(사용자 개입) 전까지 스스로 해결

## 사용자 개입 시점 (최소화)

### 교착 상태 처리 (레벨별)

- **L2 도달 시**: codex에게 교착 상태 근본 원인 분석 요청

```bash
codex exec --skip-git-repo-check '## 교착 상태 근본 원인 분석

L0-L1 총 6회 시도 후 해결 실패.

### 지적 내용
[핵심 지적 요약]

### 기존 시도 (L0: 즉시 수정 3회 + L1: 다른 방법 3회)
[시도한 해결책들]

### 해결 안 되는 이유 추정
[왜 안 되는지]

### 요청
근본 원인을 분석하고 완전히 다른 접근법을 제시해달라.
'
```

- **L3-L4**: 자동 처리 (codex 분석 기반 다른 접근법 + 범위 축소)
- **L5 도달 시**: 사용자에게 개입 요청

### 사용자 개입 필요

- L5 에스컬레이션 도달 (L0~L4 모든 시도 소진)
- 외부 서비스 API 키 입력 필요
- 보안 관련 결정 (민감 정보 처리 방식)

**주의**: 권장사항 진행 여부는 묻지 않음 - 자동으로 구현

## 외부 서비스 설정 필요시

- API 키는 환경설정 등 중앙화 후 작업 완료 후 안내
- 환경설정 필요시 마찬가지로 완료 후 같이 안내
