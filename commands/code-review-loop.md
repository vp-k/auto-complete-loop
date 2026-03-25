---
description: "코드 리뷰 반복 수행 (2자: codex). codex-cli가 SEC/ERR/DATA/PERF/CODE 전 관점에서 독립 리뷰"
argument-hint: "[--rounds N | --goal \"조건\"] <scope>"
---

# 코드 리뷰 루프 (Code Review Loop)

코드 리뷰를 **자동 반복** 수행합니다. 리뷰→수정→재리뷰 사이클을 Ralph Loop으로 자동화합니다.
codex-cli가 SEC/ERR/DATA/PERF/CODE 전 관점에서 독립 리뷰, Claude Code가 검증 및 수정.

## 인수

- `$ARGUMENTS` 형식: `[--rounds N | --goal "조건"] [scope]`
- scope는 리뷰 범위 (파일/디렉토리/자연어 설명)

## 실행 모드

| 모드 | 사용법 | 동작 |
|------|--------|------|
| 기본 | `/code-review-loop [scope]` | 3라운드 리뷰→수정 반복 |
| 횟수 지정 | `/code-review-loop --rounds 5 [scope]` | N라운드 반복 |
| 목표 기반 | `/code-review-loop --goal "CRITICAL/HIGH 0개" [scope]` | 목표 달성까지 반복 (최대 10라운드) |
| 대화형 | `/code-review-loop --interactive [scope]` | 각 finding별 Fix/Acknowledge/FP 선택 |

---

## 0단계: Ralph Loop 자동 설정 (최우선 실행)

**이 단계를 가장 먼저, 다른 어떤 작업보다 우선하여 실행합니다.**

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

### 0-1. 인수 파싱

`$ARGUMENTS`에서 다음을 추출:

1. **모드 결정**:
   - `--rounds N` 있으면 → rounds 모드, targetRounds = N
   - `--goal "조건"` 있으면 → goal 모드, targetRounds = 10 (최대)
   - **둘 다 있으면** → goal 모드 우선, targetRounds = N (--rounds 값을 최대 횟수로 사용)
   - 둘 다 없으면 → rounds 모드, targetRounds = 3 (기본)
   - `--interactive` 있으면 → interactive 모드 활성화 (다른 모드와 조합 가능)
2. **scope**: 나머지 인수를 scope로 사용 (없으면 `src/`)

### 0-2. 복구 감지

`.claude-review-loop-progress.json` 파일이 이미 존재하면:
- `status`가 `in_progress`면 → `currentRound`와 `handoff`를 읽고 이어서 진행
- `status`가 `completed`면 → "이미 완료된 리뷰입니다" 안내 후 종료
- 존재하지 않으면 → 새로 시작

### 0-3. `.claude-review-loop-progress.json` 초기화

새로 시작하는 경우, 스크립트로 초기화:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template review "" "자연어 scope 원문"
```

생성 후 mode, targetRounds, goal 등을 jq로 설정합니다.

findingHistory 각 항목 스키마:
- `id`: finding ID (예: "SEC-CRITICAL-001")
- `file`: 파일 경로
- `line`: 줄번호
- `description`: 문제 설명
- `severity`: "CRITICAL" | "HIGH" | "MEDIUM" | "LOW"
- `category`: "SEC" | "ERR" | "DATA" | "PERF" | "CODE"
- `discoveredInRound`: 최초 발견 라운드
- `status`: "open" | "fixed" | "regressed" | "deferred"
- `fixedInRound`: 수정된 라운드 (null이면 미수정)

### 0-4. Ralph Loop 파일 생성

스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "REVIEW_LOOP_COMPLETE" ".claude-review-loop-progress.json" $targetRounds
```

**주의**: `max_iterations`는 rounds 모드면 `targetRounds`, goal 모드면 `10`으로 설정.

---

## 1단계: 스코프 확인

scope($ARGUMENTS에서 추출)를 자연어 그대로 보존하여 codex에게 전달합니다.
Claude가 파일 목록을 결정하지 않으며, codex가 자체적으로 codebase를 탐색합니다.

1. **scope 확인**: `$ARGUMENTS`에서 추출한 자연어 scope를 확인
2. **progress 파일 업데이트**: `scope` 필드에 자연어 원문 저장, `currentRound` → 1

**스코프 예시:**

| 자연어 입력 | 전달 내용 |
|------------|----------|
| `src/` | "src/" 그대로 전달 |
| `인증 시스템` | "인증 시스템" 그대로 전달 |
| 미지정 | "src/" 기본값 전달 |

---

## 2단계: 리뷰 실행 (codex 독립 리뷰)

**라운드 1**: 자연어 scope를 codex에게 전달하여 자체 탐색
**라운드 2+**: 수정된 파일 전체 (`git diff --name-only`) 목록을 전달. 이전 finding 목록은 **참고용으로만** 프롬프트에 포함 (범위 제한 금지). codex가 Claude가 놓친 새로운 이슈를 독립적으로 발견할 수 있어야 함.

### codex-cli 호출 (SEC, ERR, DATA, PERF, CODE 전 관점)

```bash
codex exec --skip-git-repo-check '## 역할
당신은 보안/에러 처리/데이터 일관성/성능/코드 품질 전문 코드 리뷰어입니다.
이 프로젝트의 codebase에서 아래 범위에 해당하는 코드를 직접 탐색하여 리뷰하세요.
파일을 직접 찾고, 읽고, 분석하세요. 테스트 파일과 설정 파일은 제외합니다.

## 전문 리뷰 관점
1. **Security (SEC)**: 아래 서브카테고리별로 분류하여 보고
   - SEC-INJ: SQL/NoSQL/Command injection
   - SEC-XSS: Cross-site scripting, 미이스케이프 출력
   - SEC-AUTH: 인증/인가 우회, 세션 관리 미흡
   - SEC-TOCTOU: Time-of-check to time-of-use race condition
   - SEC-LLM: LLM 출력을 DB/shell/eval에 직접 전달하는 패턴
   - SEC-CRYPTO: truncation vs hashing, MD5/SHA1, 하드코딩 salt
   - SEC-TYPE: JS == vs ===, PHP loose comparison 등 type coercion
   - SEC-RACE: 동시성 race condition (find_or_create without unique index 등)
   - SEC-TIME: 토큰 만료, 세션 관리 타이밍 이슈
   - SEC-SECRET: 시크릿/API키 노출, 하드코딩 자격증명
2. **Error Handling (ERR)**: try-catch 누락, 에러 응답 불일치, 에지 케이스 미처리
3. **Data Consistency (DATA)**: 트랜잭션 누락, 스키마 불일치, race condition
4. **Performance (PERF)**: N+1 쿼리, 불필요한 DB 호출, 대량 데이터 미처리, 메모리 누수
5. **Code Consistency (CODE)**: 컨벤션 위반, 패턴 불일치, 타입 안전성 부족, 미사용 코드

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
**CRITICAL 예시**: `db.query("SELECT * FROM users WHERE id = " + userId)` → SEC-INJ (SQL injection)
**HIGH 예시**: `catch(e) {}` 빈 catch 블록 → ERR (에러 무시)
**MEDIUM 예시**: API 응답에서 페이지네이션 없이 전체 목록 반환 → PERF (대량 데이터)
**LOW 예시**: 함수명 `getData`가 구체적이지 않음 → CODE (네이밍)

## 리뷰 범위
### 범위 지정
- **라운드 1**: [자연어 scope 원문]
- **라운드 2+**: 아래 git diff에 나열된 변경 파일 전체

[라운드 2+에만 삽입]
### 변경된 파일 목록 (git diff --name-only)
{실제 git diff 출력}

## 참고: 이전 라운드에서 알려진 이슈 (라운드 2+에만 포함)
[이전 finding 목록 — 참고용. 이 목록에 없는 새로운 이슈도 반드시 보고하세요]

## 출력 형식
### {CATEGORY}-{SEVERITY}-{번호}: {제목}
- 파일: {경로}
- 라인: {줄번호}
- 설명: {문제 상세}
- 권장: {수정안}

finding 없으면 "NO_FINDINGS".
마지막 줄: FINDING_COUNT: N'
```

**호출 실패 시**: 재시도 1회 → 여전히 실패 시 Claude가 전 관점 직접 리뷰.

---

## 3단계: Finding 검증 (Claude Code 판정)

codex가 발견한 각 finding을 직접 검증:

### 검증 프로세스

각 finding에 대해:
1. **Read 도구**로 해당 파일의 해당 라인 직접 읽기
2. **판정**:
   - **Confirmed**: 실제 문제. severity 조정 가능.
   - **Dismissed**: false positive, 의도된 설계 → 구체적 기각 사유를 roundResults.dismissedDetails에 기록 (필수)

### 라운드 간 Finding 매칭 (라운드 2+)

이전 라운드 finding과 대조:
- 동일 파일 + 라인 범위 겹침(±5줄) + 문제 유형 유사 → 같은 finding
- 상태 분류:
  - 이전 `open` → 이번 미발견 → `fixed`
  - 이전 `fixed` → 이번 재발견 → `regressed`
  - 이번 신규 → `new` (status: `open`)
  - MEDIUM/LOW 보류 → `deferred`

### Finding ID 형식

`{CATEGORY}-{SEVERITY}-{번호}` (예: SEC-CRITICAL-001, PERF-HIGH-002)

---

## 4단계: 수정 (CRITICAL/HIGH 자동 수정)

confirmed **CRITICAL** 및 **HIGH** finding을 **Edit 도구**로 자동 수정:

1. 각 finding의 파일과 라인 확인
2. 권장 수정안을 기반으로 코드 수정
3. 수정 결과를 finding status에 반영
4. MEDIUM/LOW는 이 라운드에서 수정하지 않음 (`deferred`)

**수정 원칙:**
- 최소한의 변경으로 문제 해결
- 기존 코드 스타일 및 패턴 유지
- 한 finding 수정이 다른 코드에 영향주지 않도록 주의

### Interactive 모드 (`--interactive`)

`--interactive` 플래그 활성 시, 각 confirmed finding에 대해 사용자에게 선택지를 제시합니다:

```
### SEC-HIGH-001: SQL injection in user query
- 파일: src/db/users.ts:42
- 설명: 사용자 입력이 직접 쿼리에 삽입됨
- 권장: parameterized query 사용

선택하세요:
  A) Fix (권장) — 즉시 수정
  B) Acknowledge — 인지하고 넘어감 (deferred)
  C) False positive — suppression list에 등록
```

**동작:**
- **A (Fix)**: 기존 자동 수정과 동일하게 즉시 수정
- **B (Acknowledge)**: finding status를 `deferred`로 설정, 사유 기록
- **C (False positive)**: `.claude-review-suppressions.json`에 해당 패턴 등록 (파일 + 카테고리 + 키워드). 30일 후 자동 만료.

**적용 범위**: standalone `/code-review-loop --interactive`에만 적용. `/full-auto` Phase 3의 코드 리뷰는 기존 자동 모드를 유지합니다.

---

## 5단계: 수정 후 빌드/테스트 검증

수정 후 스크립트로 품질 게이트를 실행합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-review-loop-progress.json
```

스크립트가 자동으로:
1. 프로젝트 유형을 감지하고 빌드/타입/린트/테스트 명령을 결정
2. 각 명령을 실행하고 결과를 `.claude-verification.json`에 기록 (stop-hook 호환 포맷)
3. progress 파일의 DoD를 업데이트

**빌드/테스트 실패 시**: 해당 라운드에서 수정 시도. 수정 불가 시 handoff에 기록.

---

### 5.5단계: 수정 사항 커밋

품질 게이트 통과 후, 이번 라운드의 수정 사항을 커밋합니다.

**커밋 조건**: 4단계에서 실제로 코드를 수정한 경우에만 커밋 (수정 없으면 생략)

```bash
git add -A && git commit -m "[auto] 코드 리뷰 Round {currentRound} 수정 완료"
```

---

## 6단계: 라운드 결과 기록 + 종료 조건 평가

### 6-1. 결과 기록

`.claude-review-loop-progress.json` 업데이트:

- `currentRound` 증가
- `roundResults`에 현재 라운드 결과 추가:
  ```json
  {
    "round": 1,
    "findings": {
      "total": 12,
      "confirmed": 10,
      "dismissed": 2,
      "dismissedDetails": [
        { "id": "CODE-LOW-003", "reason": "테스트 파일의 의도적 매직넘버, 프로덕션 코드 아님" }
      ],
      "bySeverity": { "CRITICAL": 1, "HIGH": 3, "MEDIUM": 4, "LOW": 2 }
    },
    "fixes": { "attempted": 4, "succeeded": 4, "failed": 0 },
    "verification": "shared-gate.sh quality-gate 실행 결과 (.claude-verification.json 참조)",
    "timestamp": "ISO"
  }
  ```
- `findingHistory` 업데이트 (각 finding의 상태 반영)
- `handoff` 업데이트 (다음 반복을 위한 컨텍스트)

### 6-2. 종료 조건 평가

**횟수 모드** (`mode: "rounds"`):
- `currentRound >= targetRounds` → 종료 조건 충족

**목표 모드** (`mode: "goal"`):
- 목표 조건 파싱:
  - "CRITICAL 0개" → CRITICAL severity open finding 0개
  - "CRITICAL/HIGH 0개" → CRITICAL + HIGH open finding 합계 0개
  - "finding 5개 이하" → 전체 confirmed open finding 5개 이하
- 수렴 감지: 2라운드 연속 open finding 수 동일 → 더 이상 개선 불가, 중단

**공통 조건** (모드 무관):
- 빌드/테스트 통과 필수 (verification의 build/test가 0)

### 6-3. DoD 업데이트

```json
"dod": {
  "all_rounds_complete": { "checked": [종료 조건 충족 여부], "evidence": "Round N/N 완료" },
  "build_pass": { "checked": [빌드 통과 여부], "evidence": "build exit 0" },
  "no_critical_high": { "checked": [open CRITICAL+HIGH == 0 여부], "evidence": "open CRITICAL: N, HIGH: M" }
}
```

**주의**: `no_critical_high.checked`는 실제 open CRITICAL + HIGH 수가 0일 때만 `true`. 종료 조건에는 포함하지 않으나(rounds/goal 모드가 제어), evidence에 실제 수치를 기록하여 투명성 확보.

### 6-4. 종료 또는 계속

**종료 조건** = (rounds 또는 goal 조건 충족) && (빌드/테스트 통과)

- **종료 조건 충족**: → DoD 최종 업데이트, `.claude-review-loop-progress.json`의 `status`를 `"completed"`로 변경, 완료 보고 후 `<promise>REVIEW_LOOP_COMPLETE</promise>` 출력
- **미충족**: → `handoff`에 다음 라운드 안내 기록, 현재 턴에서 종료 (stop-hook이 다음 반복 트리거)

---

## 완료 보고

모든 라운드 완료 후 간결하게 보고:

```
## 코드 리뷰 루프 완료

- **라운드**: N회 수행
- **총 Finding**: X건 발견 → Y건 확인, Z건 기각
- **수정 결과**: A건 수정 (CRITICAL: B, HIGH: C)
- **남은 Finding**: D건 (MEDIUM: E, LOW: F)
- **빌드/테스트**: 통과

### 라운드별 추이
| 라운드 | 발견 | 수정 | 남은 CRITICAL/HIGH |
|--------|------|------|-------------------|
| 1      | 12   | 4    | 0                 |
| 2      | 3    | 1    | 0                 |
| ...    | ...  | ...  | ...               |
```

보고 후 `<promise>REVIEW_LOOP_COMPLETE</promise>` 출력.

---

## 목표 조건 파싱 규칙

`--goal` 인수의 자연어를 파싱:

| 입력 | 해석 |
|------|------|
| "CRITICAL 0개" | CRITICAL open finding 0개 |
| "CRITICAL/HIGH 0개" | CRITICAL + HIGH open finding 합계 0개 |
| "finding 5개 이하" | 전체 confirmed open finding ≤ 5개 |
| "보안 이슈 없음" | SEC 카테고리 open finding 0개 |

**수렴 감지**: 2라운드 연속 open finding 수 동일 → 더 이상 개선 불가로 판단, 루프 중단.

---

## 강제 규칙 (절대 위반 금지)

> `shared-rules.md`의 공통 강제 규칙 + 컨텍스트 관리 + Handoff 규칙을 따릅니다.

**code-review-loop 추가 규칙:**
1. **자체 탐색**: codex에게 자연어 scope(R1) 또는 git diff 파일 목록(R2+)만 전달. Claude가 파일 목록을 결정하지 않음.
2. **codex 독립 리뷰**: codex가 SEC/ERR/DATA/PERF/CODE 전 관점에서 독립 리뷰 수행

## 포기 방지 규칙 (강제)

- codex 호출 실패 시 → 재시도 1회, 이후에도 실패 시 Claude가 전 관점 직접 리뷰
- 파싱 실패 시 → 출력 원문 기반 수동 파싱
- 컨텍스트 부족 시 → `/compact` 실행 후 계속 진행
