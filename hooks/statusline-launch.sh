#!/usr/bin/env bash
# statusline-launch.sh — statusline 브리지 런처 (statusline-setup --apply 가 <ctx_dir>/bin 에 복사해 등록한다)
#
# 왜 런처가 필요한가:
#   마켓플레이스 설치본은 ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/ 에 놓이고,
#   플러그인을 업데이트하면 <version> 디렉토리가 바뀐다. settings.json 의 statusLine 에 그 절대 경로를
#   박아 두면 업데이트마다 statusline 이 깨진다. 런처는 매 호출마다 실행할 브리지를 다시 찾는다:
#     1. source.json 의 cacheDir 아래에서 가장 높은 버전 디렉토리의 hooks/statusline-bridge.sh
#     2. source.json 의 pluginRoot/hooks/statusline-bridge.sh (개발 체크아웃 등 비-캐시 설치)
#     3. 같은 디렉토리에 복사된 statusline-bridge.sh (폴백 — 플러그인이 지워져도 상태줄은 산다)
#   stdin(statusline JSON)은 그대로 브리지에 넘긴다. 실패해도 exit 0.

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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/source.json"
TARGET=""

_pick_newest_cached() {
  # $1 = cacheDir (…/cache/<marketplace>/<plugin>) — 버전 디렉토리 중 브리지가 있는 가장 높은 버전
  local d="$1" v
  [[ -d "$d" ]] || return 1
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    if [[ -f "$d/$v/hooks/statusline-bridge.sh" ]]; then
      printf '%s' "$d/$v/hooks/statusline-bridge.sh"
      return 0
    fi
  done < <(ls -1 "$d" 2>/dev/null | sort -V -r)
  return 1
}

if [[ -f "$SRC" ]] && command -v jq >/dev/null 2>&1; then
  _cache=$(jq -r '.cacheDir // empty' "$SRC" 2>/dev/null || true)
  _root=$(jq -r '.pluginRoot // empty' "$SRC" 2>/dev/null || true)
  if [[ -n "$_cache" ]]; then
    TARGET=$(_pick_newest_cached "$_cache" || true)
  fi
  if [[ -z "$TARGET" ]] && [[ -n "$_root" ]] && [[ -f "$_root/hooks/statusline-bridge.sh" ]]; then
    TARGET="$_root/hooks/statusline-bridge.sh"
  fi
fi
if [[ -z "$TARGET" ]] && [[ -f "$HERE/statusline-bridge.sh" ]]; then
  TARGET="$HERE/statusline-bridge.sh"
fi

if [[ -n "$TARGET" ]]; then
  exec bash --noprofile --norc "$TARGET"
fi
# 브리지를 전혀 찾지 못함 — 상태줄만 정직하게 표시
cat >/dev/null 2>&1 || true
printf '%s\n' "acl: statusline bridge missing (re-run: shared-gate.sh statusline-setup --apply)"
exit 0
