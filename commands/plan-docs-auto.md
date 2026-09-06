---
description: "Planning doc refinement (auto-discussion). A reviewer (codex-cli, codex x2, or a fresh-context subagent) and Claude Code debate until no new Critical/High"
argument-hint: <definition(overview.md)> <doclist(README.md)>
---

# 기획 문서 완성 (자동 토론형)

정의 문서(헌법)를 기준으로 문서 리스트의 각 문서를 검토/작성합니다.
검토자(`--mode`에 따라 codex-cli, codex 2회, 또는 fresh-context 검토 서브에이전트)와 Claude Code가 **순차적으로 자동 토론**하여 신규 Critical/High가 0건인 라운드에서 합의합니다 (최소 라운드 수 없음).

## 인수

- 정의 문서 경로: $1
- README 경로: $2
- `--mode <solo|codex|dual>` (선택, 기본값: codex)

### --mode 옵션

| mode | 설명 | 참여자 |
| ---- | ---- | ------ |
| `codex` (기본) | Claude + codex-cli 2자 토론 | codex-cli가 피드백, Claude가 분석/반론/수정 |
| `solo` | fresh-context 검토 서브에이전트 | 외부 AI 불필요 (Agent 툴로 새 컨텍스트 검토자 호출) |
| `dual` | Claude + codex 1차 + codex 2차 3자 토론 | codex-cli 두 번의 독립 호출이 피드백, Claude가 종합/수정 |

### --mode 처리

$ARGUMENTS에서 `--mode` 값을 파싱합니다. 지정되지 않으면 `codex`로 동작합니다.

검토자 분기는 `skills/doc-planning/SKILL.md` Step 1-2의 `{REVIEW_MODE}` 분기를 그대로 쓴다 (이 파일에 프롬프트를 다시 적지 않는다):

- **`--mode codex`** (기본): Step 1-2 "2-A" — codex-cli 왕복.
- **`--mode solo`**: Step 1-2 "2-B" — Agent 툴로 호출한 **fresh-context 검토 서브에이전트**가 검토한다 (같은 컨텍스트의 역할극이 아님). 서브에이전트에는 `templates/doc-planning-common.md`와 대상 문서·정의 문서 경로만 넘기고 finding만 받는다. Agent 툴을 쓸 수 없을 때만 같은 기준의 자기검토로 폴백하고 `reviewFallback`을 기록한다.
- **`--mode dual`**: Step 1-2 "2-A"를 **서로의 결과를 참조하지 않는 codex 2회 독립 호출**로 수행하고, 두 결과를 합쳐 분석한다. 합의 기준은 양쪽 리뷰 모두 신규 Critical/High 0건인 라운드.

수렴 기준(신규 Critical/High 0건 라운드에서 즉시 합의, 최소 라운드 없음)과 라운드 상한(codex/dual 5, solo 3)은 모드와 무관하게 스킬 Step 1-2 "토론 규칙"을 따른다.

## 0단계: Ralph Loop 자동 설정 (최우선 실행)

`Read ${CLAUDE_PLUGIN_ROOT}/templates/ralph-loop-setup.md`를 읽고, 아래 파라미터로 치환하여 공통 절차(규칙 로드→인수 파싱→복구 감지→init→init-ralph→완료 조건/Iteration 규칙)를 수행합니다.

| 파라미터 | 값 |
|----------|-----|
| PROMISE_TAG | `ALL_DOCS_REVIEWED` |
| PROGRESS_FILE | `.claude-plan-progress.json` |
| INIT_TEMPLATE | (없음) — progress 파일은 2단계에서 `shared-gate.sh init --template plan`으로 생성 |
| MAX_ITERATIONS | (기본값) |
| EXTRA_INIT | (없음) |

### 인수 파싱

- 정의 문서 경로: $1
- README 경로: $2
- `--mode <solo|codex|dual>` 파싱 (위 "--mode 처리" 참조, 기본값: codex)

### 복구 시 재개 규칙 / 추가 복구 절차

아래 "복구 감지 상세"를 따릅니다 (definitionDoc/readmePath 일치 확인, 파일이 없으면 README와 실제 파일 비교 복구 시도).

### 추가 완료 조건

`<promise>ALL_DOCS_REVIEWED</promise>` 출력 전 다음 게이트를 **직전에 실행**하여 모두 통과해야 합니다 (3단계 종료 후 게이트 섹션 참조):

- `spec-completeness` exit 0 — PASS 시 dod `user_story`/`data_model`/`api_contract`/`error_scenarios` 자동 기록
- `definition-conflict` exit 0 — PASS 시 dod `no_definition_conflict` 자동 기록
- `clarification-gate` exit 0 — `[NEEDS-CLARIFICATION]` 잔존 0건
- `doc-consistency` 이슈 0건

dod 5키가 모두 `checked: true`가 되는 유일한 경로는 위 게이트 실행입니다 (모델 직접 세팅 금지).

### Iteration 단위

- 한 iteration에서 **1~2개 문서**만 처리

## 진행 상태 파일 (`.claude-plan-progress.json`)

프로젝트 루트에 진행 상태 파일을 생성/관리하여 중단 시 복구 지원:

```json
{
  "project": "프로젝트명",
  "created": "2025-01-03T10:00:00Z",
  "status": "in_progress",
  "definitionDoc": "정의문서경로",
  "readmePath": "README경로",
  "documents": [
    {"name": "문서1.md", "status": "pending"},
    {"name": "문서2.md", "status": "completed"},
    {"name": "문서3.md", "status": "in_progress", "round": 2}
  ],
  "currentDocument": "문서3.md",
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {
    "user_story": { "checked": false, "evidence": null },
    "data_model": { "checked": false, "evidence": null },
    "api_contract": { "checked": false, "evidence": null },
    "error_scenarios": { "checked": false, "evidence": null },
    "no_definition_conflict": { "checked": false, "evidence": null }
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

**dod 5키의 기록 주체 (게이트 자동 기록 — 모델 직접 세팅 금지):**

| dod 키 | 기록 주체 |
|--------|----------|
| `user_story` / `data_model` / `api_contract` / `error_scenarios` | `shared-gate.sh spec-completeness` PASS 시 자동 기록 |
| `no_definition_conflict` | `shared-gate.sh definition-conflict` PASS 시 자동 기록 |

**상태 전이:**

- `pending` -> `in_progress`: 해당 문서 토론 시작 시
- `in_progress` -> `completed`: 검토자와 합의 완료 시 (스킬 Step 1-2 수렴 기준)

**파일 저장 시점:**

| 시점 | 업데이트 내용 |
| ---- | -------------- |
| 스킬 시작 | 파일 생성 또는 읽기 |
| 문서 시작 | status -> `in_progress` |
| 토론 라운드 완료 | round 값 업데이트 |
| `/compact` 실행 | turnCount, lastCompactAt |
| 문서 완료 | status -> `completed` |
| Iteration 종료 전 | `handoff` 필드 업데이트 |

## 복구 감지 상세 (0단계에서 사용)

> 공통 분기(파일 존재/없음)는 ralph-loop-setup.md를 따르되, 이 명령은 아래 고유 규칙을 추가로 적용합니다.

**파일이 존재하는 경우 (재시작) — 추가 확인:**

1. `definitionDoc`, `readmePath` 확인 (인수와 일치해야 함)
2. `in_progress` 상태인 문서 찾기 -> 해당 문서부터 재개
3. `in_progress`가 없으면 첫 번째 `pending` 문서부터 재개
4. 모든 문서가 `completed`면 -> 4단계(완료 보고)로 이동

**파일이 없는 경우 (파일 비교 복구 시도):**

> 이전에 실패한 작업도 복구 가능하도록 README와 실제 파일을 비교

1. README($2)에서 문서 목록 추출
2. 각 문서 파일이 실제로 존재하는지 확인 (Glob 사용)
3. **파일 비교 결과:**
   - 파일이 존재하고 내용이 있음 -> `completed`로 간주
   - 파일이 없거나 비어있음 -> `pending`으로 간주
4. `pending` 문서가 있으면:
   - AskUserQuestion으로 "이전 작업을 이어서 진행할까요?" 확인
   - "예" -> `.claude-plan-progress.json` 생성 후 첫 `pending` 문서부터 재개
   - "아니오" -> 새로 시작 (1단계부터)
5. 모든 문서가 `completed`면:
   - "모든 문서가 이미 작성되어 있습니다" 안내 후 종료

### DoD 로드

DoD의 단일 출처는 progress 파일(`.claude-plan-progress.json`)의 `dod` 체크리스트다 (별도 `DONE.md`는 사용하지 않음 — 어떤 게이트도 읽지 않는다).
내장 기획 문서 DoD(유저스토리/데이터모델/API계약/에러시나리오/정의문서충돌없음)는 `shared-gate.sh init --template plan`이 생성하며,
프로젝트 고유 기준이 필요하면 `add-dod-key <key> "<설명>"`으로 추가한다.

**완전 새로 시작:**

- 위 비교에서 모든 문서가 `pending`이고 사용자가 "새로 시작" 선택 시
- 1단계부터 정상 진행

## 1단계: 맥락 파악 (doc-planning 스킬 로드)

이 명령의 문서 토론 절차는 full-auto Phase 1과 같은 doc-planning 스킬을 **단일 출처**로 쓴다. 절차·프롬프트·체크리스트를 이 파일에 다시 적지 않는다:

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/doc-planning/SKILL.md
```

**치환 규칙** (스킬은 full-auto 오케스트레이터 기준으로 쓰여 있다):

| 스킬의 표기 | 이 명령에서의 값 |
|-------------|------------------|
| `{PROGRESS_FILE}` | `.claude-plan-progress.json` |
| `{REVIEW_MODE}` | `--mode` 값 (`codex`·`solo`·`dual` — `teams`는 이 명령에 없음) |
| `phases.phase_1.documents` | 최상위 `documents` 배열 ("진행 상태 파일" 섹션의 구조) |
| 정의 문서 / overview.md | `$1` |

**적용 범위**: 이 명령은 스킬의 다음 부분만 수행한다.
- Step 1-0의 "overview.md 구조 검증" 소절 (필수 섹션 5종, 누락 시 1회 자동 보완 + 경고 — 하드 실패 아님)
- Step 1-2 자동 토론 루프 전체 (검토자 분기 2-A/2-B, 토론 프로세스, 토론 규칙, 라운드 상한, 템플릿 lazy-load 규칙, `doc-planning-common.md`의 기획 수준 원칙·문서 품질 체크리스트·검토 기준·피드백 우선순위)
- Step 1-4 복구 시 토론 재개

수행하지 않는 부분: Step 1-0의 표준 문서 3종·DESIGN.md 복사(`projectScope`/`projectSize`가 이 progress 파일에 없다), Step 1-1(문서 등록은 2단계가 담당), Step 1-3(아래 "Iteration 단위"가 대체), Step 1-5~1-10(Phase 1 게이트·아키텍처 리뷰·검증 스크립트·인수 테스트 동결·test-strategist). 이 명령의 완료 게이트는 "3단계 종료 후" 4종뿐이다 — SPEC.md를 다룰 때 provenance 마커는 스킬 규칙대로 기록하되, `provenance-gate`는 이 명령에 없고 `/plan-docs-full`이 검증한다.

정의 문서($1)를 읽고 프로젝트의 핵심 원칙·경계·책임을 파악한다. 이 문서가 "헌법"으로서 모든 하위 문서의 기준임을 인지하고, 이어서 스킬 Step 1-0의 "overview.md 구조 검증"을 적용한다 (기존 프로젝트가 PM Planning 없이 직접 이 명령을 실행해도 호환되도록 자동 보완만 한다).

## 2단계: 문서 목록 파악

README($2)에서:

- 작성할 문서 목록 추출
- 각 문서의 현재 상태 (완료/미작성) 확인
- AskUserQuestion으로 작업할 문서 범위 질문 (새로 시작할 때만)

**진행 상태 파일 생성** (새로 시작하는 경우) — 직접 JSON을 작성하지 않고 `init --template plan`을 사용합니다:

```bash
# 1. plan 템플릿으로 progress 파일 생성 (dod 5키 포함 — "진행 상태 파일" 섹션의 구조와 동일)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template plan \
  "<프로젝트명 (README에서 추출)>" "" --progress-file .claude-plan-progress.json

# 2. 인수/문서 목록 반영 (definitionDoc, readmePath, documents)
_tmp=$(mktemp)
jq --arg def "$1" --arg readme "$2" \
  '.definitionDoc = $def | .readmePath = $readme
   | .documents = [
       {"name": "선택된문서1.md", "status": "pending"},
       {"name": "선택된문서2.md", "status": "pending"}
     ]' .claude-plan-progress.json > "$_tmp" && mv "$_tmp" .claude-plan-progress.json
```

템플릿이 생성하는 dod 5키(`user_story`/`data_model`/`api_contract`/`error_scenarios`/`no_definition_conflict`)는
**spec-completeness · definition-conflict 게이트가 PASS 시 자동 기록**합니다 (위 "dod 5키의 기록 주체" 표 참조).
`"dod": {}`처럼 빈 dod로 파일을 직접 만들거나, 모델이 jq로 dod를 직접 세팅하지 않습니다.

**복구 시**: 이 단계는 건너뛰고 `.claude-plan-progress.json`에서 문서 목록 사용

## 3단계: 자동 토론 루프 (스킬 Step 1-2 수행)

선택된 모든 문서에 대해 순차적으로 `skills/doc-planning/SKILL.md` **Step 1-2**를 1단계의 치환 규칙으로 수행한다. 검토자만 `{REVIEW_MODE}`로 갈리고(2-A: codex/dual, 2-B: solo), 나머지는 스킬과 동일하다:

- 토론 프로세스 8단계 (문서 시작 → 검토 요청 → 비판적 분석/반론 → 수렴 판단 → 체크리스트 → 확정(+ 새 아키텍처 결정은 `docs/adr/`) → 완료 처리 + `/compact` → 다음 문서)
- 수렴 기준: 신규 Critical/High 0건 라운드에서 합의, 최소 라운드 없음, Medium/Low 반영은 재검토 대상이 아님
- 검토자 제외 규칙(동일 피드백 3회 / 근거 없는 approve 3회), 라운드 상한(codex/dual 5, solo 3)과 상한 도달 후 Critical 잔존 시 AskUserQuestion
- 표준 템플릿 문서 1라운드 상한 — 단, 이 명령은 템플릿 복사를 하지 않으므로 파일명이 아니라 **내용이 실제 템플릿 사본(placeholder 잔존)일 때만** 적용한다. 사용자가 직접 쓴 `docs/error-policy.md`·`docs/DESIGN.md` 등은 일반 문서로 토론한다
- 문서 품질 체크리스트·검토 기준·피드백 우선순위: `templates/doc-planning-common.md` (Step 1-2 진입 시 1회 Read, 미충족 항목이 있으면 합의 불가)

이 명령 고유 사항:

- 문서 상태 전이는 최상위 `documents` 배열에 기록한다 (`currentDocument`, 해당 문서의 `status`, `round`; 완료 시 `round` 삭제)
- 복구로 `in_progress` 문서부터 재시작할 때는 스킬 Step 1-4를 따른다 — 이전 토론 내용은 없으므로 맥락은 파일로만 복구한다

### Handoff (Iteration 종료 전 필수)

> `shared-rules.md`의 Handoff 업데이트 규칙을 따릅니다. progress 파일: `.claude-plan-progress.json`

## 컨텍스트 관리

> `shared-rules.md`의 컨텍스트 관리 + 외부 AI 자체 탐색 규칙을 따릅니다.

### 3단계 종료 후: 완료 게이트 실행 (promise 발행 전 필수)

모든 문서 토론 완료 후, 아래 게이트를 **순차 실행**합니다. 하나라도 실패하면 해당 이슈를 수정하고 재실행합니다.

```bash
# 1. 문서 일관성 검사 (이슈 0건이어야 통과)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/
# 발견된 구조적 불일치(모델 용어, API 엔드포인트, 네이밍 혼용, 상호참조 깨짐 등)를 Claude가 수정

# 2. 스펙 완전성 (PASS 시 dod user_story/data_model/api_contract/error_scenarios 자동 기록)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh spec-completeness \
  --progress-file .claude-plan-progress.json

# 3. 정의 문서 충돌 탐지 (PASS 시 dod no_definition_conflict 자동 기록)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh definition-conflict docs/ \
  --progress-file .claude-plan-progress.json

# 4. [NEEDS-CLARIFICATION] 태그 잔존 게이트
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate docs/
```

dod 5키는 위 게이트의 PASS로만 `checked: true`가 됩니다. 게이트를 실행하지 않으면 dod가 영원히 미충족 상태로 남아 완주할 수 없습니다 (데드락 방지).

## 4단계: 전체 완료 후 보고

모든 문서 작업 완료 시 **간결하게** 보고:

- 문서별 한 줄 요약 (생성/수정 여부 + 주요 변경점)
- 전체 토론 상세 내용은 포함하지 않음
- README 상태 업데이트

**Ralph Loop 완료:** 모든 조건 충족 시 `<promise>ALL_DOCS_REVIEWED</promise>` 출력

## 사용자 개입 시점 (이 시점에만 AskUserQuestion 허용)

**허용된 질문 시점:**
- 처음 실행 시 작업할 문서 범위 선택 (복구 시에는 생략)
- 토론이 교착 상태일 때 — 검토자가 제외됐거나, 라운드 상한(codex/dual 5, solo 3) 도달 후 Critical 잔존 (스킬 Step 1-2 토론 규칙)

**금지된 질문 (절대 하지 않음):**
- "다음 문서로 진행할까요?"
- "이 문서 작업을 시작할까요?"
- "계속 진행해도 될까요?"
- 기타 확인성 질문

## 강제 규칙

> `shared-rules.md`의 공통 강제 규칙을 따릅니다.

**plan-docs-auto 추가 규칙:**
- 라운드 상한·검토자 제외 후 처리는 스킬 Step 1-2 토론 규칙을 따른다 — 상한을 이유로 Critical을 미해결로 넘기지 않는다
- 검토자 제외 시 → Claude Code가 `doc-planning-common.md` 체크리스트 기준으로 단독 결정하고 마무리
- **원칙:** 문서 목록이 비워질 때까지 멈추지 않음
