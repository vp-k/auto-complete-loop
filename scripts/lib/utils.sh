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

# ─── verification.json 기록 헬퍼 ───
# 게이트 결과를 .claude-verification.json에 병합 기록한다 (stop-hook이 읽는 유일한 하드락 증거).
# 파일이 없으면 생성. jq가 없으면 경고 후 무시 (게이트 자체 exit code 의미는 유지).

# 최상위 키 기록
# Usage: record_verification <key> <json_object>
record_verification() {
  local key="$1" json="$2"
  if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found — cannot record '$key' to $VERIFICATION_FILE" >&2
    return 0
  fi
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --arg k "$key" --argjson v "$json" '.[$k] = $v'
  else
    jq -n --arg k "$key" --argjson v "$json" '{($k): $v}' | write_json_atomic "$VERIFICATION_FILE"
  fi
}

# qualityDimensions 하위 키 기록 (stop-hook이 .qualityDimensions.<key>를 읽는 게이트용 — layerCoverage 등)
# Usage: record_verification_qd <key> <json_object>
record_verification_qd() {
  local key="$1" json="$2"
  if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found — cannot record 'qualityDimensions.$key' to $VERIFICATION_FILE" >&2
    return 0
  fi
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --arg k "$key" --argjson v "$json" \
      '.qualityDimensions = ((.qualityDimensions // {}) + {($k): $v})'
  else
    jq -n --arg k "$key" --argjson v "$json" '{"qualityDimensions": {($k): $v}}' | write_json_atomic "$VERIFICATION_FILE"
  fi
}

# ─── 원자적 JSON 파일 쓰기 ───
# `jq -n ... > "$FILE"` 직접 리다이렉트는 jq 실패/중단 시 파일을 truncate로 파괴한다.
# tmp에 먼저 쓰고 유효성 검증 후 mv로 교체 — 실패 시 기존 파일 무손상.
# Usage: write_json_atomic <file> [json_string]   (json 인수 생략 시 stdin에서 읽음)
write_json_atomic() {
  local file="${1:?write_json_atomic: file argument required}"
  local json="${2:-}"
  local tmp
  tmp=$(mktemp)
  if [[ -n "$json" ]]; then
    printf '%s\n' "$json" > "$tmp"
  else
    cat > "$tmp"
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    die "write_json_atomic: refusing to write empty content to $file"
  fi
  if ! jq empty "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "write_json_atomic: refusing to write invalid JSON to $file"
  fi
  mv "$tmp" "$file"
}

# 안전한 jq 인플레이스 업데이트 (temp 파일 자동 정리 + 무결성 검증 + self-heal + 베스트에포트 락)
jq_inplace() {
  local file="$1"; shift

  # ── 베스트에포트 스핀락 (mkdir 기반 — flock은 Git Bash에 없을 수 있음) ──
  # 같은 파일 대상 동시 업데이트로 인한 lost-update 완화. 최대 2초 대기 후 경고하고 진행.
  local _ji_lockdir="${file}.lock.d" _ji_locked=false _ji_i
  for ((_ji_i = 0; _ji_i < 20; _ji_i++)); do
    if mkdir "$_ji_lockdir" 2>/dev/null; then
      _ji_locked=true
      break
    fi
    sleep 0.1
  done
  if [[ "$_ji_locked" != "true" ]]; then
    echo "WARNING: jq_inplace: lock busy for $file (waited 2s) — proceeding without lock" >&2
  fi
  # 락 해제 헬퍼 (die 경로 포함 모든 종료 지점에서 호출)
  _ji_unlock() { [[ "$_ji_locked" == "true" ]] && rmdir "$_ji_lockdir" 2>/dev/null; return 0; }

  # ── self-heal: 대상 파일이 존재하는데 유효 JSON이 아니면(빈 파일 포함) 백업 후 {}로 초기화 ──
  # 무음 소실 방지: 이전에는 jq가 즉시 실패해 게이트 기록이 통째로 사라졌다.
  if [[ -f "$file" ]] && ! jq -e type "$file" >/dev/null 2>&1; then
    local _ji_backup
    _ji_backup="${file}.corrupt.$(date +%s 2>/dev/null || echo 0)"
    cp "$file" "$_ji_backup" 2>/dev/null || true
    echo "WARNING: jq_inplace: $file is not valid JSON — backed up to $_ji_backup and reset to {}" >&2
    printf '{}\n' > "$file"
  fi

  local tmp
  tmp=$(mktemp)
  if jq "$@" "$file" > "$tmp"; then
    # 출력이 비어 있으면 die (mv 시 대상 파일이 빈 파일로 파괴되는 것 방지)
    if [[ ! -s "$tmp" ]]; then
      rm -f "$tmp"
      _ji_unlock
      die "jq produced empty output for $file"
    fi
    # 출력이 유효한 JSON인지 검증 (손상 방지)
    if ! jq empty "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      _ji_unlock
      die "jq produced invalid JSON for $file"
    fi
    mv "$tmp" "$file"
    _ji_unlock
  else
    rm -f "$tmp"
    _ji_unlock
    die "jq update failed for $file"
  fi
}
