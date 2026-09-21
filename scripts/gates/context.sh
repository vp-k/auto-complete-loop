# gates/context.sh — 컨텍스트 창 브리지 설정 (statusline-setup)
#
# 배경: 훅은 컨텍스트 창 크기(200K / 1M)를 알 수 없다. 그 값은 Claude Code statusLine 명령이 받는
# JSON 에만 실린다. hooks/statusline-bridge.sh 를 statusLine 으로 등록하면 세션별 파일에 창 크기가
# 기록되고, stop-hook 은 그 파일을 분모로 읽어 사용률(%)을 계산한다.
#
# 설치 형태: 마켓플레이스 설치본은 …/plugins/cache/<mp>/<plugin>/<version>/ 에 놓여 업데이트마다 경로가
# 바뀐다. 그래서 statusLine 에는 플러그인 경로가 아니라 <ctx_dir>/bin/ 의 런처를 등록하고, 런처가 매 호출마다
# 가장 높은 버전의 브리지를 찾아 실행한다 (hooks/statusline-launch.sh 참조). bin/ 에는 브리지 사본도 두어
# 플러그인이 지워져도 상태줄이 살아 있게 한다.
#
# 기존 statusLine 명령은 <ctx_dir>/chain.json 에 보존되고, 브리지가 매 호출마다 그 명령에 출력을 위임한다.

# 플랫폼별 경로 표기 (Windows: cmd.exe 가 여는 경로이므로 백슬래시)
_ctx_native_path() {
  local p="$1"
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$p" 2>/dev/null || printf '%s' "$p"
        return 0
      fi
      ;;
  esac
  printf '%s' "$p"
}

# 플러그인 루트가 마켓플레이스 캐시(…/cache/<mp>/<plugin>/<version>) 안이면 <version> 의 부모를 출력
_ctx_cache_dir_of() {
  local root="$1" parent grand
  parent="$(dirname "$root")"
  grand="$(dirname "$parent")"
  if [[ "$(basename "$grand")" != "cache" ]] && [[ "$(basename "$(dirname "$grand")")" == "cache" ]]; then
    printf '%s' "$parent"
    return 0
  fi
  return 1
}

# --apply 가 설치하는 파일 목록 (--remove 는 이 목록만 지운다 — 디렉토리 통째 삭제 금지)
_CTX_INSTALLED_FILES="run-hook.cmd statusline-bridge.sh statusline-launch.sh source.json"

# 설치 파일만 제거한다. source.json 이 없으면 우리가 만든 디렉토리가 아니므로 손대지 않는다.
# 우리 파일을 지운 뒤 다른 파일이 남아 있으면 디렉토리는 그대로 둔다 (남의 것을 지우지 않는다).
_ctx_uninstall_files() {
  local bin_dir="$1" chain_file="$2" f
  rm -f "$chain_file" "${chain_file%.json}.cmd" 2>/dev/null || true
  [[ -d "$bin_dir" ]] || return 0
  if [[ ! -f "$bin_dir/source.json" ]]; then
    echo "statusline-setup: $bin_dir has no source.json (not installed by statusline-setup) — left untouched"
    return 0
  fi
  for f in $_CTX_INSTALLED_FILES; do
    rm -f "$bin_dir/$f" 2>/dev/null || true
  done
  rm -f "$bin_dir"/.*.tmp.* 2>/dev/null || true
  if ! rmdir "$bin_dir" 2>/dev/null; then
    echo "statusline-setup: $bin_dir kept (contains files not installed by statusline-setup)"
  fi
  return 0
}

# Windows: 보존한 기존 statusLine 명령을 cmd.exe 가 그대로 실행할 수 있게 .cmd 로도 남긴다
# (브리지가 bash -c 대신 이 파일을 cmd.exe 로 실행 — 역슬래시 경로·cmd 내장 구문 보존). 다른 OS 에서는 만들지 않는다.
_ctx_write_chain_cmd() {
  local target="$1" command="$2"
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) rm -f "$target" 2>/dev/null || true; return 0 ;;
  esac
  local tmp="${target}.tmp.$$"
  if printf '@%s\r\n' "$command" > "$tmp" 2>/dev/null && mv -f "$tmp" "$target" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  die "statusline-setup: cannot write $target"
}

cmd_statusline_setup() {
  local apply=false remove=false settings=""
  while (($#)); do
    case "$1" in
      --apply) apply=true ;;
      --remove) remove=true ;;
      --settings) [[ -n "${2:-}" ]] || die "statusline-setup: --settings requires a path"; settings="$2"; shift ;;
      --settings=*) settings="${1#*=}" ;;
      *) die "statusline-setup: unknown argument: $1" ;;
    esac
    shift
  done
  require_jq
  $apply && $remove && die "statusline-setup: --apply and --remove are mutually exclusive"

  local plugin_root hooks_dir
  plugin_root="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)" || die "statusline-setup: plugin root not found"
  hooks_dir="$plugin_root/hooks"
  local f
  for f in run-hook.cmd statusline-bridge.sh statusline-launch.sh; do
    [[ -f "$hooks_dir/$f" ]] || die "statusline-setup: $hooks_dir/$f not found"
  done

  local config_dir="${CLAUDE_CONFIG_DIR:-${HOME:-.}/.claude}"
  [[ -n "$settings" ]] || settings="$config_dir/settings.json"
  local ctx_dir="${ACL_CONTEXT_DIR:-$config_dir/acl-context}"
  local bin_dir="$ctx_dir/bin"
  local chain_file="$ctx_dir/chain.json"
  local chain_cmd_file="$ctx_dir/chain.cmd"
  local cmd snippet
  cmd=$(printf '"%s" statusline-launch.sh' "$(_ctx_native_path "$bin_dir/run-hook.cmd")")
  snippet=$(jq -n --arg c "$cmd" '{statusLine: {type: "command", command: $c}}')

  if ! $apply && ! $remove; then
    echo "statusline-setup: --apply installs a version-independent launcher into $bin_dir and merges this into $settings:"
    echo "$snippet"
    echo "context files: $ctx_dir/<session_id>.json (read by stop-hook as the context-window denominator)"
    echo "threshold: ACL_COMPACT_THRESHOLD_PCT (default 60); manual window override: ACL_CONTEXT_WINDOW"
    return 0
  fi

  local existing="{}"
  if [[ -f "$settings" ]]; then
    existing=$(cat "$settings")
    printf '%s' "$existing" | jq -e 'type == "object"' >/dev/null 2>&1 \
      || die "statusline-setup: $settings is not a JSON object"
  fi
  local current
  current=$(printf '%s' "$existing" | jq -r '.statusLine.command // empty')
  local ts
  ts=$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null || date '+%Y%m%dT%H%M%S')

  if $remove; then
    if [[ -z "$current" ]]; then
      # settings 에 statusLine 이 없어도 이전 설치가 남긴 bin/chain 은 정리한다 (고아 방지)
      echo "statusline-setup: no statusLine configured in $settings"
      _ctx_uninstall_files "$bin_dir" "$chain_file"
      return 0
    fi
    [[ "$current" == *statusline-launch.sh* || "$current" == *statusline-bridge.sh* ]] \
      || { echo "statusline-setup: statusLine is not the bridge — leaving $settings untouched"; return 0; }
    local restored=""
    [[ -f "$chain_file" ]] && restored=$(jq -r '.command // empty' "$chain_file" 2>/dev/null || true)
    cp "$settings" "${settings}.bak-${ts}" 2>/dev/null || die "statusline-setup: backup failed"
    if [[ -n "$restored" ]]; then
      printf '%s' "$existing" | jq --arg c "$restored" \
        '.statusLine = ((if (.statusLine | type) == "object" then .statusLine else {} end) + {type: "command", command: $c})' \
        | write_json_atomic "$settings"
      echo "statusline-setup: bridge removed, previous command restored: $restored"
    else
      printf '%s' "$existing" | jq 'del(.statusLine)' | write_json_atomic "$settings"
      echo "statusline-setup: bridge removed (no previous command to restore)"
    fi
    _ctx_uninstall_files "$bin_dir" "$chain_file"
    echo "backup: ${settings}.bak-${ts}"
    return 0
  fi

  # --apply: 런처 + 브리지 사본 설치 (재실행 시 갱신 — 멱등)
  # 사본은 statusline 이 실행 중일 수 있으므로 제자리에서 덮어쓰지 않고 temp → mv 로 교체한다
  mkdir -p "$bin_dir" 2>/dev/null || die "statusline-setup: cannot create $bin_dir"
  local tmp
  for f in run-hook.cmd statusline-bridge.sh statusline-launch.sh; do
    tmp="$bin_dir/.$f.tmp.$$"
    cp "$hooks_dir/$f" "$tmp" || { rm -f "$tmp" 2>/dev/null; die "statusline-setup: copy of $f failed"; }
    chmod +x "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$bin_dir/$f" || { rm -f "$tmp" 2>/dev/null; die "statusline-setup: install of $f failed"; }
  done
  local cache_dir version
  cache_dir=$(_ctx_cache_dir_of "$plugin_root" || true)
  version=$(jq -r '.version // "unknown"' "$plugin_root/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)
  jq -n --arg root "$plugin_root" --arg cache "$cache_dir" --arg v "$version" --arg ts "$ts" \
    '{pluginRoot: $root, cacheDir: (if $cache == "" then null else $cache end), installedFrom: $v, installedAt: $ts}' \
    | write_json_atomic "$bin_dir/source.json"
  echo "statusline-setup: launcher installed in $bin_dir (source: $plugin_root, v$version)"

  if [[ "$current" == "$cmd" ]]; then
    echo "statusline-setup: statusLine already points to the launcher in $settings"
    return 0
  fi
  if [[ -n "$current" ]] && [[ "$current" != *statusline-launch.sh* ]] && [[ "$current" != *statusline-bridge.sh* ]]; then
    # 기존 statusline 명령 보존 → 브리지가 매 호출마다 여기에 출력을 위임한다
    jq -n --arg c "$current" --arg from "$settings" --arg ts "$ts" \
      '{command: $c, from: $from, savedAt: $ts}' | write_json_atomic "$chain_file"
    _ctx_write_chain_cmd "$chain_cmd_file" "$current"
    echo "statusline-setup: previous statusLine command preserved in $chain_file (bridge will chain to it)"
  elif [[ -z "$current" ]]; then
    # statusLine 이 비어 있으면 이전 설치가 남긴 chain 은 더 이상 유효하지 않다 (stale 위임 차단)
    rm -f "$chain_file" "$chain_cmd_file" 2>/dev/null || true
  fi
  mkdir -p "$(dirname "$settings")" 2>/dev/null || die "statusline-setup: cannot create $(dirname "$settings")"
  if [[ -f "$settings" ]]; then
    cp "$settings" "${settings}.bak-${ts}" 2>/dev/null || die "statusline-setup: backup failed"
    echo "backup: ${settings}.bak-${ts}"
  fi
  printf '%s' "$existing" | jq --arg c "$cmd" \
    '.statusLine = ((if (.statusLine | type) == "object" then .statusLine else {} end) + {type: "command", command: $c})' \
    | write_json_atomic "$settings"
  echo "statusline-setup: statusLine set in $settings"
  echo "$snippet"
  echo "context files: $ctx_dir/<session_id>.json — takes effect on the next Claude Code session"
  return 0
}
