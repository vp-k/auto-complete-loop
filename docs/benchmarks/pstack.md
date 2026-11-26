# pstack 벤치마킹 (v4.26.0)

pstack을 분석해 auto-complete-loop(이하 ACL)에 넣을 것과 넣지 않을 것을 가른 기록이다.
넣지 않은 항목도 이유와 함께 남긴다. 같은 항목을 다음에 다시 검토할 때 이 문서에서 시작한다.

## 출처

| 항목 | 값 |
|------|----|
| 레포 | `backnotprop/pstack` (Cursor `cursor/plugins/pstack`의 미러) |
| 버전 | v0.15.48 |
| 커밋 | `c81f1bf680803f9e3f0cade6adb62593f43fb61f` (2026-11-25) |
| 라이선스 | MIT, Copyright (c) 2026 Lauren Tan |
| 분석 방법 | 문서만 읽었다. 레포의 스크립트는 실행하지 않았다 |
| 분석 범위 | 스킬 35개, principle 스킬 24개, poteto-mode 플레이북 22개, 에이전트 2개, automations, docs/guide |

ACL에 들어간 것은 문장이 아니라 규칙이다. pstack의 텍스트를 복사하지 않고 ACL의 용어와 구조로 다시 썼다.

## 판단 기준

세 질문에 모두 "예"인 것만 넣었다.

1. ACL이 실제로 겪는 실패 모드를 막는가.
2. ACL의 기존 계약과 충돌하지 않는가. 계약은 SPEC 선행, 동결 인수 테스트, fail-closed 게이트, 정해진 질문 지점이다.
3. 비용보다 효과가 큰가. 세션마다 주입되는 규칙은 매번 토큰이 든다.

## 반영한 것

| ID | 반영 내용 | ACL 위치 | pstack 출처 | 강제 수준 |
|----|-----------|----------|-------------|-----------|
| A | CRITICAL/HIGH 지적에 실행 증거 요구, 같은 근본 원인 지적 병합 | `templates/review-perspectives.md`, `commands/code-review-loop.md`, `skills/team-code-review` | `skills/interrogate`, `poteto-mode/references/bugbot-triage.md`, `playbooks/bug-fix.md` | 문서 규칙. `proof` 필드는 선택 |
| B | 레벨을 올리기 전에 실패한 수정들의 공통 전제를 적고 직접 검증 | `rules/error-escalation-rules.md` | `principle-attack-the-premise` | 문서 규칙. 전제가 틀렸으면 `record-error --reset-count`로 같은 레벨 재시작 1회 |
| C | 효과 없던 시도는 파일 단위로 되돌린 뒤 다음 시도 | `rules/error-escalation-rules.md` | `playbooks/bug-fix.md`, `playbooks/autonomous-run.md`, `skills/figure-it-out` | 문서 규칙 |
| D | `record-decision --supersedes D-NNNN` | `scripts/gates/decisions.sh`, `hooks/pre-compact.sh`, `rules/shared-rules.md` | `skills/show-me-your-work` (뒤집힌 결정은 새 행이 대체) | 스크립트 검증. 없는 id, `kind=none`, 이미 뒤집힌 결정은 거부 |
| E | 인수 테스트는 동작을 검증하고 내부를 검증하지 않는다 | `templates/acceptance-tests-guide.md`, `skills/implementation` | `principle-test-behavior-not-implementation`, `skills/correct` 3단계 | 문서 규칙 |
| F | 서브에이전트 착수 지시 3항목 | `rules/shared-rules.md` | `poteto-mode/worker.md` | 문서 규칙 |
| G | 이어받은 기록을 종류별로 얼마나 믿을지 | `rules/shared-rules.md` | `playbooks/session-pickup.md` | 문서 규칙. 일부만 반영 |
| H | 새 게이트·검사를 추가할 때의 층 순서와 삭제 조건 | `CONTRIBUTING.md` | `skills/correct`, `principle-encode-lessons-in-structure` | 플러그인 저자용 가이드 |

### 왜 넣었나

**A. C/H 증거와 근본 원인 병합.**
ACL은 CRITICAL/HIGH 지적마다 수정 의무를 만들고 라운드 예산을 쓴다.
증거 없는 지적도 같은 비용을 치르게 한다.
재현 명령과 출력을 요구하면 실행으로 반증되는 지적이 수정 전에 걸러진다.
같은 원인의 지적 여러 건을 따로 고치면 수정 라운드만 늘어난다.
병합하면 원인 한 곳을 한 번 고친다.

**B. 전제 공격.**
L1에서 L2, L3로 올라가면 방법은 바뀌지만 전제는 그대로 따라간다.
같은 게이트에 두 번 이상 막힌 수정들이 같은 전제를 공유하면 그 전제를 먼저 시험한다.
전제가 틀렸다면 레벨을 올릴 문제가 아니라 처음부터 다시 풀 문제다.
그래서 같은 레벨 재시작을 1회만 허용하고 결정 로그에 이유를 남긴다.

**C. 실패한 시도 되돌리기.**
효과 없던 수정이 작업 트리에 남으면 다음 시도가 그 위에서 시작한다.
리뷰 소스 지문도 그 잔재를 포함해 바뀐다.
되돌릴 때는 `git checkout -- <files>`처럼 파일을 지정한다. 작업 트리 전체 초기화는 쓰지 않는다.

**D. 결정 뒤집기.**
v4.20의 결정 로그는 append-only지만 뒤집혔다는 사실을 표시할 방법이 없었다.
뒤집힌 결정이 `--list`, `handoff.keyDecisions`, 컴팩션 요약에 살아 있는 결정처럼 남았다.
컴팩션 뒤 모델이 죽은 결정을 이어받을 수 있었다.
이제 새 결정이 옛 결정을 가리키고, 세 출력 모두 옛 결정에 `[superseded by D-xxxx]`를 붙인다.
같은 결정을 두 번 뒤집으면 어느 쪽이 유효한지 갈라지므로 거부하고 현재 결정을 알려준다.
assumption-review 교차 검증도 뒤집힌 interview 결정을 빼고 센다.
pstack은 TSV 파일에 같은 규칙을 문장으로 둔다. ACL은 스크립트가 거부하는 층에 둔다.

**E. 동작 검증 테스트.**
인수 테스트는 동결된다. 내부 구현을 단언하는 테스트는 리팩터링 때마다 깨진다.
그러면 사용자 승인 재동결이 필요해진다.
반대로 내부만 보는 테스트는 동작이 깨져도 통과할 수 있다.
가이드에 두 가지 상상 수정을 넣었다. 내부만 바꿨는데 깨지면 내부를 본다. 동작을 깨뜨렸는데 통과하면 아무것도 지키지 않는다.

**F. 서브에이전트 착수 지시.**
solo 리뷰어, repo-fact 자동 조사, verification-auditor는 이 세션의 규칙을 읽지 않는다.
지시가 없으면 자기 게이트를 덧붙이거나 사용자에게 묻는다.
세 항목을 프롬프트에 넣게 했다.

| 항목 | 내용 |
|------|------|
| 기준 | 지시에 적힌 기준이 기준의 전부다. 게이트, 승인, 리뷰 라운드를 더하지 않는다 |
| 질문 | 사용자에게 묻지 않는다. 되돌릴 수 있는 선택은 하고 보고한다 |
| 증거 | 명령, 종료 코드, 핵심 출력 줄을 함께 낸다 |

배포, 데이터 삭제, 공유 브랜치 force-push, 외부 발송 앞에서는 멈추고 보고한다.
사용자에게 묻는 것은 오케스트레이터만 한다.

**G. 이어받은 기록의 신뢰 수준.**
handoff를 읽는 규칙에 신뢰 수준이 없었다.
그래서 결정을 다시 따지거나, 반대로 자기신고 게이트 결과를 그대로 믿을 수 있었다.
결정은 따르고, 게이트 결과와 자기신고는 다시 돌리고, warnings와 nextSteps는 출발점으로 쓴다.

**H. 검사 추가 사다리.**
v4.11부터 v4.25까지 게이트와 훅 검사가 계속 늘었다.
CONTRIBUTING에는 새 검사를 언제 어느 층에 둘지 기준이 없었다.
pstack `correct`의 순서를 ACL의 층으로 옮겼다. 순서는 구조, 스크립트 검증, 게이트, 훅 관측, 문서 규칙이다.
같은 실수가 두 번 있었을 때 만들고, 실제 실수로 실패를 보이고, 실수가 불가능해지면 지운다.

## 일부만 반영한 것

| pstack 항목 | 반영한 부분 | 반영하지 않은 부분과 이유 |
|-------------|-------------|---------------------------|
| `session-pickup` | 이전 기록의 결정은 다시 따지지 않는다 | "이전 재현을 다시 돌리지 말라"는 따르지 않는다. ACL은 자기신고를 믿지 않고 게이트를 항상 다시 돌린다. 기록을 믿는 비용보다 거짓 통과를 이어받는 비용이 크다 |
| `worker.md` "기준이 기준의 전부" | 서브에이전트에만 적용 | 메인 루프에 적용하면 ACL의 게이트 자체가 "기준 위의 게이트"가 된다. ACL에서 기준을 정하는 것은 DoD와 게이트다 |
| `never-block-on-the-human` | 서브에이전트는 묻지 않는다 | ACL은 일부러 둔 질문 지점이 있다. 착수 전 assumption 일괄 확인, clarification batch-ask, 동결 해제 승인이다. 묻지 않고 넘긴 assumption은 전 화면과 전 테스트에 퍼진다 |
| `show-me-your-work` | 뒤집힌 결정 연결 | TSV 형식은 넣지 않는다. 기존 JSONL 로그가 `--why` 길이 검증, runId 격리, 락 채번을 이미 갖고 있다 |
| `interrogate` | 증거 요구, 근본 원인 병합 | 다른 모델 여러 개로 공격하는 팬아웃은 넣지 않는다. codex와 dual 모드가 교차 모델 리뷰를 이미 맡는다 |
| `correct` | 층 순서, 두 번 규칙, 삭제 조건 | 채팅 이력을 캐서 실수 유형을 뽑는 자동화는 넣지 않는다. ACL은 이벤트 로그와 lesson 메모리로 같은 신호를 모은다 |
| `figure-it-out` | 실패한 시도 되돌리기 | 플레이북을 새로 설계하는 절차는 넣지 않는다. ACL의 워크플로우는 고정돼 있다 |

## 반영하지 않은 것

### 원칙 수준에서 충돌하는 것

| pstack 입장 | 넣지 않은 이유 |
|-------------|----------------|
| 계획을 믿지 않는다. 가장 좋은 스펙은 코드다 | ACL은 SPEC과 동결 인수 테스트가 완료의 정의다. 코드를 스펙으로 삼으면 "다 됐다"를 판정할 외부 기준이 사라진다 |
| 사용자에게 절대 묻지 않는다 | 위 표의 `never-block-on-the-human` 참조 |
| 베이스에 이미 있던 문제는 한 줄로 보고하고 막지 않는다 | ACL은 CRITICAL/HIGH를 deferred로 넘기지 못하게 막아 왔다. "원래 있던 문제"라는 분류가 C/H 세탁 경로가 된다 |
| 다른 벤더 모델이 기록을 읽고 Attention 절을 붙인다 | 교차 모델 검토는 codex와 dual 리뷰가 이미 맡는다. 같은 일을 두 채널로 하면 비용만 는다 |

### Cursor·pstack 전용 인프라

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `automations/benny`, Bugbot 연동, 클라우드 에이전트 | Cursor 서버 기능에 묶여 있다. pstack의 Claude Code 하네스 문서도 건너뛰라고 한다 |
| benny 하위 스킬 `setup-benny`, `triage-issue-reports`, `reproduce-and-fix-issues` | Slack 이슈 접수, 트래커 연동, 초안 PR 생성을 하는 benny 자동화 전용이다. 위 행과 같은 이유다 |
| `make-bot-ui` | Grok Bot 웹훅과 Tailscale 연동 UI다. ACL 범위 밖이다 |
| `poteto-help`, `poteto-mode` 진입점 | pstack 내부 길잡이와 라우터다. ACL은 `/full-auto` 등 자체 진입점이 있다 |
| `setup-pstack` | 역할별 모델 설정이다. ACL은 `shared-rules.md` 모델 라우팅 가이드가 같은 일을 한다 |
| `automate-me` | 개인 작업 이력에서 `-mode` 스킬을 만드는 도구다. 완료 프레임워크의 일이 아니다 |
| 에이전트 `poteto-agent` | poteto-mode를 서브에이전트로 띄우는 정의다. 진입점과 같은 이유다 |

### PR·머지 수명주기

| 항목 | 넣지 않은 이유 |
|------|----------------|
| 플레이북 `opening-a-pr`, `shipping`, `babysit`, `autopilot-full`, `autopilot-stack` | ACL은 로컬 커밋에서 끝난다. 푸시와 PR은 외부로 나가는 행동이라 사용자 승인 대상이다 |
| 플레이북 `worktree-cleanup` | 머지된 worktree와 iOS 시뮬레이터 정리다. 개발 환경 관리는 ACL 범위 밖이다 |
| poteto-mode 보조 스크립트 `scripts/watch-pr`, `worktree-audit.sh`, `bootstrap.ts` | `babysit`와 `worktree-cleanup` 플레이북, poteto-mode 설치를 돕는 스크립트다. 플레이북을 넣지 않았으므로 스크립트도 넣지 않는다 |
| `worker.md`의 PR 제목·본문 형식 | 같은 이유다. ACL의 출력 형식은 보고 작성 규칙이 맡는다 |

### 사람에게 설명하거나 글을 다듬는 도구

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `how`, `why`, `teach`, `bro`, `ketchup`, `ketchup-video` | 사람이 직접 불러 설명을 듣는 대화형 도구다. 자율 완료 루프에 끼울 자리가 없다 |
| `in-your-own-words`, `reframe`, `sharpen` | 요구를 되묻고 다듬는 일은 Phase 0 명확성 인터뷰가 점수와 게이트로 이미 한다 |
| `unslop`, `technical-writing` | ACL이 내는 보고와 커밋은 보고 작성 규칙이 다룬다. 일반 문서 문체는 ACL의 일이 아니다 |
| 플레이북 `investigation` | 읽기 전용 질의응답이다. 완료 루프의 단계가 아니다 |

### 병렬 시도

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `arena`, `swarm` | 같은 일을 N번 시도하면 비용이 N배다. ACL은 병렬을 리뷰에만 둔다. 구현 병렬은 teams 모드가 맡는다 |
| principle `exhaust-the-design-space` | 경쟁 프로토타입 2~3개를 만드는 원칙이다. ACL은 설계 갈림길을 Phase 0 인터뷰와 ADR에서 정하고 SPEC을 동결한다 |
| 플레이북 `prototype` | 버리는 코드를 계획 없이 빨리 짜는 절차다. 동결된 SPEC 위에서 구현하는 ACL과 반대 방향이다 |

### 검증 스킬 생성과 형식 검증

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `create-verification-skill`, `maintain-verification-skill` | 앱 기능 지도로 프로젝트 전용 검증 스킬을 만든다. 지금은 live-testing, runtime-gate, functional-flow와 겹친다. 기능 지도는 쓸모가 있어 TODO에 남겼다 |
| `create-formal-verification-skill`, `maintain-formal-verification-skill` | TLA+ 같은 도구 체인이 무겁다. ACL이 다루는 프로젝트에서 필요한 경우가 드물다 |
| `statechart` | TLA+ 모델을 전제로 한다. 같은 이유다 |

### 성능

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `benchmark-checklist`, principle `explain-the-number` | ACL에는 성능 단계가 없다. 성능 요구는 SPEC의 AC로 들어오고 테스트로 검증된다. 성능 주장을 검증하는 체크리스트는 TODO에 남겼다 |
| 플레이북 `perf-issue`, `hillclimb`, `runtime-forensics`, `trace-forensics` | 같은 이유다. 프로파일링 산출물 분석은 ACL이 만드는 결과물이 아니다 |

### 언어·스타일 특화

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `no-comments`, 에이전트 `comment-sicko` | 주석을 지우는 정책이다. ACL은 언어와 스타일에 중립이다. 주석 정책은 프로젝트가 정한다 |
| `typescript-best-practices` | TypeScript 전용이다. 같은 이유다 |

### 설계 철학 principle

| 항목 | 넣지 않은 이유 |
|------|----------------|
| core: `laziness-protocol`, `foundational-thinking`, `redesign-from-first-principles`, `subtract-before-you-add`, `minimize-reader-load`, `outcome-oriented-execution`, `experience-first`, `build-the-lever` | 코드를 어떻게 설계할지에 대한 철학이다. ACL은 끝까지 만들었는지를 검증한다. 설계 품질은 리뷰 관점 템플릿과 architect 에이전트가 본다 |
| architecture: `model-the-domain`, `boundary-discipline`, `type-system-discipline`, `make-operations-idempotent`, `migrate-callers-then-delete-legacy-apis`, `separate-before-serializing-shared-state` | 같은 이유다. 게이트로 검증할 수 없는 원칙을 세션마다 주입하면 토큰만 든다 |

### 나머지 스킬과 플레이북

| 항목 | 넣지 않은 이유 |
|------|----------------|
| `architect` | 함수 경계를 넘는 코드 전에 호출부 모양을 정한다. ACL은 Phase 1 아키텍처 리뷰와 SPEC 데이터 모델이 이 일을 한다 |
| `blast-radius` | 작은 변경의 영향 범위를 추정한다. ACL은 추정 대신 동결 인수 테스트 전체와 runtime-gate를 다시 돌려 실측한다 |
| `recall`, `reflect` | 이력에서 맥락을 재구성하고 교훈을 스킬로 남긴다. session-start 이벤트 주입과 lesson 메모리 루프가 같은 일을 한다 |
| `tdd` | ACL은 인수 테스트 선작성과 동결로 TDD를 이미 강제한다 |
| 플레이북 `feature`, `refactoring`, `multi-phase-plan` | 데이터 모양부터 짓기, 동작 보존 변경, 다단계 계획이다. ACL의 SPEC 데이터 모델, 동결 인수 테스트, Phase 구조가 이미 맡는다 |
| 플레이북 `visual-parity` | 픽셀 단위 UI 일치 검증이다. 디자인 검증은 design-polish 플러그인이 맡는다 |
| 플레이북 `eval`, `authoring-a-skill` | 스킬 저자용 도구다. ACL 자체 검증은 bats가 맡고 저자 가이드는 CONTRIBUTING이 맡는다 |

## ACL에 이미 있는 것

pstack에 있지만 ACL이 다른 이름으로 이미 하고 있는 것이다. 새로 넣지 않았다.

| pstack 항목 | ACL의 기존 장치 |
|-------------|-----------------|
| 플레이북 `pause-safely` | handoff 필드와 `handoff-update` |
| 플레이북 `autonomous-run` "멈추지 않고 끝까지" | Ralph 루프와 fail-closed stop-hook |
| 정체되면 방향을 바꾼다 | 막힘 패턴 감지 `DIMINISHING_RETURNS`, `OSCILLATION` |
| 판정 기준을 완화하지 않는다 | 인수 테스트와 SPEC 해시 동결, 사용자 승인 재동결 |
| principle `prove-it-works` | 증거 기반 완료와 게이트 기록 |
| principle `fix-root-causes` | 에러 에스컬레이션 L2 근본 원인 분석. 리뷰 쪽은 이번에 A로 보강 |
| principle `sequence-verifiable-units` | US 단위 구현과 US별 인수 테스트 |
| principle `guard-the-context-window` | v4.25 컨텍스트 관측 훅과 `doc-section`, `run-capped` |
| principle `attack-the-premise` | 이번에 B로 반영 |
| principle `test-behavior-not-implementation` | 이번에 E로 반영 |
| principle `encode-lessons-in-structure` | 이번에 H로 반영 |

## 후속

`TODO.md`의 "v4.26.0 pstack 벤치마킹" 절에 남겼다.

| 항목 | 다시 볼 조건 |
|------|--------------|
| C/H `proof` 필드 게이트 승격 | 실제 실행에서 증거 없는 C/H가 반복되는 것이 이벤트나 findingHistory에 보일 때 |
| 성능 주장 체크리스트 | SPEC에 성능 AC가 있는 프로젝트를 돌릴 때 |
| 프로젝트별 기능 지도 | live-testing이 같은 기능을 반복해서 놓칠 때 |
| 전제 재시작 1회 제한을 스크립트로 강제 | `error.recorded` 이벤트의 `reset` 필드에서 같은 오류에 `reset:true`가 두 번 나올 때 |
