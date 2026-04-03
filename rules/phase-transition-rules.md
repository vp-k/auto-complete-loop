# Phase 전이 규칙

이 파일은 full-auto 계열 오케스트레이터의 5개 Phase 전이 로직을 정의합니다.
각 전이의 가드 조건, 스크립트 명령, DoD 기준을 포함합니다.

파라미터 `{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`은 오케스트레이터에서 정의합니다.

## Director Agent 공통 규칙

모든 Phase 전이에서 Director Agent를 호출합니다. 다음 공통 규칙을 따릅니다:

### NO-GO Escape Hatch (무한 루프 방지)
- Director NO-GO 횟수를 progress 파일의 `phases.{phase}.directorNoGoCount`에 기록
- **3회 연속 NO-GO** 시 사용자에게 선택지를 제시 (AskUserQuestion):
  1. **강제 진행**: Director 판정을 무시하고 다음 Phase로 진행 (위험 감수)
  2. **수동 해결**: 사용자가 직접 블로커를 해결한 후 재시도
  3. **중단**: 워크플로우를 중단하고 현재 상태 저장
- 사용자가 강제 진행을 선택하면 progress에 `"directorOverride": true` 기록
- GO 또는 CONDITIONAL GO 시 `directorNoGoCount`를 0으로 리셋

## Phase 0 → Phase 1

```
Progress 초기화 (Phase 0 진입 전 — $ARGUMENTS에서 프로젝트명과 요구사항을 추출하여 전달):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<$ARGUMENTS에서 추출한 프로젝트명>" "<$ARGUMENTS 원문>" --progress-file {PROGRESS_FILE}
Phase 0 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/pm-planning/SKILL.md
Phase 0 스킬의 Step 0-0 ~ 0-10 수행 (Step 0-11은 outputs 기록만, init 없음)
Phase 0 완료 시:
  *** Director Agent 전이 게이트 (Phase 0 → 1) ***
  Agent tool로 `director` 에이전트를 호출하여 GO/NO-GO/CONDITIONAL GO 판정:
  - overview.md + progress 파일 경로를 입력으로 제공
  - 전이 유형: "Phase 0 → Phase 1 (Planning → Documentation)"
  - NO-GO → Phase 0 블로커 해결 후 재시도
  - CONDITIONAL GO → 조건 기록 후 진행
  - GO → 진행

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_0 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 in_progress --progress-file {PROGRESS_FILE}
```

## Phase 1 → Phase 2 (Pre-mortem 가드 포함)

```
Phase 1 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/doc-planning/SKILL.md
Phase 1 스킬의 Step 1-0 ~ 1-9 수행 (Step 1-6: 스펙 깊이 검증, Step 1-7: 검증 스크립트 생성, Step 1-8: 완료 검증)
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

  *** Director Agent 전이 게이트 (Phase 1 → 2) ***
  Agent tool로 `director` 에이전트를 호출하여 GO/NO-GO/CONDITIONAL GO 판정:
  - overview.md + SPEC.md + docs/test-plan.md + progress 파일 경로를 입력으로 제공
  - 전이 유형: "Phase 1 → Phase 2 (Documentation → Implementation)"
  - Architecture Review Report + Test Plan 존재 여부 확인
  - NO-GO → Phase 1 블로커 해결 후 재시도
  - CONDITIONAL GO → 조건 기록 후 진행
  - GO → 진행

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

  *** Director Agent 전이 게이트 (Phase 2 → 3) ***
  Agent tool로 `director` 에이전트를 호출하여 GO/NO-GO/CONDITIONAL GO 판정:
  - progress 파일 + 구현된 코드 파일 목록 제공
  - 전이 유형: "Phase 2 → Phase 3 (Implementation → Review)"
  - NO-GO → Phase 2 블로커 해결 후 재시도

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 in_progress --progress-file {PROGRESS_FILE}
```

DoD: `"dod.all_code_implemented": { "checked": true, "evidence": "모든 문서 구현 + doc-code 일관성 검사 + E2E 테스트 통과" }`

## Phase 3 → Phase 4

```
Phase 3 진입 → Read ${CLAUDE_PLUGIN_ROOT}/{PHASE_3_SKILL}
Phase 3 스킬의 지정된 Step 범위 수행 (오케스트레이터에서 PHASE_3_STEPS로 정의)
Phase 3 완료 시:
  *** Director Agent 전이 게이트 (Phase 3 → 4) ***
  Agent tool로 `director` 에이전트를 호출하여 GO/NO-GO/CONDITIONAL GO 판정:
  - progress 파일 + 코드 리뷰 결과 (findings 목록) 제공
  - 전이 유형: "Phase 3 → Phase 4 (Review → Verification)"
  - CRITICAL/HIGH findings 잔존 시 NO-GO
  - NO-GO → Phase 3에서 미해결 findings 수정 후 재시도

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 in_progress --progress-file {PROGRESS_FILE}
```

DoD: `"dod.code_review_pass": { "checked": true, "evidence": "N라운드 리뷰 완료, CRITICAL/HIGH/MEDIUM: 0" }`

## Phase 4 → 완료

```
Phase 4 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/verification/SKILL.md
Phase 4 스킬의 Step 4-1 ~ 4-7 수행
Phase 4 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 completed --progress-file {PROGRESS_FILE}

모든 steps completed + DoD 전체 checked + verification 통과 확인 후:
<promise>{PROMISE_TAG}</promise>
```
