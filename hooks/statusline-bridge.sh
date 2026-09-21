#!/usr/bin/env bash
# statusline-bridge.sh — Claude Code statusLine 명령으로 등록해 컨텍스트 창 정보를 세션별 파일에 남긴다.
#
# 왜 필요한가:
#   훅(Stop 등)의 stdin JSON에는 컨텍스트 창 크기(200K / 1M)가 없다. 그 값은 statusLine 명령이
#   받는 JSON(context_window.context_window_size)에만 실린다. 이 스크립트가 다리 역할을 한다.
#
# 동작 (모두 best-effort, 어떤 실패에도 exit 0 — statusline이 깨지면 사용자 화면이 깨진다):
#   1. stdin JSON → <ctx_dir>/<session_id>.json 원자적 기록
#      ctx_dir = $ACL_CONTEXT_DIR | $CLAUDE_CONFIG_DIR/acl-context | ~/.claude/acl-context
#   2. <ctx_dir>/chain.json 에 기존 statusline 명령이 등록돼 있으면 같은 JSON을 그대로 넘겨 출력 위임
#      (statusline-setup --apply 가 기존 명령을 여기에 보존한다; Windows 는 chain.cmd 를 cmd.exe 로 실행)
#   3. 없으면 최소 상태줄 출력: [모델] ctx 45% / 200K  (체인이 실패했으면 " (chain failed)" 를 덧붙인다)
#
# stop-hook.sh 는 <ctx_dir>/<session_id>.json 의 context_window_size 를 분모로 읽는다.
# 이 파일이 없으면 stop-hook 은 ACL_CONTEXT_WINDOW → 200000 순으로 폴백한다.

set -uo pipefail

# Windows: statusLine 명령은 hooks 와 달리 Git Bash 의 /usr/bin 이 PATH 에 없는 셸에서 spawn 될 수 있다.
# (실측: PowerShell → run-hook.cmd → bash --noprofile --norc 에서 dirname/jq 미발견). 실행 중인 bash 의
# 디렉토리를 PATH 앞에 붙여 coreutils 를 되찾는다. 외부 명령을 쓰기 전에 와야 하므로 여기서 한다.
case "${OSTYPE:-}" in
  msys*|cygwin*)
    _bash_dir="${BASH%/*}"
    [[ -n "$_bash_dir" && -d "$_bash_dir" ]] && export PATH="${_bash_dir}:${PATH:-}"
    ;;
esac

INPUT=$(cat 2>/dev/null || true)
CTX_DIR="${ACL_CONTEXT_DIR:-${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}/acl-context}"

# ─── 2. 체인 위임 ───
# 기존 명령에 원본 JSON을 그대로 넘긴다. 성공(exit 0)이면 0, 실패면 1, 체인이 없으면 2.
#
# Windows: Claude Code 는 statusLine 명령을 cmd.exe 로 띄운다(run-hook.cmd 가 존재하는 이유). 그 명령을
# 여기서 `bash -c` 로 돌리면 역슬래시 경로·cmd 내장 구문이 깨진다. 그래서 statusline-setup --apply 가
# 같은 명령을 <ctx_dir>/chain.cmd 로도 남기고, msys/cygwin 에서는 그 파일을 cmd.exe 로 실행한다
# (부작용 있는 명령을 두 번 돌리지 않도록 cmd.exe 경로가 실패해도 bash -c 로 재시도하지 않는다).
_run_chain() {
  local chain_file="$CTX_DIR/chain.json" chain_cmd="$CTX_DIR/chain.cmd" cmd="" native=""
  if [[ -f "$chain_file" ]] && command -v jq >/dev/null 2>&1; then
    cmd=$(jq -r '.command // empty' "$chain_file" 2>/dev/null || true)
  fi
  [[ -n "$cmd" ]] || return 2
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      if [[ -f "$chain_cmd" ]] && command -v cmd.exe >/dev/null 2>&1; then
        native=$(cygpath -w "$chain_cmd" 2>/dev/null || printf '%s' "$chain_cmd")
        if printf '%s' "$INPUT" | MSYS_NO_PATHCONV=1 cmd.exe /d /c "$native" 2>/dev/null; then
          return 0
        fi
        return 1
      fi
      ;;
  esac
  if printf '%s' "$INPUT" | bash -c "$cmd" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ─── 3. 기본 상태줄 ───
_emit_status() {
  local chain_rc=2 suffix=""
  _run_chain; chain_rc=$?
  [[ "$chain_rc" -eq 0 ]] && return 0
  # 체인이 실패하면 기본 상태줄로 폴백하되, 조용히 삼키지 않고 상태줄에 표시한다 (설정 결함 진단용)
  [[ "$chain_rc" -eq 1 ]] && suffix=" (chain failed)"
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "acl: jq missing${suffix}"
    return 0
  fi
  # jq 는 빈 입력에 아무것도 출력하지 않는다 — 침묵 대신 원인을 남긴다 (stdin 이 안 넘어온 배선 진단용)
  if [[ -z "$INPUT" ]]; then
    printf '%s\n' "acl: no statusline input${suffix}"
    return 0
  fi
  printf '%s' "$INPUT" | jq -r --arg suffix "$suffix" '
    def k: if . == null then "?" else ((. / 1000) | floor | tostring) + "K" end;
    "[" + (.model.display_name // .model.id // "?") + "] ctx "
      + ((.context_window.used_percentage // 0) | floor | tostring) + "% / "
      + ((.context_window.context_window_size // null) | k) + $suffix
  ' 2>/dev/null || printf '%s\n' "acl: statusline parse failed${suffix}"
  return 0
}

# jq 없으면 기록 불가 — 상태줄만 출력하고 끝
if ! command -v jq >/dev/null 2>&1 || [[ -z "$INPUT" ]]; then
  _emit_status
  exit 0
fi

# ─── 1. 세션별 컨텍스트 파일 기록 ───
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
# 경로 조작 방지: 세션 id 는 영숫자·-·_ 만 허용
if [[ -n "$SESSION_ID" ]] && [[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
  RECORD=$(printf '%s' "$INPUT" | jq -c \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')" '
    {
      session_id: .session_id,
      model: (.model.id // null),
      model_name: (.model.display_name // null),
      context_window_size: (.context_window.context_window_size // null),
      used_percentage: (.context_window.used_percentage // null),
      total_input_tokens: (.context_window.total_input_tokens // null),
      current_usage: (.context_window.current_usage // null),
      updated_at: $ts
    }
    | select((.context_window_size | type) == "number" and .context_window_size > 0)
  ' 2>/dev/null || true)
  if [[ -n "$RECORD" ]]; then
    if mkdir -p "$CTX_DIR" 2>/dev/null; then
      _target="$CTX_DIR/${SESSION_ID}.json"
      # 원자적 쓰기: 같은 디렉토리에 temp → mv (stop-hook 이 절반 쓰인 파일을 읽지 않도록)
      _tmp=$(mktemp "${_target}.XXXXXX" 2>/dev/null || true)
      if [[ -n "$_tmp" ]]; then
        if printf '%s\n' "$RECORD" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$_target" 2>/dev/null; then
          :
        else
          rm -f "$_tmp" 2>/dev/null || true
        fi
      fi
      # 오래된 세션 파일 정리 (7일). 매 호출마다 돌리지 않도록 확률적으로 실행.
      if (( RANDOM % 50 == 0 )); then
        find "$CTX_DIR" -maxdepth 1 -name '*.json' ! -name 'chain.json' -mtime +7 -delete 2>/dev/null || true
      fi
    fi
  fi
fi

_emit_status
exit 0
