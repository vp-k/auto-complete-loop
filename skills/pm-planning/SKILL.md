# Phase 0: PM Planning (순수 로직)

이 스킬은 full-auto 오케스트레이터에서 Phase 0 진입 시 Read로 로드됩니다.
Ralph/progress/promise 코드 없음 — 오케스트레이터가 관리.

## 전제 조건

- `shared-rules.md`가 이미 로드된 상태
- progress 파일이 이미 초기화된 상태 (오케스트레이터에서 init 완료)
- `$ARGUMENTS`에 사용자 요구사항 존재

## Phase 0 절차

### Step 0-0: 프로젝트 규모 1차 판별

사용자 요구사항을 분석하여 규모를 추정합니다.

**기준** (`shared-rules.md` 프로젝트 규모 판정 참조):
- **Small**: 기능 5개 미만
- **Medium**: 기능 5~15개
- **Large**: 기획 문서 8개+, 모듈/기능 그룹 4개+, 외부/타팀 이해관계자 3팀+ 중 1개 이상

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

프로젝트에 적용할 디자인 원칙/아키텍처 원칙을 정합니다.
기술 스택에 맞는 구체적 원칙 (예: Clean Architecture 레이어, 상태 관리 패턴 등).

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

### Step 0-7: Codex 검토 (강화)

codex-cli에게 다음 관점에서 전체 기획을 검토 요청:

```bash
codex exec --skip-git-repo-check '## Phase 0 기획 검토

### 검토 관점 (7가지)
1. 요구사항 누락 (사용자 요구 vs 기능 목록 대조)
2. 기술적 리스크 (스택 선택, 성능 병목)
3. 의존성 순서 오류 (Round 배치 검증)
4. Non-Goals 침범 (기능이 Non-Goals와 모순?)
5. 보안/인증 누락
6. 사용자 가치 관점 불필요 기능? (페르소나/JTBD와 무관한 기능 식별)
7. Pre-mortem: 이 프로젝트가 실패할 수 있는 이유

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
## (Large만) 이해관계자 맵
## 데이터 모델 개요
```

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
