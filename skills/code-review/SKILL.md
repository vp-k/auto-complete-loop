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
   7. IMPL (구현 완성도): SPEC.md를 읽고 각 API 엔드포인트/페이지에 대해 검증
      - IMPL-STUB: 빈 함수 body, placeholder 응답 (res.json({}), return null이 유일 로직인 핸들러)
      - IMPL-SCHEMA: SPEC.md API 스키마와 불일치하는 요청/응답 구조 (필드 누락, 타입 불일치)
      - IMPL-MISSING: SPEC에 정의됐지만 코드에 미구현된 엔드포인트/페이지/컴포넌트
      - IMPL-HARDCODE: 하드코딩된 mock 데이터가 프로덕션 코드에 존재 (테스트 파일 제외)
      - IMPL-FLOW: 핵심 플로우(회원가입→로그인→프로필 등)의 연결이 실제로 작동하지 않음

   ### 리뷰 대상 파일
   [파일 경로 목록 — 직접 읽고 검토]

   ### 리뷰 원칙 (회의적 리뷰어 역할)
   - 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
   - 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라. 수정이 불완전하거나 새로운 문제를 도입했을 수 있다.
   - 의심스러우면 severity를 한 단계 높게 판정하라. 과소평가보다 과대평가가 안전하다.
   - "이 정도면 괜찮다"는 판단을 경계하라. 프로덕션에서 장애를 일으킬 코드를 찾는 것이 목표다.

   ### 심각도 판정 기준 (Few-shot 참고)
   **CRITICAL 예시**: `db.query("SELECT * FROM users WHERE id = " + userId)` → SEC-INJ (SQL injection)
   **CRITICAL 예시**: SPEC에 정의된 `/auth/register` 엔드포인트가 코드에 없음 → IMPL-MISSING
   **HIGH 예시**: `catch(e) {}` 빈 catch 블록 → ERR (에러 무시)
   **HIGH 예시**: `app.get('/users', (req, res) => res.json({}))` 빈 응답 반환 → IMPL-STUB
   **HIGH 예시**: SPEC에 `{id, name, email}` 응답인데 코드는 `{success: true}`만 반환 → IMPL-SCHEMA
   **MEDIUM 예시**: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF (대량 데이터)
   **MEDIUM 예시**: `const users = [{name: "John"}]` 하드코딩 mock 데이터 → IMPL-HARDCODE
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

2. **Claude Code가 codex 피드백 분석 및 수정**

   > 공통 리뷰 규칙은 아래 파일을 Read하여 적용합니다.
   > Read ${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md

   Finding 검증, severity별 수정 처리, 품질 게이트 재실행, 라운드 결과 기록, Suppression List, 리뷰 완료 조건, Phase 3 완료, Iteration 관리 모두 위 템플릿을 따릅니다.

3. **자동 커밋** (품질 게이트 통과 시):
   ```bash
   git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N 수정 완료"
   ```

4. **다음 라운드** 또는 완료 판단
