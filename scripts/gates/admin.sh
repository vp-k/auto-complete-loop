# gates/admin.sh — 초기화, 상태 관리, 에러 추적, 체크포인트 등 관리 명령

# ─── init: progress JSON 초기화 ───

cmd_init() {
  local template="full-auto"
  local project="unnamed"
  local requirement=""

  # 인수 파싱
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)
        template="${2:?--template requires a type}"
        shift 2
        ;;
      *)
        if [[ "$project" == "unnamed" ]]; then
          project="$1"
        else
          requirement="$1"
        fi
        shift
        ;;
    esac
  done

  require_jq

  # 템플릿별 파일명 결정
  local target_file
  case "$template" in
    full-auto)  target_file=".claude-full-auto-progress.json" ;;
    plan)       target_file=".claude-plan-progress.json" ;;
    implement)  target_file=".claude-progress.json" ;;
    review)     target_file=".claude-review-loop-progress.json" ;;
    polish)     target_file=".claude-polish-progress.json" ;;
    e2e)        target_file=".claude-e2e-progress.json" ;;
    doc-check)  target_file=".claude-doc-check-progress.json" ;;
    *)          die "Unknown template: $template. Valid: full-auto, plan, implement, review, polish, e2e, doc-check" ;;
  esac

  if [[ -f "$target_file" ]]; then
    echo "WARNING: $target_file already exists. Skipping init."
    return 0
  fi

  local safe_project safe_requirement
  safe_project=$(jq -Rn --arg v "$project" '$v')
  safe_requirement=$(jq -Rn --arg v "$requirement" '$v')

  case "$template" in
    full-auto)
      cat > "$target_file" <<ENDJSON
{
  "schemaVersion": 7,
  "project": $safe_project,
  "userRequirement": $safe_requirement,
  "status": "in_progress",
  "currentPhase": "phase_0",
  "gateHistory": [],
  "conditionalGoItems": [],
  "steps": [
    {"name": "phase_0", "label": "PM Planning", "status": "in_progress"},
    {"name": "phase_1", "label": "Planning", "status": "pending"},
    {"name": "phase_2", "label": "Implementation", "status": "pending"},
    {"name": "phase_3", "label": "Code Review", "status": "pending"},
    {"name": "phase_4", "label": "Verification", "status": "pending"}
  ],
  "phases": {
    "phase_0": { "outputs": { "definitionDoc": null, "readmePath": null, "techStack": null, "rounds": [], "assumptions": [], "nsm": null, "successCriteria": [], "premortem": {"tigers":[],"paperTigers":[],"elephants":[]}, "projectSize": null, "projectScope": null, "stakeholders": null, "implementationOrder": [] } },
    "phase_1": { "documents": [], "currentDocument": null },
    "phase_2": { "documents": [], "currentDocument": null, "completedFiles": [], "context": {}, "documentSummaries": {}, "scopeReductions": [], "e2e": {"applicable": null, "projectType": null, "dataStrategy": null, "e2eFramework": null, "fallbackReason": null, "scenarios": []} },
    "phase_3": { "currentRound": 0, "roundResults": [], "findingHistory": [] },
    "phase_4": { "verificationSteps": [], "designPolish": null }
  },
  "consistencyChecks": {
    "doc_vs_doc": { "checked": false, "evidence": null },
    "doc_vs_code": { "checked": false, "evidence": null },
    "code_quality": { "checked": false, "evidence": null }
  },
  "dod": {
    "pm_approved": { "checked": false, "evidence": null },
    "assumptions_documented": { "checked": false, "evidence": null },
    "premortem_done": { "checked": false, "evidence": null },
    "all_docs_complete": { "checked": false, "evidence": null },
    "all_code_implemented": { "checked": false, "evidence": null },
    "build_pass": { "checked": false, "evidence": null },
    "test_pass": { "checked": false, "evidence": null },
    "code_review_pass": { "checked": false, "evidence": null },
    "security_review": { "checked": false, "evidence": null },
    "secret_scan": { "checked": false, "evidence": null },
    "e2e_pass": { "checked": false, "evidence": null },
    "design_quality": { "checked": false, "evidence": null },
    "launch_ready": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "currentPhase": "phase_0",
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    plan)
      cat > "$target_file" <<ENDJSON
{
  "project": $safe_project,
  "created": "$(timestamp)",
  "status": "in_progress",
  "definitionDoc": null,
  "readmePath": null,
  "documents": [],
  "currentDocument": null,
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {
    "user_story": { "checked": false, "evidence": null },
    "data_model": { "checked": false, "evidence": null },
    "api_contract": { "checked": false, "evidence": null },
    "error_scenarios": { "checked": false, "evidence": null },
    "no_definition_conflict": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    implement)
      cat > "$target_file" <<ENDJSON
{
  "project": $safe_project,
  "created": "$(timestamp)",
  "status": "in_progress",
  "documents": [],
  "dod": {
    "build_pass": { "checked": false, "evidence": null },
    "test_pass": { "checked": false, "evidence": null },
    "code_review": { "checked": false, "evidence": null },
    "e2e_pass": { "checked": false, "evidence": null }
  },
  "currentDocument": null,
  "lastCommitSha": null,
  "errorHistory": {
    "currentError": null,
    "attempts": []
  },
  "completedFiles": [],
  "context": {
    "architecture": null,
    "patterns": null
  },
  "documentSummaries": {},
  "lastVerifiedAt": null,
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    review)
      cat > "$target_file" <<ENDJSON
{
  "mode": "rounds",
  "targetRounds": 3,
  "goal": null,
  "goalMet": false,
  "scope": $safe_requirement,
  "currentRound": 0,
  "status": "in_progress",
  "roundResults": [],
  "findingHistory": [],
  "dod": {
    "all_rounds_complete": { "checked": false, "evidence": null },
    "build_pass": { "checked": false, "evidence": null },
    "no_critical_high": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "Round 1 시작",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    polish)
      cat > "$target_file" <<ENDJSON
{
  "project": $safe_project,
  "created": "$(timestamp)",
  "status": "in_progress",
  "definitionDoc": null,
  "readmePath": null,
  "steps": [
    {"name": "프로젝트 분석", "status": "pending", "group": 1, "evidence": {}},
    {"name": "기획 대비 검토", "status": "pending", "group": 1, "evidence": {}},
    {"name": "빌드 검증", "status": "pending", "group": 2, "evidence": {}},
    {"name": "테스트 검증", "status": "pending", "group": 2, "evidence": {}},
    {"name": "보안 검토", "status": "pending", "group": 3, "evidence": {}},
    {"name": "문서화 확인", "status": "pending", "group": 3, "evidence": {}},
    {"name": "릴리즈 체크리스트", "status": "pending", "group": 4, "evidence": {}},
    {"name": "최종 검증", "status": "pending", "group": 4, "evidence": {}}
  ],
  "currentStep": null,
  "turnCount": 0,
  "lastCompactAt": 0,
  "dod": {
    "build_pass": { "checked": false, "evidence": null },
    "test_pass": { "checked": false, "evidence": null },
    "security_review": { "checked": false, "evidence": null },
    "docs_complete": { "checked": false, "evidence": null },
    "final_verification": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    e2e)
      cat > "$target_file" <<ENDJSON
{
  "project": $safe_project,
  "created": "$(timestamp)",
  "status": "in_progress",
  "mode": null,
  "docsDir": null,
  "projectType": null,
  "e2eFramework": null,
  "dataStrategy": null,
  "mockSchemaSource": null,
  "steps": [
    {"name": "analyze_project", "label": "프로젝트 분석", "status": "pending"},
    {"name": "derive_scenarios", "label": "시나리오 도출", "status": "pending"},
    {"name": "setup_framework", "label": "E2E 프레임워크 설정", "status": "pending"},
    {"name": "write_tests", "label": "E2E 테스트 작성", "status": "pending"},
    {"name": "verify_tests", "label": "테스트 검증", "status": "pending"}
  ],
  "scenarios": [],
  "errorHistory": {
    "currentError": null,
    "attempts": []
  },
  "dod": {
    "framework_setup": { "checked": false, "evidence": null },
    "scenarios_documented": { "checked": false, "evidence": null },
    "tests_written": { "checked": false, "evidence": null },
    "e2e_pass": { "checked": false, "evidence": null },
    "build_pass": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
    doc-check)
      cat > "$target_file" <<ENDJSON
{
  "project": $safe_project,
  "created": "$(timestamp)",
  "status": "in_progress",
  "docsDir": "docs/",
  "steps": [
    {"name": "구조적 검사", "status": "pending", "evidence": {}},
    {"name": "의미적 검증", "status": "pending", "evidence": {}},
    {"name": "최종 확인", "status": "pending", "evidence": {}}
  ],
  "dod": {
    "doc_consistency": { "checked": false, "evidence": null },
    "doc_code_check": { "checked": false, "evidence": null },
    "semantic_review": { "checked": false, "evidence": null }
  },
  "handoff": {
    "lastIteration": null,
    "completedInThisIteration": "",
    "nextSteps": "",
    "keyDecisions": [],
    "warnings": "",
    "currentApproach": ""
  }
}
ENDJSON
      ;;
  esac

  echo "OK: $target_file initialized (template: $template)"
}

# ─── init-ralph: Ralph Loop 파일 생성 ───

cmd_init_ralph() {
  local promise="${1:?Usage: init-ralph <promise> <progress_file> [max_iter]}"
  local progress_file="${2:?Usage: init-ralph <promise> <progress_file> [max_iter]}"
  local max_iter="${3:-0}"

  # 입력 검증: max_iter는 반드시 정수
  if ! [[ "$max_iter" =~ ^[0-9]+$ ]]; then
    die "init-ralph: max_iter must be a non-negative integer, got '$max_iter'"
  fi

  # 입력 검증: promise/progress_file에 개행/제어문자 금지
  if [[ "$promise" == *$'\n'* ]] || [[ "$promise" == *$'\r'* ]]; then
    die "init-ralph: promise must not contain newlines"
  fi
  if [[ "$progress_file" == *$'\n'* ]] || [[ "$progress_file" == *$'\r'* ]]; then
    die "init-ralph: progress_file must not contain newlines"
  fi

  # 입력 검증: progress_file 경로 조작 방지
  if [[ "$progress_file" == /* ]]; then
    die "init-ralph: progress_file must be a relative path, got '$progress_file'"
  fi
  if [[ "$progress_file" == *..* ]]; then
    die "init-ralph: progress_file must not contain '..', got '$progress_file'"
  fi
  if [[ ! "$progress_file" =~ ^\.claude-.*progress.*\.json$ ]]; then
    die "init-ralph: progress_file must match pattern '.claude-*progress*.json', got '$progress_file'"
  fi

  mkdir -p .claude

  local ralph_file=".claude/ralph-loop.local.md"

  if [[ -f "$ralph_file" ]]; then
    echo "WARNING: $ralph_file already exists. Skipping."
    return 0
  fi

  local now
  now=$(timestamp)

  cat > "$ralph_file" <<ENDRALPH
---
active: true
iteration: 1
max_iterations: $max_iter
completion_promise: "$promise"
progress_file: "$progress_file"
started_at: "$now"
---

이전 작업을 이어서 진행합니다.
\`$progress_file\`을 읽고 상태를 확인하세요.
특히 \`handoff\` 필드를 먼저 읽어 이전 iteration의 맥락을 복구하세요.

1. completed 단계는 건너뛰세요
2. in_progress 단계가 있으면 해당 단계부터 재개
3. pending 단계가 있으면 다음 pending 단계 시작
4. 모든 단계가 completed이고 검증을 통과하면 <promise>$promise</promise> 출력

검증 규칙:
- $progress_file의 모든 단계/문서 status가 completed여야 함
- dod 체크리스트가 모두 checked여야 함
- 조건 미충족 시 절대 <promise> 태그를 출력하지 마세요
ENDRALPH

  echo "OK: $ralph_file created (promise: $promise, progress: $progress_file, max_iter: $max_iter)"
}

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

# ─── artifact-check: 빌드 아티팩트 존재 + 크기 검증 ───

cmd_artifact_check() {
  echo "=== Artifact Check ==="
  require_jq

  local artifact_found=false
  local artifact_path=""
  local artifact_type=""

  # 프로젝트 유형별 아티팩트 확인
  if [[ -f "package.json" ]]; then
    artifact_type="web"
    for d in dist build .next out; do
      if [[ -d "$d" ]]; then
        # 빈 디렉토리 체크
        local file_count
        file_count=$(find "$d" -type f 2>/dev/null | head -5 | wc -l)
        if [[ "$file_count" -gt 0 ]]; then
          artifact_found=true
          artifact_path="$d"
          break
        fi
      fi
    done
  elif [[ -f "pubspec.yaml" ]]; then
    artifact_type="flutter"
    if [[ -d "build/app/outputs" ]]; then
      local file_count
      file_count=$(find "build/app/outputs" -type f 2>/dev/null | head -5 | wc -l)
      if [[ "$file_count" -gt 0 ]]; then
        artifact_found=true
        artifact_path="build/app/outputs"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    artifact_type="go"
    # Go 바이너리: go.mod의 module 이름으로 추정
    local mod_name
    mod_name=$(head -1 go.mod | awk '{print $2}' | xargs basename 2>/dev/null || echo "")
    if [[ -n "$mod_name" ]] && [[ -f "$mod_name" ]]; then
      artifact_found=true
      artifact_path="$mod_name"
    fi
  elif [[ -f "Cargo.toml" ]]; then
    artifact_type="rust"
    if [[ -d "target/release" ]] || [[ -d "target/debug" ]]; then
      artifact_found=true
      artifact_path="target/"
    fi
  fi

  # verification.json에 기록
  local ts
  ts=$(timestamp)
  local result
  if [[ "$artifact_found" == "true" ]]; then
    result="pass"
    echo "[artifact-check] PASS ($artifact_type: $artifact_path)"
  else
    result="soft_fail"
    if [[ -n "$artifact_type" ]]; then
      echo "[artifact-check] SOFT_FAIL ($artifact_type: no build artifact found)"
    else
      echo "[artifact-check] SKIP (unknown project type)"
      result="skip"
    fi
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg type "$artifact_type" --arg path "$artifact_path" --arg result "$result" \
      '.artifactCheck = {"timestamp": $ts, "projectType": $type, "artifactPath": $path, "result": $result}'
  else
    jq -n --arg ts "$ts" --arg type "$artifact_type" --arg path "$artifact_path" --arg result "$result" \
      '{"artifactCheck": {"timestamp": $ts, "projectType": $type, "artifactPath": $path, "result": $result}}' > "$VERIFICATION_FILE"
  fi

  echo "=== ARTIFACT CHECK: ${result^^} ==="
  if [[ "$result" == "soft_fail" ]]; then
    return 1
  fi
  return 0
}

# ─── record-error: 에러 반복 판별 + errorHistory 업데이트 ───

cmd_record_error() {
  local err_file="" err_type="" err_msg="" err_level="" err_action="" err_result="" reset_count=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)        err_file="${2:?--file requires a value}"; shift 2 ;;
      --type)        err_type="${2:?--type requires a value}"; shift 2 ;;
      --msg)         err_msg="${2:?--msg requires a value}"; shift 2 ;;
      --level)       err_level="${2:?--level requires L0-L5}"; shift 2 ;;
      --action)      err_action="${2:?--action requires a description}"; shift 2 ;;
      --result)      err_result="${2:?--result requires pass|fail}"; shift 2 ;;
      --reset-count) reset_count=true; shift ;;
      *)             shift ;;
    esac
  done

  [[ -n "$err_file" ]] || die "Usage: record-error --file <f> --type <t> --msg <m> [--level L0-L5] [--action '...'] [--result pass|fail] [--reset-count]"
  [[ -n "$err_type" ]] || die "Usage: record-error --file <f> --type <t> --msg <m>"
  [[ -n "$err_msg" ]]  || die "Usage: record-error --file <f> --type <t> --msg <m>"

  require_jq
  require_progress

  # 에러 레벨 유효성 검사
  if [[ -n "$err_level" ]]; then
    echo "L0 L1 L2 L3 L4 L5" | grep -qw "$err_level" || die "Invalid level: $err_level. Valid: L0 L1 L2 L3 L4 L5"
  fi

  # 에스컬레이션 레벨별 예산
  # L0=3, L1=3, L2=1, L3=3, L4=1
  local -A level_budget=( ["L0"]=3 ["L1"]=3 ["L2"]=1 ["L3"]=3 ["L4"]=1 ["L5"]=0 )

  # 현재 errorHistory 읽기
  local current_err_type current_err_file current_count
  current_err_type=$(jq -r '.errorHistory.currentError.type // ""' "$PROGRESS_FILE")
  current_err_file=$(jq -r '.errorHistory.currentError.file // ""' "$PROGRESS_FILE")
  current_count=$(jq '.errorHistory.currentError.count // 0' "$PROGRESS_FILE")

  # 현재 에스컬레이션 레벨/예산 읽기
  local current_escalation current_budget
  current_escalation=$(jq -r '.errorHistory.escalationLevel // "L0"' "$PROGRESS_FILE")
  current_budget=$(jq '.errorHistory.escalationBudget // 3' "$PROGRESS_FILE")

  # --level이 제공되면 에스컬레이션 레벨/예산 항상 반영
  if [[ -n "$err_level" ]]; then
    current_escalation="$err_level"
    current_budget="${level_budget[$err_level]:-3}"
  fi

  # --reset-count 시 카운터 리셋
  if [[ "$reset_count" == "true" ]]; then
    current_count=0
  fi

  # 동일 에러 판별 (type + file + 메시지 핵심 일치)
  # 메시지 정규화: 숫자/라인번호 제거하여 핵심만 비교
  local msg_normalized
  msg_normalized=$(echo "$err_msg" | sed 's/[0-9]//g' | sed 's/  */ /g' | head -c 100)
  local prev_msg_normalized
  prev_msg_normalized=$(jq -r '.errorHistory.currentError.msgNormalized // ""' "$PROGRESS_FILE" 2>/dev/null)
  if [[ "$current_err_type" == "$err_type" ]] && [[ "$current_err_file" == "$err_file" ]] && [[ "$msg_normalized" == "$prev_msg_normalized" ]]; then
    current_count=$((current_count + 1))
  else
    current_count=1
  fi

  # 진행/회귀 판별 (에러 레벨 기반)
  local direction="same"
  if [[ -n "$err_level" ]]; then
    local level_history
    level_history=$(jq -r '.errorHistory.levelHistory // [] | .[-1] // ""' "$PROGRESS_FILE")
    if [[ -n "$level_history" ]] && [[ "$level_history" != "$err_level" ]]; then
      local prev_num=${level_history#L}
      local curr_num=${err_level#L}
      if [[ "$curr_num" -gt "$prev_num" ]]; then
        direction="forward"
      elif [[ "$curr_num" -lt "$prev_num" ]]; then
        direction="backward"
      fi
    fi

    # 회귀 연속 횟수 체크
    if [[ "$direction" == "backward" ]]; then
      local last_two_directions
      last_two_directions=$(jq -r '
        .errorHistory.levelHistory // [] |
        if length >= 2 then
          [.[length-2], .[length-1]] |
          if .[0] > .[1] then "backward" else "not" end
        else "not" end
      ' "$PROGRESS_FILE")
      if [[ "$last_two_directions" == "backward" ]]; then
        echo "WARNING: 회귀 2회 연속 — 현재 접근법을 재검토하세요 (codex 호출 또는 다른 접근법)"
      fi
    fi
  fi

  # 에스컬레이션 로그 엔트리 생성
  local ts
  ts=$(timestamp)
  local log_entry
  log_entry=$(jq -n \
    --arg ts "$ts" \
    --arg level "${err_level:-$current_escalation}" \
    --argjson attempt "$current_count" \
    --arg error "$err_msg" \
    --arg action "${err_action:-}" \
    --arg result "${err_result:-fail}" \
    '{ts: $ts, level: $level, attempt: $attempt, error: $error, action: $action, result: $result}')

  # errorHistory 업데이트 (확장된 구조)
  jq_inplace "$PROGRESS_FILE" \
    --arg type "$err_type" \
    --arg file "$err_file" \
    --arg msg "$err_msg" \
    --argjson count "$current_count" \
    --arg escalation "$current_escalation" \
    --argjson budget "$current_budget" \
    --arg level "${err_level:-}" \
    --arg mnorm "$msg_normalized" \
    --argjson logEntry "$log_entry" '
    .errorHistory.currentError = {
      "type": $type,
      "file": $file,
      "message": $msg,
      "msgNormalized": $mnorm,
      "count": $count,
      "escalationLevel": $escalation
    }
    | .errorHistory.attempts += [$msg]
    | .errorHistory.escalationLevel = $escalation
    | .errorHistory.escalationBudget = $budget
    | if $level != "" then
        .errorHistory.levelHistory = ((.errorHistory.levelHistory // []) + [$level])
      else . end
    | .errorHistory.escalationLog = ((.errorHistory.escalationLog // []) + [$logEntry])
  '

  echo "Error recorded: $err_type in $err_file (count: $current_count, escalation: $current_escalation)"
  [[ -n "$err_level" ]] && echo "DIRECTION: $direction (error level: $err_level)"

  # exit code로 에스컬레이션 결과 전달
  # exit 0: 현재 레벨 예산 내 → 계속 시도
  # exit 1: 현재 레벨 예산 소진 → 다음 레벨로 에스컬레이트
  # exit 2: L2 도달 → codex 분석 필요
  # exit 3: L5 도달 → 사용자 개입 필요
  if [[ "$current_escalation" == "L5" ]]; then
    # L5는 최종 단계 — 항상 사용자 개입 필요
    echo "ACTION: L5 → 사용자 개입 필요"
    exit 3
  elif [[ "$current_escalation" == "L4" ]] && [[ $current_count -ge ${level_budget[L4]} ]]; then
    # L5 상태를 progress 파일에 기록 (반복 간 추적 가능)
    jq_inplace "$PROGRESS_FILE" '
      .errorHistory.escalationLevel = "L5"
      | .errorHistory.escalationBudget = 0
      | .errorHistory.levelHistory = ((.errorHistory.levelHistory // []) + ["L5"])
    '
    echo "ACTION: L4 예산 소진 → L5 사용자 개입 필요"
    exit 3
  elif [[ "$current_escalation" == "L2" ]]; then
    echo "ACTION: L2 → codex 분석 필요"
    exit 2
  elif [[ $current_count -ge $current_budget ]]; then
    # 예산 소진 → 다음 레벨로 자동 전이 + 카운터 리셋
    local next_levels=("L0" "L1" "L2" "L3" "L4" "L5")
    local current_idx=0
    for i in "${!next_levels[@]}"; do
      [[ "${next_levels[$i]}" == "$current_escalation" ]] && current_idx=$i
    done
    local next_level="${next_levels[$((current_idx + 1))]:-L5}"
    local next_budget="${level_budget[$next_level]:-3}"
    jq_inplace "$PROGRESS_FILE" --arg nl "$next_level" --argjson nb "$next_budget" '
      .errorHistory.escalationLevel = $nl
      | .errorHistory.escalationBudget = $nb
      | .errorHistory.currentError.count = 0
      | .errorHistory.levelHistory = ((.errorHistory.levelHistory // []) + [$nl])
    '
    echo "ACTION: $current_escalation 예산 소진 ($current_count/$current_budget) → $next_level 로 자동 에스컬레이트"
    exit 1
  else
    echo "ACTION: 계속 시도 ($current_count/$current_budget)"
    exit 0
  fi
}

# ─── check-tools: codex/gemini CLI 존재 확인 ───

cmd_check_tools() {
  local has_codex=false has_gemini=false

  if command -v codex >/dev/null 2>&1; then
    has_codex=true
    echo "[codex] Available: $(command -v codex)"
  else
    echo "[codex] Not found"
  fi

  if command -v gemini >/dev/null 2>&1; then
    has_gemini=true
    echo "[gemini] Available: $(command -v gemini)"
  else
    echo "[gemini] Not found"
  fi

  # JSON 출력
  echo ""
  echo "{\"codex\": $has_codex, \"gemini\": $has_gemini}"
}

# ─── find-debug-code: 디버그 코드 탐색 ───

cmd_find_debug_code() {
  local search_dir="${1:-.}"

  echo "=== Debug Code Scan ==="
  echo "Scanning: $search_dir"

  local found=0

  # 언어별 디버그 패턴
  # JavaScript/TypeScript
  if ls "$search_dir"/**/*.{js,ts,jsx,tsx} 2>/dev/null | head -1 >/dev/null 2>&1 || \
     find "$search_dir" -maxdepth 5 \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo ""
    echo "[JS/TS] console.log/debug/debugger:"
    local js_debug
    js_debug=$(grep -rn --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" \
      -e 'console\.log' -e 'console\.debug' -e 'console\.warn' -e 'debugger' \
      "$search_dir" 2>/dev/null | grep -v node_modules | grep -v '.test.' | grep -v '.spec.' | head -20 || true)
    if [[ -n "$js_debug" ]]; then
      echo "$js_debug"
      found=$((found + $(echo "$js_debug" | wc -l)))
    else
      echo "  None found"
    fi
  fi

  # Python
  if find "$search_dir" -maxdepth 5 -name "*.py" 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo ""
    echo "[Python] print/pdb/breakpoint:"
    local py_debug
    py_debug=$(grep -rn --include="*.py" \
      -e '^[[:space:]]*print(' -e 'pdb\.set_trace' -e 'breakpoint()' -e 'import pdb' \
      "$search_dir" 2>/dev/null | grep -v __pycache__ | grep -v test_ | head -20 || true)
    if [[ -n "$py_debug" ]]; then
      echo "$py_debug"
      found=$((found + $(echo "$py_debug" | wc -l)))
    else
      echo "  None found"
    fi
  fi

  # Dart
  if find "$search_dir" -maxdepth 5 -name "*.dart" 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo ""
    echo "[Dart] print/debugPrint:"
    local dart_debug
    dart_debug=$(grep -rn --include="*.dart" \
      -e '^[[:space:]]*print(' -e 'debugPrint(' \
      "$search_dir" 2>/dev/null | grep -v _test.dart | head -20 || true)
    if [[ -n "$dart_debug" ]]; then
      echo "$dart_debug"
      found=$((found + $(echo "$dart_debug" | wc -l)))
    else
      echo "  None found"
    fi
  fi

  # Go
  if find "$search_dir" -maxdepth 5 -name "*.go" 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo ""
    echo "[Go] fmt.Print/log.Print:"
    local go_debug
    go_debug=$(grep -rn --include="*.go" \
      -e 'fmt\.Print' -e 'log\.Print' \
      "$search_dir" 2>/dev/null | grep -v _test.go | head -20 || true)
    if [[ -n "$go_debug" ]]; then
      echo "$go_debug"
      found=$((found + $(echo "$go_debug" | wc -l)))
    else
      echo "  None found"
    fi
  fi

  echo ""
  echo "=== Debug code instances found: $found ==="
  [[ "$found" -eq 0 ]] && return 0 || return 1
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

# ─── init-config: .claude-auto-config.json 초기화 ───

cmd_init_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "OK: $CONFIG_FILE already exists"
    return 0
  fi

  cat > "$CONFIG_FILE" <<'ENDJSON'
{
  "quality": {
    "stubThreshold": 5,
    "assertionRatio": 0.7,
    "skipRatio": 0.2
  },
  "smoke": {
    "timeout": 15,
    "maxRetries": 3,
    "backoffSeconds": 5
  },
  "docs": {
    "maxSizeKB": 30
  }
}
ENDJSON
  echo "OK: $CONFIG_FILE initialized with defaults"
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

# ─── checkpoint: Git 체크포인트 생성/조회 ───

cmd_checkpoint() {
  local action="${1:?Usage: checkpoint create <name> | checkpoint list | checkpoint suggest-rollback}"
  shift

  case "$action" in
    create)
      local name="${1:?Usage: checkpoint create <name>}"
      # 태그명 안전화: 영숫자/하이픈/점만 허용, 선행/후행 점/하이픈 제거
      local safe_name
      safe_name=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/-/g; s/^[.-]*//; s/[.-]*$//' | head -c 50)
      [[ -z "$safe_name" ]] && safe_name="unnamed"
      local tag_name="auto-checkpoint-${safe_name}"

      # git 상태 확인
      if ! command -v git >/dev/null 2>&1; then
        echo "[checkpoint] SKIP (git not available)"
        return 0
      fi
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] SKIP (not a git repo)"
        return 0
      fi

      # git ref 규칙 검증
      if ! git check-ref-format "refs/tags/$tag_name" 2>/dev/null; then
        echo "[checkpoint] WARN: invalid tag name '$tag_name' — skipping"
        return 0
      fi

      # 커밋이 있어야 태그 가능
      local head_sha
      head_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
      if [[ -z "$head_sha" ]]; then
        echo "[checkpoint] SKIP (no commits yet)"
        return 0
      fi

      # 이미 같은 태그가 있으면 덮어쓰기
      if ! git tag -f "$tag_name" HEAD 2>&1; then
        echo "[checkpoint] WARN: git tag failed for '$tag_name'"
        return 0
      fi
      echo "OK: checkpoint '$tag_name' created at $head_sha"
      ;;

    list)
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] No git repo"
        return 0
      fi
      echo "=== Auto Checkpoints ==="
      git tag -l 'auto-checkpoint-*' --sort=-creatordate 2>/dev/null | head -20 || echo "(none)"
      ;;

    suggest-rollback)
      if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[checkpoint] No git repo"
        return 0
      fi
      local latest_tag
      latest_tag=$(git tag -l 'auto-checkpoint-*' --sort=-creatordate 2>/dev/null | head -1)
      if [[ -z "$latest_tag" ]]; then
        echo "[checkpoint] No checkpoints found — rollback not available"
        return 1
      fi
      local tag_sha
      tag_sha=$(git rev-parse "$latest_tag" 2>/dev/null)
      echo "=== Rollback Suggestion ==="
      echo "Latest checkpoint: $latest_tag ($tag_sha)"
      echo "Current HEAD:      $(git rev-parse --short HEAD)"
      echo ""
      echo "To rollback, run:  git reset --hard $latest_tag"
      echo "⚠ This is a destructive operation — confirm with user before proceeding."
      ;;

    *)
      die "checkpoint: unknown action '$action'. Use: create, list, suggest-rollback"
      ;;
  esac
}

# ─── docker-build-check: Dockerfile 빌드 검증 ───

cmd_docker_build_check() {
  echo "=== Docker Build Check ==="

  local dockerfile=""
  for candidate in "Dockerfile" "docker/Dockerfile" "Dockerfile.dev"; do
    [[ -f "$candidate" ]] && { dockerfile="$candidate"; break; }
  done

  if [[ -z "$dockerfile" ]]; then
    echo "[docker-build-check] SKIP (no Dockerfile found)"
    append_gate_history "docker-build-check" "skip" '{"reason":"no Dockerfile"}'
    return 0
  fi

  echo "[docker-build-check] Found: $dockerfile"

  # Dockerfile 기본 문법 검증 (FROM 존재)
  if ! grep -qE '^FROM\s+' "$dockerfile" 2>/dev/null; then
    echo "[docker-build-check] FAIL: no FROM instruction in $dockerfile"
    append_gate_history "docker-build-check" "fail" '{"reason":"no FROM instruction"}'
    echo "=== DOCKER BUILD CHECK: FAIL ==="
    return 1
  fi

  # docker 명령 존재 확인
  if ! command -v docker >/dev/null 2>&1; then
    echo "[docker-build-check] SKIP (docker not installed)"
    append_gate_history "docker-build-check" "skip" '{"reason":"docker not installed"}'
    return 0
  fi

  # .dockerignore 존재 확인
  if [[ ! -f ".dockerignore" ]]; then
    echo "[docker-build-check] WARN: .dockerignore not found — sensitive files (.env, keys) may be sent to build context"
  fi

  # 실제 빌드 시도 (타임아웃 120초)
  echo "[docker-build-check] Building $dockerfile..."
  local build_output build_exit
  build_output=$(timeout 120 docker build -f "$dockerfile" --no-cache --progress=plain . 2>&1) && build_exit=0 || build_exit=$?

  if [[ "$build_exit" -eq 0 ]]; then
    echo "[docker-build-check] Build successful"
    append_gate_history "docker-build-check" "pass" "$(jq -n --arg df "$dockerfile" '{"dockerfile":$df}')"
    echo "=== DOCKER BUILD CHECK: PASS ==="
    return 0
  elif [[ "$build_exit" -eq 124 ]]; then
    echo "[docker-build-check] Build timed out (120s)"
    echo "$build_output" | tail -20
    append_gate_history "docker-build-check" "fail" '{"reason":"timeout"}'
    echo "=== DOCKER BUILD CHECK: FAIL (timeout) ==="
    return 1
  else
    echo "[docker-build-check] Build failed (exit $build_exit)"
    echo "$build_output" | tail -30
    append_gate_history "docker-build-check" "fail" "{\"reason\":\"build error\",\"exitCode\":$build_exit}"
    echo "=== DOCKER BUILD CHECK: FAIL ==="
    return 1
  fi
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
