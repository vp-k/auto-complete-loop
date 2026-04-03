# Phase 0: PM Planning

Loaded by the full-auto orchestrator at Phase 0 entry via Read.
No Ralph/progress/promise code — managed by the orchestrator.

## 전제 조건

- `shared-rules.md`가 이미 로드된 상태
- progress 파일이 이미 초기화된 상태 (오케스트레이터에서 init 완료)
- `$ARGUMENTS`에 사용자 요구사항 존재

## Phase 0 절차

### Step 0-0: 프로젝트 규모 1차 판별

사용자 요구사항을 분석하여 규모를 추정합니다.

**기준** (`rules/project-size-rules.md` 참조):
- **Small**: 기능 5개 미만
- **Medium**: 기능 5~15개
- **Large**: 기능 16개 이상, 또는 기획 문서 8개+, 모듈/기능 그룹 4개+, 외부/타팀 이해관계자 3팀+ 중 1개 이상

1차 판별은 요구사항 텍스트 기반 추정. Step 0-9.5에서 확정된 문서/모듈 수로 2차 재판정.

결과를 progress 파일에 기록:
```bash
jq '.phases.phase_0.outputs.projectSize = "Medium"' ...
```

**Large로 판별된 경우 즉시 DoD 키 추가**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh add-dod-key stakeholders_mapped --progress-file .claude-full-auto-progress.json
```

---

### Step 0-1: 사용자/가치 이해

기능 도출 **전에** 다음을 먼저 정의합니다:

#### Problem Statement
"왜 이 앱이 필요한가" 1단락.
- 현재 상태(As-Is) → 문제점 → 바람직한 상태(To-Be)

#### 경량 페르소나 (1~2개)
```
- 이름: [가상 이름]
- 역할: [직업/상황]
- 핵심 니즈: [가장 중요한 1가지]
- 페인포인트: [현재 겪는 가장 큰 불편]
```

#### Core Jobs (JTBD, 3~5개)
```
When [상황], I want to [행동], So I can [가치]
```

#### 의도된 트레이드오프
```
- [X]를 위해 [Y]를 포기한다 (이유: ...)
```

Non-Goals의 "이유" 버전. 왜 특정 기능/접근을 의도적으로 제외하는지 명시.

---

### Step 0-2: 요구사항 확장 + 우선순위

#### 1. 기능 도출
페르소나 + JTBD 기반으로 필요 기능을 도출합니다.
"당연히 있어야 할 기능"이 아닌 "이 페르소나의 이 Job을 해결하는 기능" 관점.

#### 2. MoSCoW 분류 (모든 규모)
- **Must**: 없으면 앱이 동작하지 않음
- **Should**: 릴리즈에 강하게 기대됨
- **Could**: 있으면 좋지만 없어도 릴리즈 가능
- **Won't**: 이번 프로젝트에서 하지 않음 → Non-Goals로 이동

#### 3. ICE 점수 (Medium/Large만)
Must/Should 내에서 세밀 정렬:
- **Impact** (1-10): 사용자 가치 영향도
- **Confidence** (1-10): 구현 확신도
- **Ease** (1-10): 구현 용이성

ICE = Impact x Confidence x Ease → 점수순 정렬

#### 4. Kano 조정 (Medium/Large만)
ICE 점수에 Kano 보정:
- **Basic** (없으면 불만): 무조건 Must, Round 1 배치
- **Performance** (많을수록 만족): ICE 점수 유지
- **Excitement** (있으면 감동): ICE 점수가 높아도 후순위 Round로

#### 5. Round 배치
MoSCoW → ICE → Kano 결과에 따라 기능을 Round로 배치.
Won't 항목은 Non-Goals로 이동.

#### 6. 기술 스택 결정
요구사항에 맞는 기술 스택을 결정하고 근거를 기록합니다.

---

### Step 0-2.5: 아키텍처 레이어 매핑

요구사항에서 필요한 아키텍처 레이어를 **명시적으로** 식별합니다.

#### 1. 기능별 레이어 태깅

각 기능이 어떤 레이어에 걸치는지 매핑합니다:

| 기능 | Frontend | Backend (API + DB 포함) |
|------|----------|------------------------|
| (예) 로그인 | ✅ 로그인 페이지 | ✅ Auth API + users 테이블 |
| (예) 대시보드 | ✅ 대시보드 UI | ✅ Stats API + 집계 쿼리 |

#### 2. 프로젝트 스코프 결정

- Frontend 있는 기능이 1개 이상 → `hasFrontend: true`
- Backend 있는 기능이 1개 이상 → `hasBackend: true`

#### 3. progress 파일에 기록

```bash
jq '.phases.phase_0.outputs.projectScope = {"hasFrontend": true, "hasBackend": true}' {PROGRESS_FILE} > /tmp/pg.tmp && mv /tmp/pg.tmp {PROGRESS_FILE}
```

#### 4. overview.md에 레이어 섹션 추가

기술 스택 아래에 다음 섹션을 반드시 포함:

```markdown
## 아키텍처 레이어
- Frontend: [프레임워크] — pages, components, hooks
- Backend: [프레임워크 + DB/ORM] — endpoints, services, middleware, schema, migrations
```

**주의**: 이 레이어 매핑은 이후 Phase 1→2 전이 게이트, Phase 2 구현 검증, Phase 4 아티팩트 검증에서 사용됩니다. 누락 시 전체 워크플로우가 차단됩니다.

---

### Step 0-3: 가정 식별 + 우선순위화 (Discovery)

기능 목록 도출 후, **"이 기능이 필요하다는 가정"**을 명시합니다.

#### 가정 식별 (5~10개)
각 핵심 가정에 대해:

```json
{
  "assumption": "기능/행동 설명",
  "category": "value|usability|feasibility|viability|accessibility",
  "impact": "1-5 (틀렸을 때 영향)",
  "confidence": "1-5 (현재 확신도)",
  "priority": "critical|high|medium|low",
  "validation_owner": "user"
}
```

5가지 카테고리:
- **value**: 이 기능이 사용자에게 가치가 있는가?
- **usability**: 사용자가 이 방식으로 사용할 수 있는가?
- **feasibility**: 기술적으로 구현 가능한가?
- **viability**: 사업적으로 지속 가능한가?
- **accessibility**: 대상 사용자가 접근 가능한가?

#### 가정 우선순위화
Impact x (6 - Confidence) 매트릭스로 검증 필요 순위 결정:
- Impact 높고 Confidence 낮음 → **critical** (반드시 검증)
- Impact 높고 Confidence 높음 → **medium** (모니터링)
- Impact 낮음 → **low** (무시 가능)

#### 미검증 가정 리스크 기록
검증되지 않은 가정은 리스크로 기록합니다.
AI가 실험을 수행할 수는 없으므로, "가정을 의식적으로 드러내는 것" 자체가 가치.

progress 파일에 기록:
```bash
jq '.phases.phase_0.outputs.assumptions = [...]' ...
```

---

### Step 0-4: 핵심 User Stories + 플로우

#### User Stories (5~10개, 규모별)
```
US-001: As a [페르소나], I want to [행동], so that [가치]
  - AC-001-1: [수락 기준]
  - AC-001-2: [예외 케이스]
  - AC-001-3: [에러 시나리오]
```

#### (Medium+) 핵심 사용자 플로우 (3개)
주요 사용 시나리오의 단계별 흐름.
```
플로우 1: [시나리오명]
1. 사용자가 [행동]
2. 시스템이 [반응]
3. ...
```

---

### Step 0-5: 디자인 원칙 수립

#### Part A: 아키텍처 원칙 (기존)
기술 스택에 맞는 구체적 원칙 (예: Clean Architecture 레이어, 상태 관리 패턴 등).

#### Part B: 비주얼 디자인 방향 (3가지 결정)

Step 0-1의 페르소나 + JTBD + 사용 맥락에서 도출합니다.
overview.md "디자인 원칙" 섹션에 아래 테이블로 기록:

| 영역 | 결정 | 근거 | 구현 제약 |
|------|------|------|-----------|
| 디자인 자세 | 톤 / 밀도 / 금지 규칙 | 페르소나+JTBD+맥락 | Phase 2 금지/우선순위 |
| UI 시스템 | 라이브러리 / 커스터마이징 정책 | 일관성, 속도 | override 허용 범위 |
| 앱 쉘+반응형 | 내비게이션 / 반응형 / 다크모드 / 전환 규칙 | 사용 환경, 디바이스 | 모바일 전환 규칙 |

**1. 디자인 자세 (Design Posture)**

| 요소 | 설명 | 예시 |
|------|------|------|
| 톤 | 전체적 분위기 | 전문적 / 캐주얼 / 따뜻한 / 냉철한 |
| 정보 밀도 | 화면당 정보량 | 고밀도(대시보드) / 중밀도(SaaS) / 저밀도(랜딩) |
| 금지 규칙 | 하지 말 것 (2-4개, 관찰 가능한 것만) | "장식용 애니메이션 금지" / "3단 이상 중첩 금지" / "카드 안 카드 금지" |

예: "톤: 전문적, 밀도: 고밀도, 금지: 장식적 애니메이션, 3단 이상 중첩 네비게이션"

금지 규칙 원칙: 추상적 금지 불가("세련되지 않은 느낌" X), 관찰 가능한 것만("그라데이션 배경 금지" O), 2-4개 제한.

**2. UI 시스템**

| 결정 | 예시 |
|------|------|
| 컴포넌트 라이브러리 | Tailwind + shadcn/ui, MUI, Ant Design, Chakra UI |
| 커스터마이징 정책 | "라이브러리 기본 primitives 우선, custom variant 최소화" |

**3. 앱 쉘 + 반응형**

| 결정 | 예시 |
|------|------|
| 내비게이션 구조 | sidebar + content, top-nav + content, bottom-tab(mobile) |
| 반응형 전략 | mobile-first / desktop-first / desktop-only |
| 다크모드 | 지원 / 미지원 / 후속 |
| 핵심 전환 규칙 | "sidebar→drawer, 2열→1열 붕괴, table→card 전환" |

> **역할 분리**: Phase 0 = 구조와 제약, design-polish = 시각 완성도(색상/타이포/아이콘)

---

### Step 0-6: 성공 기준 정의

#### North Star Metric (1개)
"이 앱의 성공을 측정하는 단일 지표"

예시:
- "주간 활성 사용자의 핵심 플로우 완수율"
- "게시글 작성 후 24시간 내 댓글 비율"

#### Success Criteria (3~5개)
정성적/정량적 기준:
```
- SC-1: 사용자가 핵심 플로우를 N분 내 완수
- SC-2: 첫 방문 시 가입 전환율 N% 이상
- SC-3: ...
```

progress 파일에 기록:
```bash
jq '.phases.phase_0.outputs.nsm = "..." | .phases.phase_0.outputs.successCriteria = [...]' ...
```

---

### Step 0-7: Codex + PM Agent 병렬 검토

**PM Planner Agent**와 **Codex 검토**를 병렬로 실행합니다:

#### 7-A. PM Planner Agent (병렬 실행)

Agent tool로 `pm-planner` 에이전트를 호출합니다:
- 페르소나/JTBD 품질, MoSCoW→ICE→Kano 일관성, User Story INVEST 기준, Non-Goals 모순 검증
- overview.md 경로를 프롬프트에 포함
- 결과: PM Review Report (REVIEW_SCORE 포함)

#### 7-B. Codex 검토 (병렬 실행)

codex-cli에게 다음 관점에서 전체 기획을 검토 요청:

```bash
codex exec --skip-git-repo-check '## Phase 0 기획 검토

### 검토 관점 (8가지)
1. 요구사항 누락 (사용자 요구 vs 기능 목록 대조)
2. 기술적 리스크 (스택 선택, 성능 병목)
3. 의존성 순서 오류 (Round 배치 검증)
4. Non-Goals 침범 (기능이 Non-Goals와 모순?)
5. 보안/인증 누락
6. 사용자 가치 관점 불필요 기능? (페르소나/JTBD와 무관한 기능 식별)
7. 10-Star Product 관점: 이 요구사항이 사용자가 진짜 원하는 것인지 의문을 제기하라. 문자 그대로의 요청이 아닌, 그 안에 숨어있는 10배 더 좋은 제품을 찾아라. 예: "사진 업로드" → "사진으로 자동 상품 등록"
8. Pre-mortem: 이 프로젝트가 실패할 수 있는 이유

### Pre-mortem 분류 기준
- Tigers (발생 가능성 높음 + 영향 큼): 반드시 대응책 필요
- Paper Tigers (발생 가능성 높음 + 영향 작음): 과대평가된 리스크, 무시 가능
- Elephants (발생 가능성 낮음 + 영향 큼): 불확실하지만 치명적, 모니터링

### 검토 대상
[overview.md 경로 — 직접 읽고 검토]

### 출력 형식
피드백을 Critical/High/Medium/Low로 분류.
Pre-mortem 결과를 Tigers/Paper Tigers/Elephants로 분류.
각 Tiger에 대해 blocking 여부와 대응책 제시.
'
```

#### Pre-mortem 결과 기록

```json
{
  "premortem": {
    "tigers": [
      { "risk": "설명", "impact": "high", "likelihood": "high", "mitigation": "대응책", "blocking": true }
    ],
    "paperTigers": [
      { "risk": "설명", "impact": "low", "likelihood": "high" }
    ],
    "elephants": [
      { "risk": "설명", "impact": "high", "likelihood": "low" }
    ]
  }
}
```

**blocking Tiger 규칙**:
- `blocking: true` + `mitigation: ""` → **Phase 2 진입 불가**
- Phase 1(기획 문서 작성) 중 대응책을 반드시 수립
- 대응책 수립 후 progress의 해당 tiger.mitigation 업데이트

progress 파일에 기록:
```bash
jq '.phases.phase_0.outputs.premortem = {...}' ...
```

---

### Step 0-8: (Large만) 이해관계자 맵

**활성화 조건**: Step 0-0에서 Large로 판별된 경우만.

#### Power/Interest 매트릭스 (2x2)

```
                High Interest
                    |
    Keep Satisfied  |  Manage Closely
                    |
   ---------------------------------------- Power
                    |
    Monitor         |  Keep Informed
                    |
                Low Interest
```

#### 커뮤니케이션 계획 (1~3줄)
"누구에게 무엇을 언제 알릴 것인가"

progress 파일에 기록:
```bash
jq '.phases.phase_0.outputs.stakeholders = {...}' ...
```

---

### Step 0-9: 피드백 반영 + 문서 생성

codex 검토 피드백을 분석하고 수용/반론합니다:
1. Critical/High 피드백 → 즉시 반영
2. Medium → 판단하여 수용 또는 근거 있는 반론
3. Low → 기록만

수정 반영 후 **overview.md** 생성:

```markdown
# 프로젝트 개요

## Problem Statement
## Target Users / 페르소나
## Core Jobs (JTBD)
## 의도된 트레이드오프
## 성공 기준
  - North Star Metric
  - Success Criteria
## 핵심 가정 + 리스크
## 핵심 User Stories
## (Medium+) 핵심 플로우
## 기능 목록 (MoSCoW 분류 포함)
## Round별 의존성 그룹
## 기술 스택
## Non-Goals
## 디자인 원칙
### 아키텍처 원칙
(Part A 내용)
### 비주얼 디자인 방향
| 영역 | 결정 | 근거 | 구현 제약 |
|------|------|------|-----------|
| 디자인 자세 | 톤/밀도/금지 규칙 | ... | ... |
| UI 시스템 | 라이브러리/커스터마이징 | ... | ... |
| 앱 쉘+반응형 | 내비/반응형/다크모드/전환 규칙 | ... | ... |

## (Large만) 이해관계자 맵
## 데이터 모델 목록
## (hasBackend=true) API 엔드포인트 목록
## 핵심 플로우 (자연어)
## (hasFrontend=true) 페이지 목록
```

#### 필수 Spec 상세 섹션 (목록 수준)

> **output-guard 정책 준수**: 코드 스니펫, SQL, JSON 스키마 금지. 아래 테이블은 **LISTING 수준**만 작성.
> 상세 스키마/타입/제약조건은 Phase 1 기획 문서에서 정의합니다.

overview.md에 다음 섹션이 **반드시** 포함되어야 합니다:

**1. API 엔드포인트 목록** (`hasBackend=true` 시 필수)

| Method | Path | 설명 | Auth 필요 |
|--------|------|------|----------|
| (각 엔드포인트를 한 줄로 — request/response 상세는 Phase 1에서) |

**2. 데이터 모델 목록** (필수)

| 모델명 | 주요 필드 (이름만) | 관계 |
|--------|-------------------|------|
| (각 모델을 한 줄로 — 필드 타입/제약조건은 Phase 1에서) |

**3. 핵심 플로우** (필수, 자연어로 2-3개)

```
1. 회원가입 → 로그인 → 프로필 조회
2. 로그인 → 게시글 작성 → 목록에서 확인
```
(curl 검증 가능한 상세는 Phase 1에서)

**4. 페이지 목록** (`hasFrontend=true` 시 필수)

| 페이지 | 경로 | 핵심 기능 |
|--------|------|----------|
| (각 페이지를 한 줄로) |

> **검증**: Step 0-10 사용자 승인 전, 위 섹션 누락 시 overview.md가 불완전한 것으로 간주합니다.

**README.md** 생성: 문서 목록 + 빌드/실행 가이드 뼈대.

---

### Step 0-9.5: 프로젝트 규모 2차 재판정 (최종)

확정된 문서 수/모듈 수로 Large 기준 재검증:
- 기획 문서 8개+ → Large
- 모듈/기능 그룹 4개+ → Large
- 외부/타팀 이해관계자 3팀+ → Large

**1차와 다를 경우**:
- Small/Medium → Large로 변경: `add-dod-key stakeholders_mapped` 호출
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh add-dod-key stakeholders_mapped --progress-file .claude-full-auto-progress.json
  ```
- Large → Medium/Small로 변경: Large 전용 DoD 키 삭제 (jq로 직접 제거)

progress 파일의 projectSize 업데이트.

---

### Step 0-10: 사용자 승인

overview.md + README.md를 사용자에게 제시하고 승인 요청.

**허용되는 AskUserQuestion**:
- "이 기획을 승인하시겠습니까? 수정이 필요한 부분이 있으면 말씀해주세요."

수정 요청 시 해당 부분 수정 후 재승인 요청.

---

### Step 0-11: Phase 0 결과 기록

**주의**: Progress init은 오케스트레이터에서 이미 완료. 여기서는 outputs 기록만.

1. Phase 0 outputs를 progress 파일에 기록 (assumptions, nsm, successCriteria, premortem, projectSize, stakeholders)
2. DoD 업데이트:
   ```bash
   jq '.dod.pm_approved.checked = true | .dod.pm_approved.evidence = "사용자 승인 완료"
       | .dod.assumptions_documented.checked = true | .dod.assumptions_documented.evidence = "N개 가정 식별 + 우선순위화"
       | .dod.premortem_done.checked = true | .dod.premortem_done.evidence = "Tigers N개, blocking N개 (모두 mitigation 완료)"' ...
   ```
   **Large 프로젝트인 경우** (projectSize가 "Large"이면):
   ```bash
   jq '.dod.stakeholders_mapped.checked = true | .dod.stakeholders_mapped.evidence = "이해관계자 맵 + 커뮤니케이션 계획 완료"' ...
   ```
3. Phase 전이는 오케스트레이터가 수행 (이 스킬에서 하지 않음)
