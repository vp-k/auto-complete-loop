---
description: "Post-project analysis. Run Metrics/Retrospective/Launch/Competitive analysis sequentially"
argument-hint: [--only metrics|retro|launch|competitive]
---

# Post-Analysis: 완성된 프로젝트 분석 (오케스트레이터)

완성된 프로젝트의 코드와 기획 문서를 분석하여 **Metrics/Retrospective/Launch/Competitive** 4가지 관점의 분석 보고서를 생성합니다.

**핵심 원칙**: 코드+기획문서에서 뽑을 수 있는 건 AI가 채우고, 외부 데이터가 필요한 부분은 `[조사 필요]`로 표시.

**Ralph Loop/Progress 불필요** — 1회 실행, 반복 없음.

## 인수 파싱

`$ARGUMENTS`에서 `--only` 옵션을 확인합니다:

- `--only metrics` → metrics-recommendation만 실행
- `--only retro` → retrospective만 실행
- `--only launch` → launch-analysis만 실행
- `--only competitive` → competitive-frame만 실행
- 옵션 없음 → 4개 모두 순차 실행

## 공통 맥락 수집 (1회만)

**어떤 분석을 실행하든 먼저 아래 맥락을 수집합니다.** 이 결과를 각 skill에 전달합니다.

### 1. 기획 문서 스캔

```
docs/ 디렉토리에서 다음 파일들을 탐색:
- overview.md, SPEC.md, spec.md
- personas/, user-stories/
- PRD.md, requirements.md
- 기타 .md 파일
```

각 문서의 존재 여부와 핵심 내용(제목, 첫 섹션)을 요약합니다.

### 2. 소스 코드 구조

```
프로젝트 루트에서 소스 코드 디렉토리 탐색:
- lib/ (Flutter/Dart)
- src/ (일반)
- app/ (Next.js, Rails 등)
- pages/, components/ (React)
```

디렉토리 트리(2단계 깊이)와 주요 파일 목록을 수집합니다.

### 3. Progress JSON

`.claude-full-auto-progress.json` 존재 여부를 확인합니다.
- 존재 시: Phase별 상태, iteration 횟수, 에러 로그 요약
- 미존재 시: "progress 데이터 없음" 기록

### 4. Git Log

```bash
# 커밋 존재 여부 확인 후 실행 (빈 저장소 대응)
if git log --oneline -1 &>/dev/null; then
  git log --oneline -50
else
  echo "커밋 데이터 없음"
fi
```

최근 50개 커밋 메시지를 수집합니다. 커밋이 없으면 "커밋 데이터 없음"으로 기록합니다.

### 5. 프로젝트 메타데이터

```
프로젝트 설정 파일 탐색:
- pubspec.yaml (Flutter)
- package.json (Node.js)
- build.gradle (Android)
- Podfile (iOS)
```

앱 이름, 버전, 의존성 목록을 추출합니다.

## 분석 순차 실행

수집된 공통 맥락을 기반으로 각 skill을 순차 실행합니다.

### 출력 디렉토리 생성

```bash
mkdir -p docs/post-analysis
```

### 실행 순서

**`--only` 옵션이 없으면 4개 모두 순서대로 실행합니다.**

#### 1. Metrics Recommendation

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/post-analysis/metrics-recommendation/SKILL.md
```

SKILL.md의 절차에 따라 분석을 수행하고 `docs/post-analysis/metrics-recommendation.md`에 저장합니다.

완료 후 `/compact`를 실행합니다.

#### 2. Retrospective

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/post-analysis/retrospective/SKILL.md
```

SKILL.md의 절차에 따라 분석을 수행하고 `docs/post-analysis/retrospective.md`에 저장합니다.

완료 후 `/compact`를 실행합니다.

#### 3. Launch Analysis

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/post-analysis/launch-analysis/SKILL.md
```

SKILL.md의 절차에 따라 분석을 수행하고 `docs/post-analysis/launch-analysis.md`에 저장합니다.

완료 후 `/compact`를 실행합니다.

#### 4. Competitive Frame

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/post-analysis/competitive-frame/SKILL.md
```

SKILL.md의 절차에 따라 분석을 수행하고 `docs/post-analysis/competitive-frame.md`에 저장합니다.

## 완료 보고

모든 분석이 완료되면 요약을 출력합니다:

```
## Post-Analysis 완료

생성된 파일:
- docs/post-analysis/metrics-recommendation.md ✅
- docs/post-analysis/retrospective.md ✅
- docs/post-analysis/launch-analysis.md ✅
- docs/post-analysis/competitive-frame.md ✅

[조사 필요] 표시된 항목은 외부 데이터가 필요합니다.
해당 항목을 채운 후 더 정확한 분석이 가능합니다.
```

`--only` 옵션 사용 시 해당 분석만 표시합니다.
