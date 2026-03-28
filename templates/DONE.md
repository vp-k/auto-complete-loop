# Definition of Done

## 공통 DoD
- [ ] 빌드 성공 (exit code 0)
- [ ] 타입 체크 통과
- [ ] 린트 통과
- [ ] 관련 테스트 전체 통과

## 기획 문서 DoD
- [ ] Problem Statement 명시
- [ ] 페르소나 정의됨
- [ ] 핵심 Job/가치 제안 명시 (JTBD)
- [ ] MoSCoW 분류 완료
- [ ] 핵심 가정 식별 + 우선순위화
- [ ] Pre-mortem 완료
- [ ] 성공 기준 정의됨
- [ ] 유저스토리/목적이 명시됨
- [ ] 데이터 모델 정의됨
- [ ] API 계약 명시됨 (해당 시)
- [ ] 에러/예외 시나리오 포함
- [ ] 정의 문서와 충돌 없음
- [ ] (Medium+) 핵심 플로우 정의됨
- [ ] (Large) 이해관계자 맵 작성됨

## 구현 DoD
- [ ] SPEC.md의 모든 유저스토리 구현 (Frontend + Backend 모두)
- [ ] projectScope.hasFrontend=true → 프론트엔드 페이지/컴포넌트 구현 완료
- [ ] projectScope.hasBackend=true → API 엔드포인트/서비스 구현 완료
- [ ] 모든 레이어의 User Stories가 구현됨 (US-F-* + US-B-*)
- [ ] 백엔드: 테스트 커버리지 충분
- [ ] .env.example에 환경 변수 반영
- [ ] 코드 리뷰 완료

## 릴리즈 DoD
- [ ] 전체 빌드/테스트/린트 통과
- [ ] 보안 취약점 스캔 통과
- [ ] README 업데이트
- [ ] 디버그 코드 제거
- [ ] WCAG AA 접근성 준수 (또는 design-polish 미설치로 SKIP)
- [ ] 릴리즈 노트 작성
- [ ] 배포 체크리스트 완료
