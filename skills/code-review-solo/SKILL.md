# Phase 3: Code Review (Solo Multi-Perspective)

Loaded by the full-auto-solo orchestrator at Phase 3 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- Phase 2 완료 (모든 코드 구현 완료)
- `shared-rules.md`가 이미 로드된 상태

## Phase 3 절차

### Step 3-1: 리뷰 범위 결정

1. 구현된 전체 코드를 리뷰 범위로 설정
2. progress 파일에서 `phases.phase_2.completedFiles` 확인
3. progress 파일에서 `phases.phase_2.documents[].acceptanceCriteria` 로드 (있으면 리뷰 프롬프트에 포함)
4. 리뷰 우선순위: 보안 관련 > 비즈니스 로직 > UI/UX > 유틸리티

### Step 3-2: 다관점 순차 리뷰 (Claude 솔로)

각 라운드에서 외부 AI 없이 Claude가 **관점별 순차 패스**로 리뷰합니다. 각 패스에서 다른 관점은 의도적으로 무시합니다.

> 리뷰 관점(서브카테고리 정의)·리뷰 원칙·심각도 기준·Few-shot 예시·출력 형식은 `${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md`를 단일 출처로 따른다.
> 각 패스 시작 전에 이 파일을 Read하여 "리뷰 관점 (전체)"에서 해당 패스의 카테고리 정의를, "리뷰 원칙 (회의적 리뷰어 역할)"·"심각도 기준"·"심각도 판정 기준 (Few-shot 참고)"을 모든 패스에 적용한다. (3-pass 분할은 "관점 분할 가이드" 섹션 참조)

**라운드 2+**: `git diff --name-only`로 변경된 파일만 리뷰 범위로 사용. 이전 finding 목록은 **참고용으로만** 포함 (범위 제한 금지). 새로운 이슈도 반드시 보고.

#### Pass 1: 보안 + 에러 처리 전문가

지금부터 당신은 **보안 및 에러 처리 전문가**입니다. 다른 관점(성능, 코드 품질, 구현 완성도)은 무시하세요.
Read 도구로 리뷰 대상 파일을 직접 읽고 **SEC (보안, 서브카테고리별 분류)** + **ERR (에러 처리)** 관점만 검토 (정의: 단일 출처의 SEC/ERR 항목).

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록.

#### Pass 2: 데이터 + 성능 전문가

지금부터 당신은 **데이터 일관성 및 성능 전문가**입니다. 보안/에러는 이미 검토했으니 무시하세요.
동일 파일을 다시 Read 도구로 읽고 **DATA (데이터 무결성)** + **PERF (성능)** 관점만 검토 (정의: 단일 출처의 DATA/PERF 항목).

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록. 번호는 Pass 1에서 이어서 부여.

#### Pass 3: SPEC 대조 + 코드 품질 전문가

지금부터 당신은 **SPEC 준수 및 코드 품질 전문가**입니다. 보안/에러/데이터/성능은 이미 검토했으니 무시하세요.
SPEC.md (또는 docs/api-spec.md)가 존재하면 먼저 읽고, 코드와 1:1 대조하여 **CODE (코드 품질)** + **IMPL (구현 완성도)** + **E2E (E2E 테스트 품질)** 관점만 검토 (정의: 단일 출처의 CODE/IMPL/E2E 항목).

출력: 발견된 finding을 `{CATEGORY}-{SEVERITY}-{번호}` 형식으로 기록. 번호는 Pass 2에서 이어서 부여.

#### 패스 결과 합산

각 패스의 finding을 합산하여 전체 finding 목록을 생성합니다.

### Step 3-2 continued: Claude Code가 finding 분석 및 수정

> 공통 리뷰 규칙은 아래 파일을 Read하여 적용합니다.
> Read ${CLAUDE_PLUGIN_ROOT}/templates/review-perspectives.md

Finding 출력 형식, 검증, severity별 수정 처리, 품질 게이트 재실행, 라운드 결과 기록, Suppression List, 리뷰 완료 조건, Phase 3 완료, Iteration 관리 모두 위 템플릿을 따릅니다.

**자동 커밋** (품질 게이트 통과 시):
```bash
git add -A && git commit -m "[auto] Phase 3 코드 리뷰 Round N (solo) 수정 완료"
```
