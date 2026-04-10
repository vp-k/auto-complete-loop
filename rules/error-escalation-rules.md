# Error Classification & Escalation

## 에러 레벨 (Progress Heuristic)
| 레벨 | 분류 | 예시 |
|------|------|------|
| L0 | environment | 패키지 미설치, PATH, 권한 |
| L1 | build | 컴파일 에러, 번들 실패 |
| L2 | type | 타입 불일치, 인터페이스 누락 |
| L3 | runtime | 테스트 실패, 런타임 에러 |
| L4 | quality | 린트, 코드 스타일, 경고 |

**방향 판별**: L0→L1→...→L4 = 진행(forward), 역방향 = 회귀(backward)
회귀 2회 연속 시 현재 접근법을 재검토 (codex 호출 또는 다른 접근법)

## 에스컬레이션 (레벨별 시도 예산)

각 레벨마다 독립적인 시도 예산이 있으며, 예산 소진 시 다음 레벨로 에스컬레이트.
레벨 전환 시 `record-error --reset-count`로 카운터 리셋.

| 레벨 | 예산 | 설명 |
|------|------|------|
| **L0: 즉시 수정** | 3회 | 같은 방법 내 수정 (import 추가, 타입 수정, 간단한 로직) |
| **L1: 다른 방법** | 3회 | 같은 설계, 다른 구현 (라이브러리 교체, 패턴 변경, API 변경) |
| **L2: codex 분석 + 라운드테이블** | 1회 | codex-cli에 근본 원인 분석 요청 + **라운드테이블 토론** (Senior Developer(리드), Architect, QA, Devil's Advocate) + 변경 파일만 `git stash push -- <files>`로 안전 지점 확보 (repo-wide stash 금지) |
| **L3: 완전히 다른 접근법** | 3회 | 설계/아키텍처 수준 전환 (REST→GraphQL, CSR→SSR, WebSocket→폴링). codex 분석 + 라운드테이블 합의 기반 |
| **L4: 범위 축소** | 1회 | 최소 동작 버전으로 구현 + `scopeReductions`에 기록 |
| **L5: 사용자 개입** | - | 선택지 제시 |

에러 기록:
```bash
# 일반 기록
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error --file <f> --type <t> --msg <m> --level <L0-L4> --action "시도한 행동"
# 레벨 전환 시 카운터 리셋
bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh record-error --file <f> --type <t> --msg <m> --level <L0-L4> --reset-count
```

record-error exit code:
- `exit 0`: 현재 레벨 예산 내 → 계속 시도
- `exit 1`: 현재 레벨 예산 소진 → 다음 레벨로 에스컬레이트
- `exit 2`: L2 도달 → codex 분석 필요
- `exit 3`: L5 도달 → 사용자 개입 필요

## L2+ 라운드테이블 토론 (다관점 이슈 해결)

L2 에스컬레이션 도달 시, codex 분석과 함께 `roundtable` 에이전트를 호출하여 다관점 토론을 수행합니다:

**참여 페르소나** (축소 라운드테이블 — 4-5명):
- Senior Developer (리드) — 구현 대안, 기술 부채 평가
- Architect — 설계 수준 전환 필요 여부 판단
- QA Specialist — 테스트 가능성, 회귀 영향
- Devil's Advocate — 현재 접근법의 근본 문제, 숨겨진 가정

**스코프 변경 제안 시 추가 소집**:
- Product Planner — 스코프 축소의 사용자 가치 영향
- PM — 일정/리소스 영향

**프로세스**:
1. codex 근본 원인 분석 결과를 라운드테이블에 입력
2. 각 페르소나가 독립적으로 대안 제시
3. 대안 간 교차 검증 → 합의된 접근법 선택
4. 합의 실패 시 → L3로 에스컬레이트 (다른 접근법 시도)

## Scope Reduction (범위 축소)

**원칙**: 동작하는 제품 + 문서화된 갭 > 모든 기능 갖춘 깨진 제품

**범위 축소 조건:**
- 동일 기능에서 5회 이상 실패 (다른 접근법까지 시도한 후)
- codex 분석 + 접근법 전환 후에도 해결 불가
- 해당 기능이 전체 시스템의 핵심 경로가 아닌 경우

**절차:**
1. 기능을 최소 동작 버전으로 구현 (예: 실시간 알림 → 폴링 기반 알림)
2. progress 파일 `scopeReductions` 배열에 기록:
   ```json
   {"feature": "실시간 알림", "original": "WebSocket 실시간 알림",
    "reduced": "30초 폴링 기반 알림", "reason": "WebSocket 연결 안정성 4회 실패",
    "ticket": "POST_RELEASE_001"}
   ```
3. 프로젝트 루트에 `SCOPE_REDUCTIONS.md` 생성/업데이트
4. 코드에 `// SCOPE_REDUCED: <ticket>` 주석 추가

**범위 축소 불가 항목** (핵심 경로):
- 인증/인가
- 데이터 CRUD의 기본 동작
- 빌드/배포 파이프라인

## 포기 방지
- L0→L1→L2→L3→L4→L5 순서로 에스컬레이트
- 각 레벨에서 예산만큼 시도 후 다음 레벨로 자동 에스컬레이트
- 범위 축소는 핵심 경로(인증, CRUD 기본, 빌드) 제외
- "사용자가 직접 확인해주세요" 금지 (L5 전까지)
