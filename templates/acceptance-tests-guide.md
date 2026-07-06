# 인수 테스트 생성 가이드 (Acceptance Tests Guide)

Phase 1(Doc Planning)에서 SPEC의 인수 조건(AC)으로부터 **실행 가능한** 인수 테스트를 생성할 때 Read하는 가이드입니다.
생성 완료 후 `acceptance-freeze`로 해시 동결되며, 구현 Phase는 이 테스트를 수정할 수 없습니다 (훅 차단 + `acceptance-gate` 해시 무결성 검증).

## 목적 / 원칙

- SPEC.md의 각 User Story(US-F-*/US-B-*)의 AC(Given/When/Then) **1개당 최소 1개**의 실행 가능한 테스트를 작성한다.
- **의사코드/placeholder 금지.** 지금 실행하면 어서션이 실패(red)하는 "진짜 테스트"여야 한다.
  - "실행 불가능한 스크립트"와 "red"는 다르다: **러너는 정상 실행되고, 어서션이 실패**해야 한다. 문법 오류·존재하지 않는 명령으로 실행 자체가 안 되는 테스트는 불합격.
- 기획 시점에는 앱이 없으므로 전체 red가 **정상**이다 (TDD red→green). 구현 Phase가 자신이 수정할 수 없는 이 테스트를 green으로 만들어야만 완주된다.

## 파일 구조

```
tests/acceptance/
├── run.sh                  # 러너 (필수 — 없으면 acceptance-freeze 실패)
├── us-b-001-login.sh       # US 1개당 1개 이상, 파일명에 US-ID 포함 (필수)
├── us-b-002-signup.sh
└── us-f-001-dashboard.spec.ts   # 프로젝트 유형에 따라 .spec.ts 등 가능 — 단 run.sh가 전부 실행·집계
```

- 파일명 ↔ US-ID 매핑 필수: `us-<id>-<slug>.sh` (예: `us-b-001-login.sh`). RTM 역추적의 기준.
- `.sh` 외 형식(Playwright `.spec.ts` 등)을 쓰더라도 **run.sh가 전부 실행하고 집계**해야 한다.

## 러너 규약 (`tests/acceptance/run.sh`)

- **전부 통과 시에만 exit 0**, 하나라도 실패하면 exit 1
- 마지막 줄에 반드시 출력: `ACCEPTANCE_RESULT: total=N passed=N failed=N`

골격 예시:

```bash
#!/usr/bin/env bash
# tests/acceptance/run.sh — 인수 테스트 러너
set -u
cd "$(dirname "$0")"
total=0; passed=0; failed=0
for t in us-*.sh; do
  [[ -f "$t" ]] || continue
  total=$((total+1))
  if bash "$t"; then passed=$((passed+1)); echo "PASS: $t"
  else failed=$((failed+1)); echo "FAIL: $t"; fi
done
# .spec.ts 등 다른 형식을 쓰면 여기서 실행하고 결과를 total/passed/failed에 합산
echo "ACCEPTANCE_RESULT: total=$total passed=$passed failed=$failed"
[[ $total -gt 0 && $failed -eq 0 ]] && exit 0 || exit 1
```

**서버/환경 자체 통제 (green 세탁 방지)**: run.sh가 대상 서버의 기동·포트·종료를 **직접 통제**해야 한다.
`BASE_URL` 등 외부 환경변수로 대상 주소를 받지 마라 — 목 서버로 조향해 green을 세탁하는 경로가 되며,
`acceptance-gate`는 BASE_URL/API_URL 계열 env를 제거하고 실행한다. 대상 URL은 run.sh 내부에서
자체 기동한 포트로 구성한다 (예: `BASE="http://localhost:$PORT"` — run.sh가 $PORT로 직접 기동).
테스트가 참조하는 헬퍼/픽스처 파일도 반드시 `tests/acceptance/` 내부에 두어 동결 범위에 포함시킨다.

## 프로젝트 유형별 작성법

- **API (hasBackend=true)**: `curl`로 호출 + 응답 어서션. (`$BASE`는 run.sh가 자체 기동한 서버 주소)
  - 상태코드 검증: `code=$(curl -s -o /tmp/res.json -w '%{http_code}' -X POST "$BASE/auth/login" -H 'Content-Type: application/json' -d '{...}')` → `[[ "$code" == "200" ]] || exit 1`
  - 필드 검증: `jq -e '.accessToken and .refreshToken' /tmp/res.json || exit 1`
- **웹 프론트 (hasFrontend=true)**: 가능하면 Playwright 스크립트(요소 존재/네비게이션/폼 제출 어서션). 불가 시 페이지 로드 + 핵심 요소 존재를 curl/grep으로 확인.
- **라이브러리/CLI**: 명령 실행 + 출력 어서션 (`out=$(mycli convert x); [[ "$out" == *"expected"* ]] || exit 1`).
- **외부 서비스만 mock** (결제/소셜 로그인 등). 자체 백엔드는 실제 기동을 가정한다 — mock으로 대체 금지.

## 품질 기준

- **어서션 없는 테스트 금지**: "실행됐다"만 확인하고 exit 0 하는 테스트는 무효. 반드시 응답/출력/상태를 검증한다.
- AC의 **실패 조건도 커버**: 잘못된 입력 → 4xx, 권한 없음 → 403 등 부정 경로 어서션 포함.
- 하드코딩된 `sleep` 최소화 — 가능하면 폴링/헬스체크 대기 사용.
- 테스트 간 독립성: 실행 순서에 의존하지 않게 작성.

## 동결 / 변경 절차

1. 생성 완료 → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh acceptance-freeze` 실행 (tests/acceptance/ 전체 해시 동결 → `tests/acceptance/.manifest.json` 생성).
2. 동결 후 tests/acceptance/** 수정은 protect-files-guard 훅이 차단하며, 우회 수정도 `acceptance-gate`의 해시 무결성 검사(변조/추가/삭제 감지)가 잡는다.
3. 이후 **스펙 변경 시에만**: 사용자 승인 → SPEC 갱신 → `acceptance-freeze --approved-by-user`로 재동결.
4. **구현 편의를 위한 테스트 완화는 스펙 변경이 아니다 — 금지.** 테스트가 어렵다는 이유로 어서션을 약화/삭제하지 않는다.
