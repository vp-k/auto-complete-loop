# Phase 전이 규칙

이 파일은 full-auto 계열 오케스트레이터의 5개 Phase 전이 로직을 정의합니다.
각 전이의 가드 조건, 스크립트 명령, DoD 기준을 포함합니다.

파라미터 `{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`은 오케스트레이터에서 정의합니다.

## Phase 전이 공통 규칙

Phase 전이는 **결정론 게이트만으로** 판정한다. 각 전이의 가드/게이트(Pre-mortem 가드, 스코프 완전성,
검증 스크립트, 인수 테스트 동결, 기획 게이트 3종, E2E 가드, code-review-findings 등)가 전부 통과하면
`update-phase`로 바로 다음 Phase로 진행한다 — 별도의 판정 에이전트를 두지 않는다.

이유: 판정 에이전트의 GO/NO-GO 결과를 차단에 사용하는 스크립트·훅이 없어 전이를 실제로 막지 못했고,
실질 차단은 전부 결정론 게이트(그리고 stop-hook의 fail-closed 필수 키)가 수행한다. 판정만 하고 아무것도
막지 못하는 호출은 지연 비용만 남기므로 제거했다.

**게이트가 FAIL이면 전이하지 않는다** — 출발 Phase를 `completed`로 마킹하지 않고, 블로커를 해결한 뒤
게이트를 재실행해 PASS를 확인하고 진행한다. 게이트 결과는 verification.json에 기록되며,
모델이 이 키들을 직접 기록하는 것은 금지된다 (게이트 실행 결과로만 세팅).

## --start-phase 스킵 처리

`$ARGUMENTS`에 `--start-phase N`이 포함된 경우 (N은 0-4):

```
1. $ARGUMENTS에서 --start-phase N을 추출하고 나머지를 순수 요구사항으로 사용
2. N >= 2일 때: docs/ 폴더에 .md 파일이 1개 이상 존재하는지 확인
   - 없으면: "기획 문서가 없습니다. Phase 0부터 시작합니다." 경고 → N=0으로 폴백
3. Progress 초기화:
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<프로젝트명>" "<요구사항>" --progress-file {PROGRESS_FILE}
4. Phase 스킵 실행:
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh skip-phases <N> --progress-file {PROGRESS_FILE}
   # 예: skip-phases 2 → Phase 0, 1 스킵 후 Phase 2부터 시작
5. Phase N의 스킬을 Read하여 해당 Phase부터 워크플로우 시작
```

**스킵된 Phase의 가드 조건은 면제됩니다** — Pre-mortem 가드, 스코프 완전성 게이트 등은 해당 Phase가 실제로 실행될 때만 적용.

## Phase 0 → Phase 1

```
Progress 초기화 (Phase 0 진입 전 — $ARGUMENTS에서 프로젝트명과 요구사항을 추출하여 전달):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<$ARGUMENTS에서 추출한 프로젝트명>" "<$ARGUMENTS 원문>" --progress-file {PROGRESS_FILE}
Phase 0 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/pm-planning/SKILL.md
Phase 0 스킬의 Step 0-0 ~ 0-10 수행 (Step 0-11은 outputs 기록만, init 없음)
Phase 0 완료 시:
  (Phase 0 산출물 — overview.md, projectSize, projectScope, premortem — 이 progress에 기록됐는지 확인 후 바로 전이)

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_0 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 in_progress --progress-file {PROGRESS_FILE}
```

## Phase 1 → Phase 2 (Pre-mortem 가드 포함)

```
Phase 1 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/doc-planning/SKILL.md
Phase 1 스킬의 Step 1-0 ~ 1-9 수행 (Step 1-6: 스펙 깊이 검증, Step 1-7: 검증 스크립트 생성, Step 1-7.5: 인수 테스트 생성+동결, Step 1-8: 완료 검증)
Phase 1 완료 시:
  *** Pre-mortem 전이 가드 (Phase 2 진입 전 필수 — phase_1 completed 마킹보다 선행) ***
  1. progress 파일에서 phases.phase_0.outputs.premortem.tigers 조회
  2. blocking=true && mitigation="" 인 항목 존재 여부 확인
  3. 존재하면 → "Launch-Blocking Tiger 미해결" 경고 출력 → Phase 2 전이 차단
     - Phase 1은 completed로 마킹하지 않음 (대응책 수립 후 재시도)
     - 기획 문서에 mitigation 추가 → progress의 해당 tiger.mitigation 업데이트
     - 재검증 통과 시 아래로 진행
  4. 없으면 → 통과

  *** 스코프 완전성 게이트 (Pre-mortem 가드 통과 후 추가 검증) ***
  0. progress 파일에서 phases.phase_0.outputs.projectScope 조회
     - projectScope가 null 또는 미설정이면 → "projectScope 미정의 — Phase 0에서 Step 0-2.5 수행 필요" → Phase 2 전이 차단 (fail-closed)
  1. projectScope 존재 확인 후:
  2. projectScope.hasFrontend=true인 경우:
     - SPEC.md에 "User Stories — Frontend" **AND** "Frontend Pages & Components" 섹션 모두 존재 확인
     - 기획 문서 목록에 프론트엔드 관련 내용이 1건 이상 있는지 확인
     - 하나라도 없으면 → "프론트엔드 기획 문서 누락" 경고 → Phase 2 전이 차단
       - Phase 1에서 프론트엔드 문서 추가 작성 후 재시도
  3. projectScope.hasBackend=true인 경우:
     - SPEC.md에 "User Stories — Backend" **AND** "API Contract" 섹션 모두 존재 확인
     - 하나라도 없으면 → "백엔드 기획 문서 누락" 경고 → Phase 2 전이 차단
  4. 통과 시 아래로 진행

  *** 검증 스크립트 게이트 (Phase 2 진입 전 필수 — 스코프 완전성 가드 통과 후) ***
  1. 검증 스크립트 존재 확인:
     - hasBackend=true → tests/api-smoke.sh 존재 확인
     - hasFrontend=true → tests/ui-smoke.sh 또는 tests/ui-smoke.spec.ts 또는 tests/ui-smoke.spec.js 존재 확인
     - library/CLI → tests/lib-smoke.sh 존재 확인
  2. 하나도 없으면 → "검증 스크립트 미생성 — Step 1-7 수행 필요" → Phase 2 전이 차단
     - Phase 1에서 smoke 스크립트 생성 후 재시도
  3. SPEC.md (또는 docs/api-spec.md)에 US-F-*/US-B-* ID 존재 확인:
     - 0건이면 → WARN (차단하지 않지만 경고: "US-* ID 없음, test-quality 커버리지 측정 불가")
  4. 통과 시 아래로 진행

  *** 인수 테스트 동결 게이트 (Phase 2 진입 전 필수 — 검증 스크립트 가드 통과 후) ***
  1. 인수 테스트 생성+동결 완료 확인: verification.json의 acceptanceFreeze = pass
     (Phase 1 스킬 Step 1-7.5에서 tests/acceptance/ 생성 + acceptance-freeze 실행 결과)
  2. 미실행/실패 시 → "인수 테스트 미동결 — Step 1-7.5 수행 필요" → Phase 2 전이 차단
     - Phase 1에서 tests/acceptance/run.sh + US별 테스트 생성 후
       bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh acceptance-freeze --progress-file {PROGRESS_FILE}
       재실행 → pass 확인
  3. 이 시점에 인수 테스트가 red인 것은 정상 (앱 미구현 — TDD red→green). 동결 여부만 확인한다.
  4. 통과 시 아래로 진행

  *** 기획 게이트 3종 (인수 테스트 동결 가드 통과 후 — 전이 전 필수) ***
  1. Spec 완전성:
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh spec-completeness --progress-file {PROGRESS_FILE}
     - CRITICAL > 0 → Phase 2 전이 차단 (HARD gate). CRITICAL 이슈 해결 후 재시도.
     - MAJOR > 0 → 경고 출력 (차단하지 않지만 Phase 2에서 반드시 반영)
     - MINOR → 정보성 (Phase 2에서 결정 가능)
  2. Clarification 게이트:
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate --progress-file {PROGRESS_FILE}
     - 스펙 문서에 [NEEDS-CLARIFICATION: ...] 태그 잔존 시 → Phase 2 전이 차단 (질문 해소 + 스펙 반영 후 재시도)
  3. 문서 완전성:
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-completeness --progress-file {PROGRESS_FILE}
     - 필수 기획 문서 미비 시 → Phase 2 전이 차단

  *** 전이 조건 (fail-closed) ***
  위 3개 게이트의 실행 결과가 verification.json에 각각 specCompleteness / clarificationGate / docCompleteness = pass로
  기록되어 있어야 Phase 2 전이 가능. **미실행 = 기록 없음 = 전이 불가** (stop-hook이 full-auto 계열 progress에서
  이 키들을 fail-closed로 요구). 모델이 이 키들을 직접 기록하는 것 금지 — 게이트 실행 결과로만 세팅된다.

  *** 산출물 존재 확인 (전이 전 마지막 체크) ***
  - SPEC.md 존재 확인 (없으면 Phase 1 미완 → 전이 차단)
  - docs/test-plan.md 존재 확인 — 단, `projectSize=Small`이고 `phases.phase_1.outputs.testPlan.verdict == "SKIPPED_SMALL"`이면 면제
    (규모 분기 단일 출처: rules/project-size-rules.md. Small은 Step 1-8 test-strategist를 호출하지 않는다)

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 in_progress --progress-file {PROGRESS_FILE}
  (shared-gate.sh의 update-phase에서도 이중 검사: blocking Tiger 미해결 시 exit 1)
```

## Phase 2 → Phase 3

```
Phase 2 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/implementation/SKILL.md
Phase 2 스킬의 Step 2-1 ~ 2-7 수행
Phase 2 완료 시:
  *** E2E 전이 가드 (Phase 3 진입 전 필수 — phase_2 completed 마킹보다 선행) ***
  1. progress 파일에서 phases.phase_2.e2e.applicable 조회
  2. applicable=true인 경우:
     - bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file {PROGRESS_FILE}
     - phases.phase_2.e2e.scenarios에서 모든 시나리오의 status가 "completed"인지 확인
  3. E2E 미통과 시 → "E2E 테스트 미완료" 경고 출력 → Phase 3 전이 차단
     - Phase 2는 completed로 마킹하지 않음 (E2E 작성/수정 후 재시도)
     - 재검증 통과 시 아래로 진행
  4. applicable=false 또는 applicable=null인 경우 → 통과

  (E2E 가드 통과 시 바로 전이 — 구현 품질 판정은 Phase 3 코드 리뷰가 수행한다)

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 in_progress --progress-file {PROGRESS_FILE}
```

DoD: `"dod.all_code_implemented": { "checked": true, "evidence": "모든 문서 구현 + doc-code 일관성 검사 + E2E 테스트 통과" }`

## Phase 3 → Phase 4

```
Phase 3 진입 → *** 리뷰 승격 판정 (스킬 로드 전 필수) ***
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh review-escalation-check --progress-file {PROGRESS_FILE}
  - 위험 트리거(L2+ 에스컬레이션 / 범위 축소 / 인수 테스트 재동결) 평가 → reviewEscalation = skip | pending
  - skip → 기존 리뷰 모드만으로 진행

Phase 3 진입 → Read ${CLAUDE_PLUGIN_ROOT}/{PHASE_3_SKILL}
Phase 3 스킬의 지정된 Step 범위 수행 (오케스트레이터에서 PHASE_3_STEPS로 정의)
Phase 3 완료 시:
  *** 리뷰 승격 완료 검증 (pending이었던 경우 — code-review-findings보다 선행) ***
  reviewEscalation이 pending이면 승격 리뷰 1라운드를 추가 실행한다:
  - targetMode=dual: codex 2차 독립 리뷰 1회 (code-review 스킬의 codex 라운드 절차 재사용, 관점 분할)
  - targetMode=roundtable: Agent tool로 `roundtable` 에이전트 호출 (입력: 변경 파일 + 트리거 사유)
  - 승격 라운드도 시작 시 `shared-gate.sh source-hash`를 캡처해 sourceHash로 기록 (v4.9.0)
  - 승격 리뷰 finding은 findingHistory에 "escalated": true로 append (동일 스키마)
  - 승격 라운드를 roundResults에 {escalated: true, reviewMode: "<targetMode>", sourceHash: "<캡처값>"} 포함해 기록 (0-finding이어도 필수)
  - bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh review-escalation-check --mark-complete --progress-file {PROGRESS_FILE}
  - 증거 없으면 FAIL → 승격 리뷰 수행 후 재실행 (stop-hook이 reviewEscalation=pass|skip을 fail-closed로 요구)
  - **승격 finding 수정이 있었던 경우**: 수정을 커밋한 뒤, **전체 라운드 절차(지문 캡처 →
    리뷰어 실제 호출 → 검증 → 기록)로 비승격 리뷰 라운드를 1회 더 실행**해야
    code-review-findings의 sourceHash 대조를 통과한다 — 리뷰어 호출 없이 라운드 항목만
    append하는 것은 금지 (0-finding 승격 라운드는 지문 불변이므로 추가 조치 불필요)

  *** Code Review Findings 게이트 (전이 전 필수 — HARD gate) ***
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh code-review-findings --round-kind <fix|verify|rerecord> --progress-file {PROGRESS_FILE}
  - --round-kind 생략 금지 (생략 시 기본값 verify → 수정 라운드가 상한 5에 계수되지 않는다):
      fix      = 이번에 마감하는 라운드에서 소스 수정이 1건이라도 있었다 (승격 리뷰 finding 수정 포함)
      verify   = 확인 전용 라운드 (수정 0건 — 수렴 라운드: 신규 finding이 MEDIUM/LOW뿐이라 전부 deferred)
      rerecord = 귀속용 재기록 라운드 (직전 소스 변경을 새 지문에 귀속하려 리뷰를 1회 더 돌렸고 그 라운드의 수정은 0건)
    신고와 무관하게, 마지막 마감 이후 소스 지문이 바뀌었으면 게이트가 fix로 계상한다 (declaredKind에 신고값 보존)
  - open CRITICAL/HIGH finding을 집계하여 1건 이상이면 FAIL → Phase 4 전이 차단 (수정 후 재실행)
  - PASS 결과가 verification.json의 codeReviewFindings에 기록되어야 전이 가능 (미실행 = 전이 불가, fail-closed)
  - dod.code_review_pass는 이 게이트의 PASS 결과로만 세팅한다 (모델 직접 기록 금지)

  (code-review-findings PASS = open CRITICAL/HIGH 0건이 확인되면 바로 전이)

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 in_progress --progress-file {PROGRESS_FILE}
```

DoD: `"dod.code_review_pass": { "checked": true, "evidence": "N라운드 리뷰 완료, open CRITICAL/HIGH: 0 (MEDIUM/LOW deferred: M건)" }`
(이 DoD는 `code-review-findings` 게이트의 PASS 결과로만 세팅 — 모델이 직접 checked:true를 쓰지 않는다)

## Phase 4 → 완료

```
Phase 4 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/verification/SKILL.md
Phase 4 스킬의 Step 4-1 ~ 4-7 수행 (Step 4-6.6: clarification-gate 재실행 — Phase 2에서 `docs/CLARIFICATIONS.md`에 남긴 [NEEDS-CLARIFICATION] 잔존 차단, Step 4-6.7: acceptance-gate 필수 실행, Step 4-6.8: Phase 4 소스 변경 시 최종 델타 리뷰 — code-review-findings의 sourceHash 정합 확보)
Phase 4 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 completed --progress-file {PROGRESS_FILE}

모든 steps completed + DoD 전체 checked + verification 통과 확인 후:
<promise>{PROMISE_TAG}</promise>
```

완주 조건 주의: stop-hook이 verification.json의 `acceptanceTests = pass`를 fail-closed로 요구한다
(`acceptance-gate` 실행 결과로만 기록 — 무결성 통과 + `tests/acceptance/run.sh` 전체 green.
미실행 = 기록 없음 = 완주 불가. `dod.acceptance_pass`도 이 게이트가 자동 기록하며 모델 직접 세팅 금지).
