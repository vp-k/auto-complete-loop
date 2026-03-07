---
description: "기획→구현→검수 올인원. 한 줄 요구사항으로 기획 문서→코드 구현→코드 리뷰→최종 검증까지 자동 완주"
argument-hint: <요구사항 (자연어)>
---

# Full Auto: 기획→구현→검수 올인원 (오케스트레이터)

한 줄 요구사항으로 **기획 문서 작성 → 코드 구현 → 코드 리뷰 → 최종 검증**까지 자동 완주합니다.

**역할 분담**: Claude = PM + 구현자, Codex = 기획 토론 + 코드 리뷰
**핵심 원칙**: Phase 0에서만 사용자 질문, 이후 완전 자동 | MVP 금지, 릴리즈 수준 | 스크립트로 토큰 절약

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "커뮤니티 사이트를 만들어줘")

## 아키텍처: 오케스트레이터 + Phase 스킬

```
이 파일 (오케스트레이터) — Ralph Loop, Phase 전이, Progress 관리 소유 (유일)
    ↓ Read로 Phase별 스킬 로드
    ├── skills/pm-planning/SKILL.md     (Phase 0 순수 로직)
    ├── skills/doc-planning/SKILL.md    (Phase 1 순수 로직)
    ├── skills/implementation/SKILL.md  (Phase 2 순수 로직)
    ├── skills/code-review/SKILL.md     (Phase 3 순수 로직)
    └── skills/verification/SKILL.md    (Phase 4 순수 로직)
```

**단일 소스 원칙**: 규칙은 각 스킬 파일과 `shared-rules.md`에만 존재. 이 파일은 오케스트레이션만 담당.

## 5-Phase 워크플로우

```
Phase 0: PM Planning ─── 사용자 승인 (유일한 상호작용)
    ↓
Phase 1: Planning ───── codex 토론으로 기획 문서 완성
    ↓ [일관성 검사 #1: doc↔doc]
    ↓ [Pre-mortem 가드: blocking Tiger 미해결 시 Phase 2 진입 금지]
Phase 2: Implementation ── Claude 직접 구현 + TDD
    ↓ [일관성 검사 #2: doc↔code]
Phase 3: Code Review ──── codex 리뷰 + Claude 수정
    ↓ [일관성 검사 #3: code quality]
Phase 4: Verification ─── 최종 검증 + 폴리싱 + Launch Readiness
    ↓
<promise>FULL_AUTO_COMPLETE</promise>
```

## Ralph Loop 자동 설정 (최우선 실행)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "FULL_AUTO_COMPLETE" ".claude-full-auto-progress.json"
```

### Ralph Loop 완료 조건

`<promise>FULL_AUTO_COMPLETE</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-full-auto-progress.json`의 모든 steps status가 `completed`
2. `.claude-full-auto-progress.json`의 `dod` 체크리스트가 모두 checked
3. `.claude-verification.json`의 모든 검증 항목이 통과 (build/typeCheck/lint/test는 `exitCode: 0`, secretScan/artifactCheck/smokeCheck/designPolish는 `result: "pass"` 또는 `result: "skip"` 또는 `result: "soft_fail"`)
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 한 iteration에서 **한 Phase의 일부 작업**만 처리
- Phase 0/1: 1~2개 문서 처리
- Phase 2: 1~2개 문서 또는 3~5개 티켓
- Phase 3: 1 리뷰 라운드
- Phase 4: 두 그룹으로 분할 가능 — Group A(Step 4-1~4-4), Group B(Step 4-5~4-7)
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 토큰 절약 스크립트 활용

```bash
# Progress 초기화
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "프로젝트명" "요구사항" --progress-file .claude-full-auto-progress.json
# 현재 상태 확인
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status --progress-file .claude-full-auto-progress.json
# Phase 전이
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 completed --progress-file .claude-full-auto-progress.json
# 품질 게이트/시크릿/아티팩트/스모크/E2E/에러기록/문서일관성/문서코드체크/디자인폴리싱
# → shared-gate.sh의 각 서브커맨드 사용
```

## 복구 감지 (0단계 전 실행)

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 `.claude-full-auto-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**
1. 파일 읽기 (schemaVersion 마이그레이션은 shared-gate.sh가 자동 처리)
2. `handoff` 필드를 최우선으로 확인 → 이전 iteration 맥락 복구
3. `handoff.currentPhase`로 현재 Phase 확인
4. 해당 Phase의 진행 상태에 따라 재개
5. 모든 steps가 `completed`면 → Phase 4(최종 검증)로 이동

**파일이 없는 경우 (신규):**
- Phase 0부터 정상 시작

---

## Phase 전이 오케스트레이션

### Phase 0 → Phase 1

```
Progress 초기화 (Phase 0 진입 전 — $ARGUMENTS에서 프로젝트명과 요구사항을 추출하여 전달):
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<$ARGUMENTS에서 추출한 프로젝트명>" "<$ARGUMENTS 원문>" --progress-file .claude-full-auto-progress.json
Phase 0 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/pm-planning/SKILL.md
Phase 0 스킬의 Step 0-0 ~ 0-10 수행 (Step 0-11은 outputs 기록만, init 없음)
Phase 0 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_0 completed --progress-file .claude-full-auto-progress.json
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 in_progress --progress-file .claude-full-auto-progress.json
```

### Phase 1 → Phase 2 (Pre-mortem 가드 포함)

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

  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_1 completed --progress-file .claude-full-auto-progress.json
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 in_progress --progress-file .claude-full-auto-progress.json
  (shared-gate.sh의 update-phase에서도 이중 검사: blocking Tiger 미해결 시 exit 1)
```

### Phase 2 → Phase 3

```
Phase 2 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/implementation/SKILL.md
Phase 2 스킬의 Step 2-1 ~ 2-7 수행
Phase 2 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_2 completed --progress-file .claude-full-auto-progress.json
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 in_progress --progress-file .claude-full-auto-progress.json
```

DoD: `"dod.all_code_implemented": { "checked": true, "evidence": "모든 문서 구현 + doc-code 일관성 검사 통과" }`

### Phase 3 → Phase 4

```
Phase 3 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/code-review/SKILL.md
Phase 3 스킬의 Step 3-1 ~ 3-4 수행
Phase 3 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_3 completed --progress-file .claude-full-auto-progress.json
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 in_progress --progress-file .claude-full-auto-progress.json
```

DoD: `"dod.code_review_pass": { "checked": true, "evidence": "N라운드 리뷰 완료, CRITICAL/HIGH: 0" }`

### Phase 4 → 완료

```
Phase 4 진입 → Read ${CLAUDE_PLUGIN_ROOT}/skills/verification/SKILL.md
Phase 4 스킬의 Step 4-1 ~ 4-7 수행
Phase 4 완료 시:
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_4 completed --progress-file .claude-full-auto-progress.json

모든 steps completed + DoD 전체 checked + verification 통과 확인 후:
<promise>FULL_AUTO_COMPLETE</promise>
```

---

## Handoff (Iteration 종료 전 필수)

`.claude-full-auto-progress.json`의 `handoff` 필드를 반드시 업데이트:

```json
"handoff": {
  "lastIteration": 3,
  "currentPhase": "phase_2",
  "completedInThisIteration": "Phase 2: auth.md, user-profile.md 구현 완료",
  "nextSteps": "Phase 2: post.md 구현 시작",
  "keyDecisions": ["JWT + refresh token 방식 확정"],
  "warnings": "rate limiting 미구현",
  "currentApproach": ""
}
```

## 컨텍스트 관리 (Prompt Too Long 방지)

| 조건 | 트리거 |
|------|--------|
| 단일 Phase 내 작업 12턴 이상 | `/compact` |
| "prompt too long" 에러 | 즉시 `/compact` |
| Phase 전환 시 | `/compact` |
| 문서 완료 후 | 다음 문서 시작 전 `/compact` |

## 사용자 개입 시점 (최소화)

**허용된 질문 시점 (Phase 0에서만):** 프로젝트 계획 승인/수정
**예외적 허용:** L5 에스컬레이션 도달, 외부 서비스 API 키 입력 필요
**금지된 질문:** "다음 Phase로 진행할까요?" 등 확인성 질문

## 강제 규칙 (절대 위반 금지)

1. **자동 진행**: Phase 간, 문서 간 사용자 확인 없이 자동 진행
2. **단일 in_progress**: 동시에 하나의 문서만 `in_progress` 상태
3. **완료 전 진행 금지**: `in_progress` 작업이 `completed` 되기 전 다음 작업 시작 금지
4. **스킵 금지**: 어떤 이유로도 `pending` 작업을 건너뛰지 않음
5. **중간 종료 금지**: 모든 Phase가 `completed` 될 때까지 종료하지 않음
6. **상태 파일 동기화**: 상태 변경 시 반드시 progress 파일 업데이트
7. **질문 금지**: Phase 0과 예외 상황 외에는 AskUserQuestion 절대 사용 금지
8. **자체 탐색**: codex에게 파일 경로를 전달하여 직접 읽도록 함
9. **handoff 필수**: 매 iteration 종료 시 handoff 필드 업데이트
10. **스크립트 우선**: 구조적/기계적 검사는 `shared-gate.sh`로 먼저 실행

## 포기 방지 규칙 (강제)

**강제 행동 (레벨별 에스컬레이션):**
- L0 즉시 수정 (3회) → L1 다른 방법 (3회) → L2 codex 분석 → L3 다른 접근법 (3회) → L4 범위 축소 → L5 사용자 개입
- 각 레벨에서 예산만큼 시도 후 다음 레벨로 자동 에스컬레이트
- 범위 축소는 핵심 경로(인증, CRUD 기본, 빌드) 제외
- 모든 Phase 완료까지 계속 진행

**원칙:** L5(사용자 개입) 전까지 스스로 해결. 모든 Phase가 완료될 때까지 멈추지 않음.
