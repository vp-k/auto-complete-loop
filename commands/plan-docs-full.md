---
description: "PM Planning + Doc Planning end-to-end. One-line requirement → overview.md + all planning docs + SPEC + smoke scripts, with 4 strict gates"
argument-hint: <요구사항 (자연어)>
---

# Plan Docs Full: 한 줄 요구사항 → 임의 판단 없는 기획문서 (오케스트레이터)

한 줄 요구사항으로 **PM Planning(Phase 0) + Doc Planning(Phase 1)**을 자동 수행해, **구현자가 추가 판단 없이 코딩 가능한** 수준의 기획 산출물을 생성합니다.

`full-auto`의 Phase 0~1만 추출한 형태입니다. Phase 2(구현)부터는 별도로 `/full-auto --start-phase 2` 또는 `/implement-docs-auto`로 실행하세요.

**역할 분담** (모드별):
- **codex** (기본): Claude = PM, codex-cli = 기획 토론 상대
- **solo**: Claude = PM + 자기 토론 (외부 AI 불필요)
- **teams**: Claude(리드) + Agent Teams 병렬 검토
- **dual**: Claude + codex 1차 + codex 2차 3자 토론 (codex-cli 두 번 독립 호출)

**핵심 원칙**:
- Phase 0에서만 사용자 질문 (overview.md 승인 + Critical 잔존 시 결정 위임)
- MVP 금지, 릴리즈 수준 기획
- **신규 게이트 4종이 모두 PASS해야 promise 발행** (임의 판단 자동 차단)
- 스크립트로 토큰 절약

## 파라미터 (모드별)

| 파라미터 | codex (기본) | solo | teams | dual |
|----------|-------------|------|-------|--------|
| PROMISE_TAG | `PLAN_DOCS_FULL_COMPLETE` | `PLAN_DOCS_FULL_COMPLETE` | `PLAN_DOCS_FULL_TEAMS_COMPLETE` | `PLAN_DOCS_FULL_DUAL_COMPLETE` |
| PROGRESS_FILE | `.claude-plan-docs-full-progress.json` | `.claude-plan-docs-full-progress.json` | `.claude-plan-docs-full-teams-progress.json` | `.claude-plan-docs-full-dual-progress.json` |
| PHASE_1_SKILL | `skills/doc-planning/SKILL.md` | `skills/doc-planning-solo/SKILL.md` | `skills/doc-planning/SKILL.md` | `skills/doc-planning/SKILL.md` |

`--mode` 미지정 시 codex 모드를 사용합니다.

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "학생들이 일일 학습 목표를 등록하고 달성률을 보는 웹 대시보드")
- `--mode <solo|codex|teams|dual>` (선택, 기본: codex)
  - `codex`: Claude + codex-cli 2자 토론
  - `solo`: Claude 단독 다관점 토론 (외부 AI 불필요)
  - `teams`: Agent Teams 병렬 검토 (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 필요)
  - `dual`: Claude + codex 1차 + codex 2차 3자 토론 (codex-cli 두 번 독립 호출)

## 아키텍처: 오케스트레이터 + Phase 스킬 재사용

```
이 파일 (오케스트레이터) — Ralph Loop, Phase 전이, Progress 관리, 게이트 호출 소유
    ↓ Read로 Phase별 스킬 로드 (코드 중복 없음)
    ├── skills/pm-planning/SKILL.md        (Phase 0 — 기존 재사용)
    └── {PHASE_1_SKILL}                    (Phase 1 — 모드별 스킬 재사용)

→ [게이트 5종 — 모두 PASS여야 promise 발행]
   0. spec-completeness    (HARD_FAIL: 필수 섹션 + 핵심 섹션 TBD 0건)
   1. doc-completeness     (HARD_FAIL: API 블록 정량 임계값)
   2. doc-consistency      (WARN: 모델/엔드포인트/네이밍 교차 검증)
   3. definition-conflict  (SOFT_FAIL: Non-Goals 침범 탐지 + Claude 판정 기록)
   4. spec-to-tests        (HARD_FAIL: SPEC ↔ smoke 1:1 매핑)

→ <promise>{PROMISE_TAG}</promise>
```

**단일 소스 원칙**: Phase 0/1 로직은 기존 스킬 그대로 사용. 이 파일은 오케스트레이션 + 신규 게이트 호출만 담당.

## --mode 처리

`$ARGUMENTS`에서 `--mode <value>`를 감지하면:

1. `$ARGUMENTS`에서 `--mode <value>` 부분을 제거하여 순수 요구사항만 추출
2. value 검증: `solo`, `codex`, `teams`, `dual` 중 하나
3. 위 "파라미터" 테이블에서 해당 모드의 값을 적용
4. **teams 모드 전제 조건**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 환경 변수 확인
   - 미설정 시: `~/.claude/settings.json`에 자동 추가 후 새 세션 안내 및 중단
5. **dual 모드 전제 조건**: `codex` CLI 존재 확인 (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh check-tools`)
   - 미설치 시: codex 모드로 자동 폴백 + 경고 출력
6. `--mode` 미지정 시 기본값 `codex` 적용

## 공통 규칙 로드

```
Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md
```

## Ralph Loop 자동 설정 (최우선 실행)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "{PROMISE_TAG}" "{PROGRESS_FILE}"
```

### Ralph Loop 완료 조건

`<promise>{PROMISE_TAG}</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:

1. `{PROGRESS_FILE}`의 `phases.phase_0` + `phases.phase_1` 모든 step status가 `completed`
2. `{PROGRESS_FILE}`의 `dod`(아래 DoD 키 목록) 모두 `checked: true`
3. **게이트 5종 모두 통과** (직전 실행 결과 — 이전 iteration 재사용 금지):
   - `spec-completeness` exit 0 (CRITICAL 0건)
   - `doc-completeness` exit 0
   - `doc-consistency` exit 0 (이슈 0건)
   - `definition-conflict` exit 0 + 매치가 있다면 progress의 `nonGoalsAudit`에 모든 매치 판정 기록 완료
   - `spec-to-tests` exit 0
4. 기존 Phase 1 게이트 통과:
   - `clarification-gate` exit 0 (`[NEEDS-CLARIFICATION]` 잔존 0건)
   - `placeholder-check` exit 0
5. 위 조건을 **직전에 확인**한 결과여야 함

### Iteration 단위 작업 규칙

- 한 iteration에서 다음 중 하나만 처리:
  - Phase 0의 한 단계 그룹 (Step 0-0~0-5, Step 0-6~0-10)
  - Phase 1의 1~2개 문서
  - 게이트 검증 + 게이트 실패 수정
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료
- Stop Hook이 promise 미발행 감지 시 자동으로 다음 iteration 시작

## DoD 키 목록 (이 명령 전용)

`shared-gate.sh init`로 progress 파일을 만든 후 다음 DoD 키를 추가합니다:

```bash
for key in pm_approved assumptions_documented premortem_done all_docs_complete \
           spec_md_generated smoke_scripts_generated doc_completeness_passed \
           doc_consistency_passed definition_conflict_resolved spec_to_tests_passed \
           clarification_resolved; do
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh add-dod-key "$key" --progress-file {PROGRESS_FILE}
done
```

Large 프로젝트인 경우 `pm-planning` Step 0-9.5에서 `stakeholders_mapped`가 추가됩니다.

## 2-Phase 워크플로우

```
Phase 0: PM Planning ───── 사용자 승인 (유일한 상호작용)
    ↓ pm_approved.checked, assumptions_documented.checked, premortem_done.checked
Phase 1: Doc Planning ──── {PHASE_1_SKILL}로 기획문서 + SPEC.md + smoke 스크립트 완성
    ↓ all_docs_complete.checked, spec_md_generated.checked, smoke_scripts_generated.checked
[신규 게이트 4종 검증]
    ↓ doc_completeness_passed, doc_consistency_passed, definition_conflict_resolved, spec_to_tests_passed
[기존 게이트 2종 검증]
    ↓ clarification_resolved (placeholder는 자동)
<promise>{PROMISE_TAG}</promise>
```

## 0단계: 초기화 (최초 1회)

`{PROGRESS_FILE}`이 없으면:

```bash
# 1. progress 파일 생성 (plan 템플릿)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template plan \
  "<프로젝트명>" "$ARGUMENTS" --progress-file {PROGRESS_FILE}

# 2. 이 명령 전용 DoD 키 추가 (위 'DoD 키 목록' 블록 실행)
```

`{PROGRESS_FILE}`이 있으면 복구 모드로 진입:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh recover --progress-file {PROGRESS_FILE}
```

handoff + next steps를 읽어 직전에 멈춘 지점부터 재개합니다.

## 1단계: Phase 0 — PM Planning

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/pm-planning/SKILL.md
```

스킬 절차 그대로 수행. 산출:
- `overview.md` (정의 문서)
- `README.md` (문서 목록 + 빌드/실행 뼈대)
- progress의 `phases.phase_0.outputs`: assumptions, nsm, successCriteria, premortem, projectSize, projectScope, implementationOrder

**Step 0-10에서 사용자 승인 받은 후** 다음 진행. 미승인 상태로 Phase 1 진입 금지.

DoD 갱신은 스킬의 Step 0-11에서 처리합니다.

## 2단계: Phase 1 — Doc Planning

```
Read ${PHASE_1_SKILL}
```

스킬 절차 그대로 수행. 산출:
- `docs/*.md` (각 도메인 기획문서, 모두 `completed` 상태)
- `SPEC.md` (또는 `docs/SPEC.md`) — User Stories + API Contract + Data Model
- `tests/api-smoke.sh` (hasBackend=true 시) / `tests/ui-smoke.*` (hasFrontend=true 시) / `tests/lib-smoke.sh` (library/CLI 시)
- progress의 `phases.phase_1.outputs`

스킬 내 Step 1-9에서 이미 `clarification-gate`가 호출됩니다. HARD_FAIL이면 사용자 질의로 모두 해소.

## 3단계: 게이트 5종 순차 검증 (Phase 1 종료 직후)

스킬 완료 후 오케스트레이터가 다음 게이트를 **순차** 실행합니다. 하나라도 실패하면 Phase 1 재진입(해당 이슈 수정).

> 게이트 결과는 `.claude-verification.json`에 자동 기록되며, stop-hook이 `specCompleteness` · `clarificationGate` · `docCompleteness` · `specToTests` 키가 전부 `pass`인지 최종 검증합니다 (미실행 = 완주 불가, fail-closed).

```bash
# 게이트 0: spec-completeness (HARD_FAIL: CRITICAL 이슈 0건 — 핵심 섹션 TBD 포함)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh spec-completeness \
  --progress-file {PROGRESS_FILE}
# 실패 → overview/SPEC의 누락 섹션·핵심 섹션 내 TBD를 구체 결정으로 교체 후 재실행

# 게이트 1: doc-completeness (HARD_FAIL)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-completeness docs/ \
  --progress-file {PROGRESS_FILE}
# 실패 → SPEC.md API 블록의 Request/Response/테스트케이스 보강 후 재실행

# 게이트 2: doc-consistency (WARN — 이슈 0건이어야 통과)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency docs/
# WARN → 모델 용어/엔드포인트/네이밍/상호참조/수치 단위를 일치시킴

# 게이트 3: definition-conflict (SOFT_FAIL — 매치 시 모든 라인을 Claude가 판정)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh definition-conflict docs/
# 매치된 라인 각각에 대해:
#  (a) 의도된 명시적 예외인지 확인 — overview.md에 근거 추가
#  (b) 또는 해당 부분을 docs/*.md / SPEC.md에서 삭제
# 판정을 progress.phases.phase_1.outputs.nonGoalsAudit 배열에 기록:
#   { "file": "docs/auth.md", "line": 42, "keyword": "OAuth", "decision": "exception|removed", "rationale": "..." }

# 게이트 4: spec-to-tests (HARD_FAIL)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh spec-to-tests \
  --progress-file {PROGRESS_FILE}
# 실패 → tests/api-smoke.sh에 누락된 엔드포인트 curl 호출 추가
```

각 게이트 통과 시 DoD 갱신:

```bash
jq_inplace {PROGRESS_FILE} \
  '.dod.spec_completeness_passed = {checked:true, evidence:"shared-gate.sh spec-completeness PASS"}
   | .dod.doc_completeness_passed = {checked:true, evidence:"shared-gate.sh doc-completeness PASS"}
   | .dod.doc_consistency_passed = {checked:true, evidence:"shared-gate.sh doc-consistency PASS (0 issues)"}
   | .dod.definition_conflict_resolved = {checked:true, evidence:"N matches reviewed, all recorded in nonGoalsAudit"}
   | .dod.spec_to_tests_passed = {checked:true, evidence:"shared-gate.sh spec-to-tests PASS"}
   | .dod.clarification_resolved = {checked:true, evidence:"clarification-gate PASS in Phase 1 Step 1-9"}'
```

## 4단계: 최종 보고 + Promise 발행

모든 DoD 키가 `checked: true`인지 확인:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status --progress-file {PROGRESS_FILE}
```

이상 없으면 간결한 완료 보고 (각 산출물 한 줄 요약) 후:

```
<promise>{PROMISE_TAG}</promise>
```

## 사용자 개입 시점 (이 시점에만 AskUserQuestion 허용)

**허용된 질문 시점**:
- Phase 0 Step 0-10 (overview.md/README.md 사용자 승인)
- Phase 1 토론 5라운드 후 Critical 잔존 시 (스킬 내 처리)
- `clarification-gate` HARD_FAIL 시 잔존 태그 답변

**금지된 질문**: "다음 단계 진행할까요?", "이 게이트 실행할까요?" 등 확인성 질문

## 강제 규칙

- `pm-planning` / `doc-planning` 스킬 내부 로직을 이 파일에 복사하지 않는다 (단일 소스 원칙)
- 4종 게이트 중 하나라도 실패한 채로 promise를 발행하지 않는다
- `definition-conflict`의 매치된 라인 각각이 `nonGoalsAudit`에 기록되지 않은 채로 진행하지 않는다 (임의 판단 회피)
- progress 파일의 DoD는 게이트 PASS evidence와 함께만 `checked: true`로 갱신한다
