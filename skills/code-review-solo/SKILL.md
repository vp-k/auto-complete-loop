# Phase 3: Code Review (Solo Multi-Perspective)

Loaded by the full-auto-solo orchestrator at Phase 3 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 2 완료 (모든 코드 구현 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 3 절차

### Step 3-1: 리뷰 범위 결정

1. 구현된 전체 코드를 리뷰 범위로 설정
2. progress 파일에서 `phases.phase_2.completedFiles` 확인
3. progress 파일에서 `phases.phase_2.documents[].acceptanceCriteria` 로드 (있으면 리뷰 프롬프트에 포함)
4. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티

### Step 3-2: 다관점 병렬 리뷰 (Claude 서브에이전트 3개)

각 라운드에서 외부 AI 없이 **Claude 서브에이전트 3개를 병렬로** 띄워 관점별 리뷰를 수행합니다. 각 에이전트는 담당 관점만 검토하고 다른 관점은 의도적으로 무시합니다. 패스 간 데이터 의존성이 없으므로 병렬 실행이 안전합니다.

> 리뷰 관점(서브카테고리 정의)·리뷰 원칙·심각도 기준·Few-shot 예시·출력 형식은 `${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md`를 단일 출처로 따른다. (관점 분할은 "관점 분할 가이드" 섹션 참조)

**라운드 2+**: `git diff --name-only`로 변경된 파일만 리뷰 범위로 사용. 이전 finding 목록은 **참고용으로만** 포함 (범위 제한 금지). 새로운 이슈도 반드시 보고.

#### 병렬 실행 방법

**Agent 툴로 3개 서브에이전트를 한 메시지에서 동시에 호출**합니다 (한 메시지 다중 호출로 병렬 실행 충족; `run_in_background` 파라미터는 지원되는 환경에서만 추가). 각 에이전트 프롬프트에 다음을 반드시 포함:

1. **담당 관점 페어** (아래 표 참조) — "다른 관점은 무시하라" 지시 포함
2. **리뷰 scope**: 파일 목록(라운드 2+는 git diff 목록) 또는 자연어 scope
3. **기준 로드 지시**: `${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md`를 Read하여 "리뷰 관점 (전체)"에서 담당 카테고리 정의를, "리뷰 원칙 (회의적 리뷰어 역할)"·"심각도 기준"·"심각도 판정 기준 (Few-shot 참고)"·"Finding 출력 형식"을 기준으로 삼을 것
   - ⚠️ 서브에이전트는 `${CLAUDE_PLUGIN_ROOT}` 변수를 해석하지 못한다 — 프롬프트에 넣을 때 반드시 **절대 경로로 치환**하여 전달할 것
4. **finding 출력 형식**: `{CATEGORY}-{SEVERITY}-{번호}` 형식, 카테고리별 001부터 부여 (에이전트마다 관점 prefix가 다르므로 번호 충돌 없음)

| 에이전트 | 역할 | 담당 관점 |
|----------|------|-----------|
| Agent 1 | 보안 + 에러 처리 전문가 | **SEC** (서브카테고리별 분류) + **ERR** |
| Agent 2 | 데이터 일관성 + 성능 전문가 | **DATA** + **PERF** |
| Agent 3 | SPEC 준수 + 코드 품질 전문가 | **CODE** + **IMPL** (+ **E2E**) — SPEC.md(또는 docs/api-spec.md) 존재 시 먼저 읽고 코드와 1:1 대조. SPEC 부재 시 CODE만 |

#### 결과 병합 (메인 Claude 수행)

3개 에이전트 완료 후 메인 Claude가 결과를 병합합니다:

1. 세 에이전트의 finding을 합산하여 전체 finding 목록 생성
2. **중복 판정**: 같은 파일 + 라인 범위 겹침(±5줄) + 문제 유형 유사 → 하나의 finding으로 통합, 더 높은 severity 채택, 양쪽 설명 병합
3. 이후 검증(Confirmed/Dismissed) 단계는 기존과 동일하게 진행 (Step 3-2 continued)

#### 폴백: 순차 3-pass (Agent 툴 사용 불가 시)

Agent 툴을 사용할 수 없는 환경에서는 기존 순차 3-pass로 수행합니다. 위 표와 동일한 관점 분할로, 메인 Claude가 각 패스에서 해당 전문가 역할을 맡아 순서대로 실행:

- **Pass 1** (SEC+ERR) → **Pass 2** (DATA+PERF) → **Pass 3** (CODE+IMPL, +E2E — SPEC.md 존재 시)
- 각 패스 시작 전 `review-perspectives.md`를 Read하여 해당 카테고리 정의와 공통 규칙 적용. 각 패스에서 다른 관점은 무시
- 출력 형식은 병렬 실행과 동일 (`{CATEGORY}-{SEVERITY}-{번호}`, 카테고리별 001부터)
- 패스 결과를 합산하여 전체 finding 목록 생성 (병합 규칙 동일)

### Step 3-2 continued: Claude Code가 finding 분석 및 수정

> 공통 리뷰 규칙은 아래 파일을 Read하여 적용합니다.
> Read ${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md

Finding 출력 형식, 검증, severity별 수정 처리, 품질 게이트 재실행, 라운드 결과 기록, Suppression List, 리뷰 완료 조건, Phase 3 완료, Iteration 관리 모두 위 템플릿을 따릅니다.

**자동 커밋** (품질 게이트 통과 시):
```bash
git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N (solo) 수정 완료"
```
