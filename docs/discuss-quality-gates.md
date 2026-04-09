# /full-auto 프로덕트 퀄리티 향상을 위한 추가 게이트/메커니즘 검토

## 배경

auto-complete-loop 플러그인의 /full-auto로 생성하는 프로젝트의 구현 품질이 MVP 미달인 문제를 해결하기 위해, 1차로 다음 게이트를 구현 완료:

- implementation-depth: stub/빈 함수 탐지 (SOFT, bash grep 기반)
- test-quality: assertion 비율/skip 비율/US-* 커버리지 (SOFT)
- functional-flow: 프로젝트 유형별 smoke 스크립트 실행
- IMPL 카테고리: codex 코드 리뷰에서 SPEC 대조 (STUB/SCHEMA/MISSING/HARDCODE/FLOW)
- gateHistory: 모든 게이트 실행 이력 추적
- smoke-check 확장: tests/api-smoke.sh 우선 실행
- Phase 0 스펙 목록 강화: API 목록, 데이터 모델, 핵심 플로우, 페이지 목록
- Phase 1 smoke 스크립트 생성: curl 기반 검증 스크립트를 SPEC 산출물로 생성

## 현재 한계

1차 구현은 주로 **코드 수준** 검증에 집중. 다음 영역이 아직 커버되지 않음:

### 커버되지 않는 영역
1. **비주얼 검증**: 레이아웃 깨짐, CSS 문제, 반응형 깨짐을 감지할 수 없음
2. **실제 유저 플로우**: curl은 API만 검증. 브라우저에서 실제 클릭→입력→제출 플로우를 검증하지 않음
3. **프론트엔드 렌더링**: 컴포넌트가 실제로 화면에 렌더링되는지 (빈 페이지, 에러 화면) 검증 안 됨
4. **데이터 흐름**: 생성→조회→수정→삭제 CRUD가 실제로 DB까지 연결되는지
5. **인증 플로우**: 로그인→토큰 저장→인증된 요청이 실제로 연결되는지
6. **에러 상태 UI**: 404, 500, 네트워크 에러 시 적절한 UI가 표시되는지

## 토론 주제

현재 auto-complete-loop 플러그인의 구조(shared-gate.sh, skills/, hooks/)를 기반으로:

1. **비주얼 체크**: Playwright 스크린샷 + 기대값 비교? design-polish-gate 확장? Phase 2에서 실행 가능한 수준의 경량 비주얼 체크?
2. **E2E 플로우 자동화**: Phase 1에서 Playwright 테스트 스크립트를 SPEC 기반으로 자동 생성? 현재 tests/api-smoke.sh와 어떻게 공존?
3. **프론트엔드 렌더링 검증**: 서버 시작 후 각 페이지를 Playwright로 방문하여 "빈 페이지가 아닌지" 확인? console.error 탐지?
4. **CRUD 통합 검증**: API smoke를 확장하여 Create→Read→Update→Delete 전체 사이클을 검증?
5. **실현 가능성**: 이 모든 것이 /full-auto의 자동화 파이프라인 안에서 실행 가능한가? 시간/복잡도 부담은?
6. **우선순위**: 어떤 것을 먼저 구현해야 효과가 큰가?

## 기술적 제약

- shared-gate.sh는 bash 스크립트 (3800+줄)
- 유저 프로젝트에 Playwright가 항상 설치된 건 아님 (e2e-gate에서 auto-install 가능)
- 프로젝트 유형별 분기 필요 (API only, frontend only, fullstack, library)
- Ralph Loop 안에서 실행되므로 시간 제약 고려
