---
description: "Doc consistency check. Verify doc↔doc and doc↔code alignment with 4 script gates + AI semantic review + auto-fix. --mode codex|solo"
argument-hint: "[--mode <codex|solo>] [docs_dir (기본: docs/)]"
---

# 문서 정합성 검증 (Check Docs)

문서 간 일관성(doc↔doc) + 문서↔코드 매칭(doc↔code)을 **스크립트 구조적 검사(4종 게이트) + AI 의미적 검증 + 자동 수정**으로 한 번에 검증합니다.

**핵심 원칙**: 스크립트로 구조적 문제를 먼저 잡고, 외부 AI(또는 solo 모드의 fresh-context 서브에이전트)가 의미적 불일치를 독립 탐색. 이슈 발견 시 즉시 자동 수정.

**역할 분담** (모드별):
- **codex** (기본): codex-cli가 의미적 검증 독립 수행, Claude Code가 수정
- **solo**: Claude 서브에이전트(fresh context)가 의미적 검증 독립 수행 — 외부 AI 불필요

## 인수

- `$ARGUMENTS` 형식: `[--mode <codex|solo>] [docs_dir]`
- `--mode <codex|solo>` (선택): 의미적 검증 수행자 선택 (기본: codex)
- `docs_dir` (선택): 문서 디렉토리 경로 (기본값: `docs/`)

### --mode 처리

`$ARGUMENTS`에서 `--mode <value>`를 감지하면:

1. `$ARGUMENTS`에서 `--mode <value>` 부분을 제거하여 순수 인수(docs_dir)만 추출
2. value 검증: `codex`, `solo` 중 하나
3. `--mode` 미지정 시 기본값 `codex` 적용

---

## 0단계: Ralph Loop 자동 설정 (최우선 실행)

`Read ${CLAUDE_PLUGIN_ROOT}/templates/ralph-loop-setup.md`를 읽고, 아래 파라미터로 치환하여 공통 절차(규칙 로드→인수 파싱→복구 감지→init→init-ralph→완료 조건/Iteration 규칙)를 수행합니다.

| 파라미터 | 값 |
|----------|-----|
| PROMISE_TAG | `DOCS_CONSISTENT` |
| PROGRESS_FILE | `.claude-doc-check-progress.json` |
| INIT_TEMPLATE | `doc-check` |
| MAX_ITERATIONS | (기본값) |
| EXTRA_INIT | 아래 "EXTRA_INIT" 참조 |

### 인수 파싱

`$ARGUMENTS`에서 `--mode`를 먼저 분리(위 "--mode 처리")한 뒤, 남은 인수에서 문서 디렉토리 경로를 추출:
- 인수 있으면 → `docsDir` = 남은 인수
- 인수 없으면 → `docsDir` = `docs/`

### EXTRA_INIT

init 후 `docsDir`과 `semanticMode`(--mode 값 — 복구 iteration에서 모드 유지용)를 jq로 설정합니다:

```bash
tmp=$(mktemp) && jq --arg dir "${docsDir}" --arg mode "${mode}" '.docsDir = $dir | .semanticMode = $mode' .claude-doc-check-progress.json > "$tmp" && mv "$tmp" .claude-doc-check-progress.json
```

### 복구 시 재개 규칙

- `semanticMode` 필드에서 모드를 복원합니다 (필드 없으면 `codex`)
- 모든 steps가 `completed`면 → 3단계(최종 확인)로 이동.

### 추가 완료 조건

`<promise>DOCS_CONSISTENT</promise>` 출력 전 다음이 **모두** 충족되어야 합니다 (직전 실행 결과 기준):

- `doc-consistency` exit 0 — PASS 시 dod `doc_consistency` 자동 기록
- `doc-code-check` exit 0 — PASS/SKIP 시 dod `doc_code_check` 자동 기록
- `definition-conflict` 실행 완료 — 종결 시 dod `no_definition_conflict` 자동 기록 (SOFT 게이트)
- `clarification-gate` exit 0 — `[NEEDS-CLARIFICATION]` 잔존 0건 (fail 기록이 남으면 stop-hook이 차단)
- 의미적 검증 CONSISTENT — dod `semantic_review`는 유일하게 모델이 기록

dod 3키(`doc_consistency`/`doc_code_check`/`no_definition_conflict`)가 `checked: true`가 되는 유일한 경로는 위 게이트 실행입니다 (모델 직접 세팅 금지).

### Iteration 단위

- 1단계 + 2단계: 구조적 검사 + 의미적 검증 (1 iteration)
- 3단계: 최종 확인 (1 iteration)

---

## 1단계: 구조적 검사 (스크립트 게이트 4종)

스크립트로 문서 간 일관성과 문서↔코드 매칭을 구조적으로 검사합니다. **모든 게이트에 `--progress-file`을 반드시 전달합니다** (dod 자동 기록의 전제).

### 1-1. doc-consistency 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency "${docsDir}" --progress-file .claude-doc-check-progress.json
```

### 1-2. doc-code-check 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check "${docsDir}" --progress-file .claude-doc-check-progress.json
```

### 1-3. definition-conflict 실행 (Non-Goals 위반 탐지)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh definition-conflict "${docsDir}" --progress-file .claude-doc-check-progress.json
```

SOFT 게이트 — pass/warn/skip 모두 exit 0. WARN 매치가 나오면 각 매치를 검토해 실제 Non-Goals 위반이면 해당 문서를 수정합니다.

### 1-4. clarification-gate 실행 ([NEEDS-CLARIFICATION] 잔존 검사)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate "${docsDir}"
```

**HARD_FAIL(태그 잔존) 시**: 잔존 태그는 스펙 공백이므로 자동 수정 대상이 아닙니다 — 임의로 답을 지어 치환하지 않습니다. **"질문 금지" 규칙의 유일한 예외**로 AskUserQuestion으로 각 태그의 답변을 사용자에게 받아 치환한 뒤 게이트를 재실행합니다. (fail 기록이 verification.json에 남아 있으면 stop-hook이 완주를 차단하므로 재실행으로 pass를 갱신해야 함)

### 1-5. 결과 처리

- **모두 통과 (exit 0)** → 2단계로 진행
- **이슈 발견 시** → Claude Code가 자동 수정 후 재실행:
  1. 스크립트 출력에서 이슈 목록 파악
  2. 해당 문서 파일을 Edit 도구로 수정
  3. 동일 게이트 재실행하여 수정 확인 (dod는 PASS 시 게이트가 자동 기록)
- **재실행 후에도 실패** → 이슈 목록을 기록하고 2단계로 (의미적 검증자에게 전달)

### 1-6. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "구조적 검사" completed --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "의미적 검증" in_progress --progress-file .claude-doc-check-progress.json
```

**dod 기록 주체 (게이트 자동 기록 — 모델 직접 세팅 금지):**

| dod 키 | 기록 주체 |
|--------|----------|
| `doc_consistency` | `shared-gate.sh doc-consistency` PASS 시 자동 기록 |
| `doc_code_check` | `shared-gate.sh doc-code-check` PASS/SKIP 시 자동 기록 |
| `no_definition_conflict` | `shared-gate.sh definition-conflict` 종결 시 자동 기록 |
| `semantic_review` | **유일하게 모델이 기록** (스크립트로 판정 불가) — 2-3의 jq 명령 사용 |

steps[].evidence 기록이 필요하면 Edit 도구가 아닌 jq로 갱신합니다 (progress 파일 직접 Edit는 가드 경고 대상):

```bash
tmp=$(mktemp) && jq '(.steps[] | select(.name == "구조적 검사") | .evidence) = {"docConsistencyExitCode": 0, "docCodeCheckExitCode": 0, "autoFixed": 3}' .claude-doc-check-progress.json > "$tmp" && mv "$tmp" .claude-doc-check-progress.json
```

---

## 2단계: 의미적 검증 (모드별 분기)

스크립트가 못 잡는 의미적 불일치를 독립 컨텍스트에서 탐색합니다. 1단계에서 발견된 이슈 목록이 있으면 프롬프트에 포함합니다.

### 공통 검증 프롬프트

```
## 역할
문서 일관성 전문 검토자. 아래 디렉토리의 문서를 직접 읽고 교차 검증하세요.

## 검토 대상
${docsDir} 디렉토리의 모든 .md 파일

## 검토 관점
1. 문서 간 데이터 모델 일관성 (필드명, 타입, 관계)
2. API 엔드포인트 간 충돌/중복
3. 용어/명명 규칙 통일성
4. 의존성 관계의 논리적 정합성
5. 문서↔코드 불일치 (코드베이스 직접 탐색)

## 1단계 스크립트 결과
[스크립트가 발견한 이슈 목록 — 있는 경우만]

## 출력
불일치를 구체적으로 (파일명 + 섹션) 지적.
모든 일관성 확인 시 CONSISTENT + 검증 근거 명시.
```

### 2-1a. codex 모드 (기본)

```bash
codex exec --skip-git-repo-check '<공통 검증 프롬프트>'
```

**호출 실패 시**: 재시도 1회 → 여전히 실패 시 solo 모드 절차(2-1b)로 폴백.

### 2-1b. solo 모드

Agent 툴로 **fresh-context 서브에이전트**(general-purpose)를 생성하여 공통 검증 프롬프트를 그대로 전달합니다. 구현 세션의 선입견 없이 문서를 독립 탐색하는 것이 목적이므로, Claude가 결과를 미리 정리해 넘기지 않습니다. (`${docsDir}`는 절대 경로로 치환하여 전달 — 서브에이전트는 호출 세션의 변수를 해석하지 못함)

**서브에이전트 생성 실패 시**: Claude가 직접 의미적 검토 수행 (최후 폴백).

### 2-2. 결과 처리

- **이슈 발견** → Claude Code가 해당 문서/코드를 Edit 도구로 수정
- **CONSISTENT 응답** → 3단계로 진행
- **합의까지 최대 3라운드**: 수정 후 재검증, 3라운드까지 반복

### 2-3. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "의미적 검증" completed --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "최종 확인" in_progress --progress-file .claude-doc-check-progress.json
```

`semantic_review`는 스크립트로 판정할 수 없는 유일한 dod이므로 모델이 jq로 기록합니다 (CONSISTENT 확인 후에만 — 근거 없는 세팅 금지):

```bash
tmp=$(mktemp) && jq '.dod.semantic_review = {"checked": true, "evidence": "codex CONSISTENT (round 1)"}' .claude-doc-check-progress.json > "$tmp" && mv "$tmp" .claude-doc-check-progress.json
```

(solo 모드는 evidence를 `"subagent CONSISTENT (round N)"`으로 기록)

---

## 3단계: 최종 확인

게이트 재실행으로 수정 결과를 검증합니다. (완료 조건은 "직전에 확인한 결과"여야 하므로 반드시 재실행)

### 3-1. 게이트 재실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency "${docsDir}" --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check "${docsDir}" --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh definition-conflict "${docsDir}" --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh clarification-gate "${docsDir}"
```

### 3-2. 결과 확인

- **모두 exit 0** → 완료 (dod 3키는 게이트가 자동으로 최종 기록)
- **실패 시** → Claude Code가 수정 후 재실행 (최대 2회)

### 3-3. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "최종 확인" completed --progress-file .claude-doc-check-progress.json
```

### 3-4. 최종 상태 전환

dod를 확인하고 (`doc_consistency`/`doc_code_check`/`no_definition_conflict`는 게이트 기록, `semantic_review`는 2-3에서 기록됨) 모두 checked면 status를 완료로 전환합니다:

```bash
# dod 전체 확인
jq '.dod' .claude-doc-check-progress.json
# 전체 checked 확인 후 완료 전환
tmp=$(mktemp) && jq '.status = "completed"' .claude-doc-check-progress.json > "$tmp" && mv "$tmp" .claude-doc-check-progress.json
```

미체크 dod가 있으면 해당 게이트를 재실행해 해소합니다 — jq로 dod를 직접 세팅하는 것은 `semantic_review` 외에는 금지.

---

## 완료 보고

모든 단계 완료 후 간결하게 보고:

```
## 문서 정합성 검증 완료 (모드: codex|solo)

### 구조적 검사 (스크립트 게이트)
- doc-consistency: PASS
- doc-code-check: PASS
- definition-conflict: PASS (WARN 검토 N건)
- clarification-gate: PASS (사용자 답변 반영 N건)
- 자동 수정: N건

### 의미적 검증
- 발견 이슈: N건
- 수정 이슈: N건
- 검증 라운드: N회

### 수정된 파일
- docs/xxx.md (필드명 통일)
- docs/yyy.md (API 엔드포인트 수정)
```

보고 후 `<promise>DOCS_CONSISTENT</promise>` 출력.

---

## Handoff (Iteration 종료 전 필수)

세션을 종료하기 전에 `handoff-update` 서브커맨드로 progress 파일의 `handoff` 필드를 반드시 갱신합니다 (수기 JSON 편집 금지):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh handoff-update \
  --progress-file .claude-doc-check-progress.json \
  --iteration 1 \
  --completed "1단계: 구조적 검사 완료, 2단계: 의미적 검증 완료" \
  --next-steps "3단계: 최종 확인 시작" \
  --decision "필드명 'userId' → 'user_id' 통일" \
  --decision "API 경로 /api/v1/users 일관성 확인" \
  --approach "스크립트 구조적 검사 후 의미적 검증"
```

**필수 옵션**: `--next-steps` / **선택 옵션**: `--completed`, `--iteration`, `--decision` (복수 가능), `--warnings`, `--approach`

---

## 강제 규칙 (절대 위반 금지)

> `shared-rules.md`의 공통 강제 규칙 + 컨텍스트 관리 + Handoff 규칙을 따릅니다.

**check-docs 추가 규칙:**
1. **스크립트 우선**: 구조적 검사는 반드시 스크립트 게이트로 먼저 실행
2. **독립 탐색**: 의미적 검증자(codex/서브에이전트)에게 문서 디렉토리만 전달. Claude가 결과를 미리 정리하지 않음
3. **자동 수정**: 이슈 발견 시 사용자 확인 없이 즉시 수정 (아래 "보호 파일" 예외 참조)
4. **질문 금지**: AskUserQuestion 사용 금지. 모든 판단을 자동으로 수행. **예외 2가지**: (a) `[NEEDS-CLARIFICATION]` 태그 잔존 시 답변 수집 (1-4), (b) 보호 파일 수정 차단 시 승인 요청 (아래)
5. **dod 직접 세팅 금지**: `semantic_review` 외의 dod는 게이트만 기록. progress 파일 갱신은 Edit 도구가 아닌 서브커맨드/jq 사용

## 보호 파일 상호작용 (가드 차단 시 절차)

자동 수정 중 아래 가드에 차단될 수 있습니다. **차단을 우회하려 시도하지 않습니다** (Bash 리다이렉트 등 대체 경로 금지):

| 차단 대상 | 조건 | 절차 |
|-----------|------|------|
| `SPEC.md` / `overview.md` / `docs/specs/**` / `docs/plans/**` | full-auto Phase 2+ 진행 중 | 수정 목록을 정리해 AskUserQuestion으로 사용자 승인 요청 → 승인 시에만 수정 |
| `tests/acceptance/**` (동결됨) | 동결 manifest 존재 시 상시 | 사용자 승인 → SPEC 갱신 → `acceptance-freeze --approved-by-user` 재동결 후 수정 |
| `.claude-verification.json` | 상시 | 직접 수정 금지 — 결과를 바꾸려면 해당 게이트를 재실행 |
| `.claude/ralph-loop.local.md` | 상시 | 수정/삭제 금지 — 강제 종료가 필요하면 AskUserQuestion으로 사용자에게 요청 |

## 포기 방지 규칙 (강제)

- codex 호출 실패 시 → 재시도 1회 → solo 절차(fresh-context 서브에이전트) 폴백 → 그래도 실패 시 Claude가 직접 의미적 검토
- 파싱 실패 시 → 출력 원문 기반 수동 파싱
- 컨텍스트 부족 시 → `/compact` 실행 후 계속 진행
- 모든 단계 완료까지 계속 진행
