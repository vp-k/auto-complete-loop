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

# ─── source-hash: 리뷰 라운드 귀속용 소스 지문 출력 ───
# 각 리뷰 라운드 시작 시 이 출력을 roundResults.sourceHash로 기록한다 (gajae-code의
# frozen sourceHash cohort 채택). code-review-findings가 마지막 라운드 해시를 현재
# 상태와 대조해 "리뷰 후 무리뷰 수정" 세탁을 차단한다.
# 출력 계약: 한 줄 — "<HEAD>-<statehash>" 또는 리터럴 "no-git" (비-git). 항상 exit 0.

cmd_source_hash() {
  local fp
  fp=$(quality_fingerprint) || { echo "no-git"; return 0; }
  echo "$fp"
}

# ─── code-review-findings: progress의 findingHistory/roundResults에서 open CRITICAL/HIGH 계수 (HARD_FAIL) ───
# 코드 리뷰 finding(비-LIVE)의 open CRITICAL/HIGH가 남아 있으면 fail.
# LIVE-* finding은 live-testing-gate가 담당하므로 여기서 제외한다.
# v4.9.0: 마지막 라운드의 sourceHash를 현재 quality_fingerprint와 대조 (불일치/부재 = fail,
# 비-git = skip) — 리뷰 pass 이후의 무리뷰 코드 변경을 fail-closed로 차단한다.

cmd_code_review_findings() {
  echo "=== Code Review Findings Gate ==="
  require_jq
  require_progress

  # 기록 헬퍼 — 계약: codeReviewFindings {result: pass|fail, criticalOpen: N, highOpen: N, sourceHashCheck}
  # $5(sourceHashCheck) 생략 시 "skip" (기존 호출부 호환)
  _crf_record() {
    record_verification "codeReviewFindings" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson c "$2" --argjson h "$3" --arg note "${4:-}" \
          --arg shc "${5:-skip}" \
          '{timestamp:$ts,result:$r,criticalOpen:$c,highOpen:$h,sourceHashCheck:$shc}
           + (if $note != "" then {note:$note} else {} end)')"
  }

  # findingHistory (최상위: review 템플릿 / phases.phase_3: full-auto 템플릿)에서 open 계수
  # hasHistory는 "키 존재"가 아니라 "항목 존재" 기준 — init 템플릿이 빈 배열([])을
  # 항상 생성하므로 키 존재 기준이면 리뷰 미수행 상태가 PASS로 통과(고무도장)된다.
  local counts
  counts=$(jq '
    def rawitems:
      [ ((.findingHistory // []) | .[]),
        ((.phases.phase_3.findingHistory // []) | .[]) ]
      | map(select(type == "object"));
    def items:
      rawitems | map(select((.id // "") | startswith("LIVE-") | not));
    (items) as $all
    | ($all | map(select((.status // "open") == "open"))) as $open
    | {
        hasHistory: ((rawitems | length) > 0),
        total: ($all | length),
        critical: ($open | map(select((.severity // "") == "CRITICAL"
                                      or ((.id // "") | test("-CRITICAL-")))) | length),
        high:     ($open | map(select((.severity // "") == "HIGH"
                                      or ((.id // "") | test("-HIGH-")))) | length),
        lastRound: (((.roundResults // []) + (.phases.phase_3.roundResults // []))
                   | map(select(type == "object"))
                   | if length > 0 then .[-1] else null end),
        lastRoundHash: (((.roundResults // []) + (.phases.phase_3.roundResults // []))
                       | map(select(type == "object"))
                       | if length > 0 then (.[-1].sourceHash // "") else "" end)
      }
  ' "$PROGRESS_FILE" 2>/dev/null || echo '{"hasHistory":false,"total":0,"critical":0,"high":0,"lastRound":null,"lastRoundHash":""}')

  local has_history critical_open high_open note=""
  has_history=$(echo "$counts" | jq -r '.hasHistory')
  critical_open=$(echo "$counts" | jq -r '.critical')
  high_open=$(echo "$counts" | jq -r '.high')
  [[ "$critical_open" =~ ^[0-9]+$ ]] || critical_open=0
  [[ "$high_open" =~ ^[0-9]+$ ]] || high_open=0

  # findingHistory 항목이 없으면 roundResults의 마지막 라운드 집계로 폴백 (fail-closed 추정)
  if [[ "$has_history" != "true" ]]; then
    local has_round
    has_round=$(echo "$counts" | jq '.lastRound != null' 2>/dev/null || echo "false")
    if [[ "$has_round" != "true" ]]; then
      # 리뷰 증거가 전혀 없음 (findingHistory 항목 0 + roundResults 0) = 리뷰 미수행 → fail-closed
      # sourceHashCheck: git repo면 missing(리뷰·귀속 모두 없음), 비-git이면 skip — "skip=비-git" 계약 유지
      local _nv_shc="skip"
      quality_fingerprint >/dev/null 2>&1 && _nv_shc="missing"
      note="no review evidence (empty findingHistory, no roundResults) — code review has not run"
      echo "[code-review-findings] FAIL: $note"
      append_gate_history "code-review-findings" "fail" '{"criticalOpen":0,"highOpen":0,"reason":"no evidence"}'
      _crf_record "fail" 0 0 "$note" "$_nv_shc"
      echo "=== CODE REVIEW FINDINGS: FAIL ==="
      return 1
    fi
    local rr_counts
    rr_counts=$(echo "$counts" | jq '
      .lastRound // {} | .findings.bySeverity // {} | {critical: (.CRITICAL // 0), high: (.HIGH // 0)}
    ' 2>/dev/null || echo '{"critical":0,"high":0}')
    critical_open=$(echo "$rr_counts" | jq -r '.critical')
    high_open=$(echo "$rr_counts" | jq -r '.high')
    [[ "$critical_open" =~ ^[0-9]+$ ]] || critical_open=0
    [[ "$high_open" =~ ^[0-9]+$ ]] || high_open=0
    if [[ $((critical_open + high_open)) -gt 0 ]]; then
      note="no findingHistory entries — counted from last roundResults (per-finding status unknown, fail-closed)"
      echo "[code-review-findings] WARNING: $note"
    fi
  fi

  echo "[code-review-findings] Open code-review findings: CRITICAL=$critical_open, HIGH=$high_open"

  # sourceHash 대조 (v4.9.0): 마지막 리뷰 라운드가 귀속된 소스 지문 == 현재 지문.
  # open-count 검사보다 먼저 — stale 0-finding 라운드도 fail되어야 한다.
  local sh_check="skip" last_hash cur_fp
  last_hash=$(echo "$counts" | jq -r '.lastRoundHash // ""' 2>/dev/null || echo "")
  if cur_fp=$(quality_fingerprint); then
    if [[ -z "$last_hash" ]]; then
      sh_check="missing"
    elif [[ "$last_hash" != "$cur_fp" ]]; then
      sh_check="stale"
    else
      sh_check="pass"
    fi
  fi
  if [[ "$sh_check" == "stale" ]] || [[ "$sh_check" == "missing" ]]; then
    echo "[code-review-findings] FAIL: last review round sourceHash=$sh_check"
    if [[ "$sh_check" == "stale" ]]; then
      echo "  마지막 리뷰 이후 코드가 변경되었습니다 (미리뷰 변경으로 완주 불가)."
    else
      echo "  마지막 리뷰 라운드가 소스 지문에 귀속되지 않았습니다 (pre-4.9 기록 또는 누락)."
    fi
    echo "  Remedy: 수정을 커밋한 뒤 **전체 라운드 절차(소스 지문 캡처 → 리뷰어 실제 호출 →"
    echo "          finding 검증/수정 → 라운드 기록)를 1회 더 실행**하세요. open finding이 있으면"
    echo "          그 라운드에서 함께 수정/기각합니다. 리뷰어 호출 없이 라운드 항목만 append하는 것은 금지."
    append_gate_history "code-review-findings" "fail" "$(jq -n --arg s "$sh_check" '{reason:("sourceHash " + $s)}')"
    _crf_record "fail" "$critical_open" "$high_open" "sourceHash $sh_check — unreviewed changes" "$sh_check"
    echo "=== CODE REVIEW FINDINGS: FAIL ==="
    return 1
  fi

  if [[ $((critical_open + high_open)) -gt 0 ]]; then
    echo "[code-review-findings] FAIL: open CRITICAL/HIGH finding(s) remain"
    echo "  Fix them (or record dismissal with rationale) and set status=fixed in findingHistory."
    append_gate_history "code-review-findings" "fail" "{\"criticalOpen\":$critical_open,\"highOpen\":$high_open}"
    _crf_record "fail" "$critical_open" "$high_open" "$note" "$sh_check"
    echo "=== CODE REVIEW FINDINGS: FAIL ==="
    return 1
  fi

  append_gate_history "code-review-findings" "pass" '{"criticalOpen":0,"highOpen":0}'
  _crf_record "pass" 0 0 "$note" "$sh_check"
  # DoD 갱신: dod.code_review_pass는 이 게이트가 유일한 기록자 (모델 직접 세팅 금지)
  if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg ev "code-review-findings PASS at $(timestamp) (open CRITICAL/HIGH: 0)" '
      if (.dod | has("code_review_pass")) then
        .dod.code_review_pass = {checked: true, evidence: $ev}
      else . end'
  fi
  echo "=== CODE REVIEW FINDINGS: PASS ==="
  return 0
}

# ─── review-escalation-check: 위험 트리거 기반 리뷰 승격 판정/증거 검증 ───
# ouroboros의 조건부 consensus 채택: 평상시엔 사용자 선택 리뷰 모드로 충분하지만,
# 위험 트리거(L2+ 에스컬레이션 / 범위 축소 / 인수 테스트 재동결)가 발동한 실행은
# 추가 승격 리뷰(dual 2차 codex 또는 roundtable)를 의무화한다.
# - 플래그 없음: 트리거 평가 → reviewEscalation = skip(무트리거) | pending(승격 필요)
# - --mark-complete: 승격 리뷰 증거(roundResults의 escalated 라운드) 검증 → pass | fail
# stop-hook은 reviewEscalation이 pass|skip일 때만 완주 허용 (pending/미실행 = 차단).

cmd_review_escalation_check() {
  local mark_complete=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mark-complete) mark_complete=true; shift ;;
      *)               shift ;;
    esac
  done

  echo "=== Review Escalation Check ==="
  require_jq
  require_progress

  _rec_record() {  # $1=result $2=triggers_json $3=mode
    record_verification "reviewEscalation" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson t "${2:-[]}" --arg m "${3:-}" \
          '{timestamp:$ts,result:$r,triggers:$t} + (if $m != "" then {mode:$m} else {} end)')"
  }

  # ── 트리거 평가 (모두 결정론적 판독) ──
  local triggers_json
  triggers_json=$(jq '
    [
      (if ([.errorHistory.levelHistory // [] | .[] | select(test("^L[2-5]$"))] | length) > 0
       then {type: "escalation", detail: ("levelHistory reached " + ([.errorHistory.levelHistory // [] | .[] | select(test("^L[2-5]$"))] | last))}
       else empty end),
      (if (((.phases.phase_2.scopeReductions // []) + (.scopeReductions // [])) | length) > 0
       then {type: "scope_reduction", detail: ("scopeReductions: " + ((((.phases.phase_2.scopeReductions // []) + (.scopeReductions // [])) | length) | tostring))}
       else empty end)
    ]
  ' "$PROGRESS_FILE" 2>/dev/null || echo "[]")

  # 트리거 3: 인수 테스트 재동결 (구현 단계 승인 동결 이력 — 기획 단계 최초 동결은 미기록)
  local refreeze_count=0
  if [[ -f "tests/acceptance/.manifest.json" ]]; then
    refreeze_count=$(jq '.refreezeHistory // [] | length' "tests/acceptance/.manifest.json" 2>/dev/null || echo 0)
    [[ "$refreeze_count" =~ ^[0-9]+$ ]] || refreeze_count=0
  fi
  if [[ "$refreeze_count" -ge 1 ]]; then
    triggers_json=$(jq -cn --argjson base "$triggers_json" --argjson n "$refreeze_count" \
      '$base + [{type: "acceptance_refreeze", detail: ("refreezeHistory: " + ($n | tostring))}]')
  fi

  local trigger_count
  trigger_count=$(jq 'length' <<< "$triggers_json" 2>/dev/null || echo 0)
  [[ "$trigger_count" =~ ^[0-9]+$ ]] || trigger_count=0

  # ── 무트리거 → skip (양 모드 공통, 멱등) ──
  if [[ "$trigger_count" -eq 0 ]]; then
    echo "[review-escalation] No risk triggers (L2+/scope-reduction/re-freeze) — standard review is sufficient"
    jq_inplace "$PROGRESS_FILE" --arg ts "$(timestamp)" '
      .phases.phase_3.reviewEscalation = {required: false, triggers: [], checkedAt: $ts}'
    append_gate_history "review-escalation-check" "skip" '{"triggers":0}'
    _rec_record "skip" "[]" ""
    echo "=== REVIEW ESCALATION: SKIP ==="
    return 0
  fi

  # targetMode: codex CLI 있으면 dual(2차 codex 독립 리뷰), 없으면 roundtable 에이전트
  local target_mode="roundtable"
  command -v codex >/dev/null 2>&1 && target_mode="dual"

  if [[ "$mark_complete" == "false" ]]; then
    # ── 판정 모드: pending 기록 + 오케스트레이터 지시 ──
    echo "[review-escalation] Risk triggers detected ($trigger_count):"
    jq -r '.[] | "  - \(.type): \(.detail)"' <<< "$triggers_json" 2>/dev/null || true
    jq_inplace "$PROGRESS_FILE" --argjson t "$triggers_json" --arg m "$target_mode" --arg ts "$(timestamp)" '
      .phases.phase_3.reviewEscalation = {required: true, triggers: $t, targetMode: $m, checkedAt: $ts}'
    append_gate_history "review-escalation-check" "pending" "{\"triggers\":$trigger_count}"
    _rec_record "pending" "$triggers_json" "$target_mode"
    echo ""
    echo "[review-escalation] MANDATE: 승격 리뷰(${target_mode}) 1라운드를 추가로 실행해야 합니다."
    echo "  - dual: codex 2차 독립 리뷰 1회 추가 / roundtable: roundtable 에이전트 리뷰"
    echo "  - 승격 리뷰의 finding은 findingHistory에 \"escalated\": true로 append"
    echo "  - 승격 라운드는 roundResults에 {escalated: true, reviewMode: \"${target_mode}\"} 포함하여 기록 (0-finding이어도 필수)"
    echo "  - 완료 후: shared-gate.sh review-escalation-check --mark-complete"
    echo "=== REVIEW ESCALATION: PENDING ==="
    return 0
  fi

  # ── --mark-complete: 승격 리뷰 증거 검증 (fail-closed) ──
  local stored_mode
  stored_mode=$(jq -r '.phases.phase_3.reviewEscalation.targetMode // ""' "$PROGRESS_FILE" 2>/dev/null || echo "")
  [[ -n "$stored_mode" ]] || stored_mode="$target_mode"

  local evidence_count
  evidence_count=$(jq --arg m "$stored_mode" '
    [ ((.roundResults // []) + (.phases.phase_3.roundResults // []))[]
      | select(type == "object" and (.escalated == true) and ((.reviewMode // "") == $m)) ]
    | length
  ' "$PROGRESS_FILE" 2>/dev/null || echo 0)
  [[ "$evidence_count" =~ ^[0-9]+$ ]] || evidence_count=0

  if [[ "$evidence_count" -eq 0 ]]; then
    echo "[review-escalation] FAIL: 승격 리뷰 증거 없음 — roundResults에 {escalated: true, reviewMode: \"${stored_mode}\"} 라운드가 필요합니다"
    append_gate_history "review-escalation-check" "fail" '{"reason":"no escalated round evidence"}'
    _rec_record "fail" "$triggers_json" "$stored_mode"
    echo "=== REVIEW ESCALATION: FAIL ==="
    return 1
  fi

  echo "[review-escalation] Escalated review verified (mode: $stored_mode, rounds: $evidence_count)"
  append_gate_history "review-escalation-check" "pass" "{\"triggers\":$trigger_count}"
  _rec_record "pass" "$triggers_json" "$stored_mode"
  log_event "review.escalated" "$(jq -cn --arg m "$stored_mode" --argjson t "$trigger_count" \
    '{mode: $m, triggers: $t}' 2>/dev/null || echo '{}')" || true
  echo "=== REVIEW ESCALATION: PASS ==="
  return 0
}

# ─── record-dimension: 소프트 품질 차원 기록 (verification.json 직접 편집 대체 경로) ───
# 가드가 .claude-verification.json 직접 기록(Edit/Write/Bash 리다이렉트)을 차단하므로,
# 소프트 품질 차원(featureCompleteness/security/performance/codeQuality/documentation/
# e2eCoverage/visualRegression 등)은 이 서브커맨드로만 기록한다.
# - qualityDimensions 하위에만 기록 — 최상위 키(build/test/acceptanceTests 등)는 기록 불가
# - layerCoverage는 layer-coverage 게이트가 유일한 기록자 — 자기신고 금지 (exit 1)

cmd_record_dimension() {
  local key="${1:-}" result="${2:-}"
  shift 2 2>/dev/null || true
  local evidence="$*"

  if [[ -z "$key" || -z "$result" ]]; then
    die "Usage: record-dimension <key> <result> [evidence...] (result: pass|warn|fail|skip)"
  fi

  # layerCoverage 거부 — 하드 게이트 결과의 자기신고 차단
  if [[ "$key" == "layerCoverage" ]]; then
    die "record-dimension: 'layerCoverage'는 layer-coverage 서브커맨드 전용 — 자기신고 금지"
  fi

  # result 값 검증
  case "$result" in
    pass|warn|fail|skip) ;;
    *) die "record-dimension: invalid result '$result' (allowed: pass|warn|fail|skip)" ;;
  esac

  require_jq

  # qualityDimensions.<key>에만 기록 (최상위 키 기록 경로 없음)
  record_verification_qd "$key" \
    "$(jq -n --arg r "$result" --arg e "$evidence" --arg ts "$(timestamp)" \
        '{result: $r, evidence: $e, timestamp: $ts}')"

  append_gate_history "record-dimension" "$result" \
    "$(jq -n --arg k "$key" '{dimension: $k}')"

  echo "OK: qualityDimensions.$key = $result"
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
