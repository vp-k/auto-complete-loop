# 오케스트레이션 공통 규칙

이 파일은 full-auto 계열 오케스트레이터(`full-auto`, `full-auto-teams` 등)의 공통 규칙입니다.
각 오케스트레이터가 `Read`로 로드하며, 커맨드별 차별화 항목은 `{파라미터}`로 표시합니다.

## 파라미터 (오케스트레이터에서 정의)

| 파라미터 | 설명 | full-auto | full-auto-teams |
|----------|------|-----------|-----------------|
| `{PROMISE_TAG}` | Ralph Loop 완료 promise | FULL_AUTO_COMPLETE | FULL_AUTO_TEAMS_COMPLETE |
| `{PROGRESS_FILE}` | 진행 상태 파일 | .claude-full-auto-progress.json | .claude-full-auto-progress.json |
| `{PHASE_3_SKILL}` | Phase 3 스킬 파일 | skills/code-review/SKILL.md | skills/team-code-review/SKILL.md |

## Ralph Loop 자동 설정 (최우선 실행)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "{PROMISE_TAG}" "{PROGRESS_FILE}"
```

### Ralph Loop 완료 조건

`<promise>{PROMISE_TAG}</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `{PROGRESS_FILE}`의 모든 steps status가 `completed`
2. `{PROGRESS_FILE}`의 `dod` 체크리스트가 모두 checked
3. `.claude-verification.json`의 모든 검증 항목이 통과:
   - build/typeCheck/lint/test: `exitCode: 0`
   - secretScan/artifactCheck/designPolish: `result: "pass"` 또는 `result: "skip"` 또는 `result: "soft_fail"`
   - **smokeCheck**: `result: "pass"` 또는 `result: "skip"` (**`soft_fail`과 `fail`은 모두 불합격** — 서버가 기동되지 않으면 완주 불가)
     - `skip`은 서버가 불필요한 프로젝트(라이브러리, CLI, serverless)에서만 허용
     - `soft_fail`(서버 기동 실패) 및 `fail`(--strict 모드 하드 실패)은 반드시 해결 후 `pass`로 전환해야 함
   - **통합 검증 게이트** (Phase 4 Step 4-6.5에서 실행, 모두 exit 0이어야 함):
     - `placeholder-check`: TODO/placeholder/FIXME 잔존 0건
     - `external-service-check`: SPEC.md 명시 외부 서비스의 SDK/config 존재
     - `service-test-check`: `hasBackend=true` 시 서비스/라우트 테스트 파일 존재
     - `integration-smoke`: `hasFrontend+hasBackend` 시 연동 검증 (API URL, CORS, 서버 기동) 통과
4. 구현 품질 게이트 확인:
   - `implementation-depth`: 소스 stub 5건 미만 (SOFT — 5건 이상이면 수정 권장)
   - `functional-flow`: smoke 스크립트 통과 (존재 시, SKIP 허용)
   - `test-quality`: assertion 비율 ≥ 70%, skip 비율 ≤ 20% (SOFT)
5. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 한 iteration에서 **한 Phase의 일부 작업**만 처리
- Phase 0/1: 1~2개 문서 처리
- Phase 2: 1~2개 문서 또는 3~5개 티켓
- Phase 3: 1 리뷰 라운드 (커맨드별 상세는 오케스트레이터 파일 참조)
- Phase 4: 두 그룹으로 분할 가능 — Group A(Step 4-1~4-4), Group B(Step 4-5~4-7)
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

## 토큰 절약 스크립트 활용

```bash
# Progress 초기화
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "프로젝트명" "요구사항" --progress-file {PROGRESS_FILE}
# 현재 상태 확인
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status --progress-file {PROGRESS_FILE}
# Phase 전이
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-phase phase_N completed --progress-file {PROGRESS_FILE}
# 품질 게이트/시크릿/아티팩트/스모크/E2E/에러기록/문서일관성/문서코드체크/디자인폴리싱
# → shared-gate.sh의 각 서브커맨드 사용

# 구현 품질 게이트 (Phase 2 문서 완료 후 + Phase 4에서 실행)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh implementation-depth --progress-file {PROGRESS_FILE}
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh test-quality --progress-file {PROGRESS_FILE}
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh functional-flow --progress-file {PROGRESS_FILE}
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh page-render-check --progress-file {PROGRESS_FILE}
```

## 구현 품질 게이트 실행 시점

| 게이트 | Phase 2 (문서별) | Phase 4 |
|--------|-----------------|---------|
| `implementation-depth` | 각 문서 구현 완료 후 | Step 4-1.7 |
| `functional-flow` | — (smoke 스크립트 없을 수 있음) | Step 4-1.8 |
| `test-quality` | — | Step 4-1.9 |
| `page-render-check` | — | Step 4-5 (hasFrontend=true 시) |

**Phase 2 규칙**: 문서 구현 완료 후 `implementation-depth` 실행. 5건 이상이면 즉시 수정 후 재실행 (다음 문서로 넘어가지 않음).

**Phase 2 smoke 검증**: `tests/api-smoke.sh` 존재 시, 해당 문서의 API 엔드포인트를 서버 시작 후 curl로 검증. 응답이 빈 객체/빈 배열이면 수정 필요.

**Phase 4 규칙**: Step 4-1 (quality-gate) 직후 Step 4-1.7/4-1.8/4-1.9 순서로 실행. SOFT gate이므로 WARN은 진행 가능, FAIL은 수정 필요.

## 복구 감지 (0단계 전 실행)

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

스킬 시작 시 `{PROGRESS_FILE}` 파일 확인:

**파일이 존재하는 경우 (재시작):**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh recover --progress-file {PROGRESS_FILE}
```
스크립트가 자동으로 현재 Phase, handoff 정보, 미완료 DoD, 다음 행동을 출력합니다.
출력된 `Next Steps`를 따라 재개합니다.
(커맨드별 Phase 3 특화 처리는 오케스트레이터 참조)

**파일이 없는 경우 (신규):**
- Phase 0부터 정상 시작

## Handoff (Iteration 종료 전 필수)

스크립트로 handoff 필드를 일괄 갱신:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh handoff-update \
  --progress-file {PROGRESS_FILE} \
  --phase "phase_2" \
  --iteration 3 \
  --completed "Phase 2: auth.md, user-profile.md 구현 완료" \
  --next-steps "Phase 2: post.md 구현 시작" \
  --decision "JWT + refresh token 방식 확정" \
  --warnings "rate limiting 미구현" \
  --approach ""
```

**필수 옵션**: `--next-steps` (최소 이것만 있어도 동작)
**선택 옵션**: `--phase`, `--completed`, `--iteration`, `--decision` (복수 가능), `--warnings`, `--approach`

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

## 강제 규칙 (오케스트레이터 전용 — 절대 위반 금지)

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
