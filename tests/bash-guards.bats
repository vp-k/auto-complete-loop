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
