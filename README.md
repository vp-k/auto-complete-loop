# Auto Complete Loop

AI 코딩 완주 프레임워크. Ralph Loop 내장 + DoD/SPEC/TDD/Fresh Context Verification으로 AI가 끝까지 완성하도록 강제합니다.

## 설치

Claude Code 플러그인으로 설치:
```bash
claude plugins install /path/to/auto-complete-loop
```

설치 후 기존 `~/.claude/commands/`의 동명 파일(implement-docs-auto.md, plan-docs-auto-gemini.md, polish-for-release-gemini.md)을 삭제하세요 (충돌 방지).

## 명령어

### `/full-auto <요구사항>` (핵심)
전체 프로젝트 라이프사이클을 자동 수행합니다.
- **Phase 0: PM Planning** — Problem/Persona/JTBD/우선순위/가정/Pre-mortem/성공기준 + 사용자 승인
- **Phase 1: Planning** — codex 토론으로 기획 문서 완성
- **Phase 2: Implementation** — TDD 기반 코드 구현
- **Phase 3: Code Review** — codex 코드 리뷰 (3라운드)
- **Phase 4: Verification** — 릴리즈 검증 + 폴리싱 + Launch Readiness

### `/implement-docs-auto <definition> <doclist>`
기획 문서를 실제 코드로 구현합니다. Ralph Loop이 자동 활성화되어 완료까지 반복합니다.

### `/plan-docs-auto <definition> <doclist>`
기획 문서를 2자 자동 토론(codex-cli, Claude Code)으로 완성합니다.

### `/plan-docs-auto-gemini <definition> <doclist>`
기획 문서를 3자 자동 토론(codex-cli, Gemini, Claude Code)으로 완성합니다.

### `/polish-for-release [definition] [doclist]`
프로덕션 릴리즈 전 폴리싱을 수행합니다. codex-cli와 Claude Code 2자 토론.

### `/code-review-loop [--rounds N | --goal "조건"] <scope>`
코드 리뷰를 자동 반복 수행합니다. codex-cli가 SEC/ERR/DATA/PERF/CODE 전 관점에서 독립 리뷰.

### `/code-review-loop-gemini [--rounds N | --goal "조건"] <scope>`
3자 독립 리뷰 (codex-cli + gemini-cli).

### `/check-docs [docs_dir]`
문서 정합성을 검증합니다. doc↔doc 일관성 + doc↔code 매칭을 스크립트+AI로 검증하고 자동 수정.

### `/add-e2e [docs_dir]`
기존 프로젝트에 E2E 테스트를 추가합니다.

### `/interview-prep <overview.md 경로>` (P1)
페르소나 기반 인터뷰 스크립트를 The Mom Test 원칙으로 자동 생성. standalone, full-auto 전에 선택적 사용.

### `/interview-summary <인터뷰 기록>`
인터뷰 기록에서 패턴 추출 및 요구사항 도출. standalone.

## 아키텍처

### 오케스트레이터 + Phase 스킬 분리

```
commands/full-auto.md (~200줄, 오케스트레이션 전용)
    ├── Ralph Loop 소유 (유일)
    ├── Phase 전이 로직 소유 (유일)
    ├── Progress JSON 관리 소유 (유일)
    ├── Promise 태그 소유 (유일)
    └── 각 Phase 진입 시 해당 스킬 Read 지시

skills/pm-planning/SKILL.md      (~300줄, Phase 0 — PM Planning)
skills/doc-planning/SKILL.md     (~200줄, Phase 1 — 기획 문서 토론)
skills/implementation/SKILL.md   (~200줄, Phase 2 — 코드 구현)
skills/code-review/SKILL.md      (~100줄, Phase 3 — 코드 리뷰)
skills/verification/SKILL.md     (~150줄, Phase 4 — 검증 + Launch Readiness)
```

기존 command(`plan-docs-auto.md`, `implement-docs-auto.md`, `code-review-loop.md`)는 **독립 실행용으로 유지**. full-auto에서는 사용하지 않고, 사용자가 개별 호출 시에만 동작.

### Phase 0: PM Planning 강화

| Step | 내용 |
|------|------|
| 0-0 | 프로젝트 규모 1차 판별 (Small/Medium/Large) |
| 0-1 | Problem Statement, 페르소나, JTBD, 트레이드오프 |
| 0-2 | 기능 도출 + 3단계 우선순위 (MoSCoW → ICE → Kano) |
| 0-3 | 가정 식별 + Impact×Risk 우선순위화 (Discovery) |
| 0-4 | 핵심 User Stories + (Medium+) 사용자 플로우 |
| 0-5 | 디자인 원칙 수립 |
| 0-6 | 성공 기준 (NSM + Success Criteria) |
| 0-7 | Codex 검토 + Pre-mortem (Tigers/Paper Tigers/Elephants) |
| 0-8 | (Large만) 이해관계자 맵 |
| 0-9 | 피드백 반영 + 문서 생성 |
| 0-9.5 | 프로젝트 규모 2차 재판정 |
| 0-10 | 사용자 승인 |
| 0-11 | Phase 0 결과 기록 (outputs + DoD 업데이트) |

### Pre-mortem 하드 게이트

Phase 1 → Phase 2 전이 시, `blocking: true`인 Tiger의 `mitigation`이 비어있으면 **Phase 2 진입 금지**. Phase 1에서 대응책을 수립해야 합니다.

### Launch Readiness (Phase 4 확장)

Phase 4 Step 4-4에서:
- 릴리즈 노트 자동 생성 (`[auto]` 커밋 필터링)
- (Flutter) 앱 스토어 메타데이터 템플릿
- 배포 체크리스트

### Progress JSON v2

```json
{
  "schemaVersion": 2,
  "dod": {
    "assumptions_documented": {...},
    "premortem_done": {...},
    "launch_ready": {...},
    ...기존 DoD 항목
  },
  "phases": {
    "phase_0": {
      "outputs": {
        "assumptions": [...],
        "nsm": null,
        "successCriteria": [...],
        "premortem": {"tigers":[],"paperTigers":[],"elephants":[]},
        "projectSize": null,
        "stakeholders": null,
        ...기존 outputs
      }
    }
  }
}
```

기존 v1 파일은 `shared-gate.sh`가 자동 마이그레이션 (idempotent).

## 핵심 메커니즘

### Ralph Loop 내장
- Stop Hook이 세션 종료를 물리적으로 차단
- completion-promise + 검증 파일(.claude-verification.json)로 거짓 완료 방지
- Iteration 단위 작업 분할로 컨텍스트 고갈 방지

### 5원칙 통합
1. **DoD (Definition of Done)**: DONE.md 템플릿으로 완료 기준 명확화
2. **SPEC**: SPEC.md 템플릿으로 구현 기준 명확화
3. **티켓 분할**: 문서를 독립 검증 가능한 티켓으로 분할
4. **Fresh Context Verification**: 별도 AI가 fresh context에서 검증
5. **Handoff**: Iteration 간 맥락(왜/어떻게) 전달

## 파일 구조

```
auto-complete-loop/
├── .claude-plugin/plugin.json           # 플러그인 메타데이터
├── commands/
│   ├── full-auto.md                     # 기획→구현→검수 올인원 (오케스트레이터)
│   ├── implement-docs-auto.md           # 기획 문서 → 코드 구현 (독립)
│   ├── plan-docs-auto.md               # 기획 문서 2자 토론 (독립)
│   ├── plan-docs-auto-gemini.md         # 기획 문서 3자 토론 (독립)
│   ├── polish-for-release.md            # 릴리즈 전 폴리싱 (독립)
│   ├── code-review-loop.md             # 코드 리뷰 자동 반복 (독립)
│   ├── code-review-loop-gemini.md       # 코드 리뷰 3자 (독립)
│   ├── check-docs.md                    # 문서 정합성 검증 (독립)
│   ├── add-e2e.md                       # E2E 테스트 추가 (독립)
│   ├── interview-prep.md                # 인터뷰 스크립트 생성 (standalone)
│   └── interview-summary.md             # 인터뷰 기록 분석 (standalone)
├── skills/
│   ├── pm-planning/SKILL.md             # Phase 0 PM Planning (full-auto 전용)
│   ├── doc-planning/SKILL.md            # Phase 1 기획 토론 (full-auto 전용)
│   ├── implementation/SKILL.md          # Phase 2 구현 (full-auto 전용)
│   ├── code-review/SKILL.md             # Phase 3 코드 리뷰 (full-auto 전용)
│   └── verification/SKILL.md            # Phase 4 검증+Launch (full-auto 전용)
├── hooks/
│   └── stop-hook.sh                     # Stop hook (Ralph Loop)
├── scripts/
│   └── shared-gate.sh                   # 범용 품질 게이트 + 유틸리티
├── rules/shared-rules.md               # 모든 스킬 공통 규칙
├── templates/                           # DONE.md, SPEC.md 템플릿
└── README.md
```

## shared-gate.sh 서브커맨드

| 서브커맨드 | 용도 |
|-----------|------|
| `init --template <type>` | progress JSON 초기화 (full-auto/plan/implement/review/polish/e2e/doc-check) |
| `init-ralph <promise> <progress_file> [max]` | Ralph Loop 파일 생성 |
| `status` | 현재 상태 요약 출력 (schemaVersion 자동 마이그레이션) |
| `update-step <step> <status>` | 단계 상태 전이 (schemaVersion 자동 마이그레이션) |
| `quality-gate` | 빌드/타입/린트/테스트 일괄 실행 + verification.json 기록 |
| `record-error --file --type --msg` | 에러 반복 판별 + errorHistory 업데이트 |
| `secret-scan` | 시크릿 유출 스캔 (HARD_FAIL) |
| `artifact-check` | 빌드 아티팩트 검증 (SOFT_FAIL) |
| `smoke-check [--strict] [port] [timeout]` | 서버 기동 + 헬스체크 + SPEC.md 엔드포인트 검증. `--strict` 시 soft_fail→FAIL 승격 |
| `check-tools` | codex/gemini CLI 존재 확인 |
| `find-debug-code [dir]` | console.log/print/debugger 탐색 |
| `doc-consistency [dir]` | 문서 간 일관성 검사 |
| `doc-code-check [dir]` | 문서↔코드 매칭 |
| `e2e-gate` | E2E 테스트 프레임워크 감지 + 실행 |
| `design-polish-gate [--strict]` | WCAG 체크 + 스크린샷 캡처. `--strict` 시 WCAG 위반→FAIL 승격 |
| `placeholder-check` | TODO/placeholder/FIXME 잔존 감지 (HARD_FAIL) |
| `external-service-check` | SPEC.md 기반 외부 서비스 SDK/config 존재 확인 (HARD_FAIL) |
| `service-test-check` | 백엔드 서비스/라우트 통합 테스트 존재 확인 (HARD_FAIL) |
| `integration-smoke` | 프론트↔백 연동 검증: API URL, CORS, 서버 기동 (HARD_FAIL) |
| `add-dod-key <key>` | DoD 키 동적 추가 (idempotent) |

글로벌 옵션: `--progress-file <path>` (미지정 시 자동 탐지)
