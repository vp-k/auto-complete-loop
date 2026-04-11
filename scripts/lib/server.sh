# lib/server.sh — 서버 시작/중지/헬스체크 유틸리티

# _detect_start_cmd: package.json에서 서버 시작 명령어를 감지
# 출력: 감지된 명령어 (없으면 빈 문자열)
_detect_start_cmd() {
  if [[ -f "package.json" ]]; then
    local pm="npm"
    [[ -f "pnpm-lock.yaml" ]] && pm="pnpm"
    [[ -f "yarn.lock" ]] && pm="yarn"
    [[ -f "bun.lockb" ]] && pm="bun"

    if jq -e '.scripts.start' package.json >/dev/null 2>&1; then
      echo "$pm run start"
    elif jq -e '.scripts.dev' package.json >/dev/null 2>&1; then
      echo "$pm run dev"
    elif jq -e '.scripts.preview' package.json >/dev/null 2>&1; then
      echo "$pm run preview"
    fi
  fi
}

# _start_and_wait_server: 서버를 백그라운드로 시작하고 응답 대기
# 인수: $1=start_cmd, $2=port, $3=timeout, $4=log_prefix
# 출력: SERVER_PID, SERVER_LOG 변수 설정
# 반환: 0=성공, 1=실패
SERVER_PID=""
SERVER_LOG=""
_start_and_wait_server() {
  local start_cmd="$1" port="$2" timeout="${3:-15}" log_prefix="${4:-server}"

  SERVER_LOG=$(mktemp "/tmp/${log_prefix}-XXXXXX.log")
  local -a cmd_parts
  read -ra cmd_parts <<< "$start_cmd"
  "${cmd_parts[@]}" > "$SERVER_LOG" 2>&1 &
  SERVER_PID=$!

  trap '_cleanup_server; trap - EXIT INT TERM' EXIT INT TERM

  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    sleep 1
    elapsed=$((elapsed + 1))

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "[${log_prefix}] Server process exited prematurely"
      return 1
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null || echo "000")
    if [[ "$http_code" != "000" ]] && [[ "$http_code" =~ ^[23] ]]; then
      echo "[${log_prefix}] Got HTTP $http_code after ${elapsed}s"
      return 0
    fi
  done

  return 1
}

# _cleanup_server: 서버 프로세스 및 로그 파일 정리
_cleanup_server() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    pkill -P "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
  if [[ -n "$SERVER_LOG" ]] && [[ -f "$SERVER_LOG" ]]; then
    rm -f "$SERVER_LOG"
    SERVER_LOG=""
  fi
}
