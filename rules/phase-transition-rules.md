# Phase 전이 규칙

이 파일은 full-auto 계열 오케스트레이터의 5개 Phase 전이 로직을 정의합니다.
각 전이의 가드 조건, 스크립트 명령, DoD 기준을 포함합니다.

파라미터 `{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`은 오케스트레이터에서 정의합니다.

## Phase 0 → Phase 1

```
Progress 초기화 (Phase 0 진입 전 — $ARGUMENTS에서 프로젝트명과 요구사항을 추출하여 전달):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<$ARGUMENTS에서 추출한 프로젝트명>" "<$ARGUMENTS 원문>" --progress-file {PROGRESS_FILE}
Phase 0 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/pm-planning/SKILL.md
Phase 0 스킬의 Step 0-0 ~ 0-10 수행 (Step 0-11은 outputs 기록만, init 없음)
Phase 0 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_0 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 in_progress --progress-file {PROGRESS_FILE}
```

## Phase 1 → Phase 2 (Pre-mortem 가드 포함)

```
Phase 1 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/doc-planning/SKILL.md
Phase 1 스킬의 Step 1-0 ~ 1-6 수행
Phase 1 완료 시:
  *** Pre-mortem 전이 가드 (Phase 2 진입 전 필수 — phase_1 completed 마킹보다 선행) ***
  1. progress 파일에서 phases.phase_0.outputs.premortem.tigers 조회
  2. blocking=true && mitigation="" 인 항목 존재 여부 확인
  3. 존재하면 → "Launch-Blocking Tiger 미해결" 경고 출력 → Phase 2 전이 차단
     - Phase 1은 completed로 마킹하지 않음 (대응책 수립 후 재시도)
     - 기획 문서에 mitigation 추가 → progress의 해당 tiger.mitigation 업데이트
     - 재검증 통과 시 아래로 진행
  4. 없으면 → 통과

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

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 completed --progress-file {PROGRESS_FILE}
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 in_progress --progress-file {PROGRESS_FILE}
```

DoD: `"dod.all_code_implemented": { "checked": true, "evidence": "모든 문서 구현 + doc-code 일관성 검사 + E2E 테스트 통과" }`

## Phase 3 → Phase 4

```
Phase 3 진입 → Read ${CLAUDE_PLUGIN_ROOT}/{PHASE_3_SKILL}
Phase 3 스킬의 지정된 Step 범위 수행 (오케스트레이터에서 PHASE_3_STEPS로 정의)
Phase 3 완료 시:
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
