---
description: "Pre-release polish (solo multi-perspective). Claude acts as both executor and verifier without external AI"
argument-hint: [definition(overview.md)] [doclist(README.md)]
---

# 프로덕션 릴리즈 폴리싱 (Solo 다관점 검증)

프로젝트를 프로덕션 릴리즈 준비 상태로 만듭니다.
Claude Code가 **실행자 + 검증자 이중 역할**을 수행하며, 모든 검증 통과할 때까지 반복합니다.

**핵심 원칙**: 문제 발견 시 즉시 수정. 사용자에게 "진행할래?" 묻지 않음.

## 역할 분담

**Claude Code 이중 역할**:
- **[실행자]**: 분석 + 코드 수정/작성 (실제 작업 수행)
- **[검증자]**: 비판적 시각으로 수정 결과 검토 + 누락/부작용 확인

> 각 스텝에서 실행자가 작업 완료 후, 검증자 관점으로 전환하여 자체 검증.
> 검증자가 이슈 발견 시 실행자로 돌아가서 수정. 이슈 없을 때까지 반복.

## 인수

- (옵션) 정의 문서 경로: $1
- (옵션) README 경로: $2

**프로젝트 루트**: 현재 작업 디렉토리 사용

**기획 문서 조건**:

- $1만 제공: 정의 문서 기준으로 전체 검토
- $2만 제공: 문서 목록 기준으로 기능 완성도 검토
- 둘 다 제공: 완전한 기획 대비 검토
- 없음: 기술적 품질만 검증

## Ralph Loop 자동 설정 (최우선 실행)

스킬 시작 시 스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "RELEASE_READY" ".claude-polish-progress.json"
```

### Ralph Loop 완료 조건

`<promise>RELEASE_READY</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-polish-progress.json`의 모든 단계 status가 `completed`
2. `.claude-verification.json`의 모든 검증 항목 exitCode가 0
3. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙 (단계 그룹화)

8단계를 4개 iteration 그룹으로 분리:
- **Group 1**: 프로젝트 분석 + 기획 대비 검토
- **Group 2**: 빌드 검증 + 테스트 검증
- **Group 3**: 보안 검토 + 문서화 확인
- **Group 4**: 릴리즈 체크리스트 + 최종 검증

각 그룹이 한 iteration에서 처리되도록 구조화.
Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작.

## 진행 상태 파일 (`.claude-polish-progress.json`)

프로젝트 루트에 진행 상태 파일을 생성/관리하여 중단 시 복구 지원:

```json
{
  "project": "프로젝트명",
  "created": "2025-01-03T10:00:00Z",
  "status": "in_progress",
  "definitionDoc": "정의문서경로 (옵션)",
  "readmePath": "README경로 (옵션)",
  "steps": [
    {"name": "프로젝트 분석", "status": "completed", "group": 1, "evidence": {}},
    {"name": "기획 대비 검토", "status": "in_progress", "group": 1, "round": 2, "evidence": {}},
    {"name": "빌드 검증", "status": "pending", "group": 2, "evidence": {}},
    {"name": "테스트 검증", "status": "pending", "group": 2, "evidence": {}},
    {"name": "보안 검토", "status": "pending", "group": 3, "evidence": {}},
    {"name": "문서화 확인", "status": "pending", "group": 3, "evidence": {}},
    {"name": "릴리즈 체크리스트", "status": "pending", "group": 4, "evidence": {}},
    {"name": "최종 검증", "status": "pending", "group": 4, "evidence": {}}
  ],
  "currentStep": "기획 대비 검토",
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {
    "build_pass": { "checked": false, "evidence": null },
    "test_pass": { "checked": false, "evidence": null },
    "e2e_pass": { "checked": false, "evidence": null },
    "security_review": { "checked": false, "evidence": null },
    "secret_scan": { "checked": false, "evidence": null },
    "docs_complete": { "checked": false, "evidence": null },
    "final_verification": { "checked": false, "evidence": null }
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

**각 단계 완료 시 dod 업데이트:**
- 3단계(빌드 검증) 완료 -> `dod.build_pass` checked + evidence
- 4단계(테스트 검증) 완료 -> `dod.test_pass` checked + evidence
- 4단계(테스트 검증) 완료 -> `dod.e2e_pass` checked + evidence
- 5단계(보안 검토) 완료 -> `dod.security_review` checked + evidence
- 5단계(보안 검토) 완료 -> `dod.secret_scan` checked + evidence
- 6단계(문서화 확인) 완료 -> `dod.docs_complete` checked + evidence
- 8단계(최종 검증) 완료 -> `dod.final_verification` checked + evidence

**상태 전이:**

- `pending` -> `in_progress`: 해당 단계 시작 시
- `in_progress` -> `completed`: 검증자 확인 통과 시

**파일 저장 시점:**

| 시점 | 업데이트 내용 |
| ---- | -------------- |
| 스킬 시작 | 파일 생성 또는 읽기 |
| 단계 시작 | status -> `in_progress` |
| 검증 라운드 완료 | round 값 업데이트 |
| `/compact` 실행 | turnCount, lastCompactAt |
| 단계 완료 | status -> `completed`, evidence 업데이트 |
| Iteration 종료 전 | `handoff` 필드 업데이트 |

## 0단계: 복구 감지

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 프로젝트 루트에서 `.claude-polish-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**

1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 -> 이전 iteration 맥락 복구
3. `definitionDoc`, `readmePath` 확인 (인수와 일치해야 함)
4. `in_progress` 상태인 단계 찾기 -> 해당 단계부터 재개
5. `in_progress`가 없으면 첫 번째 `pending` 단계부터 재개
6. 모든 단계가 `completed`면 -> 완료 보고로 이동

**파일이 없는 경우 (새로 시작):**

1. 1단계(프로젝트 분석)부터 정상 진행
2. 프로젝트 분석 완료 후 파일 생성

## 1단계: 프로젝트 분석

현재 작업 디렉토리를 분석하여:

- 언어/프레임워크 감지
- 빌드 시스템 확인 (package.json, go.mod, pubspec.yaml 등)
- 테스트 프레임워크 확인
- 린트/포맷 도구 확인
- **기획 문서 제공 여부 확인** ($1, $2)

분석 완료 후 `.claude-polish-progress.json` 파일 생성.

단계 완료 시 evidence 기록:
```json
"evidence": { "language": "TypeScript", "buildSystem": "npm", "testFramework": "jest" }
```

## 2단계: 기획 문서 대비 검토 (옵션)

**기획 문서가 제공된 경우에만 수행**

### 맥락 파악

정의 문서($1)가 있으면:

- 프로젝트의 핵심 원칙, 기술 스택, 아키텍처 파악
- 이 문서가 "헌법"으로서 모든 검토의 기준임을 인지

### 기능 완성도 확인

README($2)가 있으면 기획 문서 목록 추출 후:

1. 각 기획 문서별 구현 여부 체크
2. 누락된 기능 식별
3. 부분 구현된 기능 식별

### 이중 역할 검토

Claude가 이중 역할을 수행:

**[실행자 역할]**: 요구사항 충족 여부를 분석하고, 누락/미충족 항목을 식별하여 수정합니다.
**[검증자 역할로 전환]**: "이 수정으로 새로운 문제가 생기지 않는가? 빠뜨린 것은 없는가?" 체크합니다.
검증자가 추가 이슈를 발견하면 실행자로 돌아가서 수정합니다.

### 누락/미충족 발견 시

- **Claude Code가 직접 수정**
- 구현 완료까지 반복
- 구현 후 3~7단계 품질 검증 진행

### 정합성 검사 (스크립트)

구현 수정 완료 후 스크립트로 정합성을 검증합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/ --progress-file .claude-polish-progress.json
```

스크립트가 발견한 구조적 불일치를 Claude Code가 수정.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/ --progress-file .claude-polish-progress.json
```

문서<->코드 불일치 발견 시 Claude Code가 수정 후 재실행.

단계 완료 시 evidence 기록:
```json
"evidence": { "reviewRounds": 3, "issuesFound": 5, "issuesFixed": 5, "docConsistency": "pass", "docCodeCheck": "pass" }
```

## 3단계: 빌드 검증

### 검증 항목

1. **빌드 성공 확인**
   - 언어별 빌드 명령 실행
   - 에러 없이 완료 확인

2. **타입 체크 통과**
   - TypeScript: `tsc --noEmit`
   - Go: `go vet`
   - Dart: `dart analyze`

3. **린트/포맷 검사**
   - ESLint, Prettier, gofmt, dart format 등
   - 자동 수정 가능한 것은 **Claude Code가 수정**

### 문제 발견 시 이중 역할 검토

Claude가 이중 역할을 수행:

**[실행자 역할]**: 빌드/타입/린트 문제를 분석하고 수정합니다.
**[검증자 역할로 전환]**: "이 수정으로 새로운 문제가 생기지 않는가? 빠뜨린 것은 없는가?" 체크합니다.
검증자가 추가 이슈를 발견하면 실행자로 돌아가서 수정합니다.

### 검증 결과 기록

스크립트로 빌드/타입/린트/테스트를 일괄 실행하고 결과를 기록합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-polish-progress.json
```

스크립트가 자동으로 프로젝트 유형을 감지하고, 결과를 `.claude-verification.json`에 기록하며, progress 파일의 DoD를 업데이트합니다.

단계 완료 시 evidence 기록:
```json
"evidence": { "buildExitCode": 0, "typeCheckExitCode": 0, "lintExitCode": 0 }
```

## 4단계: 테스트 검증

### 검증 항목

1. **전체 테스트 통과**
   - 언어별 테스트 명령 실행
   - 실패 테스트 없음 확인

2. **커버리지 확인** (설정된 경우)
   - 최소 기준 충족 여부

### 문제 발견 시

- 실패 테스트 -> **Claude Code가 수정** 후 재실행
- 커버리지 부족 -> 검증자 관점에서 테스트 추가 여부 결정, **Claude Code가 작성**

### E2E 테스트 검증

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-polish-progress.json
```

프레임워크 미감지 시(exit 2): E2E 설정 + 테스트 작성 후 재실행.
실패 시 Claude Code가 원인 분석 및 수정 후 재실행.

### 검증 결과 기록

`.claude-verification.json`에 테스트 결과 추가:
```json
"test": { "command": "...", "exitCode": 0, "passed": 42, "failed": 0 }
```

단계 완료 시 evidence 기록:
```json
"evidence": { "testExitCode": 0, "passed": 42, "failed": 0, "e2eExitCode": 0 }
```

## 5단계: 보안 검토

### 시크릿 스캔 (자동화, 최우선)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan --progress-file .claude-polish-progress.json
```

**HARD_FAIL**: 시크릿 발견 시 즉시 제거/환경변수 이동 후 재스캔.
이 게이트를 통과해야 나머지 보안 검토로 진행.

### 검증 항목

1. **민감 정보 노출 확인**
   - .env 파일이 .gitignore에 포함되어 있는지
   - 하드코딩된 API 키, 비밀번호 없는지
   - 로그에 민감 정보 출력하지 않는지

2. **의존성 취약점 스캔**
   - `npm audit`, `go mod verify`, `pub outdated` 등
   - Critical/High 취약점 확인

### 이중 역할 보안 검토

Claude가 이중 역할을 수행:

**[실행자 역할]**: 보안 취약점을 분석하고 수정합니다.
**[검증자 역할로 전환]**: "이 수정으로 새로운 문제가 생기지 않는가? 빠뜨린 것은 없는가?" 체크합니다.
검증자가 추가 이슈를 발견하면 실행자로 돌아가서 수정합니다.

단계 완료 시 evidence 기록:
```json
"evidence": { "envInGitignore": true, "hardcodedSecrets": 0, "criticalVulnerabilities": 0, "secretScanExitCode": 0 }
```

## 6단계: 문서화 확인

### 검증 항목

1. **README 완성도**
   - 프로젝트 설명
   - 설치 방법
   - 실행 방법
   - 환경 변수 설명

2. **API 문서** (해당시)
   - 엔드포인트 문서화
   - 요청/응답 예시

3. **환경 설정 가이드**
   - .env.example 존재 여부
   - 필수 환경 변수 목록

### 누락 시

- 검증자 관점에서 필요한 내용 결정
- **Claude Code가 문서 작성**

단계 완료 시 evidence 기록:
```json
"evidence": { "readmeComplete": true, "envExampleExists": true }
```

## 7단계: 릴리즈 체크리스트

### 확인 항목

1. **버전 관리**
   - package.json, pubspec.yaml 등의 버전 확인
   - 시맨틱 버전 규칙 준수

2. **CHANGELOG** (있는 경우)
   - 최신 변경사항 반영 여부

3. **환경 변수 정리**
   - 사용하지 않는 환경 변수 제거
   - .env.example 최신화

4. **불필요한 파일 정리**
   - 디버그 코드 탐색: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh find-debug-code --progress-file .claude-polish-progress.json`
   - 발견된 디버그 코드 제거 (console.log, print 등)
   - 주석 처리된 코드 정리
   - 미사용 import 제거

### 이중 역할 정리 검토

Claude가 이중 역할을 수행:

**[실행자 역할]**: 릴리즈 체크리스트 항목을 검토하고 정리합니다.
**[검증자 역할로 전환]**: "이 수정으로 새로운 문제가 생기지 않는가? 빠뜨린 것은 없는가?" 체크합니다.
검증자가 추가 이슈를 발견하면 실행자로 돌아가서 수정합니다.

단계 완료 시 evidence 기록:
```json
"evidence": { "debugCodeRemoved": true, "unusedImportsRemoved": true, "changelogUpdated": true }
```

## 8단계: 최종 검증

모든 단계 완료 후 스크립트로 최종 검증:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-polish-progress.json
```

빌드 아티팩트 + 서버 헬스체크:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file .claude-polish-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check --progress-file .claude-polish-progress.json
```

artifact-check 실패(SOFT_FAIL) 시 빌드 재실행.
smoke-check 실패(SOFT_FAIL) 시 서버 시작 스크립트 확인 후 재시도.
서버리스/라이브러리 프로젝트(package.json의 main/exports만 있고 start 스크립트 없음, 또는 serverless.yml/vercel.json 존재)는 스킵 허용.

스크립트가 빌드/타입/린트/테스트를 재실행하고 결과를 `.claude-verification.json`에 기록합니다.

**증거 기반 완료 선언 (필수):**

- 빌드 성공 로그 (exit code 0 확인)
- 테스트 통과 로그 (PASSED 개수 확인)
- 린트 통과 로그
- `.claude-verification.json`에 기록 완료

**금지 (실행 없이 선언):**

- "아마 통과할 것입니다"
- "테스트가 성공할 것입니다"
- 이전 실행 결과 재사용

단계 완료 시 evidence 기록:
```json
"evidence": { "finalBuildExitCode": 0, "finalTestExitCode": 0, "finalLintExitCode": 0, "artifactCheckExitCode": 0, "smokeCheckExitCode": 0 }
```

### Handoff (Iteration 종료 전 필수)

> `shared-rules.md`의 Handoff 업데이트 규칙을 따릅니다. progress 파일: `.claude-polish-progress.json`

## 완료 보고

**완료 조건**: 모든 검증 통과 + 검증자 확인 완료 + `.claude-verification.json` 기록 완료

완료 시 **간결하게** 보고:

- 단계별 검증 결과 요약
- 수정된 파일 목록
- 발견된 문제 및 해결 방법 요약
- 릴리즈 준비 상태 확인
- 외부 서비스 설정 안내 (API 키 등)

**Ralph Loop 완료:** 모든 조건 충족 시 `<promise>RELEASE_READY</promise>` 출력

## 토론 규칙

**핵심 원칙: 비판적 시각**

- 검증자 역할에서는 이전 실행자 작업을 **비판적으로 검토**해야 함
- 단순 확인보다 반론/보완/대안 제시 우선
- "정말 필요한 수정인가?" 관점에서 과도한 수정 필터링

**단순 approve 금지**:

- "문제 없습니다" 같은 단순 승인은 유효하지 않음
- "수정 없음" 선언 시 반드시 **검토한 항목과 근거** 명시 필요

**합의 기준**:

- 검증자가 **근거 있는** "수정 없음" 선언
- 또는 5회 이상 검토 후 주요 쟁점 해결

## 피드백 우선순위

1. **Critical**: 보안 취약점, 치명적 버그, 정의 문서 충돌
2. **High**: 빌드/테스트 실패, 주요 기능 누락
3. **Medium**: 성능 개선, 코드 품질
4. **Low**: 형식, 스타일, 사소한 개선

## 컨텍스트 관리

> `shared-rules.md`의 컨텍스트 관리 규칙을 따릅니다.

## 사용자 개입 시점 (최소화)

### 교착 상태 처리

- **3회 반복**: 다른 접근 방식 시도
- **5회 반복**: 사용자에게 개입 요청

### 사용자 개입 필요

- 교착 상태 5회 반복
- 보안 관련 결정 (민감 정보 처리 방식)
- 버전 번호 결정

**주의**: 자동 수정 가능한 문제는 **Claude Code가 즉시 수정**. 사용자에게 묻지 않음.

## 강제 규칙

> `shared-rules.md`의 공통 강제 규칙 + 증거 기반 완료 선언 규칙을 따릅니다.

**polish 추가 규칙:**
- 막히면 -> 검증 라운드 추가
- 7라운드 초과 시 -> Critical/High 피드백만 처리하고 마무리
- **원칙:** 8단계(최종 검증)가 완료될 때까지 멈추지 않음

## 외부 서비스 설정 필요시

- API 키는 환경설정 등 중앙화 후 작업 완료 후 안내
- 환경설정 필요시 마찬가지로 완료 후 같이 안내
