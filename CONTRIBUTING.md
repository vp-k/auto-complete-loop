# Contributing to auto-complete-loop

이 문서는 **플러그인 저자용** 가이드입니다. 워크플로우 실행 중 모델이 따르는 런타임 규칙은
`rules/` 아래에 있습니다 (`shared-rules.md`, `orchestration-rules.md`, `error-escalation-rules.md`,
`project-size-rules.md`).

## 에이전트 정의 형식 (YAML Frontmatter)

`agents/` 디렉토리에 에이전트를 정의할 때 YAML frontmatter 형식을 사용합니다:

```markdown
---
name: agent-name
description: 에이전트의 역할 (한 줄)
model: sonnet
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Agent Name

에이전트의 상세 동작 로직...
```

**필수 필드:**
- `name`: 에이전트 식별자 (kebab-case)
- `description`: 트리거 판단에 사용되는 설명
- `model`: `sonnet` 또는 `opus` (Haiku 사용 금지)

**선택 필드:**
- `tools`: 사용 가능한 도구 제한 목록 (미지정 시 모든 도구 사용 가능)

모델 선택 기준(Sonnet vs Opus)은 `rules/shared-rules.md`의 "모델 라우팅 가이드"를 따릅니다.

## 훅

훅은 `hooks/hooks.json`에 등록된 것만 실행됩니다. 새 훅 파일을 추가했다면 반드시
`hooks.json`에 배선하세요 — 등록되지 않은 스크립트는 죽은 코드입니다.

Bash 계열 가드는 단일 디스패처 `hooks/bash-guards.sh`에 검사를 추가하는 방식으로 확장합니다
(PreToolUse:Bash 훅이 여러 개면 실행 순서/입력 소비가 얽힙니다).

## 테스트

```bash
bats tests/
```

셸 스크립트를 수정했으면 `bash -n <file>`로 문법을 먼저 확인하세요.

## 버전

동작이 바뀌는 변경은 `.claude-plugin/plugin.json`의 `version`과 `README.md` 상단 버전 표기를
함께 올립니다 (SemVer).
