# /full-auto 프로덕트 퀄리티 향상: 추가 게이트 토론 결과

## 결론
> 게이트를 추가하기 전에 **Phase 1 산출물(smoke 스크립트, UI 테스트)이 Phase 전이 규칙에 하드 게이트로 등록되지 않은 것**이 진짜 병목. 즉시 구현할 2개는 **(C) smoke-check 응답 body 필드 검증**과 **(D) Page Render Gate (Playwright 기반 빈 페이지/console.error 탐지)**. Phase 1 강화 축에서는 **ui-smoke.spec.ts 생성(B)**이 CRUD 전체 사이클(A)보다 현실적.

## 상세 분석

### 1. 진짜 병목: Phase 1→2 전이 규칙 미비
- `doc-planning/SKILL.md`의 Step 1-7/1-8이 smoke 스크립트 생성을 요구하지만, `phase-transition-rules.md`는 Step 1-0~1-6만 명시
- `ui-smoke.spec.ts`를 허용하면서도 완료 검증(line 236)이 이 파일을 인식하지 않음
- **해결**: Step 1-7/1-8을 Phase 1→2 전이의 하드 게이트로 승격

### 2. (C) smoke-check 응답 body 필드 검증 — ROI 1순위
- **현재**: HTTP status code만 확인 (200이면 PASS)
- **문제**: `res.json({})` (빈 응답)도 통과
- **해결**: Phase 1에서 생성하는 `api-smoke.sh`가 이미 jq로 필수 필드 검증을 포함하므로, smoke-check가 이 스크립트를 실행하면 됨 (이미 구현됨)
- **추가 필요**: smoke-check fallback(api-smoke.sh 없을 때)에서 SPEC의 GET 엔드포인트 응답에 최소 1개 필드 존재 확인
- 구현 비용: 낮 (jq 한 줄 추가)

### 3. (D) Page Render Gate — ROI 2순위
- **현재**: design-polish-gate가 WCAG만 확인, 플러그인 미설치 시 전체 SKIP
- **문제**: 빈 페이지, JS 런타임 에러, 404 페이지를 전혀 감지 못함
- **해결 구조**:
  - 기본 (Playwright만): 각 페이지 방문 → `page.on('pageerror')`, `console.error` 캡처, body 텍스트 길이 > 0 확인
  - 추가 (design-polish 있으면): WCAG + 스크린샷 캡처
- **독립 서브커맨드**: `page-render-check` (design-polish-gate와 분리, Playwright fallback 포함)
- **Playwright 설치**: `npx playwright install --with-deps chromium` 자동 실행
- 구현 비용: 중 (Playwright wiring + 페이지 목록 추출)

### 4. Phase 1 강화: B(ui-smoke) > A(CRUD)
- **A(CRUD 전체 사이클)**: 범용 강제는 과도. "주요 리소스 1개의 canonical flow"를 Phase 1 필수로 두는 게 현실적. smoke-check가 mutating endpoint를 의도적으로 제외하므로, CRUD는 api-smoke.sh 안에서 idempotent하게 설계
- **B(ui-smoke.spec.ts)**: hasFrontend=true 프로젝트에서 Phase 1 산출물로 생성. functional-flow에서 실행
- **버그 발견**: functional-flow의 fullstack 분기에서 ui-smoke.spec.ts 실행 누락

### 5. Visual Snapshot(F): 반복 루프 게이트로는 비추
- Phase 4 최종 패스에서 advisory/warn 성격으로만 사용
- 이유: 스크린샷 + 모델 추론 지연, 동적 데이터 false positive, blank page/console error는 Playwright가 더 정확

### 6. 기타 제안 판정
| 제안 | 판정 | 이유 |
|------|------|------|
| E(e2e-gate + Phase 1 테스트 자동 실행) | 후순위 | B와 D가 먼저 해결하면 E는 자연스럽게 따라옴 |
| G(Response Schema Validation) | 후순위 | SPEC 구조화가 먼저 필요, JSON Schema 변환 복잡 |

## 합의된 권장사항

### 즉시 구현 (다음 버전)
1. **Phase 1→2 전이 규칙에 Step 1-7/1-8 하드 게이트 추가** — `phase-transition-rules.md` 수정
2. **(C) smoke-check fallback에 응답 body 필드 검증 추가** — `shared-gate.sh` 수정 (~10줄)
3. **(D) page-render-check 서브커맨드 추가** — Playwright 기반 빈 페이지/console.error 탐지
4. **functional-flow fullstack 분기에서 ui-smoke.spec.ts 실행 추가** — 버그 수정
5. **doc-planning 완료 검증에 ui-smoke.spec.ts 인식 추가** — line 236 수정

### 다음 단계 (효과 확인 후)
6. CRUD canonical flow Phase 1 필수화 (주요 리소스 1개)
7. Visual Snapshot Phase 4 advisory

## 토론 과정 요약

### 주요 쟁점
| 쟁점 | codex 입장 | 합의 결과 |
|------|-----------|-----------|
| 게이트 추가 vs Phase 1 강화 | Phase 1 산출물이 먼저 병목 | Phase 1 전이 규칙 하드 게이트 승격 우선 |
| CRUD 전체 사이클 강제 | 범용 강제는 과도 | 주요 리소스 1개 canonical flow만 |
| Page Render를 design-polish에 통합 | 독립 필요 (플러그인 미설치 시 전체 SKIP) | 별도 page-render-check + Playwright fallback |
| Visual Snapshot 위치 | 반복 루프 게이트로는 ROI 낮음 | Phase 4 advisory만 |
| ui-smoke vs api-smoke 우선순위 | B > A | 동의 — 사용자 체감 품질에 직결 |

### 토론 통계
- 총 라운드: 2회
- 참여 AI: codex-cli, Claude Code
- codex가 지적한 핵심 버그: functional-flow fullstack ui-smoke 누락, doc-planning 검증 불일치
