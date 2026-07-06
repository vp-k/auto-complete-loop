# gates/state.sh — 상태 조회/단계 전이/복구/handoff/skip-phases/DoD 키 관리 + 소형 유틸(check-tools)

# ─── status: 현재 상태 요약 출력 ───

cmd_status() {
  require_jq
  require_progress

  # schemaVersion 마이그레이션 트리거
  migrate_schema_v2 "$PROGRESS_FILE"
  migrate_schema_v3 "$PROGRESS_FILE"
  migrate_schema_v4 "$PROGRESS_FILE"
  migrate_schema_v5 "$PROGRESS_FILE"
  migrate_schema_v6 "$PROGRESS_FILE"
  migrate_schema_v7 "$PROGRESS_FILE"

  echo "=== Progress Status ($PROGRESS_FILE) ==="

  # steps 배열이 있는 경우
  local has_steps
  has_steps=$(jq 'has("steps")' "$PROGRESS_FILE")
  if [[ "$has_steps" == "true" ]]; then
    # 현재 단계 (currentPhase 또는 currentStep 사용)
    local current
    current=$(jq -r '.currentPhase // .currentStep // "unknown"' "$PROGRESS_FILE")
    echo "Current: $current"

    # 완료된 단계
    local completed
    completed=$(jq -r '[.steps[] | select(.status == "completed") | (.label // .name)] | join(", ")' "$PROGRESS_FILE")
    [[ -n "$completed" ]] && echo "Completed: $completed"

    # 진행 중인 단계
    local in_progress
    in_progress=$(jq -r '[.steps[] | select(.status == "in_progress") | (.label // .name)] | join(", ")' "$PROGRESS_FILE")
    [[ -n "$in_progress" ]] && echo "In Progress: $in_progress"

    # 대기 중인 단계
    local pending_count
    pending_count=$(jq '[.steps[] | select(.status == "pending")] | length' "$PROGRESS_FILE")
    echo "Pending: $pending_count steps"

    # Phase 소요 시간 (타임스탬프가 있는 경우)
    local timing_info
    timing_info=$(jq -r '
      [.steps[] | select(.startedAt != null and .completedAt != null) |
       "\(.label // .name): \(.startedAt) → \(.completedAt)"] | join("\n")
    ' "$PROGRESS_FILE" 2>/dev/null || true)
    if [[ -n "$timing_info" ]]; then
      echo "Phase Timing:"
      echo "$timing_info" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi

  # documents 배열이 있는 경우
  local has_docs
  has_docs=$(jq 'has("documents")' "$PROGRESS_FILE")
  if [[ "$has_docs" == "true" ]]; then
    local total_docs done_docs cur_doc
    total_docs=$(jq '.documents | length' "$PROGRESS_FILE")
    done_docs=$(jq '[.documents[] | select(.status == "completed")] | length' "$PROGRESS_FILE")
    cur_doc=$(jq -r '.currentDocument // "none"' "$PROGRESS_FILE")
    echo "Documents: $done_docs / $total_docs completed"
    echo "Current Document: $cur_doc"
  fi

  # DoD 상태
  local has_dod
  has_dod=$(jq 'has("dod")' "$PROGRESS_FILE")
  if [[ "$has_dod" == "true" ]]; then
    local dod_total dod_checked
    dod_total=$(jq '.dod | to_entries | length' "$PROGRESS_FILE")
    dod_checked=$(jq '[.dod | to_entries[].value | select(.checked == true)] | length' "$PROGRESS_FILE")
    echo "DoD: $dod_checked / $dod_total checked"
  fi

  # 에스컬레이션 상태 (errorHistory가 있는 경우)
  local has_error_history
  has_error_history=$(jq 'has("errorHistory")' "$PROGRESS_FILE")
  if [[ "$has_error_history" == "true" ]]; then
    local esc_level esc_count esc_budget
    esc_level=$(jq -r '.errorHistory.escalationLevel // "N/A"' "$PROGRESS_FILE")
    esc_count=$(jq '.errorHistory.currentError.count // 0' "$PROGRESS_FILE")
    esc_budget=$(jq '.errorHistory.escalationBudget // 0' "$PROGRESS_FILE")
    if [[ "$esc_level" != "N/A" ]] && [[ "$esc_count" -gt 0 ]]; then
      echo "Escalation: $esc_level ($esc_count/$esc_budget)"
    fi

    # 최근 에스컬레이션 로그 3개
    local recent_log
    recent_log=$(jq -r '.errorHistory.escalationLog // [] | .[-3:] | .[] | "\(.level) #\(.attempt): \(.action // "N/A") → \(.result)"' "$PROGRESS_FILE" 2>/dev/null || true)
    if [[ -n "$recent_log" ]]; then
      echo "Recent Escalation Log:"
      echo "$recent_log" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi

  # Conditional GO Items (미해결 조건)
  local has_cond_items
  has_cond_items=$(jq 'if .conditionalGoItems then ([.conditionalGoItems[] | select(.resolvedAt == null)] | length > 0) else false end' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  if [[ "$has_cond_items" == "true" ]]; then
    echo "Pending Conditional GO:"
    jq -r '.conditionalGoItems[] | select(.resolvedAt == null) | "  [\(.fromPhase)→\(.targetPhase)] \(.condition)"' "$PROGRESS_FILE" 2>/dev/null
  fi

  # Scope Reductions (있는 경우)
  local has_scope_reductions
  has_scope_reductions=$(jq 'if .phases.phase_2.scopeReductions then (.phases.phase_2.scopeReductions | length > 0) else false end' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  if [[ "$has_scope_reductions" == "true" ]]; then
    local reduction_count
    reduction_count=$(jq '.phases.phase_2.scopeReductions | length' "$PROGRESS_FILE")
    echo "Scope Reductions: $reduction_count"
  fi

  # Handoff 요약
  local next_steps
  next_steps=$(jq -r '.handoff.nextSteps // ""' "$PROGRESS_FILE")
  [[ -n "$next_steps" ]] && echo "Next Steps: $next_steps"

  echo "========================"
}

# ─── update-step: 단계 상태 전이 (동적 검증) ───

cmd_update_step() {
  local step_name="${1:?Usage: update-step <step_name> <status>}"
  local new_status="${2:?Usage: update-step <step_name> <status>}"

  require_jq
  require_progress

  # schemaVersion 마이그레이션 트리거
  migrate_schema_v2 "$PROGRESS_FILE"
  migrate_schema_v3 "$PROGRESS_FILE"
  migrate_schema_v4 "$PROGRESS_FILE"
  migrate_schema_v5 "$PROGRESS_FILE"
  migrate_schema_v6 "$PROGRESS_FILE"
  migrate_schema_v7 "$PROGRESS_FILE"

  # 유효한 상태 값 확인
  local valid_statuses="pending in_progress completed"
  echo "$valid_statuses" | grep -qw "$new_status" || die "Invalid status: $new_status. Valid: $valid_statuses"

  # progress 파일에 steps 배열이 있는지 확인
  local has_steps
  has_steps=$(jq 'has("steps") and (.steps | type == "array")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  if [[ "$has_steps" != "true" ]]; then
    die "update-step: progress file has no 'steps' array. This template may use 'documents' instead. File: $PROGRESS_FILE"
  fi

  # progress 파일에서 해당 step이 존재하는지 동적으로 확인
  local step_exists
  step_exists=$(jq --arg name "$step_name" '[.steps[] | select(.name == $name)] | length' "$PROGRESS_FILE")
  [[ "$step_exists" -gt 0 ]] || die "Step not found: $step_name. Available steps: $(jq -r '[.steps[].name] | join(", ")' "$PROGRESS_FILE")"

  # Pre-mortem 하드 게이트: phase_2 진입 시 blocking Tiger 미해결 검사
  if [[ "$step_name" == "phase_2" && "$new_status" == "in_progress" ]]; then
    local blocking_unresolved
    blocking_unresolved=$(jq '
      [.phases.phase_0.outputs.premortem.tigers // []
       | .[]
       | select(.blocking == true and (.mitigation == null or .mitigation == "" or (.mitigation | test("^\\s*$"))))]
      | length
    ' "$PROGRESS_FILE" 2>/dev/null || echo "0")

    if [[ "$blocking_unresolved" -gt 0 ]]; then
      echo "BLOCKED: $blocking_unresolved blocking Tiger(s) have no mitigation."
      echo "Resolve all blocking Tigers before entering Phase 2."
      jq -r '.phases.phase_0.outputs.premortem.tigers // [] | .[] | select(.blocking == true and (.mitigation == null or .mitigation == "" or (.mitigation | test("^\\s*$")))) | "  - \(.risk)"' "$PROGRESS_FILE"
      exit 1
    fi

    # projectScope fail-closed 게이트: null/미설정/비정상 형식이면 Phase 2 진입 차단
    local scope_valid
    scope_valid=$(jq '
      .phases.phase_0.outputs.projectScope
      | if type == "object" and has("hasFrontend") and has("hasBackend")
           and (.hasFrontend | type == "boolean") and (.hasBackend | type == "boolean")
        then "valid"
        else "invalid"
        end
    ' "$PROGRESS_FILE" 2>/dev/null || echo '"invalid"')
    if [[ "$scope_valid" != '"valid"' ]]; then
      echo "BLOCKED: projectScope is missing or malformed (need {hasFrontend: bool, hasBackend: bool})."
      echo "Run Phase 0 Step 0-2.5 to define project scope."
      exit 1
    fi
  fi

  # steps 배열에서 해당 step 상태 업데이트 + top-level 갱신 + 타임스탬프
  local ts
  ts=$(timestamp)

  jq_inplace "$PROGRESS_FILE" --arg name "$step_name" --arg status "$new_status" --arg ts "$ts" '
    (.steps[] | select(.name == $name)).status = $status
    | if $status == "in_progress" then
        (.steps[] | select(.name == $name)).startedAt //= $ts
        | (if has("currentPhase") then .currentPhase = $name else . end)
        | (if has("currentStep") then .currentStep = $name else . end)
      else . end
    | if $status == "completed" then
        (.steps[] | select(.name == $name)).completedAt = $ts
      else . end
    | if has("handoff") and (.handoff | has("currentPhase")) then
        .handoff.currentPhase = (.currentPhase // null)
      else . end
    | .status = (if ([.steps[].status] | all(. == "completed")) then "completed" else "in_progress" end)
  '

  echo "OK: $step_name -> $new_status"
}

# ─── check-tools: codex CLI 존재 확인 ───

cmd_check_tools() {
  local has_codex=false

  if command -v codex >/dev/null 2>&1; then
    has_codex=true
    echo "[codex] Available: $(command -v codex)"
  else
    echo "[codex] Not found"
  fi

  # JSON 출력
  echo ""
  echo "{\"codex\": $has_codex}"
}

# ─── recover: 복구/재개 정보 자동 출력 ───

cmd_recover() {
  require_jq
  require_progress

  migrate_schema_v2 "$PROGRESS_FILE"
  migrate_schema_v3 "$PROGRESS_FILE"
  migrate_schema_v4 "$PROGRESS_FILE"
  migrate_schema_v5 "$PROGRESS_FILE"
  migrate_schema_v6 "$PROGRESS_FILE"
  migrate_schema_v7 "$PROGRESS_FILE"

  echo "=== Recovery Info ==="
  echo "Progress: $PROGRESS_FILE"

  # 전체 상태
  local status
  status=$(jq -r '.status // "unknown"' "$PROGRESS_FILE")
  echo "Status: $status"

  if [[ "$status" == "completed" ]]; then
    echo "All phases completed. No recovery needed."
    return 0
  fi

  # 현재 Phase
  local current_phase
  current_phase=$(jq -r '.currentPhase // .handoff.currentPhase // "unknown"' "$PROGRESS_FILE")
  echo "Current Phase: $current_phase"

  # steps 요약
  echo ""
  echo "=== Phase Status ==="
  jq -r '.steps[] | "  \(.name): \(.status)"' "$PROGRESS_FILE" 2>/dev/null || true

  # handoff 정보 (핵심)
  local has_handoff
  has_handoff=$(jq 'has("handoff") and (.handoff | length > 0)' "$PROGRESS_FILE" 2>/dev/null || echo "false")

  if [[ "$has_handoff" == "true" ]]; then
    echo ""
    echo "=== Handoff (Resume Here) ==="
    local last_iter completed next_steps warnings approach
    last_iter=$(jq -r '.handoff.lastIteration // "?"' "$PROGRESS_FILE")
    completed=$(jq -r '.handoff.completedInThisIteration // "N/A"' "$PROGRESS_FILE")
    next_steps=$(jq -r '.handoff.nextSteps // "N/A"' "$PROGRESS_FILE")
    warnings=$(jq -r '.handoff.warnings // ""' "$PROGRESS_FILE")
    approach=$(jq -r '.handoff.currentApproach // ""' "$PROGRESS_FILE")

    echo "  Last Iteration: $last_iter"
    echo "  Completed: $completed"
    echo "  Next Steps: $next_steps"
    [[ -n "$warnings" && "$warnings" != "null" ]] && echo "  ⚠ Warnings: $warnings"
    [[ -n "$approach" && "$approach" != "null" ]] && echo "  Approach: $approach"

    # key decisions
    local decisions
    decisions=$(jq -r '.handoff.keyDecisions // [] | join(", ")' "$PROGRESS_FILE" 2>/dev/null)
    [[ -n "$decisions" ]] && echo "  Key Decisions: $decisions"
  else
    echo ""
    echo "No handoff data found. Start from current phase: $current_phase"
  fi

  # DoD 미완료 항목
  local unchecked
  unchecked=$(jq -r '[.dod // {} | to_entries[] | select(.value.checked != true) | .key] | join(", ")' "$PROGRESS_FILE" 2>/dev/null)
  if [[ -n "$unchecked" ]]; then
    echo ""
    echo "=== Unchecked DoD ==="
    echo "  $unchecked"
  fi

  echo ""
  echo "=== Action ==="
  echo "Resume from: $current_phase"
  echo "Follow handoff.nextSteps above."
}

# ─── handoff-update: Handoff 필드 일괄 갱신 ───

cmd_handoff_update() {
  require_jq
  require_progress

  local phase="" completed="" next_steps="" warnings="" approach="" iteration=""
  local decisions=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase)       phase="${2:?--phase requires value}"; shift 2 ;;
      --completed)   completed="${2:?--completed requires value}"; shift 2 ;;
      --next-steps)  next_steps="${2:?--next-steps requires value}"; shift 2 ;;
      --warnings)    warnings="${2:?--warnings requires value}"; shift 2 ;;
      --approach)    approach="${2:?--approach requires value}"; shift 2 ;;
      --iteration)   iteration="${2:?--iteration requires value}"; shift 2 ;;
      --decision)    decisions+=("${2:?--decision requires value}"); shift 2 ;;
      *) die "Unknown option: $1. Usage: handoff-update --phase <p> --completed <c> --next-steps <n> [--warnings <w>] [--approach <a>] [--iteration <i>] [--decision <d>]..." ;;
    esac
  done

  # 최소 필수 인수
  [[ -n "$next_steps" ]] || die "handoff-update requires at least --next-steps"

  # --iteration 숫자 검증
  if [[ -n "$iteration" ]] && ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
    die "handoff-update: --iteration must be a non-negative integer, got '$iteration'"
  fi

  # 모든 필드를 단일 jq 호출로 배치 업데이트 (원자성 보장)
  local decisions_json="null"
  if [[ ${#decisions[@]} -gt 0 ]]; then
    decisions_json=$(printf '%s\n' "${decisions[@]}" | jq -R . | jq -s .)
  fi

  jq_inplace "$PROGRESS_FILE" \
    --arg next_steps "$next_steps" \
    --arg phase "$phase" \
    --arg completed "$completed" \
    --arg warnings "$warnings" \
    --arg approach "$approach" \
    --arg iteration "$iteration" \
    --argjson decisions "$decisions_json" '
    .handoff //= {}
    | if $next_steps != "" then .handoff.nextSteps = $next_steps else . end
    | if $phase != "" then .handoff.currentPhase = $phase else . end
    | if $completed != "" then .handoff.completedInThisIteration = $completed else . end
    | if $warnings != "" then .handoff.warnings = $warnings else . end
    | if $approach != "" then .handoff.currentApproach = $approach else . end
    | if $iteration != "" then .handoff.lastIteration = ($iteration | tonumber) else . end
    | if $decisions != null then .handoff.keyDecisions = $decisions else . end
  '

  echo "OK: handoff updated"
  jq '.handoff' "$PROGRESS_FILE"
}

# ─── skip-phases: --start-phase N 지원 (Phase 0 ~ N-1 스킵) ───

cmd_skip_phases() {
  local start_phase="${1:?Usage: skip-phases <start_phase_number>}"
  require_jq
  require_progress

  # 입력 검증: 0-4 정수
  if ! [[ "$start_phase" =~ ^[0-4]$ ]]; then
    die "skip-phases: start_phase must be 0-4, got '$start_phase'"
  fi

  # 0이면 스킵할 게 없음
  if [[ "$start_phase" -eq 0 ]]; then
    echo "OK: start_phase=0, nothing to skip"
    return 0
  fi

  # full-auto progress인지 확인
  local is_full_auto
  is_full_auto=$(jq 'if .steps then [.steps[].name] | any(. == "phase_0") else false end' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  [[ "$is_full_auto" == "true" ]] || die "skip-phases: not a full-auto progress file"

  echo "Skipping Phase 0 ~ Phase $((start_phase - 1))..."

  local skip_evidence="skipped by user (--start-phase $start_phase)"
  local target_phase="phase_$start_phase"

  # 단일 jq 호출로 모든 스킵 처리 일괄 수행 (I/O 최소화)
  jq_inplace "$PROGRESS_FILE" \
    --argjson sp "$start_phase" --arg ev "$skip_evidence" --arg target "$target_phase" '
    # 스킵 대상 Phase steps를 completed로 (phase_N 형식만 매칭)
    (.steps[] | select(
      (.name | test("^phase_[0-9]+$")) and
      ((.name | ltrimstr("phase_") | tonumber) < $sp)
    )).status = "completed"
    # 시작 Phase를 in_progress로
    | (.steps[] | select(.name == $target)).status = "in_progress"
    | .currentPhase = $target
    | .handoff.currentPhase = $target
    # Phase별 DoD 키 매핑
    | (if $sp > 0 then .dod.pm_approved = {"checked":true,"evidence":$ev}
         | .dod.assumptions_documented = {"checked":true,"evidence":$ev}
         | .dod.premortem_done = {"checked":true,"evidence":$ev}
       else . end)
    | (if $sp > 1 then .dod.all_docs_complete = {"checked":true,"evidence":$ev}
       else . end)
    | (if $sp > 2 then .dod.all_code_implemented = {"checked":true,"evidence":$ev}
         | .dod.build_pass = {"checked":true,"evidence":$ev}
         | .dod.test_pass = {"checked":true,"evidence":$ev}
         | .dod.e2e_pass = {"checked":true,"evidence":$ev}
       else . end)
    | (if $sp > 3 then .dod.code_review_pass = {"checked":true,"evidence":$ev}
         | .dod.security_review = {"checked":true,"evidence":$ev}
         | .dod.secret_scan = {"checked":true,"evidence":$ev}
       else . end)
    # consistencyChecks
    | (if $sp >= 2 then .consistencyChecks.doc_vs_doc = {"checked":true,"evidence":$ev}
       else . end)
  '

  for ((i = 0; i < start_phase; i++)); do
    echo "  Phase $i: completed (skipped)"
  done

  echo "OK: Starting from Phase $start_phase ($target_phase)"
}

# ─── add-dod-key: DoD 키 동적 추가 (idempotent) ───

cmd_add_dod_key() {
  local key="${1:?Usage: add-dod-key <key_name>}"
  require_jq
  require_progress

  # 이미 존재하면 스킵 (idempotent)
  local exists
  exists=$(jq --arg k "$key" 'has("dod") and (.dod | has($k))' "$PROGRESS_FILE")
  if [[ "$exists" == "true" ]]; then
    echo "OK: dod.$key already exists"
    return 0
  fi

  jq_inplace "$PROGRESS_FILE" --arg k "$key" '.dod[$k] = {"checked":false,"evidence":null}'
  echo "OK: dod.$key added"
}
