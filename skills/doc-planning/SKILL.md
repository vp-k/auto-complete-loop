# Phase 1: Doc Planning

Loaded by the full-auto orchestrator at Phase 1 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

> `{PROGRESS_FILE}`은 오케스트레이터(full-auto.md / plan-docs-full.md의 "파라미터" 표)가 정한 값으로 치환한다
> (예: full-auto codex/solo: `.claude-full-auto-progress.json`, teams: `.claude-full-auto-teams-progress.json`,
> plan-docs-full: `.claude-plan-docs-full-progress.json`,
> `/plan-docs-auto`: `.claude-plan-progress.json` — 이 명령은 Step 1-0의 overview 검증 소절·Step 1-2·Step 1-4만 수행한다, 치환 규칙은 `commands/plan-docs-auto.md` 1단계).
>
> `{REVIEW_MODE}`도 같은 "파라미터" 표에서 치환한다 (`codex` | `solo` | `teams` | `dual`; `/plan-docs-auto`는 `--mode` 값).
> **이 스킬은 모든 모드의 단일 소스다** — 모드별 분기는 아래 두 곳(Step 1-2 토론 루프, Step 1-6 아키텍처 리뷰)뿐이고,
> 나머지 스텝(특히 Step 1-9의 게이트 5종)은 모드와 무관하게 동일하게 수행한다.

| {REVIEW_MODE} | Step 1-2 검토자 | Step 1-6 아키텍처 리뷰(Medium+) |
|---|---|---|
| `codex` (기본) | codex-cli 왕복 | roundtable 에이전트 |
| `dual` | codex-cli 2회 독립 호출 | roundtable 에이전트 |
| `teams` | codex-cli 왕복 | roundtable 에이전트 |
| `solo` | fresh-context 검토 서브에이전트 (Agent 툴) | architect 에이전트 |

## 전제 조건

- Phase 0 완료 (overview.md, README.md 존재)
- progress 파일에 Phase 0 outputs 기록 완료 (`/plan-docs-auto` 경유 시 면제 — 그 progress 파일에는 `phases.*`가 없고 Step 1-2/1-4만 적용한다)
- `shared-rules.md`가 이미 로드된 상태

## Phase 1 절차

### Step 1-0: 맥락 파악

1. overview.md (정의 문서) 읽기 — 프로젝트 핵심 원칙, 경계, 책임 파악
2. README.md에서 작성할 문서 목록 추출
3. 각 문서의 현재 상태 확인 (완료/미작성)
4. **백엔드 표준 문서 3종 생성** (`projectScope.hasBackend=true` **그리고** `projectSize`가 `Medium` 이상인 경우):
   - `docs/logging-standard.md` — 없으면 `${CLAUDE_PLUGIN_ROOT}/templates/logging-standard.md`를 docs/로 복사 후 문서 목록에 pending으로 추가
   - `docs/error-policy.md` — 없으면 동일 템플릿 복사 후 pending 등록
   - `docs/security-authn-authz.md` — 없으면 동일 템플릿 복사 후 pending 등록
   - 이 3개 문서는 Phase 1 완료 전 반드시 `completed` 상태여야 함 (이후 Step 1-9 검증에서 HARD_FAIL)
   - **규모 게이트 (Small은 생략)**: `projectSize=Small`이면 이 3종을 **복사도 검증도 하지 않는다** — 기능 5개 미만 프로젝트에 486줄 표준 문서 3종은 기획 대비 과부하이며, 로깅·에러·인증 정책은 SPEC.md의 해당 섹션에서 다룬다. 규모 분기의 단일 출처는 `rules/project-size-rules.md`.
   - 템플릿 복사 예시:
   ```bash
   project_size=$(jq -r '.phases.phase_0.outputs.projectSize // "Medium"' {PROGRESS_FILE} 2>/dev/null || echo "Medium")
   if [[ "$project_size" != "Small" ]]; then
     for t in logging-standard error-policy security-authn-authz; do
       [[ -f "docs/$t.md" ]] || cp "${CLAUDE_PLUGIN_ROOT}/templates/$t.md" "docs/$t.md"
     done
   else
     echo "SKIP: 백엔드 표준 문서 3종 생략 (projectSize=Small)"
   fi
   ```
   - **주의 (lazy-load)**: 이 시점에는 `cp`만 수행하고 템플릿 내용을 **Read하지 않는다**. 각 문서의 내용은 해당 문서를 토론하는 시점(Step 1-2)에 `docs/` 사본으로 읽는다 — Step 1-2의 "템플릿 로드 규칙" 참조.
5. **프론트엔드 필수 문서 검증** (`projectScope.hasFrontend=true`인 경우):
   - `docs/DESIGN.md` — 없으면 `${CLAUDE_PLUGIN_ROOT}/templates/DESIGN.md`를 docs/로 복사 후 문서 목록에 pending으로 추가
   - 이 문서는 **제품의 성격 계약**이다. SPEC.md가 기능을 정의한다면 DESIGN.md는 "어떤 인상을 주는가"를 정의하며, 구현 중 색·간격·모서리·폰트를 임의로 정하는 것을 막는다 (스펙 공백 시 임의 구현 금지 규칙의 디자인 버전).
   - 템플릿 복사:
   ```bash
   [[ -f "docs/DESIGN.md" ]] || cp "${CLAUDE_PLUGIN_ROOT}/templates/DESIGN.md" "docs/DESIGN.md"
   ```
   - 동일한 lazy-load 규칙 적용 — 여기서는 `cp`만 하고 내용은 해당 문서 토론 시점에 읽는다.
   - Phase 1 완료 전 `completed` 상태여야 하며, Step 1-9에서 존재를 검증한다.

#### overview.md 구조 검증 (PM Planning 산출물)

정의 문서에 다음 섹션이 존재하는지 검증:
- Problem Statement
- Target Users / 페르소나
- Core Jobs (JTBD)
- 핵심 가정 + 리스크
- 성공 기준

**누락 섹션 감지 시**: Claude가 1회 자동 보완 시도. 보완 후 경고 출력:
"overview.md에 [섹션명]이 누락되어 자동 보완했습니다. 확인해주세요."

자동 보완은 하드 실패가 아님 — 기존 프로젝트(PM Planning 없이 직접 실행) 호환성 유지.

### Step 1-1: 문서 목록 등록

progress 파일의 `phases.phase_1.documents`에 문서 목록 등록:
```json
[
  {"name": "auth.md", "status": "pending"},
  {"name": "user-profile.md", "status": "pending"}
]
```

### Step 1-2: 자동 토론 루프

선택된 모든 문서에 대해 순차적으로 토론을 수행합니다. **검토자만 `{REVIEW_MODE}`에 따라 달라지고, 나머지 절차·수렴 기준·체크리스트는 모든 모드가 동일합니다.**

#### 토론 프로세스

1. **문서 시작**
   - 문서 확인 (없으면 생성, 있으면 업데이트 대상)
   - progress 파일 업데이트: `currentDocument` 설정, 해당 문서 `status` -> `in_progress`

2. **검토 요청** — `{REVIEW_MODE}`에 따라 검토자를 선택한다 (아래 2-A / 2-B 중 하나만 실행)

   ##### 2-A. `{REVIEW_MODE}` = `codex` | `dual` | `teams` — codex-cli에게 피드백 요청

   ```bash
   codex exec --skip-git-repo-check '## 검토 대상
   - 정의 문서 (헌법): [overview.md 경로] — 직접 읽고 핵심 원칙과 Non-Goals를 파악하세요
   - 검토할 문서: [문서 경로] — 직접 읽고 정의 문서 기준으로 검토하세요

   ## 요청
   피드백을 Critical/High/Medium/Low 우선순위로 분류해서 제공해주세요.
   지적할 것이 없으면 그 판정의 근거(무엇을 확인했는지)를 항목별로 적어주세요.
   근거 없는 approve와 "전반적으로 좋다" 류의 총평은 반환하지 마세요.

   ## E2E 시나리오 관점
   SPEC.md 작성 시 핵심 E2E 시나리오 3-5개를 도출하세요.
   - 인증 플로우, CRUD 플로우, 네비게이션 플로우 우선
   - 각 시나리오에 관련 User Story ID를 매핑
   - 여러 문서에 걸치는 크로스커팅 시나리오를 명시적으로 표시
   '
   ```

   `dual`은 위 호출을 **서로의 결과를 참조하지 않는 2회 독립 호출**로 수행하고, 두 결과를 합쳐 3에서 분석한다.

   ##### 2-B. `{REVIEW_MODE}` = `solo` — fresh-context 검토 서브에이전트 호출

   외부 AI 없이도 **독립성**을 확보하기 위해, 같은 컨텍스트에서 역할을 바꾸는 대신 **Agent 툴로 새 컨텍스트의 검토 서브에이전트**를 호출한다. 검토자는 문서를 쓴 대화를 보지 못하므로, 작성 의도가 아니라 문서에 실제로 쓰인 것만으로 판정한다.

   - Agent 툴 `subagent_type`: `general-purpose` (또는 `Explore`), `description`: "기획 문서 검토"
   - 프롬프트에는 **파일 경로만** 넘기고 작성 과정·의도·이전 라운드의 변론을 넣지 않는다 (재검토 라운드에서는 "이전 라운드에서 지적된 항목" 목록만 사실로 첨부)
   - 프롬프트 본문:

   ```
   다음 파일들을 Read하여 기획 문서를 검토하고 finding을 반환하라.

   ## 검토 기준 (먼저 읽을 것)
   Read ${CLAUDE_PLUGIN_ROOT}/templates/doc-planning-common.md
   — 이 파일의 "기획 수준 원칙", "문서 품질 체크리스트", "검토 기준",
     "피드백 우선순위", "Provenance 마커 프로토콜"을 판정 기준으로 삼는다.

   ## 입력
   - 정의 문서(헌법): [overview.md 경로]
   - 검토 대상 문서: [문서 경로]
   위 두 파일 외의 파일은 교차 참조 확인이 필요한 경우에만 읽는다. 문서를 수정하지 마라.

   ## 판정 관점
   - 이 문서대로 프로덕션에 들어갔을 때 실패하는 시나리오는 무엇인가
   - 개발자가 추가 질문 없이 구현할 수 있는가 (데이터 모델/API 스키마 구체성)
   - 에러·예외·유효성·인증/인가·로깅 경로가 누락 없이 정의되어 있는가
   - overview.md의 핵심 원칙 및 Non-Goals와 모순되는가
   - 다른 문서와의 교차 참조가 일치하는가
   - (SPEC.md인 경우) 핵심 E2E 시나리오 3-5개가 도출되고 각 시나리오에
     User Story ID가 매핑되어 있는가, 크로스커팅 시나리오가 명시되어 있는가

   ## 출력 형식 (이것만 반환)
   각 finding을 한 줄씩:
   [CRITICAL|HIGH|MEDIUM|LOW] <파일>:<섹션> — <문제> / 근거: <문서에서 인용> / 제안: <구체적 수정>
   지적할 것이 없으면 그 판정의 근거(무엇을 확인했는지)를 항목별로 적는다.
   근거 없는 approve와 "전반적으로 좋다" 류의 총평은 반환하지 마라.
   ```

   **폴백 (Agent 툴 사용 불가 시에만)**: 같은 컨텍스트에서 위 "검토 기준 / 판정 관점 / 출력 형식"을 그대로 적용해 검토 finding을 먼저 목록으로 작성한 뒤, 그 목록만 근거로 문서를 수정한다. 자기 확인 편향을 의식적으로 경계하고, "수정 불필요" 선언 시 반드시 확인한 항목과 근거를 명시한다 (단순 approve 금지). 폴백을 사용한 경우 progress의 해당 문서 항목에 `"reviewFallback": "self-review"`를 기록한다.

3. **Claude Code가 검토 피드백 분석/반론**
   - 각 피드백의 타당성 검토
   - 수용할 피드백과 반론할 피드백 구분
   - 반론 시 근거와 대안 제시
   - 수용한 피드백으로 문서 수정

4. **수렴 판단 (라운드마다)** — 재검토 라운드는 기본 동작이 아니다:
   - 이번 라운드 피드백에 **신규 Critical/High가 0건**이면 → 수용한 Medium/Low만 반영하고 **합의 성립** (재검토 라운드 없이 5로 진행 — Medium/Low 반영은 재검토 대상이 아니다)
   - 신규 Critical/High가 있으면 → 수정 반영 후 같은 검토자(2-A 또는 2-B)에게 재검토 요청 → 2로 복귀. codex 모드는 이전 토론 요약을 포함하고, solo 모드는 fresh-context 유지를 위해 "이전 라운드에서 지적된 항목" 목록만 첨부한다
   - 각 라운드 완료 시 progress의 `round` 값 업데이트

5. **문서 품질 체크리스트 확인** (완료 처리 전 필수)

6. 합의된 내용으로 최종 문서 확정
   - 토론에서 **새 아키텍처 결정**(통신 방식, 저장 전략 변경 등)이 합의됐으면
     `docs/adr/NNN-<slug>.md`로 기록 (형식은 pm-planning Step 0-2 #6.5 참조 —
     ADR은 문서 충돌 시 최우선 순위로 참조됨)

7. **문서 완료 처리**
   - progress 업데이트: 해당 문서 `status` -> `completed`, `round` 삭제
   - `/compact` 실행 (다음 문서 시작 전 컨텍스트 정리)

8. 다음 문서로 자동 진행 (목록 끝까지 반복)

#### 토론 규칙

**핵심 원칙: 비판적 시각**
- 모든 참여자는 이전 피드백을 비판적으로 검토
- 단순 동의보다 반론/보완/대안 제시 우선
- "정말 필요한 수정인가?" 관점에서 과도한 피드백 필터링

**검토자 산출물**: 객관적 기준 기반 피드백, 우선순위별 분류, 구체적 개선안 (검토자가 codex든 서브에이전트든 동일)
**Claude Code 산출물**: 검토 피드백의 비판적 분석, 실제 필요한 수정만 선별, 최종 문서 수정

**단순 approve 금지** (모드 공통): "동의합니다", "문제 없습니다" 같은 근거 없는 승인은 유효한 검토가 아니다. "수정 없음" 선언은 **검토한 항목과 근거**를 항목별로 명시해야 유효하며(예: "정의 문서 원칙 X, Y 기준으로 검토 완료. 충돌 없음 확인."), 근거 없는 approve만 돌아온 라운드는 수렴 라운드로 계상하지 않고 근거를 요구해 재검토한다 — 수렴 기준이 "신규 Critical/High 0건 라운드에서 즉시 합의"이므로 이 규칙이 없으면 근거 없는 1회 approve가 문서를 확정시킨다.

**검토자 제외 규칙** (모드 공통):
- 동일 피드백 3회 반복 -> 해당 검토자 제외, Claude Code 단독 결정
- 근거 없는 approve 3회 -> 해당 검토자 제외, Claude Code 단독 결정

**합의 기준 (조기 종료 우선)**:
- 한 라운드에서 신규 Critical/High 0건 = 합의 성립. Medium/Low는 Claude가 타당성을 판단해 수용분만 반영하고 종료 — "수정 없음" 선언을 추가 라운드로 확인받지 않는다
- **최소 라운드 수는 없다**: 명확한 문서가 1라운드에 끝나는 것이 정상. 라운드 수를 채우기 위한 재검토 금지

**표준 템플릿 문서 상한 (1라운드)**: 템플릿에서 복사된 표준 문서(logging-standard.md, error-policy.md, security-authn-authz.md — Medium 이상에서만 존재, DESIGN.md — hasFrontend=true에서 존재)는 이미 검증된 구조에서 출발하므로 토론 상한 1라운드. 검토 범위는 "프로젝트 값이 실제로 채워졌는가(placeholder 잔존 여부), overview.md/SPEC.md와 모순이 없는가"로 한정한다. Critical/High가 나오면 수정 후 확인 재검토 1회만 추가 허용. 일반 기획 문서 수준의 반복 토론 금지.

**라운드 상한 + 에스컬레이션**: 상한은 `{REVIEW_MODE}`에 따른다 — `codex`/`dual`/`teams`는 5라운드, `solo`는 3라운드(서브에이전트 호출 비용 대비 수확 체감). 상한 도달 후에도 Critical 피드백이 잔존하는 경우:
- AskUserQuestion으로 사용자에게 잔여 Critical 이슈 목록 제시
- 사용자가 결정 (수용/거부/수정) 후 진행
- 상한을 이유로 Critical을 미해결로 넘기지 않는다

#### 기획 수준 원칙 / 문서 품질 체크리스트 / 검토 기준 / 피드백 우선순위

> 공통 기획 규칙은 아래 파일을 **Step 1-2 진입 시 1회만** Read하여 적용합니다.
> Read ${CLAUDE_PLUGIN_ROOT}/templates/doc-planning-common.md

기획 수준 원칙(MVP 금지, TDD, E2E), 문서 품질 체크리스트, 검토 기준, 피드백 우선순위 모두 위 템플릿을 따릅니다.

#### 템플릿 로드 규칙 (lazy-load — 컨텍스트 절약)

**템플릿을 미리 전부 Read하지 않는다.** 전 단계에 걸쳐 필요한 것은 `doc-planning-common.md` 하나뿐이며(위에서 1회 Read), 나머지 템플릿은 아래 매핑에 따라 **해당 산출물을 작성하는 시점에만** Read한다:

| 산출물 (읽는 시점) | 그때만 Read할 파일 |
|---|---|
| 모든 문서 공통 규칙 — Step 1-2 진입 시 1회 | `${CLAUDE_PLUGIN_ROOT}/templates/doc-planning-common.md` |
| SPEC.md — 작성 시작 시점 | `${CLAUDE_PLUGIN_ROOT}/templates/SPEC.md` (구조 스켈레톤) |
| 인수 테스트(tests/acceptance/) — Step 1-7.5 진입 시에만 | `${CLAUDE_PLUGIN_ROOT}/templates/acceptance-tests-guide.md` |
| docs/security-authn-authz.md — 해당 문서 토론 시 (Medium+) | Step 1-0에서 복사된 `docs/security-authn-authz.md` 사본 (원본 `templates/security-authn-authz.md` 중복 Read 금지; 복사 단계가 없는 `/plan-docs-auto`에서는 프로젝트의 해당 파일) |
| docs/error-policy.md — 해당 문서 토론 시 (Medium+) | `docs/error-policy.md` 사본 (원본 템플릿 중복 Read 금지) |
| docs/logging-standard.md — 해당 문서 토론 시 (Medium+) | `docs/logging-standard.md` 사본 (원본 템플릿 중복 Read 금지) |
| docs/DESIGN.md — 해당 문서 토론 시 (hasFrontend=true) | `docs/DESIGN.md` 사본 (원본 템플릿 중복 Read 금지) |
| 프로젝트 CLAUDE.md — Phase 0(pm-planning)에서 처리 | `templates/project-claude-md.md`는 **cp 전용**, Read 불필요 |

지금 작성 중인 문서와 무관한 템플릿은 읽지 않는다. 다음 문서로 넘어갈 때 그 문서에 필요한 템플릿을 그 시점에 Read한다.

**SPEC 작성 시 Provenance 마커 필수**: 핵심 섹션(Success Criteria, User Stories, Data Model,
API Contract, Constraints, Context)마다 헤딩 직후 첫 줄에 출처 마커 1개를 기록하며 작성한다 —
`user-fact`(요구/답변 근거) / `repo-fact:<실존 경로>`(레포 확인 — 게이트가 경로 실존을 검증) /
`assumption: <근거>`(안전 기본값) / `blocker`(사용자 결정 필요 → `[NEEDS-CLARIFICATION]` 전환).
unsafe 도메인(자격증명/결제/프로덕션 배포/파괴적 데이터 작업/개인정보) 포함 섹션은 assumption 금지.
판정 기준: doc-planning-common.md의 "Provenance 마커 프로토콜". Step 1-9의 `provenance-gate`가 HARD_FAIL로 검증한다.

### Step 1-3: Iteration 관리

- 한 iteration에서 1~2개 문서만 처리
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료
- Stop Hook이 다음 iteration 자동 시작

### Step 1-4: 복구 시 토론 재개

복구로 `in_progress` 문서부터 재시작:
1. 해당 문서 다시 읽기
2. 정의 문서 핵심 원칙 다시 로드
3. `round` 값이 있으면 해당 라운드부터, 없으면 처음부터 토론 시작

### Step 1-5: 문서 일관성 검사

모든 문서 토론 완료 후:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/
```

스크립트가 발견한 구조적 불일치를 Claude가 수정합니다.

### Step 1-6: 스펙 깊이 검증 + 아키텍처 리뷰

Phase 0의 API/모델/플로우 테이블이 Phase 1에서 충분히 상세화되었는지 검증합니다.

**규모 게이트 (Small은 아키텍처 리뷰 스킵 — 모드 공통)**: progress의 `projectSize`가 `Small`이면 아키텍처 리뷰 에이전트를 호출하지 않는다 — 아래 "Claude가 직접 수행하는 검증"만 실행하고, spec-completeness(Step 1-9)가 백스톱한다. 스킵 시 증거 기록:
```bash
_tmp=$(mktemp)
jq '.phases.phase_1.outputs.roundtableArchReview = {"verdict": "SKIPPED_SMALL", "reason": "projectSize=Small — 다관점 아키텍처 리뷰 생략, Claude 직접 검증 + spec-completeness로 대체"}' {PROGRESS_FILE} > "$_tmp" && mv "$_tmp" {PROGRESS_FILE}
```
> `{REVIEW_MODE}=solo`에서는 위 jq의 키를 `architectReview`로 바꿔 기록한다 (아래 6-B가 쓰는 키와 일치시키기 위함).

Medium/Large인 경우 `{REVIEW_MODE}`에 따라 6-A 또는 6-B 중 하나를 수행합니다.

#### 6-A. `{REVIEW_MODE}` = `codex` | `dual` | `teams` — Roundtable Agent

**Roundtable Agent**를 호출하여 다관점 아키텍처 리뷰를 수행합니다:
- Agent tool로 `roundtable` 에이전트 호출
- 컨텍스트: "Phase 1 Step 1-6 (Architecture Review)"
- overview.md + SPEC.md + docs/*.md 경로를 프롬프트에 포함
- projectScope 정보 (hasFrontend, hasBackend) 전달 → 조건부 페르소나 활성화

**라운드테이블 프로세스** (roundtable.md 참조):
1. Architect(리드), Senior Developer, QA Specialist, Devil's Advocate + 조건부 DBA/UI/UX가 독립 검토
2. 기술 스택 적합성, API 설계 일관성, 데이터 모델 무결성, NFR 커버리지, 테스트 가능성을 교차 검증
3. 충돌 지점에 대해 토론 (최대 3라운드)
4. 합의 결과: Roundtable Architecture Review Report

**블로킹 조건**:
- CRITICAL 항목 잔존 시 Phase 2 진행 차단
- Unresolved Conflicts → 사용자에게 결정 위임

결과를 progress 파일에 기록:
```bash
_tmp=$(mktemp)
jq '.phases.phase_1.outputs.roundtableArchReview = {
  "verdict": "PROCEED|REVISE|ESCALATE",
  "criticalCount": N,
  "consensusItems": [...],
  "unresolvedConflicts": [...]
}' {PROGRESS_FILE} > "$_tmp" && mv "$_tmp" {PROGRESS_FILE}
```

#### 6-B. `{REVIEW_MODE}` = `solo` — Architect Agent

외부 AI 없이 **Architect Agent**를 호출하여 아키텍처 리뷰를 수행합니다:
- Agent tool로 `architect` 에이전트 호출
- 기술 스택 적합성, 의존성 분석, API 설계 일관성, 데이터 모델, NFR 커버리지 검증
- overview.md + SPEC.md 경로를 프롬프트에 포함
- 결과: Architecture Review Report (ARCHITECTURE_SCORE 포함)
- ARCHITECTURE_SCORE < 5 또는 블로커 존재 시 Phase 2 진행 전 반드시 해결

결과를 progress 파일에 기록:
```bash
_tmp=$(mktemp)
jq '.phases.phase_1.outputs.architectReview = {
  "verdict": "PROCEED|REVISE|ESCALATE",
  "architectureScore": N,
  "blockers": [...]
}' {PROGRESS_FILE} > "$_tmp" && mv "$_tmp" {PROGRESS_FILE}
```

#### Claude가 직접 수행하는 검증 (모드·규모 공통 — 스킵 불가)

- **API 엔드포인트**: SPEC.md에 각 엔드포인트의 Request/Response 상세가 기술되어 있는지 확인 (단순 목록이 아닌 필드/타입/예시 수준)
- **User Story ID**: 모든 User Story에 `US-F-*` (프론트엔드) 또는 `US-B-*` (백엔드) 형식의 ID가 부여되었는지 확인
- **상세 부족 시 경고**: 검증 실패 항목은 경고를 출력하고, Claude가 1회 자동 보완 시도

### Step 1-7: 검증 스크립트 생성 (Phase 1 산출물)

Phase 1 완료 시 SPEC.md의 핵심 플로우를 기반으로 실행 가능한 검증 스크립트를 생성합니다:

- **hasBackend=true**: `tests/api-smoke.sh` 생성
  - SPEC.md의 핵심 플로우를 curl 명령으로 변환
  - 각 단계에서 응답의 필수 필드를 jq로 검증
  - exit 0 = 모든 플로우 통과, exit 1 = 실패
  - 서버 URL은 인수로 받음: `$BASE_URL` (기본값: http://localhost:3000)

- **hasFrontend=true**: `tests/ui-smoke.sh` 또는 `tests/ui-smoke.spec.ts` 생성
  - 핵심 1-2개 유저 플로우를 Playwright 또는 간단한 curl로 검증

- **library/CLI**: `tests/lib-smoke.sh` 생성
  - 주요 export/CLI 명령 호출 + 예상 출력 확인

US-* ID 필수화 규칙:
- SPEC.md의 모든 User Story에 US-F-001, US-B-001 형식 ID를 반드시 부여
- 이 ID가 테스트 커버리지 측정의 기준이 됨

### Step 1-7.5: 인수 테스트 생성 + 동결 (Acceptance Tests)

SPEC.md 완성 후, 기획 완료 전에 SPEC의 인수 조건(AC)으로부터 **실행 가능한** 인수 테스트를 생성하고 해시 동결합니다. 구현 Phase는 이 테스트를 수정할 수 없으며, 이 테스트를 green으로 만들어야만 완주됩니다.

1. **가이드 로드** (이 시점에만 — lazy-load 규칙 표 참조):
   ```
   Read ${CLAUDE_PLUGIN_ROOT}/templates/acceptance-tests-guide.md
   ```
2. **인수 테스트 생성**: SPEC.md의 **모든 US**(US-F-*/US-B-*)에 대해, AC 1개당 최소 1개 테스트 + `tests/acceptance/run.sh`(러너)를 가이드 준수하여 생성. 의사코드/placeholder 금지 — 어서션이 실제로 실행되는 테스트여야 함.
3. **동결 실행 — pass 확인**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh acceptance-freeze
   ```
   결과가 verification.json의 `acceptanceFreeze`에 기록됨 (pass 확인).
4. **red 상태가 정상**: 기획 시점에는 앱이 없으므로 테스트는 red — 그것이 정상 (TDD red→green). 동결 전 `bash tests/acceptance/run.sh`를 1회 실행하여 **"실행 가능하되 red"**인지 확인 권장 — 문법 오류로 실행조차 안 되는 테스트를 방지 (마지막 줄 `ACCEPTANCE_RESULT: total=N passed=N failed=N` 출력 확인).

### Step 1-8: Test Strategist Agent (Medium 이상)

**규모 게이트 (Small은 Test Plan 스킵)**: progress의 `projectSize`가 `Small`이면 Test Strategist Agent를 호출하지 않고 `docs/test-plan.md`도 만들지 않는다 — 기능 5개 미만에서는 Step 1-7.5의 **동결된 인수 테스트**(모든 AC 1:1 매핑)와 Step 1-7의 smoke 스크립트가 이미 "무엇을 테스트할지"의 계약이며, 별도 피라미드 배분 문서는 같은 내용을 한 번 더 적는 일이 된다. 인수 테스트 선작성+동결과 smoke 스크립트는 Small에서도 **그대로 필수**다. 스킵 시 증거 기록:
```bash
project_size=$(jq -r '.phases.phase_0.outputs.projectSize // "Medium"' {PROGRESS_FILE} 2>/dev/null || echo "Medium")
if [[ "$project_size" == "Small" ]]; then
  _tmp=$(mktemp)
  jq '.phases.phase_1.outputs.testPlan = {"verdict": "SKIPPED_SMALL", "reason": "projectSize=Small — 동결 인수 테스트 + smoke 스크립트로 대체"}' {PROGRESS_FILE} > "$_tmp" && mv "$_tmp" {PROGRESS_FILE}
fi
```
스킵을 기록하면 `spec-completeness`의 `test-plan.md` 존재 검사도 함께 skip된다 (`scripts/gates/docs.sh` — Small 판정은 progress의 `projectSize` 단일 출처).

Medium/Large인 경우, Phase 1 완료 직전 **Test Strategist Agent**를 호출하여 테스트 전략을 수립합니다:

- Agent tool로 `test-strategist` 에이전트 호출
- overview.md + SPEC.md + Architecture Review Report를 입력으로 제공
- 결과: Test Plan (테스트 피라미드 배분, 기능별 에지케이스, 실패 경로, 테스트 데이터 설계)
- Test Plan은 `docs/test-plan.md`에 저장
- Phase 2 구현자가 이 Test Plan을 따라 테스트 작성
- Phase 4 verification-auditor가 Test Plan 대비 커버리지 교차 검증 (projectSize=Large일 때만 — 관측·보고 전용)

### Step 1-9: Phase 1 완료 검증

모든 문서 토론 완료 및 검증 스크립트 생성 후, Phase 전이 전 최종 검증을 수행합니다.

> **모드 무관 (분기 없음)**: 아래 검증 — 스펙 깊이/US ID, smoke 스크립트 존재, 백엔드 표준 문서 3종(Medium+),
> DESIGN.md(hasFrontend), `provenance-gate`, `clarification-gate` — 은 `{REVIEW_MODE}`가 무엇이든 **전부 동일하게** 수행한다.
> `clarificationGate`는 stop-hook의 fail-closed 집합에 포함되어 있어, 이 게이트를 건너뛰면 어떤 모드든 완주가 차단된다.

```bash
# SPEC 파일 탐색 (다양한 경로 지원)
spec_file=""
for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
  [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
done

if [[ -n "$spec_file" ]]; then
  # 스펙 깊이 검증
  api_detail=$({ grep -c 'Request\|Response\|필드\|Field\|Body' "$spec_file" 2>/dev/null || true; } | tr -d '[:space:]')
  [[ -z "$api_detail" || ! "$api_detail" =~ ^[0-9]+$ ]] && api_detail=0
  if [[ $api_detail -lt 3 ]]; then
    echo "WARN: $spec_file에 API 상세 부족"
  fi

  # US-* ID 존재 체크 (US-F-*/US-B-* 형식만 허용)
  us_count=$({ grep -coE 'US-(F|B)-[0-9]+' "$spec_file" 2>/dev/null || true; } | tr -d '[:space:]')
  [[ -z "$us_count" || ! "$us_count" =~ ^[0-9]+$ ]] && us_count=0
  if [[ $us_count -eq 0 ]]; then
    echo "WARN: $spec_file에 US-* ID 없음"
  fi
else
  echo "WARN: SPEC 파일을 찾을 수 없음 (SPEC.md, docs/SPEC.md, docs/api-spec.md, spec.md)"
fi

# 검증 스크립트 존재 체크 (projectScope 기반 — progress 파일에서 로드)
has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend // "false"' {PROGRESS_FILE} 2>/dev/null || echo "false")
has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend // "false"' {PROGRESS_FILE} 2>/dev/null || echo "false")
# hasBackend=true → api-smoke.sh 필수
if [[ "$has_backend" == "true" ]] && [[ ! -f tests/api-smoke.sh ]]; then
  echo "FAIL: hasBackend=true이지만 tests/api-smoke.sh 미생성"
fi
# hasFrontend=true → ui-smoke.sh 또는 ui-smoke.spec.ts/js 필수
if [[ "$has_frontend" == "true" ]] && [[ ! -f tests/ui-smoke.sh ]] && [[ ! -f tests/ui-smoke.spec.ts ]] && [[ ! -f tests/ui-smoke.spec.js ]]; then
  echo "FAIL: hasFrontend=true이지만 tests/ui-smoke.* 미생성"
fi
# library/CLI → lib-smoke.sh
if [[ "$has_backend" != "true" ]] && [[ "$has_frontend" != "true" ]] && [[ ! -f tests/lib-smoke.sh ]]; then
  echo "FAIL: 라이브러리/CLI이지만 tests/lib-smoke.sh 미생성"
fi
```

WARN은 경고만 출력하고 진행, FAIL은 해당 단계를 재수행합니다.

#### 백엔드 표준 문서 3종 존재 검증 (hasBackend=true **그리고** projectSize가 Medium 이상인 경우)

```bash
project_size=$(jq -r '.phases.phase_0.outputs.projectSize // "Medium"' {PROGRESS_FILE} 2>/dev/null || echo "Medium")
if [[ "$has_backend" == "true" ]] && [[ "$project_size" != "Small" ]]; then
  for t in logging-standard error-policy security-authn-authz; do
    if [[ ! -f "docs/$t.md" ]]; then
      echo "FAIL: docs/$t.md 미생성 (hasBackend=true + Medium 이상은 3종 표준 문서 필수)"
    fi
  done
elif [[ "$has_backend" == "true" ]]; then
  echo "SKIP: 백엔드 표준 문서 3종 검증 생략 (projectSize=Small)"
fi
```

#### 프론트엔드 디자인 계약 존재 검증 (hasFrontend=true인 경우)

```bash
if [[ "$has_frontend" == "true" ]] && [[ ! -f "docs/DESIGN.md" ]]; then
  echo "FAIL: docs/DESIGN.md 미생성 (hasFrontend=true는 디자인 계약 필수)"
fi
```

DESIGN.md의 **제품 성격·브랜드 정체성 섹션은 `assumption` 마커가 금지**된다(`user-fact` 또는 `blocker`만 허용).
추측한 성격은 전 화면에 일관되게 전파되어 되돌리기가 가장 비싼 결정이기 때문이며,
미해결 `blocker`는 아래 provenance-gate → clarification-gate에서 최종 차단된다.

#### Provenance 마커 게이트 (HARD_FAIL — clarification-gate 직전 실행)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh provenance-gate --progress-file {PROGRESS_FILE}
```

- PASS → clarification-gate로 진행
- HARD_FAIL(마커 누락/근거 없는 assumption/unsafe-assumption) → 해당 섹션의 마커를 보완
- HARD_FAIL(blocker 잔존) → 각 blocker를 `[NEEDS-CLARIFICATION: <질문>]`으로 전환 —
  아래 clarification-gate의 batch-ask에서 함께 해소된 뒤 `user-fact`로 교체하고 재실행

#### [NEEDS-CLARIFICATION] 태그 잔존 게이트 (HARD_FAIL)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate docs/
```

- PASS → Phase 2 전이 가능
- HARD_FAIL → 잔존 태그를 사용자에게 AskUserQuestion으로 질의하여 모두 해소. 해소 전 Phase 2 진입 금지.

### Step 1-10: Phase 1 완료

모든 문서 `completed` 시:
1. DoD 업데이트: `all_docs_complete.checked = true`
2. Phase 전이는 오케스트레이터가 수행 (이 스킬에서 하지 않음)
