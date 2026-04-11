# 코드 리뷰 공통 규칙

code-review, code-review-solo 스킬이 공유하는 규칙입니다.

## 리뷰 원칙 (회의적 리뷰어 역할)

- 첫 라운드에서는 최소 1개 이상의 개선점을 반드시 찾아라. 2라운드 이후에는 실제 문제가 없으면 "NO_FINDINGS" 보고 가능.
- 이전 라운드에서 "수정됨"으로 표시된 항목도 재검증하라. 수정이 불완전하거나 새로운 문제를 도입했을 수 있다.
- 의심스러우면 severity를 한 단계 높게 판정하라. 과소평가보다 과대평가가 안전하다.
- "이 정도면 괜찮다"는 판단을 경계하라. 프로덕션에서 장애를 일으킬 코드를 찾는 것이 목표다.

## 심각도 기준

- CRITICAL: 보안 취약점, 데이터 손실 가능, 심각한 성능 문제
- HIGH: 주요 버그, 에러 처리 누락, N+1 쿼리, 주요 패턴 위반
- MEDIUM: 잠재적 문제, 일관성 위반, 잠재적 성능 문제
- LOW: 사소한 개선, 스타일, 사소한 최적화

## 심각도 판정 기준 (Few-shot 참고)

- **CRITICAL 예시**: `db.query("SELECT * FROM users WHERE id = " + userId)` → SEC-INJ (SQL injection)
- **CRITICAL 예시**: SPEC에 정의된 `/auth/register` 엔드포인트가 코드에 없음 → IMPL-MISSING
- **HIGH 예시**: `catch(e) {}` 빈 catch 블록 → ERR (에러 무시)
- **HIGH 예시**: `app.get('/users', (req, res) => res.json({}))` 빈 응답 반환 → IMPL-STUB
- **HIGH 예시**: SPEC에 `{id, name, email}` 응답인데 코드는 `{success: true}`만 반환 → IMPL-SCHEMA
- **MEDIUM 예시**: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF (대량 데이터)
- **MEDIUM 예시**: `const users = [{name: "John"}]` 하드코딩 mock 데이터 → IMPL-HARDCODE
- **LOW 예시**: 함수명 `getData`가 구체적이지 않음 → CODE (네이밍)

## Finding 출력 형식

각 발견을 아래 형식으로 출력:
```
### {CATEGORY}-{SEVERITY}-{번호}: {제목}
- 파일: {경로}
- 라인: {줄번호}
- 설명: {문제 상세}
- 권장: {수정안}
```
finding 없으면 "NO_FINDINGS".
마지막 줄: `FINDING_COUNT: N`

## Finding 검증 (Claude Code 수행)

각 finding에 대해 Read 도구로 해당 파일의 해당 라인을 직접 읽고 판정:
- **Confirmed**: 실제 문제. severity 조정 가능.
- **Dismissed**: false positive, 의도된 설계 → 구체적 기각 사유를 roundResults.dismissedDetails에 기록 (필수)

## 라운드 간 Finding 매칭 (라운드 2+)

- 동일 파일 + 라인 범위 겹침(±5줄) + 문제 유형 유사 → 같은 finding
- 이전 `open` → 이번 미발견 → `fixed`
- 이전 `fixed` → 이번 재발견 → `regressed`
- 이번 신규 → `new` (status: `open`)

## Severity별 수정 처리

- Critical/High: 즉시 수정
- Medium: 즉시 수정 (스킵 금지)
- Low: 합리적이면 수용, 과도하면 구체적 사유와 함께 스킵 (사유 기록 필수)

## 수정 후 품질 게이트 재실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
```

## 라운드 결과 기록

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

## Suppression List 적용

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

## 리뷰 완료 조건

- Critical/High/Medium 발견이 모두 0개 (라운드 제한 없음, 0개 될 때까지 반복). 특히 IMPL-MISSING-CRITICAL, IMPL-STUB-HIGH는 반드시 수정 필요.
- 품질 게이트 통과
- E2E 게이트 통과 (`phases.phase_2.e2e.applicable == true`인 경우에만, 최종 라운드에서 실행):
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file .claude-full-auto-progress.json
  ```
  applicable이 false/null이면 E2E 게이트 스킵. E2E 실패 시: 수정 후 e2e-gate만 재실행 (코드 리뷰 재실행 불필요)

## Phase 3 완료

1. 코드 품질 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```
2. DoD 업데이트: `code_review_pass.checked = true`, evidence에 "N라운드 리뷰 완료, CRITICAL/HIGH/MEDIUM: 0"
3. Phase 전이는 오케스트레이터가 수행

## Iteration 관리

- 한 iteration에서 1 리뷰 라운드만 처리
- 라운드 완료 후 handoff 업데이트하고 자연스럽게 종료
