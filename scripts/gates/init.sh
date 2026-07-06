# gates/init.sh — progress JSON / 설정 파일 / Ralph Loop 파일 초기화 (init, init-ralph, init-config)

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
