---
description: "End-to-end project automation. One-line requirement to planning → implementation → code review → verification"
argument-hint: <요구사항 (자연어)>
---

# Full Auto: 기획→구현→검수 올인원 (오케스트레이터)

한 줄 요구사항으로 **기획 문서 작성 → 코드 구현 → 코드 리뷰 → 최종 검증**까지 자동 완주합니다.

**역할 분담** (모드별):
- **codex** (기본): Claude = PM + 구현자, Codex = 기획 토론 + 코드 리뷰
- **solo**: Claude = PM + 구현자 + 기획 토론(다관점) + 코드 리뷰(다관점)
- **teams**: Claude(리드) = PM + 구현 + 리뷰 조율, Teammates = 독립 리뷰 + 상호 도전

**핵심 원칙**: Phase 0에서만 사용자 질문, 이후 완전 자동 | MVP 금지, 릴리즈 수준 | 스크립트로 토큰 절약

## 파라미터 (모드별)

| 파라미터 | codex (기본) | solo | teams |
|----------|-------------|------|-------|
| PROMISE_TAG | `FULL_AUTO_COMPLETE` | `FULL_AUTO_COMPLETE` | `FULL_AUTO_TEAMS_COMPLETE` |
| PROGRESS_FILE | `.claude-full-auto-progress.json` | `.claude-full-auto-progress.json` | `.claude-full-auto-teams-progress.json` |
| PHASE_1_SKILL | `skills/doc-planning/SKILL.md` | `skills/doc-planning-solo/SKILL.md` | `skills/doc-planning/SKILL.md` |
| PHASE_3_SKILL | `skills/code-review/SKILL.md` | `skills/code-review-solo/SKILL.md` | `skills/team-code-review/SKILL.md` |
| PHASE_3_STEPS | Step 3-1 ~ 3-4 | Step 3-1 ~ 3-4 | Step 3-1 ~ 3-7 |

`--mode` 미지정 시 codex 모드를 사용합니다.

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "커뮤니티 사이트를 만들어줘")
- `--mode <solo|codex|teams>` (선택): 리뷰 모드 선택 (기본: codex)
  - `codex`: Claude + codex-cli 2자 (기본값)
  - `solo`: Claude 단독 다관점 리뷰 (외부 AI 불필요)
  - `teams`: Agent Teams 3자 병렬 리뷰 (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 필요)
- `--start-phase N` (선택): Phase N부터 시작 (0-4). 이미 기획 문서가 있는 프로젝트에서 Phase 0-1 스킵용.
  - 예: `/full-auto --start-phase 2 커뮤니티 사이트` → Phase 2(구현)부터 시작
  - 스킵된 Phase의 DoD는 자동으로 `{checked: true, evidence: "skipped by user (--start-phase N)"}` 처리
  - `--start-phase 2` 사용 시 docs/ 폴더에 기획 문서가 존재해야 함 (없으면 경고 후 Phase 0부터 시작)

## 아키텍처: 오케스트레이터 + Phase 스킬

```
이 파일 (오케스트레이터) — Ralph Loop, Phase 전이, Progress 관리 소유 (유일)
    ↓ Read로 Phase별 스킬 로드
    ├── skills/pm-planning/SKILL.md        (Phase 0 순수 로직)
    ├── {PHASE_1_SKILL}                    (Phase 1 — 모드별 스킬 참조)
    ├── skills/implementation/SKILL.md     (Phase 2 순수 로직)
    ├── {PHASE_3_SKILL}                    (Phase 3 — 모드별 스킬 참조)
    └── skills/verification/SKILL.md       (Phase 4 순수 로직)
```

**단일 소스 원칙**: 규칙은 각 스킬 파일과 공유 규칙 파일에만 존재. 이 파일은 오케스트레이션만 담당.

## 5-Phase 워크플로우

```
Phase 0: PM Planning ─── 사용자 승인 (유일한 상호작용)
    ↓
Phase 1: Planning ───── {PHASE_1_SKILL}로 기획 문서 완성
    ↓ [일관성 검사 #1: doc↔doc]
    ↓ [Pre-mortem 가드: blocking Tiger 미해결 시 Phase 2 진입 금지]
Phase 2: Implementation ── Claude 직접 구현 + TDD
    ↓ [일관성 검사 #2: doc↔code]
Phase 3: Code Review ──── {PHASE_3_SKILL}로 리뷰 + Claude 수정
    ↓ [일관성 검사 #3: code quality]
Phase 4: Verification ─── 최종 검증 + 폴리싱 + Launch Readiness
    ↓
<promise>FULL_AUTO_COMPLETE</promise>
```

## --mode 처리

`$ARGUMENTS`에서 `--mode <value>`를 감지하면:

1. `$ARGUMENTS`에서 `--mode <value>` 부분을 제거하여 순수 요구사항만 추출
2. value 검증: `solo`, `codex`, `teams` 중 하나
3. 위 "파라미터 (모드별)" 테이블에서 해당 모드의 값을 적용
4. **teams 모드 전제 조건**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` 환경 변수 확인
   - 미설정 시: `~/.claude/settings.json`에 자동 추가 후 새 세션 안내 및 중단
5. `--mode` 미지정 시 기본값 `codex` 적용

## --start-phase 처리

`$ARGUMENTS`에서 `--start-phase N`을 감지하면:

1. `$ARGUMENTS`에서 `--start-phase N` 부분을 제거하여 순수 요구사항만 추출
2. N 값 검증 (0-4 정수)
3. docs/ 폴더 존재 확인 (N >= 2일 때):
   - docs/ 존재 + 기획 문서 1개 이상 → 정상 진행
   - docs/ 미존재 또는 빈 폴더 → "기획 문서가 없습니다. Phase 0부터 시작합니다." 경고 후 N=0으로 폴백
4. init 후 Phase 스킵 실행:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh init "<프로젝트명>" "<요구사항>" --progress-file {PROGRESS_FILE}
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh skip-phases <N> --progress-file {PROGRESS_FILE}
   ```
5. Phase N의 스킬을 Read하여 해당 Phase부터 시작

## 공통 규칙 로드

```
Read ${CLAUDE_PLUGIN_ROOT}/rules/orchestration-rules.md
Read ${CLAUDE_PLUGIN_ROOT}/rules/phase-transition-rules.md
```

위 두 파일에 정의된 파라미터(`{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`)는
이 파일 상단의 "파라미터" 섹션 값으로 치환하여 적용합니다.
