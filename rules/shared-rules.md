# 공통 규칙 (모든 스킬 적용)

## 검증 결과 기록 (필수)
모든 검증(빌드/테스트/린트) 결과는 `.claude-verification.json`에 기록되어야 합니다.
증거 없는 완료 선언은 금지입니다.
- 빌드/테스트/린트: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate` 실행 — 스크립트가 자동 기록
- 소프트 품질 차원(featureCompleteness/security/visualRegression 등): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension <key> <result> "<evidence>"` 로 기록
- **verification.json 직접 편집(Edit/Write/Bash 리다이렉트)은 가드가 차단함** — 반드시 위 서브커맨드를 사용 (읽기는 허용)

## DoD 확인
DoD의 단일 출처는 **progress 파일의 `dod` 체크리스트**입니다 (`.claude-*-progress.json`).
별도의 `DONE.md` 체크리스트 파일은 사용하지 않습니다 — 어떤 게이트도 그 파일을 읽지 않으므로
거기에 체크를 남겨도 완주 판정에 반영되지 않습니다.
- 항목 확인: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh status`
- 키 추가: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh add-dod-key <key> "<설명>"`
- 각 항목은 evidence 없이 checked=true 불가 (아래 "증거 기반 완료 선언" 참조)
- 게이트 결과(`.claude-verification.json`)와 `dod`가 모두 충족되어야 완주 promise 출력 가능

## Ralph Loop 모드
`.claude/ralph-loop.local.md`가 존재하면 Ralph Loop 모드입니다.
- 한 iteration에서 처리할 작업 단위를 최소화
- Iteration 종료 전 handoff 필드를 반드시 업데이트
- 모든 조건 충족 시에만 <promise> 태그를 출력
- Ralph Loop 파일 생성: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init-ralph <promise> <progress_file> [max_iter]`

## Self-check (완료 선언 전 필수)
1. 원래 요구사항 다시 읽기
2. 구현이 요구사항을 충족하는지 항목별 대조
3. 빌드/테스트를 **지금** 실행 (이전 결과 재사용 금지)
3.5. **E2E 테스트 실행** (phases.phase_2.e2e.applicable==true인 경우):
     - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh e2e-gate --progress-file {PROGRESS_FILE}`
     - phases.phase_2.e2e.scenarios의 모든 시나리오 status=="completed" 확인
     - E2E 결과는 e2e-gate 스크립트가 `.claude-verification.json`의 `e2e` 필드에 자동 기록
4. 결과가 `.claude-verification.json`에 기록되었는지 확인 — 게이트 결과는 각 서브커맨드가 자동 기록하고, 소프트 품질 차원은 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-dimension <key> <result> "<evidence>"` 로 기록 (직접 편집은 가드가 차단함)
5. 해당 progress 파일의 dod 체크리스트 업데이트 (evidence 포함)

## 이 파일에 없는 규칙 (분리된 규칙 파일)

아래 주제는 이 파일이 아니라 각 규칙 파일이 단일 출처다. 여기에 요약을 두지 않으므로 미리 읽지 않고, **로드 시점**에 아래 지시를 그대로 실행한다. 인용할 때도 해당 파일을 직접 가리킨다.

| 주제 | 로드 시점 → 지시 |
|------|------------------|
| 에러 레벨 분류, L0→L5 에스컬레이션 예산, L2+ 라운드테이블, TOO_BIG 분할, 범위 축소(L4) 절차, 막힘 패턴 | 첫 에러/게이트 실패를 처리하기 직전 → `Read ${CLAUDE_PLUGIN_ROOT}/rules/error-escalation-rules.md` |
| 프로젝트 규모 판정(Small/Medium/Large)과 규모별 활성화 항목 | 규모를 판정(pm-planning Step 0-1)하거나 규모 분기를 적용(doc-planning·phase-transition)하기 직전 → `Read ${CLAUDE_PLUGIN_ROOT}/rules/project-size-rules.md` |
| Phase 전이 조건·DoD evidence | full-auto 오케스트레이터가 시작 시 Read (`full-auto.md` "규칙 로드") |
| 오케스트레이터 전용 규칙(복구 감지, handoff-update, 컴팩션 트리거) | full-auto 오케스트레이터가 시작 시 Read (`full-auto.md` "규칙 로드"; plan-docs-full은 읽지 않는다) |

## 의존성 관리 (패키지 설치)

의존성 추가/제거 시 반드시 **패키지 매니저 명령어**를 사용합니다. 의존성 파일 직접 편집은 금지입니다.

| 플랫폼 | 추가 명령어 | 제거 명령어 | 직접 편집 금지 파일 |
|--------|-----------|-----------|-----------------|
| Node.js | `npm install <pkg>` | `npm uninstall <pkg>` | `package.json` |
| Flutter | `flutter pub add <pkg>` | `flutter pub remove <pkg>` | `pubspec.yaml` |
| Python | `pip install <pkg>` 또는 `uv add <pkg>` | `pip uninstall <pkg>` | `requirements.txt`, `pyproject.toml` |
| Go | `go get <pkg>` | `go mod tidy` | `go.mod` |

**이유**: 패키지 매니저가 버전 해석, lock 파일 갱신, post-install 스크립트 실행을 자동 처리합니다.

**예외**: 패키지 매니저 명령어로 표현할 수 없는 의존성 구성(예: 버전 override, 복합 조건)에 한해 직접 편집 허용.

## 중간 커밋 정책

긴 자동화 실행 중 작업 손실을 방지하기 위해, 검증 통과된 수정 사항을 즉시 커밋합니다.

### 커밋 원칙
1. **검증 후 커밋**: 빌드/테스트(품질 게이트) 통과 후에만 커밋. 깨진 상태를 커밋하지 않음
2. **`[auto]` prefix**: 모든 자동 커밋 메시지는 `[auto]` prefix 사용
3. **`git add -A && git commit -m`**: 신규 생성 파일 포함을 보장 (`.gitignore` 규칙 준수)

### 커밋 시점 (스킬별)
| 스킬 | 커밋 시점 | 메시지 형식 |
|------|----------|-------------|
| implement-docs-auto | 문서 구현 완료 시 | `[auto] {문서명} 구현 완료 [US-X-###]` |
| code-review-loop | 라운드 수정 + 품질 게이트 통과 후 | `[auto] 코드 리뷰 Round {N} 수정 완료 [US-X-###]` |
| full-auto Phase 3 | 라운드 수정 + 품질 게이트 통과 후 | `[auto] Phase 3 코드 리뷰 Round {N} 수정 완료 [US-X-###]` |
| full-auto Phase 4 | Step 4-6.8 진입 시 (잔여 변경 전부 커밋 → 델타 리뷰) | `[auto] Phase 4 폴리싱 변경 커밋 (델타 리뷰 대상)` |
| full-auto Phase 4 design | 디자인 수정 + 품질 게이트 통과 후 | `[auto] Phase 4 디자인 폴리싱 완료` |

### 요구사항 ID (US-*) suffix 규칙

**원칙**: 기능 구현/수정 커밋은 메시지 말미에 관련 User Story ID를 `[US-F-###]` 또는 `[US-B-###]` 형식으로 포함한다. 이를 통해 RTM(Requirements Traceability Matrix)에서 코드 → 요구사항 역추적이 가능하다.

**형식**: `[auto] <내용> [US-X-###]` (여러 US 관련 시 `[US-F-001,US-B-003]` 처럼 쉼표 구분)

**예시**:
- `[auto] 로그인 API 구현 완료 [US-B-001]`
- `[auto] 대시보드 카드 레이아웃 구현 [US-F-003,US-F-004]`
- `[auto] 코드 리뷰 Round 2 수정 완료 [US-B-001]`

**면제 대상 (suffix 불필요)**:
- 프로젝트 스캐폴딩, 의존성/인프라 설정, E2E 프레임워크 설치
- 최종 검증/폴리싱 단계 (여러 US에 걸쳐 적용)
- `Directive:` 트레일러가 포함된 아키텍처 결정 커밋

**검증**: `hooks/bash-guards.sh`(검사 2)가 US-suffix 형식을 검증. `[auto]` prefix 커밋에서 suffix 누락 시 에러 반환. 면제 키워드(`스캐폴딩|scaffolding|infrastructure|E2E 프레임워크|최종 검증|폴리싱|polishing`) 포함 시 통과.

### Git 트레일러 (핵심 결정 시점만)

일반 커밋에는 트레일러 불필요. **다음 상황에서만** 커밋 메시지 본문 뒤에 트레일러를 추가:

| 상황 | 트레일러 | 예시 |
|------|----------|------|
| 스코프 축소 (L4) | `Scope-risk: reduced` | `Scope-risk: WebSocket→polling (L3 3회 실패)` |
| L2+ 에러 에스컬레이션 | `Rejected: <이전 접근법>` | `Rejected: prisma ORM (SQLite 호환 실패)` |
| 아키텍처 결정 (Phase 0-1) | `Directive: <결정>` | `Directive: monorepo with turborepo` |
| 라운드테이블 합의 | `Consensus: <합의 내용>` | `Consensus: REST over GraphQL (roundtable 7/9)` |

형식:
```
[auto] Phase 2 auth 모듈 구현 완료

Directive: JWT + refresh token rotation
Rejected: session-based auth (stateless 요구)
```

## 문서 우선순위 (충돌 해결 규칙)

여러 문서 간 내용이 충돌할 때 아래 우선순위로 해결한다. 상위가 하위를 override한다.

| 순위 | 문서 | 이유 |
|------|------|------|
| 1 | `docs/adr/*.md` (ADR) | 명시적 아키텍처 결정 — 최우선 |
| 2 | `docs/security-authn-authz.md` | 보안은 기능 설계를 제약한다 |
| 3 | `docs/SPEC.md` (API Contract) | 계약 우선 — 엔드포인트/스키마 |
| 4 | `docs/*.md` (기능별 문서) | 기능 상세 |
| 5 | `docs/error-policy.md` | 에러 응답 포맷/코드 체계 |
| 6 | `docs/logging-standard.md` | 관측성 세부 |
| 7 | `docs/DESIGN.md` (디자인 계약) | 시각 결정 — 색/간격/모서리/폰트/상태 표현 |
| 8 | `overview.md` 디자인 원칙 / UI 명세 | DESIGN.md 이전에 적힌 초안 |
| 9 | 기타 | 용어집/README 등 |

**적용 시점**:
- Phase 1 Doc Planning 중 2자 토론에서 문서 간 모순 발견 시 → 상위 문서 유지, 하위 문서 수정
- Phase 2 구현 중 문서가 상충할 때 → 상위 문서 기준 구현, 하위 문서 수정 후 재검증
- 충돌 해결 근거를 `phases.phase_X.conflictResolutions`에 기록

## 강제 규칙 (모든 스킬 공통)
1. **단일 in_progress**: 동시에 하나의 문서/단계만 `in_progress` 상태
2. **완료 전 진행 금지**: `in_progress` 작업이 `completed` 되기 전 다음 작업 시작 금지
3. **스킵 금지**: 어떤 이유로도 `pending` 작업을 건너뛰지 않음
4. **중간 종료 금지**: 모든 작업이 `completed` 될 때까지 종료하지 않음
5. **상태 파일 동기화**: 상태 변경 시 반드시 progress 파일 업데이트
6. **자동 전환**: 작업 완료 → 다음 작업으로 확인 없이 자동 진행
7. **질문 금지**: 명시적으로 허용된 시점 외에는 AskUserQuestion 사용 금지

## 컨텍스트 관리 (전략적 컴팩션)

### 컴팩션 원칙
- **구현 중 컴팩션 금지**: 코드 작성/수정 도중에는 `/compact` 실행하지 않음
- **논리적 경계에서만 실행**: 아래 시점에서 수동 `/compact` 실행
- **PreCompact 훅이 컨텍스트 요약 출력**: compact 요약에 현재 상태가 포함됨 (파일 수정 없음, handoff는 수동 업데이트 필요)

### `/compact` 실행 시점 (논리적 경계)
| 시점 | 설명 |
|------|------|
| Phase 전환 | Phase 0→1, 1→2 등 단계 전환 직전 |
| 마일스톤 완료 | 주요 문서/기능 구현 완료 후 |
| 작업 방향 전환 | 실패한 접근법 → 새 접근법 전환 시 |
| 리서치 → 구현 전환 | 조사/탐색 → 코드 작성 전환 시 |
| "prompt too long" 에러 | 즉시 `/compact` |

### 컴팩션 전 컨텍스트 출력 (PreCompact 훅)
PreCompact 훅이 progress 파일의 현재 상태를 stdout에 출력 → compact 요약에 포함됨.
**주의**: 이 훅은 progress 파일을 수정하지 않음. `/compact` 전에 handoff 필드를 수동 업데이트할 것.

### 컴팩션 후 복구 불가 시
- `/compact` 후에도 "prompt too long" 반복 시:
  1. 현재 진행 상황을 progress 파일에 저장
  2. handoff 필드 업데이트
  3. 세션을 자연스럽게 종료 (Stop Hook이 다음 iteration 자동 시작)

### 메모리 관리
- 각 작업 완료 시 해당 내용은 요약으로만 기억
- 이전 작업의 전체 코드/토론을 누적하지 않음
- 현재 작업에만 집중, 필요시 다른 파일은 다시 읽기

## Handoff 업데이트 (Iteration 종료 전 필수)

progress 파일의 `handoff` 필드를 반드시 업데이트합니다:

```json
"handoff": {
  "lastIteration": N,
  "completedInThisIteration": "이번 iteration에서 완료한 작업 요약",
  "nextSteps": "다음 iteration에서 바로 시작할 작업 + 필요한 맥락",
  "keyDecisions": ["이번 iteration에서 내린 설계 결정과 이유"],
  "warnings": "주의사항, 알려진 이슈, 기술 부채",
  "currentApproach": "현재 사용 중인 아키텍처/패턴/구조"
}
```

**Iteration 시작 시 handoff 읽기:**
1. progress 파일 로드
2. `handoff.nextSteps`를 최우선으로 확인 → 여기서 시작
3. `handoff.keyDecisions`로 이전 결정 맥락 복구
4. `handoff.warnings`로 주의사항 인지
5. `handoff.currentApproach`로 진행 구조 맥락 복구

**handoff 갱신은 stop-hook이 검사한다** — 완주 선언 시 `handoff.lastIteration`이 방금 끝난 iteration과 다르면 차단된다.
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh handoff-update --next-steps "..."`로 갱신한다
(`--iteration`을 생략하면 Ralph frontmatter의 현재 iteration — stop-hook이 보는 값 — 이 자동으로 들어간다).

## 결정 기록 (단일 출처)

**이유 없는 결정은 잘못된 결정이다.** 어떤 결정을 어떤 이유로 내렸는지가 남지 않으면
다음 iteration·다음 세션·다음 사람이 같은 것을 다시 결정하고, 되돌리는 비용은 그때 발생한다.

### 원칙

1. **모든 결정에는 이유가 있어야 한다.** 사유 없이 내린 결정은 기록할 수 없고(스크립트가 거부),
   기록할 수 없는 결정은 내려서는 안 된다.
2. 기록 항목은 4가지다 — **무엇을(what) / 왜(why) / 무엇과 비교했나(alternatives) / 되돌릴 수 있나(reversible)**.
   되돌리기 비싼 결정(다른 US가 의존하게 되는 구조·공용 유틸·상태 관리 방식)은 `--reversible no`로 남긴다.
3. **기록 위치는 한 곳이다** — `.claude/acl-decisions.jsonl` (append-only, `record-decision`만 쓴다 —
   Edit/Write·Bash 경유 직접 쓰기는 훅이 차단한다. 이유 검사를 우회한 줄은 기록이 아니다).
   ADR·provenance 마커·`docs/CLARIFICATIONS.md`·`severityAdjustments`는 각자의 목적(구조 설명·출처 표시·질문 추적·심각도 근거)
   그대로 유지하되, **결정이 발생한 사실 자체는 반드시 이 로그에도 미러링**한다(`--source`로 원 채널 표시).
4. **iteration당 최소 1건.** 결정이 없었다면 없었다는 사실을 남긴다(`--none --why "<왜 없었는지>"`).

### 사용법

```bash
# 결정 1건 기록 (why 필수 — 공백 제외 10자 미만이면 exit 1)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-decision \
  --what "인증을 JWT + refresh token으로 확정" \
  --why "세션 스토어 없이 수평 확장해야 하고 만료·갱신 규약이 SPEC AC-F-003에 이미 명시되어 있다" \
  --alternatives "서버 세션 쿠키(수평 확장 시 스토어 필요)" \
  --reversible no --scope planning --source adr

# 이번 iteration에 결정이 없었음
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-decision --none \
  --why "문서 오탈자 수정만 수행했고 설계·구현 선택지가 발생하지 않았다"

# 조회 (기본은 이번 실행(runId)의 기록만 — 이전 실행까지 보려면 --all)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-decision --list --last 5
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-decision --list --all
```

| 옵션 | 값 | 의미 |
|------|-----|------|
| `--what` | 문자열 (필수) | 결정 내용 |
| `--why` | 문자열 (필수, 공백 제외 10자 이상) | 결정 이유. 없으면 기록 자체가 거부된다 |
| `--alternatives` | 문자열 (반복 가능) | 검토한 대안과 탈락 사유 |
| `--reversible` | `yes`(기본) \| `no` | 되돌리기 비용 |
| `--scope` | `interview` \| `planning` \| `implementation` \| `review` \| `escalation` \| `other` | 결정이 난 국면 |
| `--source` | `adr` \| `provenance` \| `clarification` \| `severity` \| `scope-reduction` \| `inline` | 원 채널 |
| `--phase` / `--iteration` | 문자열 / 정수 | 생략 시 ralph-loop·progress에서 자동 |

기록되는 것: `.claude/acl-decisions.jsonl` 한 줄(JSON) + `decision.recorded` 이벤트 +
`handoff.keyDecisions`에 `"D-NNNN: <what> — <why>"` **append**(`--none`은 append하지 않음).
각 줄에는 progress의 `runId`(init이 실행마다 발급)가 함께 박힌다 — **실행 식별자**다.

> `handoff-update --decision`은 `handoff.keyDecisions`에 **append**만 하는 하위호환 옵션이며
> 결정 로그에는 남지 않는다. 완주 검사를 통과시키는 것은 `record-decision`뿐이다.

### 강제

stop-hook이 완주 선언 시 **이번 iteration의 결정 기록이 0건이면 차단**한다
(progress에 `decisionLog.enabled`가 있는 워크플로우 — `init`으로 만든 모든 템플릿이 해당).

**실행 격리(runId)**: 검사는 iteration뿐 아니라 **현재 실행의 runId**로도 필터링한다. 이전 실행이
남긴 `.claude/acl-decisions.jsonl`의 옛 기록이 다음 실행의 검사를 대신 통과시키는 일이 없다
(progress에 `runId`가 없는 v4.20 이하 파일은 iteration만 보는 하위호환 경로). 완주에 성공하면
결정 로그도 progress·이벤트 로그와 함께 아카이브된다 — 같은 방어를 두 겹으로 둔다.

**assumption 교차 검증**: `assumption-review --status confirmed --count N`의 `N`은 자기신고가 아니라
이번 실행의 `record-decision --scope interview` 기록 건수와 대조되며, 다르면 exit 1이다.

어떤 지점에서 record-decision을 호출해야 하는지는 각 스킬/커맨드 문서에 지점별로 명시되어 있다.

## 외부 AI 자체 탐색 (codex 호출 시)
- codex에게 **파일 경로**를 전달하여 직접 읽도록 함
- Claude가 문서 내용을 요약/가공하여 프롬프트에 embed하지 않음 (요약 편향 방지)
- 코드 전체가 아닌 **핵심 부분만** 전달 (최대 100줄)
- 이전 토론 내용은 결론만 요약해서 전달

## 증거 기반 완료 선언 (필수)

**완료 선언 전 반드시 실행 결과 확인:**
- 빌드 성공 로그 (exit code 0 확인)
- 테스트 통과 로그 (PASSED 개수 확인)
- 린트 통과 로그
- `.claude-verification.json`에 기록 완료 (게이트 서브커맨드 자동 기록 + 소프트 차원은 `record-dimension` — 직접 편집은 가드가 차단함)
- progress 파일의 dod 체크리스트 전체 checked + evidence 포함

**금지 (실행 없이 선언):**
- "아마 통과할 것입니다"
- "테스트가 성공할 것입니다"
- 이전 실행 결과 재사용

**원칙:** evidence 없으면 checked=true 불가. 로그 없으면 완료 없음.

## 모델 라우팅 가이드

서브에이전트 또는 Agent 도구 사용 시 모델 선택 기준:

| 모델 | 용도 | 예시 |
|------|------|------|
| **Sonnet** | 메인 서브에이전트, 코드 구현, 멀티에이전트 오케스트레이션 | Explore, 코드 리뷰, 구현 에이전트 |
| **Opus** | 복잡한 아키텍처 결정, 심층 분석, 리서치 | Plan, 보안 분석, 근본 원인 분석 |

- **Haiku는 사용하지 않음**
- 모델 미지정 시 부모 세션의 모델을 상속
- Agent 도구의 `model` 파라미터로 지정: `"model": "sonnet"` 또는 `"model": "opus"`
