#!/usr/bin/env bats
# context-usage.bats — v4.24.0 컨텍스트 사용률 계측 + statusline 브리지
#   stop-hook: 트랜스크립트 usage / 창 크기(브리지 > ACL_CONTEXT_WINDOW > 200000) → 임계(기본 60) 이상이면 리마인더
#   statusline-bridge.sh: statusline JSON → <ctx_dir>/<session_id>.json, chain.json 위임, 기본 상태줄
#   statusline-launch.sh: 캐시 최고 버전 > pluginRoot > 사본 순으로 브리지 선택
#   statusline-setup: 스니펫 출력 / --apply 병합(기존 명령 chain 보존, 백업) / --remove 복원

load test_helper

HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
BRIDGE="$SCRIPT_DIR/../hooks/statusline-bridge.sh"
LAUNCH="$SCRIPT_DIR/../hooks/statusline-launch.sh"

setup() {
  setup_temp_dir
  export ACL_CONTEXT_DIR="$TEST_DIR/ctx"
  unset ACL_CONTEXT_WINDOW ACL_COMPACT_THRESHOLD_PCT
}
teardown() { teardown_temp_dir; }

# $1=used tokens (cache_read), $2=session id
_ralph_with_usage() {
  mkdir -p .claude
  cat > .claude/ralph-loop.local.md <<EOF
---
iteration: 3
max_iterations: 50
completion_promise: DONE
progress_file: .claude-progress.json
---

작업 프롬프트 본문
EOF
  cat > transcript.jsonl <<EOF
{"role":"assistant","message":{"content":[{"type":"text","text":"작업 중"}],"usage":{"input_tokens":32,"cache_read_input_tokens":$1,"cache_creation_input_tokens":5000}}}
EOF
  printf '{"session_id":"%s","transcript_path":"%s/transcript.jsonl"}' "$2" "$TEST_DIR" > hook-input.json
}

_run_hook() {
  run bash -c "cd '$TEST_DIR' && bash '$HOOK' < hook-input.json"
}

_bridge_file() {
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '{"session_id":"%s","context_window_size":%s}\n' "$1" "$2" > "$ACL_CONTEXT_DIR/$1.json"
}

_last_event() {
  jq -c 'select(.event == "context.usage")' .claude/acl-events.jsonl | tail -1
}

# ─── stop-hook 계측 ───

@test "usage: 브리지 없음 → 200K 기본 분모, 임계 이상이면 리마인더 + default 출처" {
  _ralph_with_usage 130000 "sess-a"
  _run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"컨텍스트 사용률 67%"* ]]
  [[ "$output" == *"창 출처: default"* ]]
  [[ "$output" == *"statusline-setup --apply"* ]]
  [[ "$output" == *"/compact 를 직접 실행할 수 없"* ]]
  ev=$(_last_event)
  [ "$(jq -r '.windowSource' <<<"$ev")" = "default" ]
  [ "$(jq -r '.window' <<<"$ev")" = "200000" ]
  [ "$(jq -r '.usedTokens' <<<"$ev")" = "135032" ]
  [ "$(jq -r '.reminder' <<<"$ev")" = "true" ]
}

@test "usage: 브리지 파일이 있으면 그 창 크기가 분모 (1M → 13%, 리마인더 없음)" {
  _ralph_with_usage 130000 "sess-b"
  _bridge_file "sess-b" 1000000
  _run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"컨텍스트 사용률"* ]]
  ev=$(_last_event)
  [ "$(jq -r '.windowSource' <<<"$ev")" = "bridge" ]
  [ "$(jq -r '.pct' <<<"$ev")" = "13" ]
  [ "$(jq -r '.reminder' <<<"$ev")" = "false" ]
}

@test "usage: 브리지가 없을 때 ACL_CONTEXT_WINDOW 가 분모 (env 출처)" {
  _ralph_with_usage 130000 "sess-c"
  ACL_CONTEXT_WINDOW=1000000 _run_hook
  [[ "$output" != *"컨텍스트 사용률"* ]]
  [ "$(jq -r '.windowSource' <<<"$(_last_event)")" = "env" ]
}

@test "usage: 브리지가 env 보다 우선한다 (실측 > 수동)" {
  _ralph_with_usage 130000 "sess-d"
  _bridge_file "sess-d" 200000
  ACL_CONTEXT_WINDOW=1000000 _run_hook
  [[ "$output" == *"컨텍스트 사용률 67%"* ]]
  [ "$(jq -r '.windowSource' <<<"$(_last_event)")" = "bridge" ]
}

@test "usage: ACL_COMPACT_THRESHOLD_PCT 로 임계 조정 (10 → 13%에서 리마인더)" {
  _ralph_with_usage 130000 "sess-e"
  _bridge_file "sess-e" 1000000
  ACL_COMPACT_THRESHOLD_PCT=10 _run_hook
  [[ "$output" == *"컨텍스트 사용률 13%"* ]]
  [[ "$output" != *"statusline-setup --apply"* ]]
  [ "$(jq -r '.threshold' <<<"$(_last_event)")" = "10" ]
}

@test "usage: 잘못된 임계(0, 101, 문자)는 60 으로 폴백" {
  _ralph_with_usage 130000 "sess-f"
  _bridge_file "sess-f" 1000000
  for bad in 0 101 abc; do
    ACL_COMPACT_THRESHOLD_PCT="$bad" _run_hook
    [ "$(jq -r '.threshold' <<<"$(_last_event)")" = "60" ]
  done
}

@test "usage: 브리지 파일의 창 크기가 비정상(0/문자)이면 env/기본으로 폴백" {
  _ralph_with_usage 130000 "sess-g"
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '{"session_id":"sess-g","context_window_size":"big"}\n' > "$ACL_CONTEXT_DIR/sess-g.json"
  _run_hook
  [ "$(jq -r '.windowSource' <<<"$(_last_event)")" = "default" ]
}

@test "usage: 세션 id 에 경로 문자가 있으면 브리지 파일을 찾지 않는다" {
  _ralph_with_usage 130000 "../sess-h"
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '{"context_window_size":1000000}\n' > "$ACL_CONTEXT_DIR/sess-h.json"
  _run_hook
  [ "$(jq -r '.windowSource' <<<"$(_last_event)")" = "default" ]
}

@test "usage: usage 가 없는 트랜스크립트는 이벤트도 리마인더도 없다 (기존 테스트 호환)" {
  _ralph_with_usage 130000 "sess-i"
  printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"작업 중"}]}}' > transcript.jsonl
  _run_hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"컨텍스트 사용률"* ]]
  [ ! -f .claude/acl-events.jsonl ] || [ -z "$(_last_event)" ]
}

@test "usage: 리마인더는 차단하지 않는다 (decision=block 루프 계속, iteration 증가)" {
  _ralph_with_usage 130000 "sess-j"
  _run_hook
  [ "$(jq -r '.decision' <<<"$output")" = "block" ]
  grep -q '^iteration: 4$' .claude/ralph-loop.local.md
}

# ─── statusline-bridge.sh ───

_sl_json() {
  printf '{"session_id":"%s","model":{"id":"claude-fable-5-1[1m]","display_name":"Fable 5.1"},"context_window":{"context_window_size":%s,"used_percentage":13.7,"total_input_tokens":500,"current_usage":{"input_tokens":32,"cache_read_input_tokens":86475,"cache_creation_input_tokens":5386}}}' "$1" "$2"
}

@test "bridge: 세션 파일을 기록하고 기본 상태줄을 출력한다" {
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-1 1000000)") | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ "$output" = "[Fable 5.1] ctx 13% / 1000K" ]
  [ -f "$ACL_CONTEXT_DIR/sl-1.json" ]
  [ "$(jq -r '.context_window_size' "$ACL_CONTEXT_DIR/sl-1.json")" = "1000000" ]
  [ "$(jq -r '.model' "$ACL_CONTEXT_DIR/sl-1.json")" = "claude-fable-5-1[1m]" ]
  [ "$(jq -r '.current_usage.cache_read_input_tokens' "$ACL_CONTEXT_DIR/sl-1.json")" = "86475" ]
  jq -e '.updated_at | length > 0' "$ACL_CONTEXT_DIR/sl-1.json" >/dev/null
}

@test "bridge: chain.json 이 있으면 원본 JSON 을 그 명령에 넘겨 출력을 위임한다" {
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '%s\n' '{"command":"jq -r \".model.display_name + \\\" via chain\\\"\""}' > "$ACL_CONTEXT_DIR/chain.json"
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-2 200000)") | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ "$output" = "Fable 5.1 via chain" ]
  [ -f "$ACL_CONTEXT_DIR/sl-2.json" ]
}

@test "bridge: chain 명령이 실패하면 기본 상태줄로 폴백하되 실패를 상태줄에 표시한다" {
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '%s\n' '{"command":"exit 3"}' > "$ACL_CONTEXT_DIR/chain.json"
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-3 200000)") | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ "$output" = "[Fable 5.1] ctx 13% / 200K (chain failed)" ]
}

@test "bridge: Windows 에서는 chain.cmd 를 cmd.exe 로 실행한다 — 역슬래시 경로·stdin 보존 (msys/cygwin 전용)" {
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) skip "cmd.exe 위임은 OSTYPE=msys/cygwin 에서만 동작" ;; esac
  command -v cmd.exe >/dev/null 2>&1 || skip "cmd.exe 없음"
  mkdir -p "$ACL_CONTEXT_DIR"
  # bash -c 로는 깨지는 명령: 따옴표 없는 역슬래시 네이티브 경로
  printf '%s\n' '{"command":"C:\\Windows\\System32\\findstr.exe Fable"}' > "$ACL_CONTEXT_DIR/chain.json"
  printf '@C:\\Windows\\System32\\findstr.exe Fable\r\n' > "$ACL_CONTEXT_DIR/chain.cmd"
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-w1 200000)") | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"display_name":"Fable 5.1"'* ]]
  # chain.cmd 가 실패하면 bash -c 로 재시도하지 않고 실패로 표시한다
  printf '@exit /b 3\r\n' > "$ACL_CONTEXT_DIR/chain.cmd"
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-w2 200000)") | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ "$output" = "[Fable 5.1] ctx 13% / 200K (chain failed)" ]
}

@test "bridge: 창 크기가 없거나 세션 id 가 비정상이면 파일을 만들지 않고 exit 0" {
  run bash -c "printf '%s' '{\"session_id\":\"sl-4\",\"model\":{\"display_name\":\"X\"}}' | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ ! -f "$ACL_CONTEXT_DIR/sl-4.json" ]
  run bash -c "printf '%s' '{\"session_id\":\"../evil\",\"context_window\":{\"context_window_size\":1000000}}' | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/evil.json" ]
  [ ! -e "$ACL_CONTEXT_DIR/../evil.json" ]
}

@test "bridge: 빈 stdin / 깨진 JSON 에도 exit 0 (빈 입력은 침묵하지 않고 진단줄)" {
  run bash -c "printf '' | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
  [ "$output" = "acl: no statusline input" ]
  run bash -c "printf 'not json' | bash '$BRIDGE'"
  [ "$status" -eq 0 ]
}

@test "bridge/launch: Windows 에서 coreutils 없는 PATH 로 spawn 돼도 자가 복구한다 (msys/cygwin 전용)" {
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) skip "Git Bash 전용 회귀 (PATH 자가 복구는 OSTYPE=msys/cygwin 에서만 동작)" ;; esac
  # 실측 재현: cmd.exe → run-hook.cmd → bash --noprofile --norc 에서는 /usr/bin 이 PATH 에 없어 dirname/cat/jq 를 못 찾았다.
  mkdir -p bin
  cp "$LAUNCH" bin/statusline-launch.sh
  cp "$BRIDGE" bin/statusline-bridge.sh
  printf '{"cacheDir":null,"pluginRoot":"%s/nowhere"}\n' "$TEST_DIR" > bin/source.json
  local jq_dir; jq_dir="$(dirname "$(command -v jq)")"
  run env -i PATH="/nonexistent:$jq_dir" HOME="$TEST_DIR" ACL_CONTEXT_DIR="$ACL_CONTEXT_DIR" \
    "$BASH" --noprofile --norc -c "printf '%s' '$(_sl_json path-1 1000000)' | '$BASH' --noprofile --norc '$TEST_DIR/bin/statusline-launch.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "[Fable 5.1] ctx 13% / 1000K" ]
  [ "$(jq -r '.context_window_size' "$ACL_CONTEXT_DIR/path-1.json")" = "1000000" ]
}

# ─── statusline-launch.sh ───

_fake_cache() {
  # $1=cache dir, 나머지=버전들. 각 버전에 자기 버전을 echo 하는 가짜 브리지
  local d="$1"; shift
  local v
  for v in "$@"; do
    mkdir -p "$d/$v/hooks"
    printf '#!/usr/bin/env bash\ncat >/dev/null; echo "bridge %s"\n' "$v" > "$d/$v/hooks/statusline-bridge.sh"
  done
}

@test "launch: 캐시에서 가장 높은 버전의 브리지를 고른다 (sort -V)" {
  mkdir -p bin cache/mp/acl
  cp "$LAUNCH" bin/statusline-launch.sh
  _fake_cache "$TEST_DIR/cache/mp/acl" 4.4.0 4.23.0 4.24.0 4.9.1
  printf '{"cacheDir":"%s","pluginRoot":"%s/nowhere"}\n' "$TEST_DIR/cache/mp/acl" "$TEST_DIR" > bin/source.json
  run bash -c "printf '{}' | bash '$TEST_DIR/bin/statusline-launch.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "bridge 4.24.0" ]
}

@test "launch: 캐시가 없으면 pluginRoot, 그것도 없으면 사본, 전부 없으면 안내줄" {
  mkdir -p bin root/hooks
  cp "$LAUNCH" bin/statusline-launch.sh
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo "bridge root"\n' > root/hooks/statusline-bridge.sh
  printf '{"cacheDir":null,"pluginRoot":"%s/root"}\n' "$TEST_DIR" > bin/source.json
  run bash -c "printf '{}' | bash '$TEST_DIR/bin/statusline-launch.sh'"
  [ "$output" = "bridge root" ]
  rm -rf root
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo "bridge copy"\n' > bin/statusline-bridge.sh
  run bash -c "printf '{}' | bash '$TEST_DIR/bin/statusline-launch.sh'"
  [ "$output" = "bridge copy" ]
  rm -f bin/statusline-bridge.sh
  run bash -c "printf '{}' | bash '$TEST_DIR/bin/statusline-launch.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"statusline bridge missing"* ]]
}

# ─── statusline-setup ───

@test "setup: 인자 없이 실행하면 스니펫만 출력하고 settings 를 건드리지 않는다" {
  run run_gate statusline-setup --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"statusLine"'* ]]
  [[ "$output" == *"statusline-launch.sh"* ]]
  [ ! -f "$TEST_DIR/settings.json" ]
  [ ! -d "$ACL_CONTEXT_DIR/bin" ]
}

@test "setup: --apply 가 런처를 설치하고 settings 에 병합한다 (기존 명령은 chain 에 보존, 백업 생성)" {
  printf '%s\n' '{"model":"opus","statusLine":{"type":"command","command":"echo old-line","padding":0}}' > settings.json
  run run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [ -f "$ACL_CONTEXT_DIR/bin/run-hook.cmd" ]
  [ -f "$ACL_CONTEXT_DIR/bin/statusline-bridge.sh" ]
  [ -f "$ACL_CONTEXT_DIR/bin/statusline-launch.sh" ]
  [ "$(jq -r '.pluginRoot' "$ACL_CONTEXT_DIR/bin/source.json")" != "" ]
  [ "$(jq -r '.installedFrom' "$ACL_CONTEXT_DIR/bin/source.json")" = "$(jq -r .version "$SCRIPT_DIR/../.claude-plugin/plugin.json")" ]
  cmd=$(jq -r '.statusLine.command' settings.json)
  [[ "$cmd" == *"statusline-launch.sh" ]]
  [[ "$cmd" == *"run-hook.cmd"* ]]
  [ "$(jq -r '.statusLine.type' settings.json)" = "command" ]
  [ "$(jq -r '.statusLine.padding' settings.json)" = "0" ]
  [ "$(jq -r '.model' settings.json)" = "opus" ]
  [ "$(jq -r '.command' "$ACL_CONTEXT_DIR/chain.json")" = "echo old-line" ]
  ls settings.json.bak-* >/dev/null
}

@test "setup: --apply 재실행은 멱등 (chain 을 덮어쓰지 않고 settings 는 그대로)" {
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo old-line"}}' > settings.json
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  first=$(cat settings.json)
  run run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already points to the launcher"* ]]
  [ "$(cat settings.json)" = "$first" ]
  [ "$(jq -r '.command' "$ACL_CONTEXT_DIR/chain.json")" = "echo old-line" ]
}

@test "setup: settings 가 없으면 새로 만든다 (chain 없음)" {
  run run_gate statusline-setup --apply --settings "$TEST_DIR/sub/settings.json"
  [ "$status" -eq 0 ]
  [ -f sub/settings.json ]
  [[ "$(jq -r '.statusLine.command' sub/settings.json)" == *"statusline-launch.sh" ]]
  [ ! -f "$ACL_CONTEXT_DIR/chain.json" ]
}

@test "setup: settings 가 JSON 객체가 아니면 거부한다" {
  printf 'not json' > settings.json
  run run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a JSON object"* ]]
  [ "$(cat settings.json)" = "not json" ]
}

@test "setup: --remove 가 이전 명령을 복원하고 bin/chain 을 지운다" {
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo old-line"}}' > settings.json
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  run run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' settings.json)" = "echo old-line" ]
  [ ! -f "$ACL_CONTEXT_DIR/chain.json" ]
  [ ! -d "$ACL_CONTEXT_DIR/bin" ]
}

@test "setup: --remove 는 설치 파일만 지운다 — source.json 없는 bin 은 남의 것이라 손대지 않는다" {
  printf '%s\n' '{"statusLine":{"type":"command","command":"bash x/statusline-launch.sh"}}' > settings.json
  mkdir -p "$ACL_CONTEXT_DIR/bin"
  printf 'keep\n' > "$ACL_CONTEXT_DIR/bin/user-file.sh"
  run run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no source.json"* ]]
  [ -f "$ACL_CONTEXT_DIR/bin/user-file.sh" ]
  # 우리가 설치한 디렉토리에 남의 파일이 섞여 있으면 우리 파일만 지우고 디렉토리는 남긴다
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo old-line"}}' > settings.json
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  printf 'keep\n' > "$ACL_CONTEXT_DIR/bin/user-file.sh"
  run run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept"* ]]
  [ -f "$ACL_CONTEXT_DIR/bin/user-file.sh" ]
  [ ! -f "$ACL_CONTEXT_DIR/bin/statusline-launch.sh" ]
  [ ! -f "$ACL_CONTEXT_DIR/bin/source.json" ]
}

@test "setup: statusLine 이 없어도 --remove 는 이전 설치의 bin/chain 고아를 정리한다" {
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo old-line"}}' > settings.json
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  printf '%s\n' '{}' > settings.json
  run run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no statusLine configured"* ]]
  [ ! -f "$ACL_CONTEXT_DIR/chain.json" ]
  [ ! -d "$ACL_CONTEXT_DIR/bin" ]
}

@test "setup: statusLine 이 비어 있는 상태로 --apply 하면 stale chain 을 지운다" {
  mkdir -p "$ACL_CONTEXT_DIR"
  printf '%s\n' '{"command":"echo stale"}' > "$ACL_CONTEXT_DIR/chain.json"
  printf '%s\n' '{}' > settings.json
  run run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [ ! -f "$ACL_CONTEXT_DIR/chain.json" ]
  [ ! -f "$ACL_CONTEXT_DIR/chain.cmd" ]
}

@test "setup: --apply 재실행은 사본을 temp → mv 로 교체한다 (임시 파일 잔존 없음, 내용 갱신)" {
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  printf 'old\n' > "$ACL_CONTEXT_DIR/bin/statusline-bridge.sh"
  run run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  cmp -s "$BRIDGE" "$ACL_CONTEXT_DIR/bin/statusline-bridge.sh"
  [ -z "$(ls -A "$ACL_CONTEXT_DIR/bin" | grep '\.tmp\.' || true)" ]
}

@test "setup: Windows 에서 --apply 는 chain.cmd 도 남기고 --remove 가 함께 지운다 (msys/cygwin 전용)" {
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) skip "chain.cmd 는 Windows 에서만 생성" ;; esac
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo old-line"}}' > settings.json
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  [ -f "$ACL_CONTEXT_DIR/chain.cmd" ]
  [ "$(tr -d '\r' < "$ACL_CONTEXT_DIR/chain.cmd")" = "@echo old-line" ]
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json sl-w3 200000)") | bash '$ACL_CONTEXT_DIR/bin/statusline-launch.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "old-line" ]
  run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json" >/dev/null
  [ ! -f "$ACL_CONTEXT_DIR/chain.cmd" ]
}

@test "setup: --remove 는 브리지가 아닌 statusLine 을 건드리지 않는다" {
  printf '%s\n' '{"statusLine":{"type":"command","command":"echo mine"}}' > settings.json
  run run_gate statusline-setup --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not the bridge"* ]]
  [ "$(jq -r '.statusLine.command' settings.json)" = "echo mine" ]
}

@test "setup: 미지 인자 / --apply --remove 동시 지정은 거부" {
  run run_gate statusline-setup --bogus
  [ "$status" -ne 0 ]
  run run_gate statusline-setup --apply --remove --settings "$TEST_DIR/settings.json"
  [ "$status" -ne 0 ]
}

@test "setup: 설치된 런처가 실제 브리지를 실행해 세션 파일을 만든다 (end-to-end)" {
  run_gate statusline-setup --apply --settings "$TEST_DIR/settings.json" >/dev/null
  run bash -c "$(printf '%q ' printf '%s' "$(_sl_json e2e-1 1000000)") | bash '$ACL_CONTEXT_DIR/bin/statusline-launch.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "[Fable 5.1] ctx 13% / 1000K" ]
  [ "$(jq -r '.context_window_size' "$ACL_CONTEXT_DIR/e2e-1.json")" = "1000000" ]
}
