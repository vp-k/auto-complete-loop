# 공통 규칙 (모든 스킬 적용)

## 검증 결과 기록 (필수)
모든 검증(빌드/테스트/린트) 결과는 `.claude-verification.json`에 기록합니다.
증거 없는 완료 선언은 금지입니다.
품질 게이트는 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate`로 실행합니다.

## DoD 확인
프로젝트 루트의 `DONE.md`가 있으면 반드시 읽고 체크리스트로 사용합니다.
없으면 각 스킬의 내장 완료 기준을 사용합니다 (빌드/테스트/린트/리뷰 통과).
필요 시 `${CLAUDE_PLUGIN_ROOT}/templates/DONE.md` 템플릿을 참고할 수 있습니다.

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
4. 결과를 `.claude-verification.json`에 기록
5. 해당 progress 파일의 dod 체크리스트 업데이트 (evidence 포함)

## Error Classification & Escalation
→ 상세 규칙: `Read ${CLAUDE_PLUGIN_ROOT}/rules/error-escalation-rules.md`
에러 발생 시 L0→L5 에스컬레이션, 범위 축소 절차는 분리된 규칙 파일 참조.

## 프로젝트 규모 판정
→ 상세 규칙: `Read ${CLAUDE_PLUGIN_ROOT}/rules/project-size-rules.md`
Small(<5)/Medium(5~15)/Large(8+docs) 기준 및 DoD 키 관리는 분리된 규칙 파일 참조.

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
| implement-docs-auto | 문서 구현 완료 시 | `[auto] {문서명} 구현 완료` |
| code-review-loop | 라운드 수정 + 품질 게이트 통과 후 | `[auto] 코드 리뷰 Round {N} 수정 완료` |
| full-auto Phase 3 | 라운드 수정 + 품질 게이트 통과 후 | `[auto] Phase 3 코드 리뷰 Round {N} 수정 완료` |
| full-auto Phase 4 | 최종 검증 + 폴리싱 완료 후 | `[auto] 최종 검증 및 폴리싱 완료` |
| full-auto Phase 4 design | 디자인 수정 + 품질 게이트 통과 후 | `[auto] Phase 4 디자인 폴리싱 완료` |

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

## 외부 AI 자체 탐색 (codex/gemini 호출 시)
- codex/gemini에게 **파일 경로**를 전달하여 직접 읽도록 함
- Claude가 문서 내용을 요약/가공하여 프롬프트에 embed하지 않음 (요약 편향 방지)
- 코드 전체가 아닌 **핵심 부분만** 전달 (최대 100줄)
- 이전 토론 내용은 결론만 요약해서 전달

## 증거 기반 완료 선언 (필수)

**완료 선언 전 반드시 실행 결과 확인:**
- 빌드 성공 로그 (exit code 0 확인)
- 테스트 통과 로그 (PASSED 개수 확인)
- 린트 통과 로그
- `.claude-verification.json`에 기록 완료
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

## 에이전트 정의 형식 (YAML Frontmatter)

agents/ 디렉토리에 에이전트를 정의할 때 YAML frontmatter 형식을 사용합니다:

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
