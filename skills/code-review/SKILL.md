# Phase 3: Code Review (순수 리뷰 로직)

이 스킬은 full-auto 오케스트레이터에서 Phase 3 진입 시 Read로 로드됩니다.
Ralph/progress/promise 코드 없음 — 오케스트레이터가 관리.

## 전제 조건

- Phase 2 완료 (모든 코드 구현 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 3 절차

### Step 3-1: 리뷰 범위 결정

1. 구현된 전체 코드를 리뷰 범위로 설정
2. progress 파일에서 `phases.phase_2.completedFiles` 확인
3. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티

### Step 3-2: codex-cli 리뷰 라운드

각 라운드에서:

1. **codex-cli에 리뷰 요청**
   ```bash
   codex exec --skip-git-repo-check '## 코드 리뷰 Round N

   ### 리뷰 관점 (5가지)
   1. SEC (보안): 인젝션, XSS, 인증/인가 우회, 시크릿 노출
   2. ERR (에러 처리): 미처리 예외, 에러 전파, 복구 로직
   3. DATA (데이터 무결성): 검증 누락, 레이스 컨디션, 일관성
   4. PERF (성능): N+1 쿼리, 메모리 누수, 불필요한 연산
   5. CODE (코드 품질): 중복, 복잡도, 네이밍, 설계 패턴

   ### 리뷰 대상 파일
   [파일 경로 목록 — 직접 읽고 검토]

   ### 출력 형식
   각 발견을 Critical/High/Medium/Low로 분류.
   파일명:줄번호와 함께 구체적 수정 방안 제시.
   '
   ```

2. **Claude Code가 codex 피드백 분석**
   - Critical/High: 즉시 수정
   - Medium: 판단하여 수용 또는 사유와 함께 스킵
   - Low: 합리적이면 수용, 과도하면 스킵

3. **수정 후 품질 게이트 재실행**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```

4. **자동 커밋** (품질 게이트 통과 시):
   ```bash
   git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N 수정 완료"
   ```

5. **다음 라운드** 또는 완료 판단

progress 파일에 라운드 결과 기록:
```json
"phase_3": {
  "currentRound": 2,
  "roundResults": [
    { "round": 1, "critical": 0, "high": 2, "medium": 3, "low": 1, "fixed": 5, "skipped": 1 }
  ]
}
```

### Step 3-3: 리뷰 완료 조건

- Critical/High 발견이 0개
- 또는 3라운드 완료 후 신규 Critical/High 0개
- 품질 게이트 통과

### Step 3-4: Phase 3 완료

1. 코드 품질 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```
2. DoD 업데이트: `code_review_pass.checked = true`, evidence에 "N라운드 리뷰 완료, CRITICAL/HIGH: 0"
3. Phase 전이는 오케스트레이터가 수행

### Iteration 관리

- 한 iteration에서 1 리뷰 라운드만 처리
- 라운드 완료 후 handoff 업데이트하고 자연스럽게 종료
