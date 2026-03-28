# 코드 리뷰 결과: 하네스 엔지니어링 개선

## 요약

> **Round 1**: 총 6건 발견 → 확인 3건 (수정 완료), 기각 3건
> **Round 2**: 총 1건 발견 → 확인 1건 (수정 완료)
> **Round 3** (스코프 누락 방지 변경): 총 8건 발견 → 확인 6건 (수정 완료), 기각 2건
> **최종**: 누적 확인 10건 모두 수정 완료

## 리뷰 범위

- **대상**: 하네스 엔지니어링 개선 전체 변경사항
- **파일 수**: 9개 (수정 5 + 신규 4)
- **청크 수**: 1개
- **리뷰어**: codex-cli (독립 탐색) → Claude Code (검증)

## Findings (확인됨 — 모두 수정 완료)

### High

#### ERR-HIGH-001: hooks.json 경로 미인용으로 공백 경로에서 훅 실패 가능
- **파일**: `hooks/hooks.json`
- **라인**: 전체 command 필드 (7개)
- **발견자**: codex-cli
- **설명**: `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` 경로가 인용 없이 사용되어 공백 포함 경로에서 쉘 토큰 분리로 실행 실패 가능. flutter-craft는 `\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\"` 형태로 인용 처리 중.
- **수정**: 모든 command에 이스케이프된 따옴표로 경로 인용 처리 완료

#### DATA-HIGH-002: session-start.sh JSON 출력 시 RALPH_INFO 미이스케이프
- **파일**: `hooks/session-start.sh`
- **라인**: 47-51, 73-80
- **발견자**: codex-cli
- **설명**: `RECOVER_OUTPUT`만 escape 처리하고 `RALPH_INFO`(PROMISE 값)와 `PROGRESS_FILE`은 원문 그대로 JSON에 삽입. 특수문자 포함 시 JSON 파손.
- **수정**: `escape_for_json()` 수동 함수를 제거하고 `jq -n --arg` 방식으로 안전하게 JSON 생성하도록 전면 리팩토링

#### ERR-HIGH-R2-001: L5 에스컬레이션이 exit 1로 잘못 반환 (Round 2)
- **파일**: `scripts/shared-gate.sh`
- **라인**: 1733-1751 (exit code 분기)
- **발견자**: codex-cli (Round 2)
- **설명**: L5의 budget=0이므로 `current_count >= current_budget` 조건이 항상 true → `exit 1`(다음 레벨 에스컬레이트)로 빠짐. L5는 최종 사용자 개입 단계이므로 `exit 3`이어야 함.
- **수정**: L5 분기를 최우선으로 추가하여 `exit 3` 반환하도록 수정

### Low

#### CODE-LOW-005: L5 도입 후 record-error usage 문구 불일치
- **파일**: `scripts/shared-gate.sh`
- **라인**: 16, 1595, 1603, 2577, 2579
- **발견자**: codex-cli
- **설명**: L5가 유효 레벨로 추가되었지만 usage/help 문구 4곳이 `L0-L4`로 남아있어 운영자 혼동 유발
- **수정**: 모든 문구를 `L0-L5`로 통일, help에 `L5=user` 설명 추가

## 기각된 Findings

| ID | 제목 | 발견자 | 기각 사유 |
|----|------|--------|----------|
| SEC-MEDIUM-003 | run-hook.cmd 인자 미인용 | codex-cli | Claude Code 하네스가 hook 호출 시 인자를 시스템이 제어. 사용자 입력이 인자로 전달되는 경로 없음. flutter-craft 동일 패턴 |
| SEC-MEDIUM-004 | run-hook.cmd 스크립트명 검증 부재 | codex-cli | SCRIPT_NAME은 hooks.json에 하드코딩. 사용자 입력으로 제어 불가. flutter-craft 동일 패턴 |
| PERF-LOW-006 | console-warn.sh 다중 서브프로세스 | codex-cli | 파일당 1회 실행, PostToolUse 훅은 저빈도 호출. 성능 영향 무시 수준 |

## 리뷰 통계

| 카테고리 | 발견 | 확인 | 기각 |
|----------|------|------|------|
| Security (SEC) | 2 | 0 | 2 |
| Error Handling (ERR) | 2 | 2 | 0 |
| Data Consistency (DATA) | 1 | 1 | 0 |
| Performance (PERF) | 1 | 0 | 1 |
| Code Consistency (CODE) | 1 | 1 | 0 |
| **합계** | **7** | **4** | **3** |
