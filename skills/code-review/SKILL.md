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
3. progress 파일에서 `phases.phase_2.documents[].acceptanceCriteria` 로드 (있으면 codex 프롬프트에 포함)
4. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티

### Step 3-2: codex-cli 리뷰 라운드

각 라운드에서:

1. **codex-cli에 리뷰 요청**
   ```bash
   codex exec --skip-git-repo-check '## 코드 리뷰 Round N

   ### 리뷰 관점 (6가지 + SEC 서브카테고리)
   1. SEC (보안): 아래 서브카테고리별로 분류하여 보고
      - SEC-INJ: SQL/NoSQL/Command injection, OS command injection
      - SEC-XSS: Cross-site scripting, 미이스케이프 출력
      - SEC-AUTH: 인증/인가 우회, 세션 관리 미흡
      - SEC-TOCTOU: Time-of-check to time-of-use race condition
      - SEC-LLM: LLM 출력을 DB/shell/eval에 직접 전달하는 패턴
      - SEC-CRYPTO: truncation vs hashing, MD5/SHA1 사용, 하드코딩 salt
      - SEC-TYPE: JS `==` vs `===`, PHP loose comparison 등 type coercion
      - SEC-RACE: 동시성 race condition (find_or_create without unique index 등)
      - SEC-TIME: 토큰 만료, 세션 관리 타이밍 이슈
      - SEC-SECRET: 시크릿/API키 노출, 하드코딩 자격증명
   2. ERR (에러 처리): 미처리 예외, 에러 전파, 복구 로직
   3. DATA (데이터 무결성): 검증 누락, 레이스 컨디션, 일관성
   4. PERF (성능): N+1 쿼리, 메모리 누수, 불필요한 연산
   5. CODE (코드 품질): 중복, 복잡도, 네이밍, 설계 패턴
   6. E2E (E2E 테스트 품질):
      - E2E 시나리오가 SPEC.md의 핵심 유저스토리를 커버하는가
      - 테스트 독립성 (상태 공유 없음)
      - 셀렉터 안정성 (data-testid > semantic > text)
      - mock/seed 데이터가 실제 스키마에서 파생되었는가
      - 외부 서비스만 모킹 (자체 백엔드는 실제 사용)

   ### 리뷰 대상 파일
   [파일 경로 목록 — 직접 읽고 검토]

   ### 리뷰 원칙 (회의적 리뷰어 역할)
   - 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
   - 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라. 수정이 불완전하거나 새로운 문제를 도입했을 수 있다.
   - 의심스러우면 severity를 한 단계 높게 판정하라. 과소평가보다 과대평가가 안전하다.
   - "이 정도면 괜찮다"는 판단을 경계하라. 프로덕션에서 장애를 일으킬 코드를 찾는 것이 목표다.

   ### 심각도 판정 기준 (Few-shot 참고)
   **CRITICAL 예시**: `db.query("SELECT * FROM users WHERE id = " + userId)` → SEC-INJ (SQL injection)
   **HIGH 예시**: `catch(e) {}` 빈 catch 블록 → ERR (에러 무시)
   **MEDIUM 예시**: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF (대량 데이터)
   **LOW 예시**: 함수명 `getData`가 구체적이지 않음 → CODE (네이밍)

   ### 출력 형식
   각 발견을 아래 형식으로 출력:
   ### {CATEGORY}-{SEVERITY}-{번호}: {제목}
   - 파일: {경로}
   - 라인: {줄번호}
   - 설명: {문제 상세}
   - 권장: {수정안}
   finding 없으면 "NO_FINDINGS".
   마지막 줄: FINDING_COUNT: N
   '
   ```

2. **Claude Code가 codex 피드백 분석**
   - Critical/High: 즉시 수정
   - Medium: 즉시 수정 (스킵 금지)
   - Low: 합리적이면 수용, 과도하면 구체적 사유와 함께 스킵 (사유 기록 필수)

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
    {
      "round": 1,
      "critical": 0, "high": 2, "medium": 3, "low": 1,
      "fixed": 5,
      "dismissed": 1,
      "dismissedDetails": [
        { "id": "CODE-LOW-003", "reason": "테스트 파일의 의도적 매직넘버, 프로덕션 코드 아님" }
      ]
    }
  ]
}
```

### Step 3-2.5: Suppression List 적용

리뷰 시 `.claude-review-suppressions.json` 파일이 존재하면 로드하여 적용:

1. **로드**: 파일에서 만료되지 않은(생성일+30일 이내) suppression 항목 로드
2. **매칭**: 각 finding에 대해 `file` + `category` + `keyword` 패턴 매칭
3. **적용**: 매칭된 finding은 자동 dismissed (reason: "suppressed")
4. **보고**: 라운드 결과에 suppressed 건수 포함
5. **만료**: 30일 경과한 항목은 자동 제거 (재검토 유도)

**파일 형식** (`.claude-review-suppressions.json`):
```json
[
  {
    "file": "src/legacy/auth.ts",
    "category": "SEC",
    "keyword": "loose comparison",
    "reason": "레거시 코드, 다음 스프린트에서 마이그레이션 예정",
    "createdAt": "2026-03-01T00:00:00Z",
    "expiresAt": "2026-03-31T00:00:00Z"
  }
]
```

### Step 3-3: 리뷰 완료 조건

- Critical/High/Medium 발견이 모두 0개 (라운드 제한 없음, 0개 될 때까지 반복)
- 품질 게이트 통과
- E2E 게이트 통과 (`phases.phase_2.e2e.applicable == true`인 경우에만, 최종 라운드에서 실행):
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json
  ```
  applicable이 false/null이면 E2E 게이트 스킵. E2E 실패 시: 수정 후 e2e-gate만 재실행 (코드 리뷰 재실행 불필요)

### Step 3-4: Phase 3 완료

1. 코드 품질 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```
2. DoD 업데이트: `code_review_pass.checked = true`, evidence에 "N라운드 리뷰 완료, CRITICAL/HIGH/MEDIUM: 0"
3. Phase 전이는 오케스트레이터가 수행

### Iteration 관리

- 한 iteration에서 1 리뷰 라운드만 처리
- 라운드 완료 후 handoff 업데이트하고 자연스럽게 종료
