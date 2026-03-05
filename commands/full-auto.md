---
description: "기획→구현→검수 올인원. 한 줄 요구사항으로 기획 문서→코드 구현→코드 리뷰→최종 검증까지 자동 완주"
argument-hint: <요구사항 (자연어)>
---

# Full Auto: 기획→구현→검수 올인원

한 줄 요구사항으로 **기획 문서 작성 → 코드 구현 → 코드 리뷰 → 최종 검증**까지 자동 완주합니다.

**역할 분담**: Claude = PM + 구현자, Codex = 기획 토론 + 코드 리뷰
**핵심 원칙**: Phase 0에서만 사용자 질문, 이후 완전 자동 | MVP 금지, 릴리즈 수준 | 스크립트로 토큰 절약

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "커뮤니티 사이트를 만들어줘")

## 5-Phase 워크플로우

```
Phase 0: PM Planning ─── 사용자 승인 (유일한 상호작용)
    ↓
Phase 1: Planning ───── codex 토론으로 기획 문서 완성
    ↓ [일관성 검사 #1: doc↔doc]
Phase 2: Implementation ── Claude 직접 구현 + TDD
    ↓ [일관성 검사 #2: doc↔code]
Phase 3: Code Review ──── codex 리뷰 + Claude 수정
    ↓ [일관성 검사 #3: code quality]
Phase 4: Verification ─── 최종 검증 + 폴리싱
    ↓
<promise>FULL_AUTO_COMPLETE</promise>
```

## Ralph Loop 자동 설정 (최우선 실행)

스킬 시작 시 스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "FULL_AUTO_COMPLETE" ".claude-full-auto-progress.json"
```

### Ralph Loop 완료 조건

`<promise>FULL_AUTO_COMPLETE</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-full-auto-progress.json`의 모든 steps status가 `completed`
2. `.claude-full-auto-progress.json`의 `dod` 체크리스트가 모두 checked
3. `.claude-verification.json`의 모든 검증 항목 exitCode가 0
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 한 iteration에서 **한 Phase의 일부 작업**만 처리
- Phase 0/1: 1~2개 문서 처리
- Phase 2: 1~2개 문서 또는 3~5개 티켓
- Phase 3: 1 리뷰 라운드
- Phase 4: 두 그룹으로 분할 가능 — Group A(Step 4-1~4-6.5 기존 검증), Group B(Step 4-6.7 디자인 폴리싱 + 4-6.6 커밋 + 4-7 DoD 최종)
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 토큰 절약 스크립트 활용

반복적/기계적 작업은 `shared-gate.sh`로 대체하여 토큰을 절약합니다.

```bash
# Progress 초기화
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "프로젝트명" "요구사항" --progress-file .claude-full-auto-progress.json

# 현재 상태 확인 (JSON 파싱 토큰 절약)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status --progress-file .claude-full-auto-progress.json

# Phase 전이
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 completed --progress-file .claude-full-auto-progress.json

# 품질 게이트 일괄 실행 (4개 명령어 → 1개)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json

# 문서 간 일관성 검사
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/ --progress-file .claude-full-auto-progress.json

# 문서↔코드 일관성 검사
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/ --progress-file .claude-full-auto-progress.json

# E2E 테스트 실행 (프레임워크 자동 감지)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json

# 시크릿 스캔 (HARD_FAIL)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan --progress-file .claude-full-auto-progress.json

# 빌드 아티팩트 검증 (SOFT_FAIL)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file .claude-full-auto-progress.json

# 서버 기동 + 헬스체크 (SOFT_FAIL)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check --progress-file .claude-full-auto-progress.json

# 에러 기록 (레벨별 에스컬레이션)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error --file <f> --type <t> --msg <m> --level L1 --action "시도한 행동" --progress-file .claude-full-auto-progress.json
```

**원칙**: 스크립트 = 구조적/기계적 검사, AI = 의미적 판단. 스크립트로 먼저 거르고, AI는 스크립트가 못 잡는 의미적 문제만 처리.

## 복구 감지 (0단계 전 실행)

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 `.claude-full-auto-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**
1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 → 이전 iteration 맥락 복구
3. `handoff.currentPhase`로 현재 Phase 확인
4. 해당 Phase의 진행 상태에 따라 재개
5. 모든 steps가 `completed`면 → Phase 4(최종 검증)로 이동

**파일이 없는 경우 (신규):**
- Phase 0부터 정상 시작

---

## Phase 0: PM Planning

**입력**: `$ARGUMENTS` (자연어, 예: "커뮤니티 사이트를 만들어줘")
**출력**: `docs/overview.md`, `docs/README.md`, Round별 문서 스켈레톤
**사용자 상호작용**: 이 Phase에서만 AskUserQuestion 허용

### Step 0-1: 요구사항 확장 (Claude PM)

`$ARGUMENTS`를 기반으로:

1. **"당연히 있어야 할 기능" 도출**
   - 명시되지 않았지만 사용자가 기대하는 기능 목록 작성
   - 예: "커뮤니티 사이트" → 회원가입/로그인, 게시글 CRUD, 댓글, 좋아요, 검색, 알림...

2. **기술 스택 결정**
   - 요구사항에 적합한 기술 스택 선택
   - 프론트엔드, 백엔드, DB, 인프라 각각 결정

3. **Non-Goals 정의**
   - 범위 밖 기능을 명시적으로 제외
   - "이것은 만들지 않는다" 목록

4. **Round 기반 의존성 그룹 설계**
   ```
   Round 1: DB 스키마, 인증 (의존성 없음)
   Round 2: 게시글, 사용자 프로필 (인증 의존)
   Round 3: 댓글, 좋아요 (게시글 의존)
   Round 4: 알림, 검색 (전체 의존)
   ```

### Step 0-1.5: 디자인 원칙 수립

요구사항에서 서비스 유형을 추론하고, design-polish 플러그인의 지식 기반을 활용하여 디자인 원칙을 수립합니다.

**DESIGN_POLISH_ROOT 감지:**
```bash
for dp in ~/.claude/plugins/marketplaces/design-polish \
          ~/.claude/plugins/design-polish; do
  [[ -f "$dp/scripts/search.cjs" ]] && DESIGN_POLISH_ROOT="$dp" && break
done
```

**design-polish 미설치 시**: 기본 디자인 원칙만 수립 (WCAG AA 준수, 44px 터치 타겟, 4.5:1 대비)

**design-polish 설치 시:**
1. `$ARGUMENTS`의 키워드로 서비스 유형 추론
2. industry-rules.md Read → 해당 서비스 유형의 추천 스타일/색상/타이포 추출
3. BM25 검색 3회 (style, color, typography)
4. 결과를 `docs/overview.md`의 "디자인 원칙" 섹션으로 포함

**docs/overview.md에 추가되는 섹션:**
- 서비스 유형 + 추천 디자인 스타일
- 색상 팔레트 (HEX 코드)
- 타이포그래피 (폰트명 + Google Fonts URL)
- 접근성 기준 (WCAG AA)
- 컴포넌트 가이드라인 핵심 요약 (Button/Card/Input Do/Don't)

### Step 0-2: Codex 검토

확장된 요구사항을 codex에게 전달하여 검토:

```bash
codex exec --skip-git-repo-check '## 역할
당신은 시니어 프로젝트 매니저입니다.
아래 프로젝트 계획을 비판적으로 검토하세요.

## 원본 요구사항
[사용자 원문]

## 확장된 계획
[Claude PM이 작성한 기능 목록 + 기술 스택 + Non-Goals + Round 구조]

## 검토 관점
1. 누락된 필수 기능이 있는가?
2. 과도한 범위(scope creep)가 있는가?
3. 기술 스택에 리스크가 있는가?
4. Round 의존성이 올바른가?
5. Non-Goals가 적절한가?

## 출력
피드백을 Critical/High/Medium/Low로 분류하여 제시하세요.'
```

### Step 0-3: 피드백 반영 + 문서 생성

Codex 피드백을 분석하여:

1. 타당한 피드백 반영 (Critical/High 우선)
2. `docs/overview.md` 생성:
   - 프로젝트 개요
   - 핵심 원칙
   - 기술 스택
   - 기능 목록 (Round별)
   - Non-Goals
   - 데이터 모델 개요
3. `docs/README.md` 생성:
   - 문서 목록 (Round별 그룹)
   - 각 문서의 간략 설명
   - 의존성 관계

### Step 0-4: 사용자 승인 (유일한 상호작용)

AskUserQuestion으로 계획 승인/수정 요청:

- 기술 스택 요약
- 기능 범위 요약 (Round별)
- Non-Goals 요약
- 예상 문서 수

**승인 시**: Phase 0 완료 → Phase 1로 진행
**수정 요청 시**: 피드백 반영 후 재승인 요청

### Step 0-5: Progress 초기화

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "프로젝트명" "원본 요구사항" --progress-file .claude-full-auto-progress.json
```

이후 progress 파일에 Phase 0 outputs를 jq로 기록:
- `phases.phase_0.outputs.definitionDoc`: `docs/overview.md`
- `phases.phase_0.outputs.readmePath`: `docs/README.md`
- `phases.phase_0.outputs.techStack`: 기술 스택 요약
- `phases.phase_0.outputs.rounds`: Round 구조

DoD 업데이트:
```json
"dod.pm_approved": { "checked": true, "evidence": "사용자 승인 완료 at [시간]" }
```

Phase 전이:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_0 completed --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 in_progress --progress-file .claude-full-auto-progress.json
```

---

## Phase 1: Planning (기획 문서 완성)

**입력**: Phase 0의 `docs/overview.md`, `docs/README.md`
**출력**: 완성된 기획 문서들
**패턴**: `plan-docs-auto.md`의 2자 토론 (codex + Claude)

### Step 1-0: 문서 목록 등록

`docs/README.md`에서 작성할 문서 목록을 추출하고 progress 파일에 등록:

```bash
# jq로 documents 배열 설정 (예시)
jq '.phases.phase_1.documents = [
  {"name": "auth.md", "status": "pending"},
  {"name": "post.md", "status": "pending"}
]' .claude-full-auto-progress.json > tmp.json && mv tmp.json .claude-full-auto-progress.json
```

Phase 2에도 동일한 문서 목록을 `phases.phase_2.documents`에 등록합니다.

### Step 1-1: 문서 작성 (Claude)

Round 순서대로 문서 작성:

1. `docs/README.md`에서 다음 문서 선택
2. `docs/overview.md`를 참조하여 문서 작성
3. **릴리즈 수준 완성도** (MVP 금지):
   - 에러 핸들링 모든 경로 정의
   - 인증/인가 요구사항 명시
   - 입력 유효성 검증 규칙
   - 백엔드 API는 테스트 시나리오 포함

### Step 1-2: Codex 피드백 (자체 탐색)

```bash
codex exec --skip-git-repo-check '## 역할
당신은 기획 문서 품질 검토 전문가입니다.
아래 파일들을 직접 읽고 검토하세요.

## 검토 대상
- 정의 문서 (헌법): [docs/overview.md 경로] — 직접 읽고 핵심 원칙과 Non-Goals를 파악하세요
- 검토할 문서: [문서 경로] — 직접 읽고 정의 문서 기준으로 검토하세요

## 검토 기준
1. 정의 문서 원칙과 충돌 여부
2. Non-Goals 침범 여부
3. 다른 문서와의 일관성
4. 릴리즈 수준 완성도 (에러 처리, 인증, 유효성 검증 포함)
5. 백엔드 API는 테스트 시나리오 존재 여부

## 출력
피드백을 Critical/High/Medium/Low로 분류하여 제시하세요.
"수정 없음"이면 NO_CHANGES_NEEDED와 함께 검토 근거를 명시하세요.'
```

### Step 1-3: 피드백 분석 + 문서 수정 (Claude)

각 피드백의 타당성 검토:
- Critical/High: 즉시 반영
- Medium: 판단하여 반영 또는 근거와 함께 기각
- Low: 필요시 반영

### Step 1-4: 반복

합의까지 반복 (최대 5라운드):
- Codex가 "NO_CHANGES_NEEDED" + 근거 명시 → 합의
- 5라운드 초과 → Critical/High만 처리하고 마무리

**Iteration 단위**: 1~2개 문서/iteration

### Step 1-5: 구조적 일관성 검사 (스크립트)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/ --progress-file .claude-full-auto-progress.json
```

스크립트가 발견한 구조적 불일치를 Claude가 수정.

### Step 1-6: 의미적 일관성 검토 (Codex)

```bash
codex exec --skip-git-repo-check '## 역할
당신은 기획 문서 일관성 검토 전문가입니다.

## 검토 대상
docs/ 디렉토리의 모든 문서를 직접 읽고 교차 검증하세요.

## 검토 관점
1. 문서 간 데이터 모델 일관성
2. API 엔드포인트 간 충돌/중복
3. 용어/명명 규칙 통일성
4. 의존성 관계의 논리적 정합성

## 출력
불일치 항목을 구체적으로 (파일명 + 섹션) 지적하세요.
모든 일관성 확인 시 CONSISTENT와 함께 검증 근거를 명시하세요.'
```

### Phase 1 완료 조건

- 모든 문서 토론 합의 완료
- `doc-consistency` 스크립트 + Codex 의미적 검토 통과
- progress 파일의 `consistencyChecks.doc_vs_doc` 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 completed --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 in_progress --progress-file .claude-full-auto-progress.json
```

DoD 업데이트:
```json
"dod.all_docs_complete": { "checked": true, "evidence": "모든 기획 문서 완성 + 일관성 검사 통과" }
```

---

## Phase 2: Implementation (코드 구현)

**입력**: 완성된 기획 문서들
**출력**: 작동하는 코드 + 테스트 통과
**패턴**: `implement-docs-auto.md`의 구현 루프

### Step 2-1: SPEC.md 자동 생성 (Claude)

기획 문서들에서 추출하여 SPEC.md 생성:
1. 유저스토리 추출
2. 데이터 모델 정리
3. API 계약 정리
4. 제약 조건 명시

### Step 2-2: SPEC 정합성 리뷰 (Codex)

```bash
codex exec --skip-git-repo-check '## SPEC 정합성 검토
SPEC.md와 docs/ 디렉토리의 기획 문서들을 직접 읽고 비교하세요.

## 검토 대상
- SPEC.md: [경로]
- 기획 문서 디렉토리: docs/

## 검토 관점
1. SPEC에 기획 문서의 모든 요구사항이 반영되었는가?
2. SPEC과 기획 문서 간 모순이 없는가?
3. 누락된 데이터 모델/API/제약 조건이 있는가?

## 출력
불일치 항목을 구체적으로 지적하세요.
모두 일치하면 SPEC_CONSISTENT와 근거를 명시하세요.'
```

### Step 2-3: 프로젝트 스캐폴딩 + 초기 커밋 (Claude)

1. 디렉토리 구조 생성
2. 설정 파일 구성 (package.json, tsconfig, .env.example 등)
3. 기본 의존성 설치
4. `docs/overview.md`의 "디자인 원칙" 섹션을 참조하여 전역 스타일 변수/Tailwind config/글로벌 CSS에 색상 팔레트, 폰트, 기본 spacing scale(4/8/12/16/24/32px) 설정
5. 초기 커밋: `git commit -am "[auto] 프로젝트 스캐폴딩 완료"`

progress 파일의 `phases.phase_2.context`에 아키텍처 맥락 저장:
```json
"context": {
  "architecture": "기술 스택 + 핵심 결정",
  "patterns": "설계 패턴"
}
```

### Step 2-4: Round 순서대로 구현 (Claude)

각 문서에 대해:

1. **문서 읽기 → 티켓 분할**
   - DB/스키마 변경 → 별도 티켓
   - API 엔드포인트별 → 별도 티켓
   - 프론트엔드 페이지/컴포넌트별 → 별도 티켓

2. **Claude가 직접 코드 작성**
   - **백엔드**: TDD (테스트 먼저 → 최소 구현 → 리팩토링)
   - **프론트엔드**: 일반 구현 (타입 체크 기본)

3. **에러 복구 (레벨별 에스컬레이션)**

   에러 레벨 분류 (`shared-rules.md` 참조):
   | 레벨 | 분류 | 예시 |
   |------|------|------|
   | L0 | environment | 패키지 미설치, PATH, 권한 |
   | L1 | build | 컴파일 에러, 번들 실패 |
   | L2 | type | 타입 불일치, 인터페이스 누락 |
   | L3 | runtime | 테스트 실패, 런타임 에러 |
   | L4 | quality | 린트, 코드 스타일, 경고 |
   | L5 | escalation | 모든 레벨 소진, 사용자 개입 필요 |

   - **L0: 즉시 수정** (3회): 같은 방법 내 수정 (import, 타입, 간단한 로직)
   - **L1: 다른 방법** (3회): 같은 설계, 다른 구현 (라이브러리 교체, 패턴 변경)
   - **L2: codex 분석** (1회): codex-cli 근본 원인 분석 + `git stash` 안전 지점
   - **L3: 완전히 다른 접근법** (3회): 설계/아키텍처 수준 전환 (codex 분석 기반)
   - **L4: 범위 축소** (1회): 최소 동작 버전 + `scopeReductions` 기록
   - **L5: 사용자 개입**: 선택지 제시

   레벨 전환 시 `record-error --reset-count`로 카운터 리셋.
   에러 레벨 추적: `record-error --level L0-L4`로 진행/회귀 판별.

   record-error exit code:
   - `0`: 현재 레벨 예산 내 → 계속 시도
   - `1`: 현재 레벨 예산 소진 → 다음 레벨로 에스컬레이트
   - `2`: L2 도달 → codex 분석 필요
   - `3`: L5 도달 → 사용자 개입 필요

### E2E 테스트 작성

구현과 함께 E2E 테스트를 작성합니다. 핵심 사용자 플로우만 커버합니다 (모든 엣지 케이스 불필요).

**프레임워크 선택 (프로젝트 유형별 자동):**
- Web (package.json): Playwright → `npm init playwright@latest` 로 설정
- Flutter (pubspec.yaml): `integration_test/` 디렉토리에 Flutter integration test 작성
- Mobile (React Native 등): Maestro → `.maestro/` 디렉토리에 YAML 플로우 작성

**작성 원칙:**
- 핵심 사용자 시나리오 3-5개만 (가입→로그인→핵심기능→결과확인 등)
- 헤드리스 실행 가능해야 함 (GUI 의존 금지)
- 테스트 데이터는 테스트 내에서 셋업/클린업

### Step 2-5: 품질 게이트 (스크립트)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

실패 시 Claude가 수정 → 재실행.

### Step 2-6: Codex 코드 리뷰 (자체 탐색)

```bash
codex exec --skip-git-repo-check '## 코드 리뷰
아래 파일들을 직접 읽고 리뷰하세요.

## 리뷰 대상
[구현된 파일 경로 목록]

## 원본 기획 문서
[기획 문서 경로]

## 리뷰 관점
1. 기획 문서 대비 누락된 기능
2. 보안 취약점 (인증/인가, 입력 검증)
3. 에러 처리 누락
4. 데이터 일관성 (트랜잭션, race condition)
5. 코드 품질 (패턴 일관성, 타입 안전성)

## 출력
{CATEGORY}-{SEVERITY}-{번호}: {제목} 형식으로 출력하세요.
finding 없으면 NO_FINDINGS.'
```

리뷰 피드백 처리:
- Critical/High: 즉시 수정
- Medium/Low: 판단하여 수용 또는 사유와 함께 deferred
- 수정 후 quality-gate 재실행

### Step 2-7: 반복

모든 문서 구현 완료까지 자동 진행.

**Iteration 단위**: 1~2개 문서 또는 3~5개 티켓/iteration

문서 완료 시:
- progress 파일의 해당 문서 `status` → `completed`
- `documentSummaries`에 핵심 결정 요약 추가
- 자동 커밋: `git commit -am "[auto] {문서명} 구현 완료"`

### Phase 2 완료 조건

- 모든 문서 구현 완료
- 품질 게이트 통과
- `doc-code-check` + Codex 의미적 검토 통과

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/ --progress-file .claude-full-auto-progress.json
```

```bash
codex exec --skip-git-repo-check '## 문서↔코드 일관성 검토
docs/ 디렉토리의 기획 문서와 실제 구현 코드를 비교하세요.

## 검토 대상
- 기획 문서: docs/
- SPEC.md: SPEC.md
- 소스 코드: src/ (또는 프로젝트 소스 디렉토리)

## 검토 관점
1. 기획 문서의 모든 기능이 구현되었는가?
2. API 엔드포인트가 문서와 일치하는가?
3. 데이터 모델이 문서와 일치하는가?
4. 테스트 케이스가 문서의 시나리오를 커버하는가?

## 출력
불일치 항목을 구체적으로 (문서 섹션 + 코드 파일) 지적하세요.
모두 일치하면 DOC_CODE_CONSISTENT와 근거를 명시하세요.'
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 completed --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 in_progress --progress-file .claude-full-auto-progress.json
```

DoD 업데이트:
```json
"dod.all_code_implemented": { "checked": true, "evidence": "모든 문서 구현 + doc-code 일관성 검사 통과" }
```

---

## Phase 3: Code Review

**입력**: 구현된 코드
**출력**: CRITICAL/HIGH 0개 달성된 코드
**패턴**: `code-review-loop.md` (codex만, 2자 구조)

### Step 3-1: Codex 전체 코드 리뷰 (자체 탐색)

```bash
codex exec --skip-git-repo-check '## 역할
당신은 시니어 코드 리뷰어입니다. 통합 관점에서 전체 코드를 리뷰하세요.
프로젝트의 소스 코드를 직접 탐색하여 리뷰하세요.

## 전문 리뷰 관점
1. **Security (SEC)**: 인증/인가 누락, 입력 검증, 민감 정보 노출, injection
2. **Error Handling (ERR)**: try-catch 누락, 에러 응답 불일치, 에지 케이스
3. **Data Consistency (DATA)**: 트랜잭션 누락, 스키마 불일치, race condition
4. **Performance (PERF)**: N+1 쿼리, 불필요한 DB 호출, 메모리 누수
5. **Code Quality (CODE)**: 컨벤션 위반, 패턴 불일치, 미사용 코드

## 심각도
- CRITICAL: 보안 취약점, 데이터 손실
- HIGH: 주요 버그, 에러 처리 누락
- MEDIUM: 잠재적 문제
- LOW: 사소한 개선

## 출력 형식
### {CATEGORY}-{SEVERITY}-{번호}: {제목}
- 파일: {경로}
- 라인: {줄번호}
- 설명: {문제 상세}
- 권장: {수정안}

finding 없으면 NO_FINDINGS. 마지막 줄: FINDING_COUNT: N'
```

### Step 3-2: Finding 검증 + 수정 (Claude)

각 finding에 대해:

1. **Read 도구로 해당 파일의 해당 라인 직접 읽기**
2. **판정**:
   - **Confirmed**: 실제 문제. severity 조정 가능.
   - **Dismissed**: false positive → 기각 사유 기록
3. **Confirmed CRITICAL/HIGH 자동 수정**: Edit 도구로 코드 수정
4. **MEDIUM/LOW**: deferred (기록만)

### Step 3-3: 품질 게이트 (스크립트)

수정 후 빌드/테스트 확인:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

### Step 3-3.5: 수정 사항 커밋

품질 게이트 통과 후, 이번 라운드의 수정 사항을 커밋합니다.

**커밋 조건**: Step 3-2에서 실제로 코드를 수정한 경우에만 (수정 없으면 생략)

```bash
git commit -am "[auto] Phase 3 코드 리뷰 Round {currentRound} 수정 완료"
```

### Step 3-4: 반복

3라운드 또는 CRITICAL/HIGH 0개 달성까지 반복.

각 라운드 결과를 progress 파일의 `phases.phase_3`에 기록:
```json
{
  "round": 1,
  "findings": { "total": 12, "confirmed": 10, "dismissed": 2 },
  "fixes": { "attempted": 4, "succeeded": 4 },
  "openCriticalHigh": 0
}
```

### Phase 3 완료 조건

- 3라운드 수행 또는 CRITICAL/HIGH open finding 0개
- 품질 게이트 통과

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 completed --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 in_progress --progress-file .claude-full-auto-progress.json
```

DoD 업데이트:
```json
"dod.code_review_pass": { "checked": true, "evidence": "N라운드 리뷰 완료, CRITICAL/HIGH: 0" }
```

---

## Phase 4: Verification & Polish

**입력**: 리뷰 완료된 코드
**출력**: 릴리즈 가능한 프로젝트

### Step 4-1: 최종 품질 게이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

### Step 4-2: E2E 테스트 검증

1. 기존 E2E 테스트 점검 (Phase 2에서 작성한 테스트를 최종 코드 기준으로 보완):
   - Phase 2에서 작성한 E2E 테스트를 실행하여 현재 상태 확인
   - 코드 리뷰(Phase 3)로 변경된 코드에 맞춰 테스트 업데이트
   - 누락된 핵심 시나리오가 있으면 추가
   - 실패하는 테스트가 있으면 원인 분석 후 수정

2. E2E 실행:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json
```

3. 프레임워크 미감지 시(exit 2): Phase 2에서 E2E를 작성하지 못한 경우. 이 시점에서 Phase 2의 "E2E 테스트 작성" 지침에 따라 프레임워크 설정 + 테스트 작성 후 재실행.

### Step 4-2.5: 시크릿 스캔 (자동화)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh secret-scan --progress-file .claude-full-auto-progress.json
```

**HARD_FAIL**: 시크릿 발견 시 즉시 제거/환경변수 이동 후 재스캔.
이 게이트를 통과해야 Step 4-3(codex 보안 스캔)으로 진행.

### Step 4-3: 보안 스캔 (Codex)

```bash
codex exec --skip-git-repo-check '## 보안 스캔
프로젝트의 소스 코드와 설정 파일을 직접 탐색하여 보안 검토하세요.

## 검토 관점
1. 하드코딩된 시크릿 (API 키, 비밀번호, 토큰)
2. .env 파일이 .gitignore에 포함되어 있는지
3. 민감 정보가 로그에 출력되는지
4. SQL injection, XSS, CSRF 등 OWASP Top 10
5. 의존성 취약점 (outdated packages)

## 출력
보안 이슈를 Critical/High/Medium/Low로 분류하세요.
이슈 없으면 SECURITY_CLEAR와 근거를 명시하세요.'
```

보안 이슈 발견 시 Claude가 즉시 수정.

### Step 4-4: 문서화 확인 (Claude)

1. **README 완성도**
   - 프로젝트 설명, 설치 방법, 실행 방법
   - 환경 변수 설명
   - API 문서 (해당시)

2. **환경 설정**
   - `.env.example` 존재 확인
   - 필수 환경 변수 목록

3. 부족한 부분 보완

### Step 4-5: 코드 정리 (Claude)

1. 디버그 코드 제거 (console.log, print 등)
2. 주석 처리된 코드 정리
3. 미사용 import 제거
4. 불필요한 파일 정리

### Step 4-6: 최종 품질 게이트 + verification.json 기록

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

### Step 4-6.5: 아티팩트 + 스모크 검증

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh artifact-check --progress-file .claude-full-auto-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh smoke-check --progress-file .claude-full-auto-progress.json
```

artifact-check 실패(SOFT_FAIL) 시 빌드 재실행.
smoke-check 실패(SOFT_FAIL) 시 서버 시작 스크립트 확인 후 재시도.
서버리스/라이브러리 프로젝트(package.json의 main/exports만 있고 start 스크립트 없음, 또는 serverless.yml/vercel.json 존재)는 스킵 허용.

### Step 4-6.7: 디자인 폴리싱 (SOFT_FAIL)

구현된 프로젝트의 디자인 품질을 검증하고 개선합니다.

**DESIGN_POLISH_ROOT 감지:** (Step 0-1.5과 동일)
미설치 시 → DoD `design_quality`에 "SKIP: design-polish not installed" 기록 후 건너뜀.

1. **WCAG 자동 체크 + 스크린샷 캡처**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh design-polish-gate --progress-file .claude-full-auto-progress.json
   ```
   - exit 2 (SKIP) → 이 스텝 전체 건너뜀
   - exit 0/1 → 계속 진행

2. **WCAG 리포트 확인**
   ```
   Read(".design-polish/accessibility/wcag-report.json")
   ```

3. **디자인 지식 로딩**
   ```
   Read("${DESIGN_POLISH_ROOT}/knowledge/industry-rules.md")
   Read("${DESIGN_POLISH_ROOT}/knowledge/component-checklist.md")
   Read("${DESIGN_POLISH_ROOT}/knowledge/ux-rules.md")
   ```

4. **서비스 유형 기반 BM25 검색** (3회)

5. **스크린샷 시각 분석** (메인 페이지 1장만 — 토큰 절약)
   ```
   Read(".design-polish/screenshots/current-main.png")
   ```

6. **Gap 분석**: 지식 기반 + WCAG 리포트 + 스크린샷 대조 → P1-P8 개선안 도출
   - 트렌드 검색(WebSearch) 생략 — 토큰 절약 + 외부 의존성 제거
   - 레퍼런스 캡처 생략

7. **P1-P4 자동 적용**
   - 적용 전 `git stash` (안전 지점)
   - Edit 도구로 코드 수정 (P1 접근성 → P2 인터랙션 → P3 성능 → P4 레이아웃)
   - 적용 후 품질 게이트 재실행
   - 빌드 실패 시 `git stash pop`으로 롤백

8. **결과 기록**
   - progress `phases.phase_4.designPolish`에 결과 기록
   - DoD `design_quality` checked + evidence

**에러 처리**: 전체 SOFT_FAIL. 디자인 폴리싱 실패해도 Step 4-6.6으로 진행.

### Step 4-6.6: 폴리싱 결과 커밋

모든 검증과 수정이 완료된 코드를 커밋합니다.

```bash
git commit -am "[auto] 최종 검증 및 폴리싱 완료"
```

### Step 4-7: DoD 최종 확인 + 완료 보고

모든 DoD 항목 최종 확인:
```json
{
  "pm_approved": { "checked": true },
  "all_docs_complete": { "checked": true },
  "all_code_implemented": { "checked": true },
  "build_pass": { "checked": true },
  "test_pass": { "checked": true },
  "code_review_pass": { "checked": true },
  "security_review": { "checked": true },
  "secret_scan": { "checked": true },
  "e2e_pass": { "checked": true },
  "design_quality": { "checked": true }
}
```

**완료 보고 형식:**

```
## Full Auto 완료 보고

### 프로젝트
- 요구사항: [원본]
- 기술 스택: [스택]

### Phase 결과
| Phase | 결과 |
|-------|------|
| PM Planning | 기능 N개, Round M개 |
| Planning | 문서 N개 완성, 일관성 검사 통과 |
| Implementation | 파일 N개 생성, 테스트 M개 |
| Code Review | N라운드, CRITICAL/HIGH 0개 |
| Verification | 빌드/테스트/보안 통과, WCAG N건 수정 |

### 주요 결정사항
[핵심 결정 목록]

### 환경 설정 안내
[필요한 외부 서비스 설정 등]
```

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 completed --progress-file .claude-full-auto-progress.json
```

모든 steps completed + DoD 전체 checked + verification 통과 확인 후:

`<promise>FULL_AUTO_COMPLETE</promise>`

---

## 진행 상태 파일 (`.claude-full-auto-progress.json`)

```json
{
  "project": "프로젝트명",
  "userRequirement": "원문 보존",
  "status": "in_progress",
  "currentPhase": "phase_0",
  "steps": [
    {"name": "phase_0", "label": "PM Planning", "status": "in_progress"},
    {"name": "phase_1", "label": "Planning", "status": "pending"},
    {"name": "phase_2", "label": "Implementation", "status": "pending"},
    {"name": "phase_3", "label": "Code Review", "status": "pending"},
    {"name": "phase_4", "label": "Verification", "status": "pending"}
  ],
  "phases": {
    "phase_0": { "outputs": { "definitionDoc": null, "readmePath": null, "techStack": null, "rounds": [] } },
    "phase_1": { "documents": [], "currentDocument": null },
    "phase_2": { "documents": [], "currentDocument": null, "errorHistory": {}, "completedFiles": [], "context": {}, "documentSummaries": {}, "scopeReductions": [] },
    "phase_3": { "currentRound": 0, "roundResults": [], "findingHistory": [] },
    "phase_4": { "verificationSteps": [], "designPolish": null }
  },
  "consistencyChecks": {
    "doc_vs_doc": { "checked": false, "evidence": null },
    "doc_vs_code": { "checked": false, "evidence": null },
    "code_quality": { "checked": false, "evidence": null }
  },
  "dod": {
    "pm_approved": { "checked": false, "evidence": null },
    "all_docs_complete": { "checked": false, "evidence": null },
    "all_code_implemented": { "checked": false, "evidence": null },
    "build_pass": { "checked": false, "evidence": null },
    "test_pass": { "checked": false, "evidence": null },
    "code_review_pass": { "checked": false, "evidence": null },
    "security_review": { "checked": false, "evidence": null },
    "secret_scan": { "checked": false, "evidence": null },
    "e2e_pass": { "checked": false, "evidence": null },
    "design_quality": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "currentPhase": "phase_0",
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
```

**stop-hook 호환**: `steps` 배열 + `dod` 필드가 기존 hook의 검증 로직과 동일 구조.

---

## Handoff (Iteration 종료 전 필수)

세션을 종료하기 전에 `.claude-full-auto-progress.json`의 `handoff` 필드를 반드시 업데이트합니다:

```json
"handoff": {
  "lastIteration": 3,
  "currentPhase": "phase_2",
  "completedInThisIteration": "Phase 2: auth.md, user-profile.md 구현 완료",
  "nextSteps": "Phase 2: post.md 구현 시작. auth 모듈의 UserRepository 재사용",
  "keyDecisions": [
    "JWT + refresh token 방식 확정",
    "Repository 패턴 + Service 레이어 분리"
  ],
  "warnings": "rate limiting 미구현 - Phase 2 마지막 문서에서 처리 예정"
}
```

**Iteration 시작 시 handoff 읽기:**
1. `.claude-full-auto-progress.json` 로드
2. `handoff.currentPhase`로 현재 Phase 확인
3. `handoff.nextSteps`를 최우선으로 확인 → 여기서 시작
4. `handoff.keyDecisions`로 이전 결정 맥락 복구
5. `handoff.warnings`로 주의사항 인지

---

## 컨텍스트 관리 (Prompt Too Long 방지)

### 압축 트리거

| 조건 | 트리거 |
|------|--------|
| 단일 Phase 내 작업 | 12턴 이상 → `/compact` |
| "prompt too long" 에러 | 즉시 `/compact` |
| Phase 전환 시 | `/compact` |
| 문서 완료 후 | 다음 문서 시작 전 `/compact` |

### 작업 중 메모리 관리

- 각 문서/Phase 작업 완료 시 해당 내용은 요약으로만 기억
- 이전 문서의 전체 코드/토론을 누적하지 않음
- 현재 작업에만 집중, 필요시 다른 파일은 다시 읽기
- `documentSummaries`로 완료된 문서의 핵심 결정만 참조

### 외부 AI 호출 시

- codex에게 파일 경로를 전달하여 직접 읽도록 함
- Claude가 문서 내용을 요약/가공하여 프롬프트에 embed하지 않음 (요약 편향 방지)
- 이전 토론 내용은 결론만 요약해서 전달

---

## 사용자 개입 시점 (최소화)

**허용된 질문 시점 (Phase 0에서만):**
- 프로젝트 계획 승인/수정

**예외적 허용:**
- L5 에스컬레이션 도달 시 (모든 레벨 소진)
- 외부 서비스 API 키 입력 필요 시

**금지된 질문 (절대 하지 않음):**
- "다음 Phase로 진행할까요?"
- "이 문서 작업을 시작할까요?"
- "계속 진행해도 될까요?"
- 기타 확인성 질문

---

## 강제 규칙 (절대 위반 금지)

1. **자동 진행**: Phase 간, 문서 간 사용자 확인 없이 자동 진행. 문서/Phase 완료 시 다음으로 자동 전환.
2. **단일 in_progress**: 동시에 하나의 문서만 `in_progress` 상태
3. **완료 전 진행 금지**: `in_progress` 작업이 `completed` 되기 전 다음 작업 시작 금지
4. **스킵 금지**: 어떤 이유로도 `pending` 작업을 건너뛰지 않음
5. **중간 종료 금지**: 모든 Phase가 `completed` 될 때까지 종료하지 않음
6. **상태 파일 동기화**: 상태 변경 시 반드시 progress 파일 업데이트
7. **질문 금지**: Phase 0과 예외 상황 외에는 AskUserQuestion 절대 사용 금지
8. **자체 탐색**: codex에게 파일 경로를 전달하여 직접 읽도록 함. Claude가 내용을 요약하여 embed하지 않음.
9. **handoff 필수**: 매 iteration 종료 시 handoff 필드 업데이트
10. **스크립트 우선**: 구조적/기계적 검사는 `shared-gate.sh`로 먼저 실행. AI는 의미적 판단만.

## 포기 방지 규칙 (강제)

**절대 금지:**
- "이 문제는 해결할 수 없습니다"
- "사용자가 직접 확인해주세요"
- 모든 Phase 완료 전 종료
- 진행 중인 작업을 포기하고 다음으로 넘어가기

**강제 행동 (레벨별 에스컬레이션):**
- L0 즉시 수정 (3회) → L1 다른 방법 (3회) → L2 codex 분석 → L3 다른 접근법 (3회) → L4 범위 축소 → L5 사용자 개입
- 각 레벨에서 예산만큼 시도 후 다음 레벨로 자동 에스컬레이트
- 레벨 전환 시 `record-error --reset-count`로 카운터 리셋
- 범위 축소는 핵심 경로(인증, CRUD 기본, 빌드) 제외
- 컨텍스트 부족 → `/compact` 실행 후 계속 진행
- 모든 Phase 완료까지 계속 진행

**원칙:** L5(사용자 개입) 전까지 스스로 해결. 모든 Phase가 완료될 때까지 멈추지 않음.
