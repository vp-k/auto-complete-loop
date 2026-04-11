# lib/progress.sh — Progress 파일 관리, 스키마 마이그레이션, 게이트 이력

# ─── schemaVersion 마이그레이션 (idempotent) ───

# full-auto progress 파일을 v1 → v2로 마이그레이션
# 여러 번 실행해도 안전 (idempotent)
migrate_schema_v2() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # schemaVersion이 이미 2 이상이면 스킵
  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 2 ]] && return 0

  # full-auto progress 파일인지 확인 (steps 배열에 phase_0가 있는지)
  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 2..."
  jq_inplace "$file" '
    .schemaVersion = 2
    | .phases.phase_0.outputs.assumptions //= []
    | .phases.phase_0.outputs.nsm //= null
    | .phases.phase_0.outputs.successCriteria //= []
    | .phases.phase_0.outputs.premortem //= {"tigers":[],"paperTigers":[],"elephants":[]}
    | .phases.phase_0.outputs.projectSize //= null
    | .phases.phase_0.outputs.stakeholders //= null
    | .dod.assumptions_documented //= {"checked":false,"evidence":null}
    | .dod.premortem_done //= {"checked":false,"evidence":null}
    | .dod.launch_ready //= {"checked":false,"evidence":null}
  '
  echo "OK: $file migrated to schemaVersion 2"
}

migrate_schema_v3() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # schemaVersion이 이미 3 이상이면 스킵
  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 3 ]] && return 0

  # full-auto progress 파일인지 확인
  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 3 (E2E support)..."
  jq_inplace "$file" '
    .schemaVersion = 3
    | .phases.phase_2.e2e //= {"applicable":null,"projectType":null,"dataStrategy":null,"e2eFramework":null,"fallbackReason":null,"scenarios":[]}
  '
  echo "OK: $file migrated to schemaVersion 3"
}

migrate_schema_v4() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 4 ]] && return 0

  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 4 (projectScope support)..."
  jq_inplace "$file" '
    .schemaVersion = 4
    | .phases.phase_0.outputs.projectScope //= null
  '
  echo "OK: $file migrated to schemaVersion 4"
}

migrate_schema_v5() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 5 ]] && return 0

  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 5 (gateHistory + implementation quality gates)..."
  jq_inplace "$file" '
    .schemaVersion = 5
    | .gateHistory //= []
  '
  echo "OK: $file migrated to schemaVersion 5"
}

migrate_schema_v6() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 6 ]] && return 0

  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 6 (implementationOrder + config support)..."
  jq_inplace "$file" '
    .schemaVersion = 6
    | .phases.phase_0.outputs.implementationOrder //= []
  '
  echo "OK: $file migrated to schemaVersion 6"
}

migrate_schema_v7() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local current_ver
  current_ver=$(jq '.schemaVersion // 1' "$file" 2>/dev/null || echo "1")
  [[ "$current_ver" -ge 7 ]] && return 0

  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$file" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || return 0

  echo "Migrating $file to schemaVersion 7 (conditionalGoItems + phase timestamps)..."
  jq_inplace "$file" '
    .schemaVersion = 7
    | .conditionalGoItems //= []
  '
  echo "OK: $file migrated to schemaVersion 7"
}

# Gate 실행 이력을 progress 파일에 추가
# Usage: append_gate_history <gate_name> <result> [details_json]
append_gate_history() {
  local gate="$1" result="$2" details="${3:-"{}"}"
  if [[ -z "$PROGRESS_FILE" ]] || [[ ! -f "$PROGRESS_FILE" ]]; then
    return 0
  fi

  # full-auto progress인지 확인
  local has_steps
  has_steps=$(jq 'has("steps")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  [[ "$has_steps" == "true" ]] || return 0

  local current_phase ts
  current_phase=$(jq -r '.currentPhase // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
  ts=$(timestamp)

  # gateHistory 초기화 + 항목 추가를 단일 jq 호출로 처리 (원자성 보장)
  jq_inplace "$PROGRESS_FILE" \
    --arg g "$gate" --arg r "$result" --arg p "$current_phase" --arg t "$ts" --argjson d "$details" '
    .gateHistory = (((.gateHistory // []) + [{"gate":$g,"phase":$p,"result":$r,"ts":$t,"details":$d}])[-100:])
  '

  # 동일 gate + 동일 phase에서 3회 연속 fail 감지
  local consecutive_fails
  consecutive_fails=$(jq --arg g "$gate" --arg p "$current_phase" '
    [.gateHistory | to_entries | reverse | .[] |
     select(.value.gate == $g and .value.phase == $p)] |
    [limit(3; .[])] |
    if length == 3 and (map(.value.result) | all(. == "fail")) then true else false end
  ' "$PROGRESS_FILE" 2>/dev/null || echo "false")

  if [[ "$consecutive_fails" == "true" ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  ⚠ CIRCULAR FAILURE DETECTED                               ║"
    echo "║  Gate: $gate"
    echo "║  Phase: $current_phase — 3 consecutive failures"
    echo "║                                                            ║"
    echo "║  ACTION REQUIRED:                                          ║"
    echo "║  1. Stop retrying the same approach                        ║"
    echo "║  2. Escalate to L3 (different approach)                    ║"
    echo "║  3. If L3 also fails, use 'checkpoint suggest-rollback'    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
  fi
}

# Progress 파일 자동 탐지
detect_progress_file() {
  for f in .claude-full-auto-progress.json .claude-full-auto-teams-progress.json \
           .claude-progress.json \
           .claude-plan-progress.json .claude-polish-progress.json \
           .claude-review-loop-progress.json .claude-e2e-progress.json \
           .claude-doc-check-progress.json; do
    [[ -f "$f" ]] && echo "$f" && return 0
  done
  return 1
}

# --progress-file 인수 파싱 (글로벌)
PROGRESS_FILE=""
parse_progress_file_arg() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --progress-file)
        PROGRESS_FILE="${2:?--progress-file requires a path}"
        # 경로 검증: 절대경로/.. 차단, allowlist 패턴
        if [[ "$PROGRESS_FILE" == /* ]]; then
          die "--progress-file must be a relative path, got '$PROGRESS_FILE'"
        fi
        if [[ "$PROGRESS_FILE" == *..* ]]; then
          die "--progress-file must not contain '..', got '$PROGRESS_FILE'"
        fi
        if [[ ! "$PROGRESS_FILE" =~ ^\.claude-.*progress.*\.json$ ]]; then
          die "--progress-file must match pattern '.claude-*progress*.json', got '$PROGRESS_FILE'"
        fi
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  # PROGRESS_FILE이 설정되지 않았으면 자동 탐지
  if [[ -z "$PROGRESS_FILE" ]]; then
    PROGRESS_FILE=$(detect_progress_file) || true
  fi
  # 나머지 인수를 REMAINING_ARGS에 저장
  REMAINING_ARGS=("${args[@]+"${args[@]}"}")
}

require_progress() {
  [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]] || die "Progress file not found. Specify --progress-file or run 'init' first."
}
