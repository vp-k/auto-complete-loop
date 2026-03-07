# Post-Analysis: Retrospective

Progress JSON과 Git Log를 데이터 기반으로 분석하여 회고 보고서를 생성합니다.

## 입력

- `.claude-full-auto-progress.json` (있을 경우)
- `git log` (최근 50개 커밋)
- 오케스트레이터가 수집한 공통 맥락

## 분석 절차

### Step 1: Progress 데이터 분석

`.claude-full-auto-progress.json`이 존재할 경우:

1. **Phase별 iteration 횟수**: `steps` 배열의 각 Phase status 변경 이력 또는 `roundResults` 배열에서 집계
2. **Phase별 소요 시간**: `created` 타임스탬프와 `roundResults[].timestamp`에서 시작~종료 계산
3. **에러 로그 분석**: `errorHistory` 객체에서 에러 유형별 빈도 집계 (필드 미존재 시 스킵)
4. **재시도 패턴**: 같은 Phase에서 반복된 실패 패턴 식별 (`errorHistory.escalationLog` 참조)

없을 경우 이 Step을 스킵하고 Step 2로 진행합니다.

### Step 2: Git Log 분석

```bash
# 커밋 존재 여부를 먼저 확인 (빈 저장소 대응)
if git rev-parse --verify HEAD &>/dev/null; then
  git log --oneline -50
  git log --format="%H %ai %s" -50
  FIRST_COMMIT=$(git log --reverse --format="%H" | head -1)
  if [[ -n "$FIRST_COMMIT" ]]; then
    git diff --stat "$FIRST_COMMIT"..HEAD
  fi
else
  echo "커밋 데이터 없음"
fi
```

> 커밋이 없는 저장소에서는 모든 Git 명령을 스킵하고 "커밋 데이터 없음"으로 대체합니다.

분석 항목:

1. **커밋 빈도**: 시간대별 커밋 분포
2. **핫스팟 파일**: 파일별 변경 횟수 상위 10개
   ```bash
   git log --pretty=format: --name-only -50 | sort | uniq -c | sort -rn | head -10
   ```
3. **커밋 유형 비율**: fix/feat/refactor/docs/test 접두사 기준 분류
4. **변경 규모**: 추가/삭제 라인 수 총계

### Step 3: 병목 구간 식별

Step 1, 2 결과를 종합하여:

1. **최다 iteration Phase**: Progress에서 가장 많이 반복된 Phase (있을 경우)
2. **최다 에러 영역**: 에러가 집중된 모듈/파일
3. **반복 수정 파일**: 3회 이상 변경된 파일 목록 + 변경 사유 추정
4. **긴 작업 구간**: 커밋 간 간격이 가장 긴 구간

### Step 4: What went well / What didn't / Action items

데이터에 기반하여 객관적으로 작성:

- **What went well**: 1회 통과한 Phase, 안정적이었던 모듈, 효율적 패턴
- **What didn't**: 병목 구간, 반복 수정, 에러 집중 영역
- **Action items**: 다음 프로젝트에서 개선할 구체적 행동 3~5개

## 출력

결과를 `docs/post-analysis/retrospective.md`에 저장합니다.

### 출력 형식

```markdown
# Retrospective

## 1. Progress 데이터 요약

> [Progress JSON 미발견 시: "Progress 데이터 없음 - Git Log 기반 분석만 수행"]

| Phase | Iterations | 소요 시간 | 에러 수 |
|-------|-----------|----------|--------|
| ... | ... | ... | ... |

### 주요 에러 패턴
| 에러 유형 | 빈도 | 발생 Phase |
|----------|------|-----------|
| ... | ... | ... |

## 2. Git Log 분석

### 커밋 통계
- 총 커밋 수: N
- feat: N (X%) / fix: N (X%) / refactor: N (X%) / 기타: N (X%)
- 총 변경: +N / -N lines

### 핫스팟 파일 (상위 10)
| # | 파일 | 변경 횟수 | 추정 사유 |
|---|------|----------|----------|
| 1 | ... | ... | ... |

## 3. 병목 분석

### 주요 병목 구간
| 구간 | 증거 | 영향도 |
|------|------|--------|
| ... | ... | 높음/중간/낮음 |

### 반복 수정 파일
| 파일 | 변경 횟수 | 추정 원인 |
|------|----------|----------|
| ... | ... | ... |

## 4. 회고 요약

### What went well
- ...

### What didn't go well
- ...

### Action items
| # | 개선 항목 | 구체적 행동 | 우선순위 |
|---|----------|-----------|---------|
| 1 | ... | ... | P1/P2/P3 |
```
