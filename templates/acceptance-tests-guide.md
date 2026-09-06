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
자체 기동한 포트로 구성한다 (예: `BASE="http://localhost:$PORT"` — 포트는 run.sh가 고른다).
테스트가 참조하는 헬퍼/픽스처 파일도 반드시 `tests/acceptance/` 내부에 두어 동결 범위에 포함시킨다.

**기동은 "프로젝트 표준 진입점 + 포트 주입"으로 한다 (구현 구조 추측 금지)**:
동결은 구현 **前**에 일어난다. run.sh가 `node src/server.js`처럼 **구체 파일 경로**를 적으면 아직 존재하지 않는
구현 구조를 추측하는 것이고, 구현이 조금만 달라져도 **수정할 수 없는** 동결 테스트가 깨진다.
그러므로 run.sh는 스택의 **표준 진입점 한 줄**만 호출하고 포트는 **환경변수로 주입**한다:

| 스택 | 기동 명령 |
|------|-----------|
| Node | `PORT=$PORT npm start` (개발 서버가 필요하면 `PORT=$PORT npm run dev`) |
| Python | `PORT=$PORT python -m <package>` |
| Make 기반 | `PORT=$PORT make run` |
| 컨테이너 | `PORT=$PORT docker compose up -d` (종료는 `docker compose down`) |

- 기동 후 **헬스체크 폴링**으로 준비를 기다리고, 종료는 `trap ... EXIT`로 보장한다 (하드코딩 sleep 최소화).
- **구현 Phase의 의무**: 이 표준 진입점(`npm start` / `make run` / `python -m <pkg>` / `docker compose up`)이
  **실제로 동작하도록 제공**해야 한다. 진입점이 없어 인수 테스트가 red인 것은 "테스트가 틀린 것"이 아니라
  **구현 미완**이다 — 동결 테스트를 고치지 말고 진입점을 만들어라. 스캐폴딩 단계에서 `package.json`의
  `scripts.start`(또는 Makefile `run` 타깃)를 **가장 먼저** 만든다.

**개별 파일 단독 실행 가능하게 작성한다 (`_helper.sh` 필수)**: 구현 Phase는 문서 단위로 해당 US 파일만 실행한다
(`bash tests/acceptance/us-b-001-*.sh`). 전체 `run.sh`는 구현 종료 시점과 Phase 4 게이트에서만 돌린다.
따라서 각 `us-*.sh`는 단독 실행 시에도 필요한 서버를 스스로 확보해야 한다 —
`tests/acceptance/_helper.sh`에 "표준 진입점으로 기동 + 헬스체크 + `trap EXIT` 종료"를 넣고
run.sh와 개별 테스트가 **같은 헬퍼를 source**한다 (헬퍼도 동결 범위 안이다). `us-*.sh`가 있는데
`_helper.sh`가 없으면 `acceptance-freeze`가 WARN을 출력한다 — 단독 실행 불가한 테스트는 구현 Phase에서
전체 러너 우회를 유발하는 결함이므로 동결 전에 고쳐라.

**서버 재사용은 같은 셸 세션이 직접 기동한 프로세스에 한정한다**: 헬퍼는 자기 셸이 띄운 서버의 pid/포트를
**셸 변수**(예: `ACC_SERVER_PID`, `ACC_PORT`)로만 기억하고, 그 변수가 비어 있으면 무조건 새로 기동한다.
파일(`.acceptance-run/` 등)·외부 env·"포트가 이미 열려 있음" 같은 **프로세스 밖의 신호로 재사용을 판정하지
마라** — 동결 범위 밖의 파일이나 환경은 누구나 쓸 수 있으므로, 거기 적힌 포트로 목 서버를 가리키면
`acceptance-gate`의 env 스크럽(BASE_URL 제거)을 우회하는 green 세탁 채널이 된다. run.sh는 시작 시
잔존 런타임 산출물(`.acceptance-run/` 같은 디렉토리를 쓰는 경우)을 **먼저 삭제**하고 자기 세션에서 기동한다.
개별 `us-*.sh` 단독 실행이 매번 서버를 새로 띄우는 것은 정상 비용이다 — 재사용 최적화는 세탁 채널의 대가로
얻는 것이므로 하지 않는다.

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
- **UI 상태 커버 (hasFrontend=true)**: SPEC의 "UI States" 명세 중 AC에 포함된 상태(빈 상태/에러 상태 등)는 반드시 테스트로 작성한다 — 예: 데이터 0건에서 빈 상태 문구 존재 어서션, API 실패 시 에러 표시 어서션. happy path만 있는 프론트 테스트는 불완전하다.
- 하드코딩된 `sleep` 최소화 — 가능하면 폴링/헬스체크 대기 사용.
- 테스트 간 독립성: 실행 순서에 의존하지 않게 작성.

## 동결 / 변경 절차

1. 생성 완료 → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh acceptance-freeze` 실행 (tests/acceptance/ 전체 + **SPEC 파일** 해시 동결 → `tests/acceptance/.manifest.json` 생성).
2. 동결 후 `tests/acceptance/**` 수정은 protect-files-guard 훅이 차단하며, 우회 수정도 `acceptance-gate`의 해시 무결성 검사가 잡는다.
   - **변조·삭제 = FAIL** (완주 차단).
   - **동결 목록에 없는 파일 추가 = WARN** — 추가는 기존 동결 파일의 어서션을 약화시킬 수 없기 때문이다. `addedFiles`로 기록되며, run.sh가 추가 파일도 실행하므로 `total`이 늘어나는 것은 정상이다.
3. **변경이 필요하면 unlock 절차로만** (승인 없이는 파일 자체가 열리지 않는다):
   1. **사용자 승인**: AskUserQuestion으로 "무엇이 왜 틀렸고 어떻게 고칠지"를 제시하고 승인받는다.
   2. **해제**: `... shared-gate.sh acceptance-unlock --approved-by-user --reason "<승인받은 사유>"` → `.claude/acceptance-unlock.json` 토큰 생성. 훅이 `SPEC.md`와 `tests/acceptance/**` 편집을 한시 허용한다(경고만 출력). `--approved-by-user` 없이 실행하면 거부된다.
   3. **수정**: SPEC과 인수 테스트를 고친다.
   4. **재동결**: `... shared-gate.sh acceptance-freeze --approved-by-user` → 토큰이 **소비(삭제)**되고 사유가 manifest의 `refreezeHistory`에 남는다.
   5. **재검증**: `... shared-gate.sh acceptance-gate` 재실행. 토큰이 남아 있으면 게이트가 FAIL(`unlock pending — re-freeze first`)하고 stop-hook이 완주를 차단한다.
4. **구현 편의를 위한 테스트 완화는 스펙 변경이 아니다 — 금지.** 테스트가 어렵다는 이유로 어서션을 약화/삭제하지 않는다.
5. **flaky 재시도**: 러너가 실패하면 `acceptance-gate`가 **1회 자동 재실행**한다. 2회차 green이면 **`soft_fail`**(`flaky: true` + 1회차 결과 `firstRun`)로 기록되고 완주가 차단된다 — 재시도는 "환경 노이즈인지 테스트 결함인지"를 분리하는 진단이지 green을 만들어 주는 장치가 아니다. 시간·순서·포트 의존을 제거한 뒤 게이트를 재실행해 **1회차에 green**이어야 `pass`가 된다. (해시 무결성 실패는 재시도하지 않는다.)
