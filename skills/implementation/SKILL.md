# Phase 2: Implementation (순수 구현 로직)

이 스킬은 full-auto 오케스트레이터에서 Phase 2 진입 시 Read로 로드됩니다.
Ralph/progress/promise 코드 없음 — 오케스트레이터가 관리.

## 전제 조건

- Phase 1 완료 (기획 문서 완성)
- Pre-mortem 가드 통과 (blocking Tiger 모두 mitigation 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 2 절차

### Step 2-1: 맥락 파악

1. overview.md (정의 문서) 읽기 — 기술 스택, 아키텍처 파악
2. SPEC.md 확인 (없으면 기획 문서들로부터 자동 생성)
3. README.md에서 구현할 문서 목록 추출
4. 구현 순서 결정 (의존성 기반)

#### DoD 로드
프로젝트 루트에서 `DONE.md` 확인:
- 파일 있음: 해당 DoD를 완료 기준으로 사용
- 파일 없음: 내장 완료 기준 사용 (빌드/테스트/린트/리뷰 통과)

### Step 2-2: 프로젝트 구조 설계

Claude가 직접 최적의 구조 설계:
1. 디렉토리 구조
2. 기술 스택 세부 결정 (버전, 라이브러리)
3. 설정 파일 구성
4. 프로젝트 스캐폴딩 생성

progress 파일에 아키텍처 맥락 저장 (크래시 복구용):
```json
"context": {
  "architecture": "기술 스택 + 핵심 결정",
  "patterns": "설계 패턴"
}
```

초기 커밋 (롤백 기준점):
```bash
git add -A && git commit -m "[auto] 프로젝트 스캐폴딩 완료"
```

### Step 2-3: 문서별 티켓 분할

문서 구현 시작 전 해당 문서를 티켓으로 분할:
1. DB/스키마 변경 -> 별도 티켓
2. API 엔드포인트별 -> 별도 티켓
3. 프론트엔드 페이지/컴포넌트별 -> 별도 티켓
4. 각 티켓은 독립적으로 빌드/테스트 검증 가능

### Step 2-4: 자동 구현 루프

모든 문서에 대해 순차적으로:

1. **문서 읽기 -> 구현 항목 추출**
   - progress: 해당 문서를 `in_progress`로 변경

2. **Claude가 구현 계획 수립 + 직접 코드 작성**
   - 백엔드: 테스트 우선 개발 (TDD)
     1. 실패하는 테스트 먼저 작성
     2. 테스트 통과하는 최소 코드 작성
     3. 리팩토링
   - 프론트엔드: 일반 구현 방식

3. **품질 게이트 통과 확인**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate --progress-file .claude-full-auto-progress.json
   ```
   - 실패 시 L0-L5 에스컬레이션 적용
   - L0 즉시 수정(3회) -> L1 다른 방법(3회) -> L2 codex 분석 -> L3 다른 접근법(3회) -> L4 범위 축소 -> L5 사용자 개입

4. **codex-cli에게 코드 리뷰 요청**
   ```bash
   codex exec --skip-git-repo-check '## 코드 리뷰
   ### 원본 문서 스펙
   [핵심 요구사항]
   ### 구현된 코드
   파일: [경로] — 직접 읽고 검토하세요
   ### 요청
   비판적 시각으로 문제점, 누락, 개선점을 제시해주세요.
   '
   ```
   - 리뷰 피드백 -> 수정 후 재리뷰
   - 권장사항 -> 즉시 구현 (사용자에게 묻지 않음)
   - 리뷰 사이클 최대 3회

5. **문서 완료 처리**
   - progress: 해당 문서 `completed`
   - `documentSummaries`에 핵심 결정 요약
   - 자동 커밋: `git add -A && git commit -m "[auto] {문서명} 구현 완료"`

### Step 2-5: Fresh Context Verification (문서/티켓 완료 전 필수)

Self-check 후, Agent 도구로 검증 에이전트를 별도 생성하여 fresh context에서 검증:
- 빌드/타입체크/린트/테스트 실행
- SPEC.md 대비 요구사항 충족 확인
- 결과를 `.claude-verification.json`에 기록

### Step 2-6: 에러 자동 복구

`shared-rules.md`의 Error Classification & Escalation 참조.

에러 기록:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error \
  --file "src/auth.ts" --type "TypeError" --msg "..." \
  --level L2 --action "시도한 행동" \
  --progress-file .claude-full-auto-progress.json
```

Edit 도구 에러 처리:
1. 즉시 파일 다시 읽기
2. `old_string` 재확인 후 재시도 (최대 3회)
3. 3회 실패 -> Write 덮어쓰기 -> 빌드/테스트 검증 -> 실패 시 `git restore --source=HEAD -- {파일}`로 해당 파일만 롤백 (다른 변경에 영향 없음)

### Step 2-7: Phase 2 완료

모든 문서 구현 + 검증 완료 시:
1. 문서-코드 일관성 검사:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh doc-code-check docs/
   ```
2. DoD 업데이트: `all_code_implemented.checked = true`
3. Phase 전이는 오케스트레이터가 수행

### Iteration 관리

- 한 iteration에서 1~2개 문서 또는 3~5개 티켓만 처리
- 처리 완료 후 handoff 업데이트하고 자연스럽게 종료

### 복구

progress 파일에서:
- `context`로 아키텍처/패턴 맥락 복구
- `documentSummaries`로 완료된 문서의 결정 사항 파악
- `completed` 문서 스킵
- `in_progress` 문서 -> 해당 문서 처음부터 다시 (맥락 있으므로 일관성 유지)
