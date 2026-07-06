# Ralph Loop 자동 설정 — Step-0 공통 절차 (단일 출처)

auto-complete-loop 명령들이 공유하는 **0단계(Ralph Loop 자동 설정)** 절차입니다.
호출한 명령 문서의 **파라미터 표**에서 다음 값을 가져와 아래 자리 표시자에 치환한 뒤, 1→5 순서대로 수행하세요:

| 자리 표시자 | 의미 |
|-------------|------|
| `{PROMISE_TAG}` | 완료 promise 태그 (예: `DOCS_CONSISTENT`) |
| `{PROGRESS_FILE}` | 진행 상태 파일명 (예: `.claude-doc-check-progress.json`) |
| `{INIT_TEMPLATE}` | `shared-gate.sh init --template` 값. `(없음)`이면 init 생략 |
| `{MAX_ITERATIONS}` | `init-ralph` 최대 반복 수. `(기본값)`이면 인수 생략 (init-ralph 기본값: 30 — 무한 루프 방지) |
| `{EXTRA_INIT}` | init 직후 수행할 명령 고유 초기화. `(없음)`이면 생략 |

**이 절차를 명령의 다른 어떤 작업보다 먼저 실행합니다.**

## 1. 공통 규칙 로드 + 인수 파싱

1. `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.
2. 명령 문서의 **"인수 파싱"** 절차를 수행합니다 (명령별 고유 — `$ARGUMENTS` 해석 규칙은 각 명령 문서에 정의).

## 2. 복구 감지

`{PROGRESS_FILE}` 파일을 확인하고 분기합니다:

**파일이 존재하고 `status`가 `"in_progress"`인 경우 (재시작):**
1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 → 이전 iteration 맥락 복구
3. 현재 단계의 진행 상태에 따라 재개. 모든 steps/documents가 `completed`면 명령의 **최종 검증/보고 단계**로 이동 (명령 문서에 "복구 시 재개 규칙"이 별도로 있으면 그것을 따름)
4. 아래 3단계(초기화)는 **건너뜀** → 4단계(Ralph Loop 파일 생성)로 진행 (`.claude/ralph-loop.local.md`가 이미 있으면 4단계도 생략)

**파일이 존재하고 `status`가 `"completed"`인 경우:**
- `{PROGRESS_FILE}` 삭제(정리) 후 "이미 완료된 작업입니다. 새로 시작하려면 명령을 다시 실행하세요" 안내하고 종료

**파일이 없는 경우 (신규):**
- 명령 문서에 추가 복구 절차(예: 파일 비교 복구)가 있으면 먼저 수행, 없으면 3단계로 진행

## 3. Progress 파일 초기화 (신규 시작 시)

`{INIT_TEMPLATE}`가 지정된 경우 스크립트로 초기화합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template {INIT_TEMPLATE} "프로젝트명"
```

- `{INIT_TEMPLATE}`가 `(없음)`이면 이 단계를 건너뜁니다 — progress 파일은 명령 본문의 해당 단계에서 생성합니다.
- 명령의 파라미터 표가 다른 형태의 init 명령을 제시하면 그것을 우선합니다.
- 이어서 `{EXTRA_INIT}`를 수행합니다 (명령 고유 필드 설정 등 — `(없음)`이면 생략).

## 4. Ralph Loop 파일 생성

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "{PROMISE_TAG}" "{PROGRESS_FILE}" {MAX_ITERATIONS}
```

`{MAX_ITERATIONS}`가 `(기본값)`이면 세 번째 인수를 생략합니다 (init-ralph가 기본값 30을 적용).

## 5. Ralph Loop 완료 조건 + Iteration 규칙 숙지

### 완료 조건 (공통)

`<promise>{PROMISE_TAG}</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:

1. `{PROGRESS_FILE}`의 모든 steps/documents status가 `completed`
2. `{PROGRESS_FILE}`의 `dod` 체크리스트가 모두 checked (dod 필드가 있는 경우)
3. 명령 문서의 **"추가 완료 조건"**이 모두 충족 (있는 경우 — 예: `.claude-verification.json` 검증 항목 통과)
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 규칙 (공통)

- 한 iteration은 명령 문서의 **"Iteration 단위"**에 정의된 범위만 처리
- 처리 완료 후 진행 상태(`handoff` 필드 포함)를 `{PROGRESS_FILE}`에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작
