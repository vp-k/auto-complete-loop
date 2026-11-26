# Contributing to auto-complete-loop

이 문서는 **플러그인 저자용** 가이드입니다. 워크플로우 실행 중 모델이 따르는 런타임 규칙은
`rules/` 아래에 있습니다 (`shared-rules.md`, `orchestration-rules.md`, `error-escalation-rules.md`,
`project-size-rules.md`).

릴리스에서 미룬 항목은 `TODO.md`가 단일 출처입니다. 보고의 "남은 것"에 적은 항목은 반드시 거기에 체크박스로 남깁니다.

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

## 결정 기록

이 플러그인을 고치는 작업 자체에도 같은 규칙이 적용됩니다 — **이유 없는 결정은 기록할 수 없고,
기록할 수 없는 결정은 내리지 않습니다.** 새 게이트/훅 검사/기본값을 정했다면:

```bash
bash scripts/shared-gate.sh record-decision \
  --what "<무엇을 정했나>" --why "<왜 이 선택인가>" \
  --alternatives "<검토하고 버린 것>" --reversible yes|no --scope <국면> --source <원 채널>
```

규칙의 단일 출처는 `rules/shared-rules.md`의 "결정 기록 (단일 출처)"입니다.
새 결정 지점을 문서에 배선할 때는 그 절을 복제하지 말고 **호출 지시 + 참조**만 남기세요
(같은 규칙이 두 곳에 있으면 한쪽만 갱신되어 갈라집니다).

## 새 게이트·검사를 추가할 때 (v4.26.0)

게이트와 훅 검사는 모델이 이미 저지른 실수를 막으려고 생긴다. 실수가 없는 곳에 둔 검사는 비용만 남는다.
새 검사를 넣기 전에 아래 세 가지를 확인한다.

1. **표의 위쪽 층부터 시도한다.** 위쪽일수록 실수가 아예 일어나지 않는다. 위쪽 층으로 막을 수 없을 때만 아래로 내려간다.

   | 순서 | 층 | 예 |
   |------|----|----|
   | 1 | 구조 | 그 실수가 일어날 경로 자체를 없앤다. 예: 보호 파일을 스크립트만 쓰게 한다 |
   | 2 | 스크립트 검증 | 서브커맨드가 입력을 거부한다. 예: `--why` 길이 검사 |
   | 3 | 게이트 | stop-hook이나 verification.json에서 fail-closed로 막는다 |
   | 4 | 훅 관측 | 차단하지 않고 이벤트로 남긴다. 예: `context.read.large` |
   | 5 | 문서 규칙 | 스킬·규칙 문서의 문장. 적기는 쉽지만 지켜지는지 알 수 없다 |

   판단이 필요해 위 층으로 못 올리는 규칙만 문서에 둔다. 그때는 지켜지는지 관측할 방법을 같이 적는다.
   관측 데이터 없이 게이트로 올리지 않는다.
2. **실제로 있었던 실수에 대해 실패하는 것을 보인다.** 같은 종류의 실수가 두 번 이상 있었을 때 검사를 만든다. 과거 실행의 실제 입력을 bats 픽스처로 넣고 새 검사가 그것을 잡는지 확인한다. 상상한 실수만 잡는 검사는 넣지 않는다.
3. **실수가 더 이상 일어날 수 없게 되면 검사를 지운다.** 구조가 바뀌어 그 경로가 사라졌다면 검사도 걷어낸다. 지운 이유는 CHANGELOG 성격의 커밋 메시지와 결정 기록에 남긴다.

## 테스트

```bash
bats tests/
```

셸 스크립트를 수정했으면 `bash -n <file>`로 문법을 먼저 확인하세요.

## 버전

동작이 바뀌는 변경은 `.claude-plugin/plugin.json`의 `version`과 `README.md` 상단 버전 표기를
함께 올립니다 (SemVer).
