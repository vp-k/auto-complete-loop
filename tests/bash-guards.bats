#!/usr/bin/env bats
# bash-guards.bats — 통합 Bash 가드 중 check_no_verify(토크나이저 기반) 검증
# 회귀 고정: (1) 여러 줄 큰따옴표 메시지 안의 --no-verify 오탐 금지
#            (2) -nm 등 n 이 마지막이 아닌 결합 단축 플래그 오검 금지

HOOK="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/hooks/bash-guards.sh"

# command 문자열을 tool_input.command 으로 감싼 JSON 을 훅에 stdin 으로 흘려
# block 여부를 반환 (BLOCK / PASS)
run_guard() {
  local cmd="$1" json out
  json=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
  out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null || true)
  if printf '%s' "$out" | grep -q '"decision": "block"'; then
    echo "BLOCK"
  else
    echo "PASS"
  fi
}

# ─── True positives: 반드시 BLOCK ───

@test "no-verify: git commit --no-verify 차단" {
  [ "$(run_guard 'git commit --no-verify -m x')" = "BLOCK" ]
}

@test "no-verify: git commit -n 차단" {
  [ "$(run_guard 'git commit -n -m x')" = "BLOCK" ]
}

@test "no-verify: git commit -nm 결합 단축(n 이 마지막 아님) 차단 [오검 회귀]" {
  [ "$(run_guard 'git commit -nm "msg"')" = "BLOCK" ]
}

@test "no-verify: git commit -vn 결합 단축 차단" {
  [ "$(run_guard 'git commit -vn -m x')" = "BLOCK" ]
}

@test "no-verify: git push --no-verify 차단" {
  [ "$(run_guard 'git push --no-verify origin main')" = "BLOCK" ]
}

@test "no-verify: git -C <path> commit --no-verify (글로벌 옵션 선행) 차단" {
  [ "$(run_guard 'git -C /repo commit --no-verify -m x')" = "BLOCK" ]
}

@test "no-verify: git -c k=v commit --no-verify (글로벌 -c 인자 소비) 차단" {
  [ "$(run_guard 'git -c user.name=x commit --no-verify')" = "BLOCK" ]
}

@test "no-verify: git commit --amend -n 차단" {
  [ "$(run_guard 'git commit --amend -n')" = "BLOCK" ]
}

# ─── False-positive guards: 반드시 PASS ───

@test "no-verify: 단일 줄 메시지 안의 --no-verify 는 통과 [오탐 회귀]" {
  [ "$(run_guard 'git commit -m "docs: explain --no-verify flag"')" = "PASS" ]
}

@test "no-verify: 여러 줄 큰따옴표 메시지 안의 --no-verify 는 통과 [오탐 회귀]" {
  local msg
  msg=$(printf 'git commit -m "line1\n- foo --no-verify bar\nend"')
  [ "$(run_guard "$msg")" = "PASS" ]
}

@test "no-verify: git commit -am (n 없음) 통과" {
  [ "$(run_guard 'git commit -am "msg"')" = "PASS" ]
}

@test "no-verify: git push -n (dry-run) 통과" {
  [ "$(run_guard 'git push -n origin main')" = "PASS" ]
}

@test "no-verify: 선행 grep -n 후 정상 commit 통과 (세그먼트 분리)" {
  [ "$(run_guard 'grep -n foo file; git commit -m x')" = "PASS" ]
}

@test "no-verify: git 이 아닌 명령의 --no-verify 통과" {
  [ "$(run_guard 'some-tool --no-verify')" = "PASS" ]
}

@test "no-verify: --no-verify-tls 같은 더 긴 플래그 통과" {
  [ "$(run_guard 'git push --no-verify-tls')" = "PASS" ]
}

@test "no-verify: 일반 commit 통과" {
  [ "$(run_guard 'git commit -m "normal message"')" = "PASS" ]
}

# ─── 검사 5: acceptance unlock 토큰 보호 (승인 위조 방지) ───

@test "unlock-token: echo 리다이렉트로 토큰 생성 차단" {
  [ "$(run_guard 'echo "{\"reason\":\"x\"}" > .claude/acceptance-unlock.json')" = "BLOCK" ]
}

@test "unlock-token: jq -n 리다이렉트로 토큰 생성 차단" {
  [ "$(run_guard "jq -n '{reason:\"x\"}' > .claude/acceptance-unlock.json")" = "BLOCK" ]
}

@test "unlock-token: rm 으로 토큰 삭제 차단 (소비는 acceptance-freeze 만)" {
  [ "$(run_guard 'rm -f .claude/acceptance-unlock.json')" = "BLOCK" ]
}

@test "unlock-token: cat 읽기는 통과" {
  [ "$(run_guard 'cat .claude/acceptance-unlock.json')" = "PASS" ]
}

@test "unlock-token: jq 조회는 통과" {
  [ "$(run_guard "jq -r .reason .claude/acceptance-unlock.json")" = "PASS" ]
}

@test "unlock-token: shared-gate.sh acceptance-unlock 호출은 통과 (파일명 미지명)" {
  [ "$(run_guard 'bash scripts/shared-gate.sh acceptance-unlock --approved-by-user --reason "AC-B-001 오탈자"')" = "PASS" ]
}

# ─── 검사 6: 결정 로그 보호 (이유 없는 결정 세탁 방지) ───

@test "decision-log: echo >> 로 로그에 한 줄 붙이기 차단" {
  [ "$(run_guard 'echo "{\"iteration\":3,\"kind\":\"none\"}" >> .claude/acl-decisions.jsonl')" = "BLOCK" ]
}

@test "decision-log: jq -c 리다이렉트로 로그 생성 차단" {
  [ "$(run_guard "jq -cn '{iteration:3,kind:\"decision\"}' > .claude/acl-decisions.jsonl")" = "BLOCK" ]
}

@test "decision-log: sed -i 로 iteration 값 고치기 차단" {
  [ "$(run_guard "sed -i 's/\"iteration\":2/\"iteration\":3/' .claude/acl-decisions.jsonl")" = "BLOCK" ]
}

@test "decision-log: rm 으로 로그 삭제 차단 (append-only)" {
  [ "$(run_guard 'rm -f .claude/acl-decisions.jsonl')" = "BLOCK" ]
}

@test "decision-log: cat / jq 읽기는 통과" {
  [ "$(run_guard 'cat .claude/acl-decisions.jsonl')" = "PASS" ]
  [ "$(run_guard "jq -s 'length' .claude/acl-decisions.jsonl")" = "PASS" ]
}

@test "decision-log: shared-gate.sh record-decision 호출은 통과 (파일명 미지명)" {
  [ "$(run_guard 'bash scripts/shared-gate.sh record-decision --what "JWT 확정" --why "세션 스토어 없이 수평 확장해야 한다"')" = "PASS" ]
}

# ─── 검사 7: 컨텍스트 채움 관측 (비차단) — v4.25.0 ───
# 반환: OBSERVE(additionalContext 안내 있음) / PASS(무출력) / BLOCK

run_observe() {
  local cmd="$1" json out
  json=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
  out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null || true)
  if printf '%s' "$out" | grep -q '"decision": "block"'; then echo "BLOCK"
  elif printf '%s' "$out" | grep -q 'additionalContext'; then
    printf '%s' "$out" | grep -q 'permissionDecision' && { echo "PERMISSION_LEAK"; return; }
    echo "OBSERVE"
  else echo "PASS"; fi
}

setup_ctx() {
  CTX_DIR=$(mktemp -d); cd "$CTX_DIR"
  mkdir -p .claude
  printf -- '---\niteration: 3\n---\n' > .claude/ralph-loop.local.md
  seq 1 400 > big.log
  seq 1 400 | sed 's/^/# H /' > big.md
  seq 1 50 > small.md
}
teardown_ctx() { cd /; rm -rf "$CTX_DIR"; }

@test "ctx-observe: cat of >threshold file without filter → OBSERVE + context.read.large(tool=Bash, iteration)" {
  setup_ctx
  [ "$(run_observe 'cat big.log')" = "OBSERVE" ]
  ev=$(grep '"event":"context.read.large"' .claude/acl-events.jsonl | tail -1)
  [ "$(printf '%s' "$ev" | jq -r '.tool')" = "Bash" ]
  [ "$(printf '%s' "$ev" | jq -r '.file')" = "big.log" ]
  [ "$(printf '%s' "$ev" | jq -r '.lines')" = "400" ]
  [ "$(printf '%s' "$ev" | jq -r '.iteration')" = "3" ]
  teardown_ctx
}

@test "ctx-observe: cat piped to tail/grep/head → PASS (filtered)" {
  setup_ctx
  [ "$(run_observe 'cat big.log | tail -20')" = "PASS" ]
  [ "$(run_observe 'cat big.md | grep -n US-001')" = "PASS" ]
  [ "$(run_observe 'cat big.log | head -5')" = "PASS" ]
  [ ! -f .claude/acl-events.jsonl ] || ! grep -q 'context.read.large' .claude/acl-events.jsonl
  teardown_ctx
}

@test "ctx-observe: cat of small file → PASS" {
  setup_ctx
  [ "$(run_observe 'cat small.md')" = "PASS" ]
  teardown_ctx
}

@test "ctx-observe: mixed args — only the large file is reported" {
  setup_ctx
  json=$(jq -n --arg c 'cat small.md big.md' '{tool_input:{command:$c}}')
  out=$(printf '%s' "$json" | bash "$HOOK")
  [[ "$out" == *"big.md(400줄)"* ]]
  [[ "$out" != *"small.md"* ]]
  teardown_ctx
}

@test "ctx-observe: bare test runner (npm test / pytest / bats / go test) → OBSERVE + context.run.uncapped" {
  setup_ctx
  [ "$(run_observe 'npm test')" = "OBSERVE" ]
  [ "$(run_observe 'pytest tests/')" = "OBSERVE" ]
  [ "$(run_observe 'bats tests/')" = "OBSERVE" ]
  [ "$(run_observe 'go test ./...')" = "OBSERVE" ]
  [ "$(grep -c '"event":"context.run.uncapped"' .claude/acl-events.jsonl)" -eq 4 ]
  teardown_ctx
}

@test "ctx-observe: test runner via shared-gate.sh / run-capped / tail / redirect → PASS" {
  setup_ctx
  [ "$(run_observe 'bash scripts/shared-gate.sh run-capped -- npm test')" = "PASS" ]
  [ "$(run_observe 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/shared-gate.sh quality-gate')" = "PASS" ]
  [ "$(run_observe 'npm test 2>&1 | tail -30')" = "PASS" ]
  [ "$(run_observe 'bats tests/ > out.log 2>&1')" = "PASS" ]
  [ ! -f .claude/acl-events.jsonl ] || ! grep -q 'context.run.uncapped' .claude/acl-events.jsonl
  teardown_ctx
}

@test "ctx-observe: unrelated commands and words containing runner names → PASS" {
  setup_ctx
  [ "$(run_observe 'git status')" = "PASS" ]
  [ "$(run_observe 'echo pytest-cov is installed')" = "PASS" ]
  [ "$(run_observe 'ls tests/')" = "PASS" ]
  teardown_ctx
}

@test "ctx-observe: ACL not active → PASS and no events file" {
  CTX_DIR=$(mktemp -d); cd "$CTX_DIR"; seq 1 400 > big.log
  [ "$(run_observe 'cat big.log')" = "PASS" ]
  [ "$(run_observe 'npm test')" = "PASS" ]
  [ ! -e .claude/acl-events.jsonl ]
  teardown_ctx
}

@test "ctx-observe: blocking checks still win over observation (no-verify + cat big)" {
  setup_ctx
  [ "$(run_observe 'cat big.log; git commit --no-verify -m x')" = "BLOCK" ]
  teardown_ctx
}

@test "ctx-observe: never emits permissionDecision" {
  setup_ctx
  [ "$(run_observe 'cat big.log; npm test')" = "OBSERVE" ]
  teardown_ctx
}

@test "ctx-observe: runner name inside a quoted string (commit message) → PASS [review M3]" {
  setup_ctx
  [ "$(run_observe 'git commit -m "fix: npm test 실패 수정"')" = "PASS" ]
  [ ! -f .claude/acl-events.jsonl ] || ! grep -q 'context.run.uncapped' .claude/acl-events.jsonl
  teardown_ctx
}

@test "ctx-observe: cat > file <<EOF (write) is not counted as a read [review M4]" {
  setup_ctx
  [ "$(run_observe 'cat > big.md <<EOF
x
EOF')" = "PASS" ]
  [ "$(run_observe 'cat big.log > copy.log')" = "PASS" ]
  teardown_ctx
}

@test "ctx-observe: go test | tee → PASS (tee counts as a capture)" {
  setup_ctx
  [ "$(run_observe 'go test ./... 2>&1 | tee out.log')" = "PASS" ]
  teardown_ctx
}
