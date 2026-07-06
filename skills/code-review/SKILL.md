# Phase 3: Code Review

Loaded by the full-auto orchestrator at Phase 3 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 2 완료 (모든 코드 구현 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 3 절차

### Step 3-1: 리뷰 범위 결정

1. 구현된 전체 코드를 리뷰 범위로 설정
2. progress 파일에서 `phases.phase_2.completedFiles` 확인
3. progress 파일에서 `phases.phase_2.documents[].acceptanceCriteria` 로드 (있으면 codex 프롬프트에 포함)
4. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티
5. **UX Reviewer 조건 확인**: overview.md에서 `projectScope.hasFrontend`를 확인하여 true이면 Step 3-2에서 UX Reviewer Agent를 codex 리뷰와 병렬로 호출

### Step 3-1.5: UX Reviewer Agent (조건부)

`projectScope.hasFrontend=true`일 때만 실행:

- Agent tool로 `ux-reviewer` 에이전트를 **codex 리뷰(Step 3-2)와 병렬로** 호출
- 프론트엔드 코드 파일 목록과 overview.md 경로를 프롬프트에 포함
- 결과: UX Review Report (정보 구조, 인터랙션, 접근성, 반응형, 일관성 + UX_SCORE)
- UX findings는 codex findings와 동일한 형식 (UX-A11Y-HIGH-001 등)으로 통합 관리
- CRITICAL/HIGH UX findings는 코드 리뷰 findings와 동일하게 즉시 수정 대상

### Step 3-2: codex-cli 리뷰 라운드

각 라운드에서:

1. **codex-cli에 리뷰 요청**

   > 리뷰 관점·리뷰 원칙·심각도 기준·Few-shot 예시·출력 형식은 `${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md`를 단일 출처로 따른다.
   > 호출 전에 이 파일을 Read하고, 아래 호출 블록의 자리 표시자에 다음을 삽입한다:
   > - `{리뷰 관점 블록}` ← "리뷰 관점 (전체)" 섹션 전체 (full-auto Phase 3이므로 IMPL/E2E 포함)
   > - `{리뷰 규칙 블록}` ← "리뷰 원칙 (회의적 리뷰어 역할)" + "심각도 기준" + "심각도 판정 기준 (Few-shot 참고)" + "Finding 출력 형식" 섹션 내용

   ```bash
   codex exec --skip-git-repo-check '## 코드 리뷰 Round N

   {리뷰 관점 블록}

   ### 리뷰 대상 파일
   [파일 경로 목록 — 직접 읽고 검토]

   {리뷰 규칙 블록}
   '
   ```

2. **Claude Code가 codex 피드백 분석 및 수정**

   > 공통 리뷰 규칙은 아래 파일을 Read하여 적용합니다.
   > Read ${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md

   Finding 검증, severity별 수정 처리, 품질 게이트 재실행, 라운드 결과 기록, Suppression List, 리뷰 완료 조건, Phase 3 완료, Iteration 관리 모두 위 템플릿을 따릅니다.

3. **자동 커밋** (품질 게이트 통과 시):
   ```bash
   git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N 수정 완료"
   ```

4. **다음 라운드** 또는 완료 판단
