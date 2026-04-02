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

### Step 3-2: 다관점 순차 리뷰 (Claude 솔로)

각 라운드에서 외부 AI 없이 Claude가 **관점별 순차 패스**로 리뷰합니다. 각 패스에서 다른 관점은 의도적으로 무시합니다.

**라운드 2+**: `git diff --name-only`로 변경된 파일만 리뷰 범위로 사용. 이전 finding 목록은 **참고용으로만** 포함 (범위 제한 금지). 새로운 이슈도 반드시 보고.

#### Pass 1: 보안 + 에러 처리 전문가

지금부터 당신은 **보안 및 에러 처리 전문가**입니다. 다른 관점(성능, 코드 품질, 구현 완성도)은 무시하세요.
Read 도구로 리뷰 대상 파일을 직접 읽고 다음만 검토:

1. **SEC (보안)**: 아래 서브카테고리별로 분류하여 보고
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
2. **ERR (에러 처리)**: try-catch 누락, 에러 응답 불일치, 에지 케이스 미처리, 에러 전파, 복구 로직

**리뷰 원칙 (회의적 리뷰어 역할)**:
- 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
- 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라. 수정이 불완전하거나 새로운 문제를 도입했을 수 있다.
- 의심스러우면 severity를 한 단계 높게 판정하라. 과소평가보다 과대평가가 안전하다.
- "이 정도면 괜찮다"는 판단을 경계하라. 프로덕션에서 장애를 일으킬 코드를 찾는 것이 목표다.

**심각도 기준**:
- CRITICAL: 보안 취약점, 데이터 손실 가능, 심각한 성능 문제
- HIGH: 주요 버그, 에러 처리 누락, N+1 쿼리, 주요 패턴 위반
- MEDIUM: 잠재적 문제, 일관성 위반, 잠재적 성능 문제
- LOW: 사소한 개선, 스타일, 사소한 최적화

**심각도 판정 기준 (Few-shot 참고)**:
- **CRITICAL 예시**: `db.query("SELECT * FROM users WHERE id = " + userId)` → SEC-INJ (SQL injection)
- **HIGH 예시**: `catch(e) {}` 빈 catch 블록 → ERR (에러 무시)

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록.

#### Pass 2: 데이터 + 성능 전문가

지금부터 당신은 **데이터 일관성 및 성능 전문가**입니다. 보안/에러는 이미 검토했으니 무시하세요.
동일 파일을 다시 Read 도구로 읽고 다음만 검토:

3. **DATA (데이터 무결성)**: 검증 누락, 트랜잭션 불일치, 스키마 불일치, 레이스 컨디션, 일관성
4. **PERF (성능)**: N+1 쿼리, 불필요한 연산, 대량 데이터 미처리, 메모리 누수, 불필요한 DB 호출

**리뷰 원칙 (회의적 리뷰어 역할)**:
- 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
- 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라.
- 의심스러우면 severity를 한 단계 높게 판정하라.

**심각도 판정 기준 (Few-shot 참고)**:
- **MEDIUM 예시**: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF (대량 데이터)

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록. 번호는 Pass 1에서 이어서 부여.

#### Pass 3: SPEC 대조 + 코드 품질 전문가

지금부터 당신은 **SPEC 준수 및 코드 품질 전문가**입니다. 보안/에러/데이터/성능은 이미 검토했으니 무시하세요.
SPEC.md (또는 docs/api-spec.md)가 존재하면 먼저 읽고, 코드와 1:1 대조:

5. **CODE (코드 품질)**: 중복, 복잡도, 네이밍, 패턴 불일치, 컨벤션 위반, 타입 안전성 부족, 미사용 코드
6. **IMPL (구현 완성도)**: SPEC.md를 읽고 각 API 엔드포인트/페이지에 대해 검증
   - IMPL-STUB: 빈 함수 body, placeholder 응답 (res.json({}), return null이 유일 로직인 핸들러)
   - IMPL-SCHEMA: SPEC.md API 스키마와 불일치하는 요청/응답 구조 (필드 누락, 타입 불일치)
   - IMPL-MISSING: SPEC에 정의됐지만 코드에 미구현된 엔드포인트/페이지/컴포넌트
   - IMPL-HARDCODE: 하드코딩된 mock 데이터가 프로덕션 코드에 존재 (테스트 파일 제외)
   - IMPL-FLOW: 핵심 플로우(회원가입→로그인→프로필 등)의 연결이 실제로 작동하지 않음
7. **E2E (E2E 테스트 품질)**:
   - E2E 시나리오가 SPEC.md의 핵심 유저스토리를 커버하는가
   - 테스트 독립성 (상태 공유 없음)
   - 셀렉터 안정성 (data-testid > semantic > text)
   - mock/seed 데이터가 실제 스키마에서 파생되었는가
   - 외부 서비스만 모킹 (자체 백엔드는 실제 사용)

**리뷰 원칙 (회의적 리뷰어 역할)**:
- 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
- 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라.
- 의심스러우면 severity를 한 단계 높게 판정하라.

**심각도 판정 기준 (Few-shot 참고)**:
- **CRITICAL 예시**: SPEC에 정의된 `/auth/register` 엔드포인트가 코드에 없음 → IMPL-MISSING
- **HIGH 예시**: `app.get('/users', (req, res) => res.json({}))` 빈 응답 반환 → IMPL-STUB
- **HIGH 예시**: SPEC에 `{id, name, email}` 응답인데 코드는 `{success: true}`만 반환 → IMPL-SCHEMA
- **MEDIUM 예시**: `const users = [{name: "John"}]` 하드코딩 mock 데이터 → IMPL-HARDCODE
- **LOW 예시**: 함수명 `getData`가 구체적이지 않음 → CODE (네이밍)

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록. 번호는 Pass 2에서 이어서 부여.

#### 패스 결과 합산

각 패스의 finding을 합산하여 전체 finding 목록을 생성합니다.
각 finding의 출력 형식:
```
### {CATEGORY}-{SEVERITY}-{번호}: {제목}
- 파일: {경로}
- 라인: {줄번호}
- 설명: {문제 상세}
- 권장: {수정안}
```
finding 없으면 "NO_FINDINGS".
마지막에 `FINDING_COUNT: N` 기록.

### Step 3-2 continued: Claude Code가 finding 분석 및 수정

1. **Finding 검증**: 각 finding에 대해 Read 도구로 해당 파일의 해당 라인을 직접 읽고 판정
   - **Confirmed**: 실제 문제. severity 조정 가능.
   - **Dismissed**: false positive, 의도된 설계 → 구체적 기각 사유를 roundResults.dismissedDetails에 기록 (필수)

2. **라운드 간 Finding 매칭 (라운드 2+)**:
   - 동일 파일 + 라인 범위 겹침(±5줄) + 문제 유형 유사 → 같은 finding
   - 이전 `open` → 이번 미발견 → `fixed`
   - 이전 `fixed` → 이번 재발견 → `regressed`
   - 이번 신규 → `new` (status: `open`)

3. **수정**:
   - Critical/High: 즉시 수정
   - Medium: 즉시 수정 (스킵 금지)
   - Low: 합리적이면 수용, 과도하면 구체적 사유와 함께 스킵 (사유 기록 필수)

4. **수정 후 품질 게이트 재실행**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```

5. **자동 커밋** (품질 게이트 통과 시):
   ```bash
   git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N (solo) 수정 완료"
   ```

6. **다음 라운드** 또는 완료 판단

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

- Critical/High/Medium 발견이 모두 0개 (라운드 제한 없음, 0개 될 때까지 반복). 특히 IMPL-MISSING-CRITICAL, IMPL-STUB-HIGH는 반드시 수정 필요.
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
