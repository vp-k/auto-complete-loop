# 코드 리뷰 결과: gstack 기반 개선사항 (2차 리뷰)

## 요약

> 총 12건 발견 (Critical: 0, High: 5, Medium: 7, Low: 0)
> 검증 후 확인: 10건, 기각: 2건

## 리뷰 범위

- **대상**: gstack 기반 개선사항 전체 (1차 리뷰 수정 반영 후)
- **파일 수**: 9개
- **청크 수**: 2개 (ACL 7파일 + design-polish 2파일)
- **리뷰어**: codex-cli (독립 탐색) → Claude Code (검증)

## Findings (확인됨)

### High

#### SEC-HIGH-001: trufflehog 실행 실패를 성공으로 오판 (Fail-Open)
- **파일**: `scripts/shared-gate.sh`
- **라인**: 1159-1166
- **발견자**: codex-cli
- **설명**: trufflehog 실행 자체가 실패(크래시/권한 등)해도 출력이 비어 있으면 PASS로 처리. 시크릿 유출 검사 우회 가능.
- **수정**: `th_exit != 0`일 때 출력이 비면 `error`로 처리하도록 분기 추가

#### SEC-HIGH-002: npm audit 파싱 실패 시 취약점 스캔 통과
- **파일**: `scripts/shared-gate.sh`
- **라인**: 942-956
- **발견자**: codex-cli
- **설명**: npm audit 비정상 실패 시 비JSON 출력을 jq fallback으로 0 처리하여 PASS. fail-open.
- **수정**: JSON 파싱 가능 여부 검증 추가, 파싱 불가 시 HIGH로 처리

#### SEC-HIGH-003: 외부 URL 캡처 시 --no-sandbox 강제 사용
- **파일**: `plugins/design-polish/scripts/capture.cjs`
- **라인**: 289-292
- **발견자**: codex-cli
- **설명**: Puppeteer를 항상 `--no-sandbox`로 실행. 외부 URL 캡처 시 호스트 보호 약화.
- **수정**: `UNSAFE_NO_SANDBOX=true` 또는 `CI=true` 환경변수 시에만 sandbox 비활성화

#### ERR-HIGH-1: captureReferences에서 browser.close() 미정리
- **파일**: `plugins/design-polish/scripts/capture.cjs`
- **라인**: 385-424
- **발견자**: codex-cli
- **설명**: try-finally 없어 예외 시 크롬 프로세스 누수
- **수정**: try-finally 패턴 적용

#### ERR-HIGH-2: wcagOnly에서 browser.close() 미정리
- **파일**: `plugins/design-polish/scripts/capture.cjs`
- **라인**: 443-480
- **발견자**: codex-cli
- **설명**: 동일 패턴의 리소스 누수
- **수정**: try-finally 패턴 적용

### Medium

#### SEC-MEDIUM-004: 고정 /tmp 로그 파일로 TOCTOU 위험
- **파일**: `scripts/shared-gate.sh`
- **라인**: 1392, 2104
- **발견자**: codex-cli
- **설명**: `/tmp/smoke-check-server.log`, `/tmp/design-polish-server.log` 고정 경로 사용. 심볼릭 링크 공격, 다중 실행 충돌 위험.
- **수정**: `mktemp`로 고유 로그 파일 생성, 종료 시 정리

#### DATA-MEDIUM-004: checkServer가 HTTP 상태코드 미검증
- **파일**: `plugins/design-polish/scripts/capture.cjs`
- **라인**: 99-101
- **발견자**: codex-cli
- **설명**: 404/500도 ok:true 반환하여 비정상 앱에서도 캡처/점수 산출 진행
- **수정**: `statusCode >= 200 && < 400`만 ok:true로 인정

#### CODE-MEDIUM-005: SKILL.md 터치 타겟 항목이 axe-core 범위 초과
- **파일**: `plugins/design-polish/skills/design-polish/SKILL.md`
- **라인**: 223
- **발견자**: codex-cli
- **설명**: 터치 타겟 44x44px이 WCAG 체크 항목으로 명시되나 axe-core에서 자동 검증 불가
- **수정**: "(수동 점검 필요)"로 명확히 표기

#### DATA-MEDIUM-006: git commit -am이 신규 파일 누락
- **파일**: `commands/code-review-loop.md`
- **라인**: 257
- **발견자**: codex-cli
- **설명**: `git commit -am`은 untracked 파일을 포함하지 않아 리뷰 수정 중 신규 파일 누락 가능
- **수정**: `git add -A && git commit -m ...`으로 변경

#### ERR-MEDIUM-007: grep -oP가 POSIX 비호환
- **파일**: `skills/verification/SKILL.md`
- **라인**: 173-177
- **발견자**: codex-cli
- **설명**: `grep -oP`(PCRE)는 BSD/macOS grep에서 미지원. `main` 브랜치 하드코딩.
- **수정**: awk 기반 POSIX 호환 파이프라인으로 교체, `BASE_BRANCH` 변수화

## 기각된 Findings

| ID | 제목 | 발견자 | 기각 사유 |
|----|------|--------|----------|
| DATA-HIGH-003 | jq_inplace 파일 락 부재 | codex-cli | shared-gate.sh는 단일 프로세스에서 순차 실행. 동시 실행 시나리오 미발생 |
| PERF-MEDIUM-005 | secret-scan 패턴별 반복 순회 | codex-cli | 16패턴 × grep은 실용적 비용. gitleaks/trufflehog 우선 사용되며 fallback만 해당 |

## 리뷰 통계

| 카테고리 | 발견 | 확인 | 기각 |
|----------|------|------|------|
| Security (SEC) | 4 | 4 | 0 |
| Error Handling (ERR) | 3 | 3 | 0 |
| Data Consistency (DATA) | 3 | 2 | 1 |
| Performance (PERF) | 1 | 0 | 1 |
| Code Consistency (CODE) | 1 | 1 | 0 |
| **합계** | **12** | **10** | **2** |
