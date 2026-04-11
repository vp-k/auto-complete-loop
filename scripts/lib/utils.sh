# lib/utils.sh — 공통 유틸리티 함수

VERIFICATION_FILE=".claude-verification.json"
CONFIG_FILE=".claude-auto-config.json"

# ─── 설정 파일 로드 ───

# .claude-auto-config.json에서 값을 읽는다. 파일 없으면 기본값 반환.
# Usage: config_get <jq_path> <default_value>
config_get() {
  local path="$1" default="$2"
  if [[ -f "$CONFIG_FILE" ]]; then
    # 설정 파일 JSON 유효성 사전 검증
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
      echo "WARNING: $CONFIG_FILE is not valid JSON — using default for $path" >&2
      echo "$default"
      return 0
    fi
    local val
    val=$(jq -r "$path // empty" "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  fi
  echo "$default"
}

# ─── 유틸리티 ───

die() { echo "ERROR: $*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"; }

# 안전한 jq 인플레이스 업데이트 (temp 파일 자동 정리 + 무결성 검증)
jq_inplace() {
  local file="$1"; shift
  local tmp
  tmp=$(mktemp)
  if jq "$@" "$file" > "$tmp"; then
    # 출력이 유효한 JSON인지 검증 (손상 방지)
    if ! jq empty "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      die "jq produced invalid JSON for $file"
    fi
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    die "jq update failed for $file"
  fi
}
