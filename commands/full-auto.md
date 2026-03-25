---
description: "기획→구현→검수 올인원. 한 줄 요구사항으로 기획 문서→코드 구현→코드 리뷰→최종 검증까지 자동 완주"
argument-hint: <요구사항 (자연어)>
---

# Full Auto: 기획→구현→검수 올인원 (오케스트레이터)

한 줄 요구사항으로 **기획 문서 작성 → 코드 구현 → 코드 리뷰 → 최종 검증**까지 자동 완주합니다.

**역할 분담**: Claude = PM + 구현자, Codex = 기획 토론 + 코드 리뷰
**핵심 원칙**: Phase 0에서만 사용자 질문, 이후 완전 자동 | MVP 금지, 릴리즈 수준 | 스크립트로 토큰 절약

## 파라미터

- PROMISE_TAG: `FULL_AUTO_COMPLETE`
- PROGRESS_FILE: `.claude-full-auto-progress.json`
- PHASE_3_SKILL: `skills/code-review/SKILL.md`
- PHASE_3_STEPS: Step 3-1 ~ 3-4

## 인수

- `$ARGUMENTS`: 자연어 요구사항 (예: "커뮤니티 사이트를 만들어줘")

## 아키텍처: 오케스트레이터 + Phase 스킬

```
이 파일 (오케스트레이터) — Ralph Loop, Phase 전이, Progress 관리 소유 (유일)
    ↓ Read로 Phase별 스킬 로드
    ├── skills/pm-planning/SKILL.md     (Phase 0 순수 로직)
    ├── skills/doc-planning/SKILL.md    (Phase 1 순수 로직)
    ├── skills/implementation/SKILL.md  (Phase 2 순수 로직)
    ├── skills/code-review/SKILL.md     (Phase 3 순수 로직)
    └── skills/verification/SKILL.md    (Phase 4 순수 로직)
```

**단일 소스 원칙**: 규칙은 각 스킬 파일과 공유 규칙 파일에만 존재. 이 파일은 오케스트레이션만 담당.

## 5-Phase 워크플로우

```
Phase 0: PM Planning ─── 사용자 승인 (유일한 상호작용)
    ↓
Phase 1: Planning ───── codex 토론으로 기획 문서 완성
    ↓ [일관성 검사 #1: doc↔doc]
    ↓ [Pre-mortem 가드: blocking Tiger 미해결 시 Phase 2 진입 금지]
Phase 2: Implementation ── Claude 직접 구현 + TDD
    ↓ [일관성 검사 #2: doc↔code]
Phase 3: Code Review ──── codex 리뷰 + Claude 수정
    ↓ [일관성 검사 #3: code quality]
Phase 4: Verification ─── 최종 검증 + 폴리싱 + Launch Readiness
    ↓
<promise>FULL_AUTO_COMPLETE</promise>
```

## 공통 규칙 로드

```
Read ${CLAUDE_PLUGIN_ROOT}/rules/orchestration-rules.md
Read ${CLAUDE_PLUGIN_ROOT}/rules/phase-transition-rules.md
```

위 두 파일에 정의된 파라미터(`{PROMISE_TAG}`, `{PROGRESS_FILE}`, `{PHASE_3_SKILL}`)는
이 파일 상단의 "파라미터" 섹션 값으로 치환하여 적용합니다.
