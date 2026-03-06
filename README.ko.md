# Auto Complete Loop

[English](README.md)

AI 코딩 완주 프레임워크. Ralph Loop 내장 + DoD/SPEC/TDD/Fresh Context Verification으로 AI가 끝까지 완성하도록 강제합니다.

## 설치

Claude Code 플러그인으로 설치:
```bash
claude plugins install /path/to/auto-complete-loop
```

설치 후 기존 `~/.claude/commands/`의 동명 파일(implement-docs-auto.md, plan-docs-auto-gemini.md, polish-for-release-gemini.md)을 삭제하세요 (충돌 방지).

## 명령어

### `/implement-docs-auto <definition> <doclist>`
기획 문서를 실제 코드로 구현합니다. Ralph Loop이 자동 활성화되어 완료까지 반복합니다.

### `/plan-docs-auto <definition> <doclist>`
기획 문서를 2자 자동 토론(codex-cli, Claude Code)으로 완성합니다.

### `/plan-docs-auto-gemini <definition> <doclist>`
기획 문서를 3자 자동 토론(codex-cli, Gemini, Claude Code)으로 완성합니다.

### `/polish-for-release [definition] [doclist]`
프로덕션 릴리즈 전 폴리싱을 수행합니다. codex-cli와 Claude Code 2자 토론.

### `/polish-for-release-gemini [definition] [doclist]`
프로덕션 릴리즈 전 폴리싱을 수행합니다. codex-cli, Gemini, Claude Code 3자 토론.

### `/code-review-loop [--rounds N | --goal "조건"] <scope>`
코드 리뷰를 자동 반복 수행합니다. codex-cli가 SEC/ERR/DATA/PERF/CODE 전 관점에서 독립 리뷰 후 Claude Code가 검증/수정.
- 기본: 3라운드 리뷰→수정 반복
- `--rounds N`: N라운드 반복
- `--goal "CRITICAL/HIGH 0개"`: 목표 달성까지 반복 (최대 10라운드)

### `/code-review-loop-gemini [--rounds N | --goal "조건"] <scope>`
코드 리뷰를 자동 반복 수행합니다. codex-cli(SEC/ERR/DATA) + gemini-cli(PERF/CODE) 3자 독립 리뷰 후 Claude Code가 검증/수정.
- 기본: 3라운드 리뷰→수정 반복
- `--rounds N`: N라운드 반복
- `--goal "CRITICAL/HIGH 0개"`: 목표 달성까지 반복 (최대 10라운드)

### `/full-auto <요구사항>`
전체 프로젝트 라이프사이클을 자동 수행합니다.
- Phase 0: 요구사항 확장 + 사용자 승인 (유일한 상호작용)
- Phase 1: codex 토론으로 기획 문서 완성
- Phase 2: TDD 기반 코드 구현
- Phase 3: codex 코드 리뷰 (3라운드)
- Phase 4: 릴리즈 검증 및 폴리싱

### `/check-docs [docs_dir]`
문서 정합성을 검증합니다. doc↔doc 일관성 + doc↔code 매칭을 스크립트+AI로 검증하고 자동 수정.
- 1단계: 스크립트 구조적 검사 (doc-consistency + doc-code-check)
- 2단계: codex 의미적 검증 (데이터 모델, API, 용어 일관성)
- 3단계: 최종 확인 (스크립트 재실행)

### `/add-e2e [docs_dir]`
기존 프로젝트에 E2E 테스트를 추가합니다.
- 문서 경로 지정 시: 문서 분석 → 문서↔코드 정합성 → 시나리오 도출
- 인수 없이 실행 시: 코드 분석 → 핵심 플로우 추론 → 회귀 방지 테스트 작성
- 프레임워크 자동 선택: Web→Playwright, Flutter→integration_test, Mobile→Maestro

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
│   ├── implement-docs-auto.md           # 기획 문서 → 코드 구현
│   ├── plan-docs-auto.md               # 기획 문서 2자 토론 완성
│   ├── plan-docs-auto-gemini.md         # 기획 문서 3자 토론 완성 (gemini 포함)
│   ├── polish-for-release.md            # 릴리즈 전 폴리싱 (2자)
│   ├── polish-for-release-gemini.md     # 릴리즈 전 폴리싱 (3자, gemini 포함)
│   ├── code-review-loop.md             # 코드 리뷰 자동 반복 (2자)
│   ├── code-review-loop-gemini.md       # 코드 리뷰 자동 반복 (3자, gemini 포함)
│   ├── full-auto.md                     # 기획→구현→검수 올인원
│   ├── add-e2e.md                       # 기존 프로젝트에 E2E 테스트 추가
│   └── check-docs.md                    # 문서 정합성 검증 (doc↔doc + doc↔code)
├── hooks/
│   ├── hooks.json                       # Hook 설정
│   └── stop-hook.sh                     # Stop hook (Ralph Loop 확장)
├── scripts/
│   └── shared-gate.sh                   # 범용 품질 게이트 + 유틸리티
├── rules/shared-rules.md               # 모든 스킬 공통 규칙
├── templates/                           # DONE.md, SPEC.md 템플릿
├── README.md                           # 영어
└── README.ko.md                        # 한국어
```

## shared-gate.sh 서브커맨드

| 서브커맨드 | 용도 |
|-----------|------|
| `init --template <type>` | progress JSON 초기화 (full-auto/plan/implement/review/polish/e2e/doc-check) |
| `init-ralph <promise> <progress_file> [max]` | Ralph Loop 파일 생성 |
| `status` | 현재 상태 요약 출력 |
| `update-step <step> <status>` | 단계 상태 전이 (동적 검증) |
| `quality-gate` | 빌드/타입/린트/테스트 일괄 실행 + verification.json 기록 |
| `record-error --file --type --msg` | 에러 반복 판별 + errorHistory 업데이트 |
| `check-tools` | codex/gemini CLI 존재 확인 |
| `find-debug-code [dir]` | console.log/print/debugger 탐색 |
| `doc-consistency [dir]` | 문서 간 일관성 검사 |
| `doc-code-check [dir]` | 문서↔코드 매칭 |
| `e2e-gate` | E2E 테스트 프레임워크 감지 + 실행 |

글로벌 옵션: `--progress-file <path>` (미지정 시 자동 탐지)
