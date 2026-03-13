---
description: "문서 정합성 검증. doc↔doc 일관성 + doc↔code 매칭을 스크립트+AI로 검증하고 자동 수정"
argument-hint: "[docs_dir (기본: docs/)]"
---

# 문서 정합성 검증 (Check Docs)

문서 간 일관성(doc↔doc) + 문서↔코드 매칭(doc↔code)을 **스크립트 구조적 검사 + codex 의미적 검증 + 자동 수정**으로 한 번에 검증합니다.

**핵심 원칙**: 스크립트로 구조적 문제를 먼저 잡고, codex가 의미적 불일치를 독립 탐색. 이슈 발견 시 즉시 자동 수정.

## 인수

- `$ARGUMENTS`: 문서 디렉토리 경로 (선택, 기본값: `docs/`)

---

## 0단계: Ralph Loop 자동 설정 (최우선 실행)

**이 단계를 가장 먼저, 다른 어떤 작업보다 우선하여 실행합니다.**

먼저 `Read ${CLAUDE_PLUGIN_ROOT}/rules/shared-rules.md`를 실행하여 공통 규칙을 로드합니다.

### 0-1. 인수 파싱

`$ARGUMENTS`에서 문서 디렉토리 경로를 추출:
- 인수 있으면 → `docsDir` = `$ARGUMENTS`
- 인수 없으면 → `docsDir` = `docs/`

### 0-2. 복구 감지

`.claude-doc-check-progress.json` 파일 확인:

**파일이 존재하는 경우 (재시작):**
1. 파일 읽기
2. `handoff` 필드를 최우선으로 확인 → 이전 iteration 맥락 복구
3. 현재 단계의 진행 상태에 따라 재개
4. 모든 steps가 `completed`면 → 3단계(최종 확인)로 이동

**파일이 없는 경우 (신규):**
- 1단계부터 정상 시작

### 0-3. `.claude-doc-check-progress.json` 초기화

새로 시작하는 경우, 스크립트로 초기화:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init --template doc-check "프로젝트명"
```

생성 후 `docsDir`을 jq로 설정합니다:

```bash
tmp=$(mktemp) && jq --arg dir "${docsDir}" '.docsDir = $dir' .claude-doc-check-progress.json > "$tmp" && mv "$tmp" .claude-doc-check-progress.json
```

### 0-4. Ralph Loop 파일 생성

스크립트로 Ralph Loop 파일을 생성합니다:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph "DOCS_CONSISTENT" ".claude-doc-check-progress.json"
```

### Ralph Loop 완료 조건

`<promise>DOCS_CONSISTENT</promise>`를 출력하려면 다음이 **모두** 참이어야 합니다:
1. `.claude-doc-check-progress.json`의 모든 steps status가 `completed`
2. `.claude-doc-check-progress.json`의 `dod` 체크리스트가 모두 checked
3. 스크립트 exit code가 0
4. 위 조건을 **직전에 확인**한 결과여야 함 (이전 iteration 결과 재사용 금지)

### Iteration 단위 작업 규칙
- 1단계 + 2단계: 구조적 검사 + 의미적 검증 (1 iteration)
- 3단계: 최종 확인 (1 iteration)
- 처리 완료 후 진행 상태를 파일에 저장하고 세션을 자연스럽게 종료
- Stop Hook이 완료 조건 미달을 감지하면 자동으로 다음 iteration 시작

---

## 1단계: 구조적 검사 (스크립트)

스크립트로 문서 간 일관성과 문서↔코드 매칭을 구조적으로 검사합니다.

### 1-1. doc-consistency 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency "${docsDir}" --progress-file .claude-doc-check-progress.json
```

### 1-2. doc-code-check 실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check "${docsDir}" --progress-file .claude-doc-check-progress.json
```

### 1-3. 결과 처리

- **둘 다 exit 0** → 2단계로 진행
- **이슈 발견 시** → Claude Code가 자동 수정 후 재실행:
  1. 스크립트 출력에서 이슈 목록 파악
  2. 해당 문서 파일을 Edit 도구로 수정
  3. 동일 스크립트 재실행하여 수정 확인
- **재실행 후에도 실패** → 이슈 목록을 기록하고 2단계로 (codex에게 전달)

### 1-4. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "구조적 검사" completed --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "의미적 검증" in_progress --progress-file .claude-doc-check-progress.json
```

evidence 업데이트:
```json
{"docConsistencyExitCode": 0, "docCodeCheckExitCode": 0, "autoFixed": 3}
```

DoD 업데이트:
```json
"dod.doc_consistency": { "checked": true, "evidence": "doc-consistency exit 0" }
"dod.doc_code_check": { "checked": true, "evidence": "doc-code-check exit 0" }
```

---

## 2단계: 의미적 검증 (codex)

스크립트가 못 잡는 의미적 불일치를 codex가 독립 탐색합니다.

### 2-1. codex 호출

1단계에서 발견된 이슈 목록이 있으면 프롬프트에 포함합니다.

```bash
codex exec --skip-git-repo-check '## 역할
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
모든 일관성 확인 시 CONSISTENT + 검증 근거 명시.'
```

### 2-2. 결과 처리

- **codex가 이슈 발견** → Claude Code가 해당 문서/코드를 Edit 도구로 수정
- **CONSISTENT 응답** → 3단계로 진행
- **합의까지 최대 3라운드**: 수정 후 codex 재검증, 3라운드까지 반복

**호출 실패 시**: 재시도 1회 → 여전히 실패 시 Claude가 직접 의미적 검토 수행.

### 2-3. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "의미적 검증" completed --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "최종 확인" in_progress --progress-file .claude-doc-check-progress.json
```

evidence 업데이트:
```json
{"semanticIssuesFound": 2, "semanticIssuesFixed": 2, "rounds": 1}
```

DoD 업데이트:
```json
"dod.semantic_review": { "checked": true, "evidence": "codex CONSISTENT (round 1)" }
```

---

## 3단계: 최종 확인

스크립트 재실행으로 수정 결과를 검증합니다.

### 3-1. 스크립트 재실행

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-consistency "${docsDir}" --progress-file .claude-doc-check-progress.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check "${docsDir}" --progress-file .claude-doc-check-progress.json
```

### 3-2. 결과 확인

- **둘 다 exit 0** → 완료
- **실패 시** → Claude Code가 수정 후 재실행 (최대 2회)

### 3-3. Progress 업데이트

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh update-step "최종 확인" completed --progress-file .claude-doc-check-progress.json
```

### 3-4. DoD 최종 업데이트

모든 DoD 항목 최종 확인:
```json
{
  "doc_consistency": { "checked": true, "evidence": "doc-consistency exit 0 (최종)" },
  "doc_code_check": { "checked": true, "evidence": "doc-code-check exit 0 (최종)" },
  "semantic_review": { "checked": true, "evidence": "codex CONSISTENT" }
}
```

`.claude-doc-check-progress.json`의 `status`를 `"completed"`로 변경.

---

## 완료 보고

모든 단계 완료 후 간결하게 보고:

```
## 문서 정합성 검증 완료

### 구조적 검사 (스크립트)
- doc-consistency: PASS
- doc-code-check: PASS
- 자동 수정: N건

### 의미적 검증 (codex)
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

세션을 종료하기 전에 `.claude-doc-check-progress.json`의 `handoff` 필드를 반드시 업데이트합니다:

```json
"handoff": {
  "lastIteration": 1,
  "completedInThisIteration": "1단계: 구조적 검사 완료, 2단계: 의미적 검증 완료",
  "nextSteps": "3단계: 최종 확인 시작",
  "keyDecisions": [
    "필드명 'userId' → 'user_id' 통일",
    "API 경로 /api/v1/users 일관성 확인"
  ],
  "warnings": "",
  "currentApproach": "스크립트 구조적 검사 후 codex 의미적 검증"
}
```

---

## 강제 규칙 (절대 위반 금지)

> `shared-rules.md`의 공통 강제 규칙 + 컨텍스트 관리 + Handoff 규칙을 따릅니다.

**check-docs 추가 규칙:**
1. **스크립트 우선**: 구조적 검사는 반드시 스크립트로 먼저 실행
2. **codex 독립 탐색**: codex에게 문서 디렉토리만 전달. Claude가 결과를 미리 정리하지 않음
3. **자동 수정**: 이슈 발견 시 사용자 확인 없이 즉시 수정
4. **질문 금지**: AskUserQuestion 사용 금지. 모든 판단을 자동으로 수행

## 포기 방지 규칙 (강제)

- codex 호출 실패 시 → 재시도 1회, 이후에도 실패 시 Claude가 직접 의미적 검토
- 파싱 실패 시 → 출력 원문 기반 수동 파싱
- 컨텍스트 부족 시 → `/compact` 실행 후 계속 진행
- 모든 단계 완료까지 계속 진행
