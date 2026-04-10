#!/usr/bin/env bash
# shared-gate.sh — 모든 auto-complete-loop 스킬용 범용 품질 게이트 + 유틸리티
# 토큰 절약: Claude가 직접 하면 토큰 소비되는 반복 작업을 스크립트로 대체
#
# 서브커맨드:
#   init [--template <type>] [project] [requirement]  - progress JSON 초기화
#   init-ralph <promise> <progress_file> [max_iter]    - Ralph Loop 파일 생성
#   status [--progress-file <path>]                    - 현재 상태 요약 출력
#   update-step <step_name> <status> [--progress-file] - 단계 상태 전이
#   quality-gate [--progress-file <path>]              - 빌드/타입/린트/테스트 일괄 실행
#   e2e-gate [--progress-file <path>]                  - E2E 테스트 프레임워크 감지/실행
#   vuln-scan [--progress-file <path>]                  - 의존성 취약점 자동 검사 (언어별 감지)
#   secret-scan                                        - 시크릿 유출 스캔 (HARD_FAIL)
#   artifact-check                                     - 빌드 아티팩트 존재/크기 검증
#   smoke-check [--strict] [port] [timeout]             - 서버 기동 + 헬스체크 + 엔드포인트 검증 (--strict: FAIL 승격)
#   record-error --file <f> --type <t> --msg <m> [--level L0-L5] [--action "..."] - 에러 기록 + 에스컬레이션
#   check-tools                                         - codex/gemini CLI 존재 확인
#   find-debug-code [dir]                              - console.log/print/debugger 탐색
#   doc-consistency [docs_dir]                         - 문서 간 일관성 검사
#   doc-code-check [docs_dir]                          - 문서↔코드 매칭
#   design-polish-gate [--strict]                       - WCAG 체크 + 스크린샷 캡처 (--strict: FAIL 승격)
#   placeholder-check                                  - TODO/placeholder/FIXME 잔존 감지 (HARD_FAIL)
#   external-service-check                             - SPEC.md 기반 외부 서비스 SDK/config 존재 확인 (HARD_FAIL)
#   service-test-check                                 - 백엔드 서비스/라우트 통합 테스트 존재 확인 (HARD_FAIL)
#   integration-smoke                                  - 프론트↔백 연동 검증: API URL, CORS, 서버 기동 (HARD_FAIL)
#   implementation-depth [--threshold N] [--dir D]       - stub/빈 함수 탐지 (SOFT gate, 임계값 기반)
#   test-quality                                        - 테스트 assertion 비율/skip 비율/US 커버리지 (SOFT gate)
#   page-render-check [--port N] [--strict]             - 프론트엔드 페이지 렌더링 검증 (빈 페이지/console.error/404 탐지)
#   functional-flow                                     - 프로젝트 유형별 smoke 스크립트 실행 (api/frontend/fullstack/library)
#   recover                                            - 복구/재개 정보 자동 출력 (handoff + next steps)
#   handoff-update --next-steps <s> [--phase <p>] ...  - Handoff 필드 일괄 갱신

set -euo pipefail

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

# 안전한 jq 인플레이스 업데이트 (temp 파일 자동 정리)
jq_inplace() {
  local file="$1"; shift
  local tmp
  tmp=$(mktemp)
  if jq "$@" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    die "jq update failed for $file"
  fi
}

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

  # gateHistory가 없으면 추가
  local has_history
  has_history=$(jq 'has("gateHistory")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  if [[ "$has_history" != "true" ]]; then
    jq_inplace "$PROGRESS_FILE" '.gateHistory = []'
  fi

  local current_phase ts
  current_phase=$(jq -r '.currentPhase // "unknown"' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
  ts=$(timestamp)

  jq_inplace "$PROGRESS_FILE" \
    --arg g "$gate" --arg r "$result" --arg p "$current_phase" --arg t "$ts" --argjson d "$details" '
    .gateHistory = ((.gateHistory + [{"gate":$g,"phase":$p,"result":$r,"ts":$t,"details":$d}])[-100:])
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
  "schemaVersion": 6,
  "project": $safe_project,
  "userRequirement": $safe_requirement,
  "status": "in_progress",
  "currentPhase": "phase_0",
  "gateHistory": [],
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

  # steps 배열에서 해당 step 상태 업데이트 + top-level 갱신
  jq_inplace "$PROGRESS_FILE" --arg name "$step_name" --arg status "$new_status" '
    (.steps[] | select(.name == $name)).status = $status
    | if $status == "in_progress" then
        (if has("currentPhase") then .currentPhase = $name else . end)
        | (if has("currentStep") then .currentStep = $name else . end)
      else . end
    | if has("handoff") and (.handoff | has("currentPhase")) then
        .handoff.currentPhase = (.currentPhase // null)
      else . end
    | .status = (if ([.steps[].status] | all(. == "completed")) then "completed" else "in_progress" end)
  '

  echo "OK: $step_name -> $new_status"
}

# ─── quality-gate: 빌드/타입/린트/테스트 일괄 실행 ───

cmd_quality_gate() {
  require_jq

  echo "=== Quality Gate ==="

  # 프로젝트 유형 자동 감지 + 명령어 결정
  local build_cmd="" type_cmd="" lint_cmd="" test_cmd=""

  if [[ -f "package.json" ]]; then
    local pm="npm"
    [[ -f "pnpm-lock.yaml" ]] && pm="pnpm"
    [[ -f "yarn.lock" ]] && pm="yarn"
    [[ -f "bun.lockb" ]] && pm="bun"

    if jq -e '.scripts.build' package.json >/dev/null 2>&1; then
      build_cmd="$pm run build"
    fi
    if jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
      type_cmd="$pm run typecheck"
    elif jq -e '.scripts["type-check"]' package.json >/dev/null 2>&1; then
      type_cmd="$pm run type-check"
    elif command -v tsc >/dev/null 2>&1 && [[ -f "tsconfig.json" ]]; then
      type_cmd="npx tsc --noEmit"
    fi
    if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
      lint_cmd="$pm run lint"
    fi
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      test_cmd="$pm run test"
    elif jq -e '.scripts["test:run"]' package.json >/dev/null 2>&1; then
      test_cmd="$pm run test:run"
    fi
  elif [[ -f "pubspec.yaml" ]]; then
    if command -v flutter >/dev/null 2>&1; then
      build_cmd="flutter build apk --debug 2>&1"
      type_cmd="dart analyze"
      lint_cmd=":"
      test_cmd="flutter test"
    else
      build_cmd="dart compile exe lib/main.dart 2>/dev/null"
      type_cmd="dart analyze"
      lint_cmd=":"
      test_cmd="dart test"
    fi
  elif [[ -f "go.mod" ]]; then
    build_cmd="go build ./..."
    type_cmd="go vet ./..."
    lint_cmd="golangci-lint run 2>/dev/null || go vet ./..."
    test_cmd="go test ./..."
  elif [[ -f "Cargo.toml" ]]; then
    build_cmd="cargo build"
    type_cmd="cargo check"
    lint_cmd="cargo clippy 2>/dev/null || cargo check"
    test_cmd="cargo test"
  elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    if [[ -f "pyproject.toml" ]] && grep -q "ruff" pyproject.toml 2>/dev/null; then
      lint_cmd="ruff check ."
    elif command -v flake8 >/dev/null 2>&1; then
      lint_cmd="flake8 ."
    fi
    if command -v mypy >/dev/null 2>&1; then
      type_cmd="mypy ."
    fi
    if command -v pytest >/dev/null 2>&1; then
      test_cmd="pytest"
    fi
  fi

  # 환경 정보 수집
  local env_node env_npm env_os env_cwd
  env_node=$(node --version 2>/dev/null || echo "N/A")
  env_npm=$(npm --version 2>/dev/null || echo "N/A")
  env_os=$(uname -s 2>/dev/null || echo "unknown")
  env_cwd=$(pwd)

  # Flutter/Dart/Go/Rust 버전도 수집 (해당 시)
  local env_extra=""
  if [[ -f "pubspec.yaml" ]]; then
    local dart_ver flutter_ver
    dart_ver=$(dart --version 2>&1 | head -1 || echo "N/A")
    flutter_ver=$(flutter --version 2>&1 | head -1 || echo "N/A")
    env_extra=", \"dart\": $(jq -Rn --arg v "$dart_ver" '$v'), \"flutter\": $(jq -Rn --arg v "$flutter_ver" '$v')"
  elif [[ -f "go.mod" ]]; then
    local go_ver
    go_ver=$(go version 2>/dev/null | awk '{print $3}' || echo "N/A")
    env_extra=", \"go\": $(jq -Rn --arg v "$go_ver" '$v')"
  elif [[ -f "Cargo.toml" ]]; then
    local rust_ver
    rust_ver=$(rustc --version 2>/dev/null || echo "N/A")
    env_extra=", \"rust\": $(jq -Rn --arg v "$rust_ver" '$v')"
  fi

  # 결과 수집
  local ts
  ts=$(timestamp)
  local results="{\"timestamp\": \"$ts\", \"environment\": {\"node\": $(jq -Rn --arg v "$env_node" '$v'), \"npm\": $(jq -Rn --arg v "$env_npm" '$v'), \"os\": $(jq -Rn --arg v "$env_os" '$v'), \"cwd\": $(jq -Rn --arg v "$env_cwd" '$v')${env_extra}}"
  local all_pass=true
  local gate_summary=""
  local any_ran=false

  run_gate() {
    local name="$1" cmd="$2"
    if [[ -z "$cmd" ]]; then
      echo "[$name] SKIP (no command detected)"
      results="$results, \"$name\": {\"command\": null, \"exitCode\": null, \"summary\": \"skipped\"}"
      return
    fi
    any_ran=true

    echo "[$name] Running: $cmd"
    local output exit_code
    output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      echo "[$name] PASS (exit 0)"
      results="$results, \"$name\": {\"command\": $(jq -Rn --arg c "$cmd" '$c'), \"exitCode\": 0, \"summary\": \"pass\"}"
    else
      echo "[$name] FAIL (exit $exit_code)"
      echo "$output" | tail -5
      all_pass=false
      local summary
      summary=$(echo "$output" | tail -1 | head -c 200)
      results="$results, \"$name\": {\"command\": $(jq -Rn --arg c "$cmd" '$c'), \"exitCode\": $exit_code, \"summary\": $(jq -Rn --arg s "$summary" '$s')}"
      gate_summary="${gate_summary}$name FAIL; "
    fi
  }

  run_gate "build" "$build_cmd"
  run_gate "typeCheck" "$type_cmd"
  run_gate "lint" "$lint_cmd"
  run_gate "test" "$test_cmd"

  results="$results}"

  # verification.json 기록 (기존 데이터 보존, qualityGate 키만 merge)
  local parsed_results
  parsed_results=$(echo "$results" | jq '.')
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson qg "$parsed_results" '. * {"build": $qg.build, "typeCheck": $qg.typeCheck, "lint": $qg.lint, "test": $qg.test}'
  else
    echo "$parsed_results" > "$VERIFICATION_FILE"
  fi
  echo ""
  echo "Results saved to $VERIFICATION_FILE"

  # progress 파일 DoD 업데이트 (존재하는 경우)
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    local has_dod
    has_dod=$(jq 'has("dod")' "$PROGRESS_FILE")
    if [[ "$has_dod" == "true" ]]; then
      local build_exit test_exit type_exit lint_exit
      build_exit=$(echo "$results" | jq '.build.exitCode // null')
      test_exit=$(echo "$results" | jq '.test.exitCode // null')
      type_exit=$(echo "$results" | jq '.typeCheck.exitCode // null')
      lint_exit=$(echo "$results" | jq '.lint.exitCode // null')

      # build_pass / test_pass 필드가 존재하는 경우만 업데이트
      jq_inplace "$PROGRESS_FILE" --argjson be "$build_exit" --argjson te "$test_exit" --argjson tye "$type_exit" --argjson le "$lint_exit" --arg ev "quality-gate at $(timestamp)" '
        # null (skipped)은 neutral — 기존 checked 값 유지
        (if .dod | has("build_pass") then
          .dod.build_pass.checked = (if $be == null then .dod.build_pass.checked else ($be == 0) end)
          | .dod.build_pass.evidence = (if $be == null then .dod.build_pass.evidence elif $be == 0 then "build pass " + $ev else "build fail " + $ev end)
        else . end)
        | (if .dod | has("test_pass") then
          .dod.test_pass.checked = (if $te == null then .dod.test_pass.checked else ($te == 0) end)
          | .dod.test_pass.evidence = (if $te == null then .dod.test_pass.evidence elif $te == 0 then "test pass " + $ev else "test fail " + $ev end)
        else . end)
        | (if has("consistencyChecks") then
          # fail-closed: 모든 게이트가 null(스킵)이면 checked=false 유지
          (if ($be == null and $te == null and $tye == null and $le == null) then
            .consistencyChecks.code_quality.checked = false
            | .consistencyChecks.code_quality.evidence = "all gates skipped " + $ev
          else
            .consistencyChecks.code_quality.checked = (($be == 0 or $be == null) and ($te == 0 or $te == null) and ($tye == 0 or $tye == null) and ($le == 0 or $le == null))
            | .consistencyChecks.code_quality.evidence = $ev
          end)
        else . end)
      '
    fi
  fi

  # ─── Health Score 산출 (0-100) ───
  local health_score=0
  local score_build=0 score_test=0 score_lint=0 score_type=0

  # 카테고리별 가중 점수: Build 25%, Test 30%, Lint 20%, TypeCheck 25%
  local build_exit_val test_exit_val lint_exit_val type_exit_val
  build_exit_val=$(echo "$results" | jq '.build.exitCode // null' 2>/dev/null)
  test_exit_val=$(echo "$results" | jq '.test.exitCode // null' 2>/dev/null)
  lint_exit_val=$(echo "$results" | jq '.lint.exitCode // null' 2>/dev/null)
  type_exit_val=$(echo "$results" | jq '.typeCheck.exitCode // null' 2>/dev/null)

  # 실행된 카테고리만 가중치에 포함 (스킵된 카테고리는 제외 후 재정규화)
  local total_weight=0
  local earned_weight=0

  if [[ "$build_exit_val" != "null" ]]; then
    total_weight=$((total_weight + 25))
    [[ "$build_exit_val" == "0" ]] && earned_weight=$((earned_weight + 25))
  fi
  if [[ "$test_exit_val" != "null" ]]; then
    total_weight=$((total_weight + 30))
    [[ "$test_exit_val" == "0" ]] && earned_weight=$((earned_weight + 30))
  fi
  if [[ "$lint_exit_val" != "null" ]]; then
    total_weight=$((total_weight + 20))
    [[ "$lint_exit_val" == "0" ]] && earned_weight=$((earned_weight + 20))
  fi
  if [[ "$type_exit_val" != "null" ]]; then
    total_weight=$((total_weight + 25))
    [[ "$type_exit_val" == "0" ]] && earned_weight=$((earned_weight + 25))
  fi

  # 재정규화: 실행된 카테고리 기준 100점 만점으로 환산
  if [[ "$total_weight" -gt 0 ]]; then
    health_score=$(( (earned_weight * 100) / total_weight ))
  else
    health_score=0
  fi
  local coverage=$(( (total_weight * 100) / 100 ))

  echo ""
  echo "Health Score: $health_score / 100 (coverage: ${coverage}% of gates executed)"

  # Regression Baseline 비교
  local baseline_file=".claude-quality-baseline.json"
  if [[ -f "$baseline_file" ]]; then
    local prev_score
    prev_score=$(jq '.healthScore // 0' "$baseline_file" 2>/dev/null || echo "0")
    local diff=$((health_score - prev_score))
    if [[ $diff -lt 0 ]]; then
      echo "WARNING: Health score REGRESSION: $prev_score → $health_score (${diff})"
    elif [[ $diff -gt 0 ]]; then
      echo "Health score IMPROVED: $prev_score → $health_score (+${diff})"
    else
      echo "Health score UNCHANGED: $health_score"
    fi
  fi

  # 개별 카테고리 점수 (baseline 호환)
  local s_bld=0 s_tst=0 s_lnt=0 s_typ=0
  [[ "$build_exit_val" != "null" && "$build_exit_val" == "0" ]] && s_bld=25
  [[ "$test_exit_val" != "null" && "$test_exit_val" == "0" ]] && s_tst=30
  [[ "$lint_exit_val" != "null" && "$lint_exit_val" == "0" ]] && s_lnt=20
  [[ "$type_exit_val" != "null" && "$type_exit_val" == "0" ]] && s_typ=25

  # Baseline 저장
  jq -n \
    --argjson score "$health_score" \
    --arg ts "$ts" \
    --argjson bld "$s_bld" \
    --argjson tst "$s_tst" \
    --argjson lnt "$s_lnt" \
    --argjson typ "$s_typ" \
    --argjson cov "$coverage" \
    '{"healthScore": $score, "timestamp": $ts, "coverage": $cov, "breakdown": {"build": $bld, "test": $tst, "lint": $lnt, "typeCheck": $typ}}' \
    > "$baseline_file"

  # verification.json에 health score 추가
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson hs "$health_score" '.healthScore = $hs'
  fi

  # gateHistory 기록
  local gh_result="pass"
  [[ "$all_pass" != "true" ]] && gh_result="fail"
  [[ "$any_ran" == "false" ]] && gh_result="skip"
  local gh_details
  gh_details=$(jq -n --argjson hs "$health_score" --arg gs "${gate_summary:-none}" '{"healthScore":$hs,"failedGates":$gs}')
  append_gate_history "quality-gate" "$gh_result" "$gh_details"

  if [[ "$any_ran" == "false" ]]; then
    echo "=== WARNING: ALL GATES SKIPPED (no project type detected) ==="
    return 1
  elif [[ "$all_pass" == "true" ]]; then
    echo "=== ALL GATES PASSED ==="
    return 0
  else
    echo "=== GATE FAILED: ${gate_summary} ==="
    return 1
  fi
}

# ─── vuln-scan: 의존성 취약점 자동 검사 ───

cmd_vuln_scan() {
  echo "=== Vulnerability Scan ==="
  require_jq

  local found_critical=0
  local found_high=0
  local total_vulns=0
  local scan_ran=false
  local scan_details=""

  # Node.js (npm/yarn/pnpm)
  if [[ -f "package.json" ]]; then
    scan_ran=true
    echo "[vuln-scan] Detected: Node.js"
    local npm_output npm_exit
    npm_output=$(npm audit --json 2>/dev/null) && npm_exit=0 || npm_exit=$?
    if [[ $npm_exit -ne 0 ]] && [[ -n "$npm_output" ]]; then
      # JSON 파싱 가능 여부 검증
      if echo "$npm_output" | jq empty 2>/dev/null; then
        local npm_critical npm_high
        npm_critical=$(echo "$npm_output" | jq '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo "0")
        npm_high=$(echo "$npm_output" | jq '.metadata.vulnerabilities.high // 0' 2>/dev/null || echo "0")
        local npm_total
        npm_total=$(echo "$npm_output" | jq '.metadata.vulnerabilities.total // 0' 2>/dev/null || echo "0")
        found_critical=$((found_critical + npm_critical))
        found_high=$((found_high + npm_high))
        total_vulns=$((total_vulns + npm_total))
        scan_details="${scan_details}npm: critical=$npm_critical, high=$npm_high, total=$npm_total; "
        echo "[vuln-scan] npm audit: critical=$npm_critical, high=$npm_high, total=$npm_total"
      else
        # JSON 파싱 불가 — npm audit 비정상 실패
        found_high=$((found_high + 1))
        scan_details="${scan_details}npm: audit output not parseable (scan error); "
        echo "[vuln-scan] npm audit: ERROR (output not parseable, treating as HIGH)"
      fi
    elif [[ $npm_exit -ne 0 ]]; then
      # npm audit 실행 실패 (출력 없음)
      found_high=$((found_high + 1))
      scan_details="${scan_details}npm: audit failed (no output); "
      echo "[vuln-scan] npm audit: ERROR (execution failed, treating as HIGH)"
    else
      echo "[vuln-scan] npm audit: PASS"
    fi
  fi

  # Python (pip-audit)
  if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    if command -v pip-audit >/dev/null 2>&1; then
      scan_ran=true
      echo "[vuln-scan] Detected: Python (pip-audit)"
      local pip_output pip_exit
      pip_output=$(pip-audit --format json 2>/dev/null) && pip_exit=0 || pip_exit=$?
      if [[ $pip_exit -ne 0 ]]; then
        local pip_count
        pip_count=$(echo "$pip_output" | jq 'length' 2>/dev/null)
        if [[ -z "$pip_count" ]] || ! [[ "$pip_count" =~ ^[0-9]+$ ]]; then
          # 파싱 실패: fail-closed (HIGH 처리)
          found_high=$((found_high + 1))
          scan_details="${scan_details}pip-audit: parse failed (treating as HIGH); "
          echo "[vuln-scan] pip-audit: ERROR (output not parseable, treating as HIGH)"
        else
          total_vulns=$((total_vulns + pip_count))
          # pip-audit doesn't classify by severity easily; count all as high
          found_high=$((found_high + pip_count))
          scan_details="${scan_details}pip-audit: $pip_count vulnerabilities; "
          echo "[vuln-scan] pip-audit: $pip_count vulnerabilities found"
        fi
      else
        echo "[vuln-scan] pip-audit: PASS"
      fi
    fi
  fi

  # Go (govulncheck)
  if [[ -f "go.mod" ]]; then
    if command -v govulncheck >/dev/null 2>&1; then
      scan_ran=true
      echo "[vuln-scan] Detected: Go (govulncheck)"
      local go_output go_exit
      go_output=$(govulncheck ./... 2>&1) && go_exit=0 || go_exit=$?
      if [[ $go_exit -ne 0 ]]; then
        local go_count
        go_count=$(echo "$go_output" | grep -c "Vulnerability" 2>/dev/null || echo "")
        if [[ -z "$go_count" ]] || ! [[ "$go_count" =~ ^[0-9]+$ ]]; then
          found_high=$((found_high + 1))
          scan_details="${scan_details}govulncheck: parse failed (treating as HIGH); "
          echo "[vuln-scan] govulncheck: ERROR (output not parseable, treating as HIGH)"
        else
          total_vulns=$((total_vulns + go_count))
          found_high=$((found_high + go_count))
          scan_details="${scan_details}govulncheck: $go_count vulnerabilities; "
          echo "[vuln-scan] govulncheck: $go_count vulnerabilities found"
        fi
      else
        echo "[vuln-scan] govulncheck: PASS"
      fi
    fi
  fi

  # Flutter/Dart (pub outdated)
  if [[ -f "pubspec.yaml" ]]; then
    scan_ran=true
    echo "[vuln-scan] Detected: Dart/Flutter"
    local dart_cmd="dart"
    command -v flutter >/dev/null 2>&1 && dart_cmd="flutter"
    local pub_output
    pub_output=$($dart_cmd pub outdated 2>&1) || true
    # Count major version behind as potential risk
    local outdated_count
    outdated_count=$(echo "$pub_output" | grep -c "resolvable" || echo "0")
    if [[ "$outdated_count" -gt 0 ]]; then
      echo "[vuln-scan] pub outdated: $outdated_count packages have newer versions"
      scan_details="${scan_details}pub outdated: $outdated_count packages; "
    else
      echo "[vuln-scan] pub outdated: all up to date"
    fi
  fi

  # Rust (cargo audit)
  if [[ -f "Cargo.toml" ]]; then
    if command -v cargo-audit >/dev/null 2>&1; then
      scan_ran=true
      echo "[vuln-scan] Detected: Rust (cargo audit)"
      local cargo_output cargo_exit
      cargo_output=$(cargo audit --json 2>/dev/null) && cargo_exit=0 || cargo_exit=$?
      if [[ $cargo_exit -ne 0 ]]; then
        local cargo_count
        cargo_count=$(echo "$cargo_output" | jq '.vulnerabilities.found // 0' 2>/dev/null)
        if [[ -z "$cargo_count" ]] || ! [[ "$cargo_count" =~ ^[0-9]+$ ]]; then
          found_high=$((found_high + 1))
          scan_details="${scan_details}cargo-audit: parse failed (treating as HIGH); "
          echo "[vuln-scan] cargo audit: ERROR (output not parseable, treating as HIGH)"
        else
          total_vulns=$((total_vulns + cargo_count))
          found_high=$((found_high + cargo_count))
          scan_details="${scan_details}cargo-audit: $cargo_count vulnerabilities; "
          echo "[vuln-scan] cargo audit: $cargo_count vulnerabilities found"
        fi
      else
        echo "[vuln-scan] cargo audit: PASS"
      fi
    fi
  fi

  # verification.json에 기록
  local ts
  ts=$(timestamp)
  local scan_result
  if [[ "$scan_ran" == "false" ]]; then
    scan_result="skipped"
  elif [[ "$found_critical" -gt 0 ]]; then
    scan_result="hard_fail"
  elif [[ "$found_high" -gt 0 ]]; then
    scan_result="soft_fail"
  else
    scan_result="pass"
  fi

  local vuln_json
  vuln_json=$(jq -n \
    --arg ts "$ts" \
    --argjson critical "$found_critical" \
    --argjson high "$found_high" \
    --argjson total "$total_vulns" \
    --arg result "$scan_result" \
    --arg details "$scan_details" \
    '{"vulnScan": {"timestamp": $ts, "critical": $critical, "high": $high, "total": $total, "result": $result, "details": $details}}')

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson vs "$(echo "$vuln_json" | jq '.vulnScan')" '.vulnScan = $vs'
  else
    echo "$vuln_json" > "$VERIFICATION_FILE"
  fi

  if [[ "$scan_ran" == "false" ]]; then
    echo "=== VULN SCAN: SKIP (no supported package manager detected) ==="
    append_gate_history "vuln-scan" "skip" '{"reason":"no supported package manager"}'
    return 0
  elif [[ "$found_critical" -gt 0 ]]; then
    echo "=== VULN SCAN HARD_FAIL: $found_critical CRITICAL vulnerability(ies) ==="
    echo "ACTION: Fix critical vulnerabilities before proceeding."
    append_gate_history "vuln-scan" "fail" "{\"critical\":$found_critical,\"high\":$found_high,\"total\":$total_vulns,\"result\":\"hard_fail\"}"
    exit 1
  elif [[ "$found_high" -gt 0 ]]; then
    echo "=== VULN SCAN SOFT_FAIL: $found_high HIGH vulnerability(ies) (warning) ==="
    append_gate_history "vuln-scan" "fail" "{\"critical\":$found_critical,\"high\":$found_high,\"total\":$total_vulns,\"result\":\"soft_fail\"}"
    return 1
  else
    echo "=== VULN SCAN PASSED ==="
    append_gate_history "vuln-scan" "pass" "{\"critical\":0,\"high\":0,\"total\":$total_vulns}"
    return 0
  fi
}

# ─── secret-scan: 시크릿 유출 스캔 (HARD_FAIL) ───

cmd_secret_scan() {
  echo "=== Secret Scan ==="
  local found=0
  local patterns=(
    # AWS
    'AKIA[0-9A-Z]{16}'
    # OpenAI
    'sk-[a-zA-Z0-9]{20,}'
    # GitHub PAT
    'ghp_[a-zA-Z0-9]{36}'
    # GitLab PAT
    'glpat-[a-zA-Z0-9\-]{20,}'
    # Private Key
    '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
    # Slack
    'xox[bps]-[a-zA-Z0-9\-]+'
    # JWT
    'eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.'
    # Azure
    'AccountKey=[a-zA-Z0-9+/=]{40,}'
    # GCP service account
    '"type"[[:space:]]*:[[:space:]]*"service_account"'
    # Database URL with credentials
    '(mysql|postgres|postgresql|mongodb|redis):\/\/[^:]+:[^@]+@'
    # Twilio
    'SK[0-9a-fA-F]{32}'
    # SendGrid
    'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'
    # Stripe
    '(sk|pk)_(test|live)_[a-zA-Z0-9]{20,}'
    # Generic password/secret assignment (single-quote safe for cross-platform grep)
    '(password|secret|api_key|apikey|access_token)[[:space:]]*[=:][[:space:]]*["'"'"'][^[:space:]"'"'"']{8,}'
  )

  # verification.json 기록 헬퍼
  _record_secret_scan() {
    local scan_found=$1 scan_result=$2 scan_tool=$3
    require_jq
    local ts
    ts=$(timestamp)
    if [[ -f "$VERIFICATION_FILE" ]]; then
      jq_inplace "$VERIFICATION_FILE" \
        --arg ts "$ts" --argjson count "$scan_found" --arg result "$scan_result" --arg tool "$scan_tool" \
        '.secretScan = {"timestamp": $ts, "found": $count, "result": $result, "tool": $tool}'
    else
      jq -n --arg ts "$ts" --argjson count "$scan_found" --arg result "$scan_result" --arg tool "$scan_tool" \
        '{"secretScan": {"timestamp": $ts, "found": $count, "result": $result, "tool": $tool}}' > "$VERIFICATION_FILE"
    fi
  }

  # 외부 도구가 설치된 경우 우선 사용
  if command -v gitleaks >/dev/null 2>&1; then
    echo "[secret-scan] Using gitleaks (external tool)..."
    local gl_output
    local gl_exit
    gl_output=$(gitleaks detect --source . --no-git --report-format json 2>&1) && gl_exit=0 || gl_exit=$?
    if [[ $gl_exit -ne 0 ]]; then
      local gl_count
      gl_count=$(echo "$gl_output" | jq 'length' 2>/dev/null || echo "0")
      _record_secret_scan "$gl_count" "fail" "gitleaks"
      echo "=== SECRET SCAN FAILED (gitleaks): $gl_count potential secret(s) found ==="
      append_gate_history "secret-scan" "fail" "{\"found\":\"$gl_count\",\"tool\":\"gitleaks\"}"
      exit 1
    else
      _record_secret_scan 0 "pass" "gitleaks"
      echo "[secret-scan] PASS (gitleaks: no secrets detected)"
      echo "=== SECRET SCAN PASSED ==="
      append_gate_history "secret-scan" "pass" '{"found":0,"tool":"gitleaks"}'
      return 0
    fi
  elif command -v trufflehog >/dev/null 2>&1; then
    echo "[secret-scan] Using trufflehog (external tool)..."
    local th_output
    local th_exit
    th_output=$(trufflehog filesystem . --json 2>&1) && th_exit=0 || th_exit=$?
    if [[ $th_exit -ne 0 ]] && { [[ -z "$th_output" ]] || [[ "$th_output" == "[]" ]]; }; then
      # trufflehog 실행 자체가 실패 (크래시/권한 등) — fail-open 방지
      _record_secret_scan 0 "error" "trufflehog"
      echo "=== SECRET SCAN ERROR (trufflehog): tool execution failed (exit=$th_exit) ==="
      append_gate_history "secret-scan" "fail" '{"found":"tool error","tool":"trufflehog"}'
      exit 1
    elif [[ -n "$th_output" ]] && [[ "$th_output" != "[]" ]]; then
      _record_secret_scan 1 "fail" "trufflehog"
      echo "=== SECRET SCAN FAILED (trufflehog): potential secrets found ==="
      append_gate_history "secret-scan" "fail" '{"found":"secrets detected","tool":"trufflehog"}'
      exit 1
    else
      _record_secret_scan 0 "pass" "trufflehog"
      echo "[secret-scan] PASS (trufflehog: no secrets detected)"
      echo "=== SECRET SCAN PASSED ==="
      append_gate_history "secret-scan" "pass" '{"found":0,"tool":"trufflehog"}'
      return 0
    fi
  fi

  # Fallback: 내장 regex 패턴 스캔
  # 루트 재귀 스캔 (exclude로 불필요 디렉토리 제외)
  # .env* 파일도 루트 스캔에 포함됨 (.env.example만 exclude)
  local scan_dirs=(".")

  # 제외 패턴 (불필요 디렉토리 + 바이너리/벤더 파일)
  local exclude_args=(
    --exclude-dir=node_modules
    --exclude-dir=dist
    --exclude-dir=build
    --exclude-dir=.git
    --exclude-dir=.next
    --exclude-dir=__pycache__
    --exclude-dir=.dart_tool
    --exclude-dir=.pub-cache
    --exclude-dir=vendor
    --exclude-dir=coverage
    --exclude='*.lock'
    --exclude='*.min.js'
    --exclude='*.min.css'
    --exclude='.env.example'
    --exclude='*.map'
    --exclude='*.png'
    --exclude='*.jpg'
    --exclude='*.woff'
    --exclude='*.woff2'
    --exclude='*.ttf'
  )

  local details=""

  for pattern in "${patterns[@]}"; do
    local matches=""
    # 루트 재귀 스캔 (.env* 포함, .env.example 제외)
    matches=$(grep -rn -E "$pattern" "${exclude_args[@]}" "${scan_dirs[@]}" 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
      local match_count
      match_count=$(echo "$matches" | wc -l)
      found=$((found + match_count))
      local masked_matches
      masked_matches=$(echo "$matches" | sed 's/\(:[0-9]*:\).*$/\1 [SECRET VALUE MASKED]/')
      details="${details}Pattern: $pattern
$masked_matches
"
    fi
  done

  # verification.json에 기록
  require_jq
  local ts
  ts=$(timestamp)
  local scan_result
  if [[ "$found" -gt 0 ]]; then
    scan_result="fail"
  else
    scan_result="pass"
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --argjson count "$found" --arg result "$scan_result" \
      '.secretScan = {"timestamp": $ts, "found": $count, "result": $result}'
  else
    jq -n --arg ts "$ts" --argjson count "$found" --arg result "$scan_result" \
      '{"secretScan": {"timestamp": $ts, "found": $count, "result": $result}}' > "$VERIFICATION_FILE"
  fi

  if [[ "$found" -gt 0 ]]; then
    echo ""
    echo "$details"
    echo "=== SECRET SCAN FAILED: $found potential secret(s) found ==="
    echo "ACTION: Remove secrets and use environment variables instead."
    append_gate_history "secret-scan" "fail" "{\"found\":$found}"
    exit 1
  else
    echo "[secret-scan] PASS (no secrets detected)"
    echo "=== SECRET SCAN PASSED ==="
    append_gate_history "secret-scan" "pass" '{"found":0}'
    return 0
  fi
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

# ─── 서버 시작 공통 헬퍼 ───

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
  eval "$start_cmd" > "$SERVER_LOG" 2>&1 &
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

# ─── smoke-check: 서버 기동 + 헬스체크 ───

cmd_smoke_check() {
  local port="3000"
  local timeout
  timeout=$(config_get '.smoke.timeout' '15')
  local max_retries
  max_retries=$(config_get '.smoke.maxRetries' '1')
  local backoff
  backoff=$(config_get '.smoke.backoffSeconds' '5')
  local strict=false

  # 플래그 파싱 (위치 무관)
  local args=()
  local i=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) strict=true; shift ;;
      --max-retries) max_retries="${2:?--max-retries requires a number}"; shift 2 ;;
      --backoff) backoff="${2:?--backoff requires seconds}"; shift 2 ;;
      --timeout) timeout="${2:?--timeout requires seconds}"; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  port="${args[0]:-$port}"
  timeout="${args[1]:-$timeout}"

  # 입력 검증: port/timeout은 반드시 정수 + 범위 검증
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    die "smoke-check: port must be a positive integer, got '$port'"
  fi
  if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
    die "smoke-check: port must be 1-65535, got '$port'"
  fi
  if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
    die "smoke-check: timeout must be a positive integer, got '$timeout'"
  fi
  if [[ "$timeout" -lt 1 ]]; then
    die "smoke-check: timeout must be >= 1, got '$timeout'"
  fi

  # 입력 검증: max_retries/backoff
  if ! [[ "$max_retries" =~ ^[0-9]+$ ]]; then
    die "smoke-check: max_retries must be a non-negative integer, got '$max_retries'"
  fi
  if ! [[ "$backoff" =~ ^[0-9]+$ ]]; then
    die "smoke-check: backoff must be a non-negative integer, got '$backoff'"
  fi

  local strict_label=""
  [[ "$strict" == "true" ]] && strict_label=" [STRICT]"
  echo "=== Smoke Check (port: $port, timeout: ${timeout}s, retries: $max_retries, backoff: ${backoff}s)${strict_label} ==="
  require_jq

  # ─── smoke 스크립트 우선 실행 (tests/api-smoke.sh 등 존재 시) ───
  local smoke_script=""
  for sf in tests/api-smoke.sh tests/smoke-test.sh tests/ui-smoke.sh tests/lib-smoke.sh; do
    if [[ -f "$sf" ]]; then
      smoke_script="$sf"
      break
    fi
  done

  if [[ -n "$smoke_script" ]]; then
    echo "[smoke-check] Found smoke script: $smoke_script — running with retries"
    [[ ! -x "$smoke_script" ]] && chmod +x "$smoke_script" 2>/dev/null || true

    local smoke_output smoke_exit attempts_made=0
    local attempt=1
    while [[ $attempt -le $((max_retries + 1)) ]]; do
      if [[ $attempt -gt 1 ]]; then
        echo "[smoke-check] Retry $((attempt - 1))/$max_retries (backoff: ${backoff}s)..."
        sleep "$backoff"
      fi

      attempts_made=$attempt
      smoke_output=$(bash "$smoke_script" 2>&1) && smoke_exit=0 || smoke_exit=$?

      if [[ $smoke_exit -eq 0 ]]; then
        break
      fi
      attempt=$((attempt + 1))
    done

    echo "$smoke_output"

    local ts
    ts=$(timestamp)
    if [[ $smoke_exit -eq 0 ]]; then
      echo "[smoke-check] Smoke script PASS (attempt $attempts_made)"
      if [[ -f "$VERIFICATION_FILE" ]]; then
        jq_inplace "$VERIFICATION_FILE" --arg ts "$ts" --arg sf "$smoke_script" \
          '.smokeCheck = {"timestamp": $ts, "result": "pass", "method": "smoke-script", "script": $sf}'
      fi
      append_gate_history "smoke-check" "pass" "{\"method\":\"smoke-script\",\"script\":\"$smoke_script\",\"attempts\":$attempts_made}"
      echo "=== SMOKE CHECK: PASS (via $smoke_script) ==="
      return 0
    else
      echo "[smoke-check] Smoke script FAIL after $max_retries retries (exit $smoke_exit)"
      if [[ -f "$VERIFICATION_FILE" ]]; then
        jq_inplace "$VERIFICATION_FILE" --arg ts "$ts" --arg sf "$smoke_script" --argjson ec "$smoke_exit" \
          '.smokeCheck = {"timestamp": $ts, "result": "fail", "method": "smoke-script", "script": $sf, "exitCode": $ec}'
      fi
      append_gate_history "smoke-check" "fail" "{\"method\":\"smoke-script\",\"script\":\"$smoke_script\",\"exitCode\":$smoke_exit,\"attempts\":$attempts_made}"
      if [[ "$strict" == "true" ]]; then
        echo "=== SMOKE CHECK: FAIL (strict mode) ==="
        return 1
      else
        echo "=== SMOKE CHECK: SOFT_FAIL (falling through to server check) ==="
      fi
    fi
  fi

  # smoke 스크립트 실패 상태 보존 (fallback 판정에 사용)
  local smoke_script_failed=false
  if [[ -n "$smoke_script" ]] && [[ "${smoke_exit:-1}" -ne 0 ]]; then
    smoke_script_failed=true
  fi

  # ─── 기존 서버 기동 + 헬스체크 (smoke 스크립트 없거나 실패 시 fallback) ───

  # 서버 시작 명령어 감지
  local start_cmd
  start_cmd=$(_detect_start_cmd)

  if [[ -z "$start_cmd" ]]; then
    # smoke 스크립트가 실패한 상태에서 서버도 없으면 → SOFT_FAIL (실패를 SKIP으로 숨기지 않음)
    if [[ "$smoke_script_failed" == "true" ]]; then
      echo "[smoke-check] SOFT_FAIL (smoke script failed + no start script to fallback)"
      echo "=== SMOKE CHECK: SOFT_FAIL ==="
      append_gate_history "smoke-check" "fail" '{"reason":"smoke script failed, no server fallback"}'
      return 1
    fi
    echo "[smoke-check] SKIP (no start/dev script detected — library or serverless project)"
    local ts
    ts=$(timestamp)
    if [[ -f "$VERIFICATION_FILE" ]]; then
      jq_inplace "$VERIFICATION_FILE" \
        --arg ts "$ts" \
        '.smokeCheck = {"timestamp": $ts, "result": "skip", "reason": "no start script"}'
    else
      jq -n --arg ts "$ts" \
        '{"smokeCheck": {"timestamp": $ts, "result": "skip", "reason": "no start script"}}' > "$VERIFICATION_FILE"
    fi
    echo "=== SMOKE CHECK: SKIP ==="
    append_gate_history "smoke-check" "skip" '{"reason":"no start script"}'
    return 0
  fi

  echo "[smoke-check] Starting server: $start_cmd"

  # 서버 시작 + 응답 대기 (공통 헬퍼 사용)
  local success=false
  if _start_and_wait_server "$start_cmd" "$port" "$timeout" "smoke-check"; then
    success=true
  fi

  # ─── 엔드포인트 검증 (서버 기동 성공 시) ───
  local endpoint_total=0 endpoint_pass=0 endpoint_fail=0 endpoint_results="[]"

  if [[ "$success" == "true" ]]; then
    # SPEC.md 또는 기획 문서에서 API 엔드포인트 추출
    local spec_file=""
    for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
      if [[ -f "$candidate" ]]; then
        spec_file="$candidate"
        break
      fi
    done

    if [[ -n "$spec_file" ]]; then
      echo "[smoke-check] Verifying API endpoints from $spec_file..."

      # SPEC.md에서 GET 엔드포인트만 추출 (POST/PUT/PATCH/DELETE는 부작용 위험으로 제외)
      local endpoints
      endpoints=$(grep -oE 'GET\s+/[a-zA-Z0-9/_:{}.-]+' "$spec_file" 2>/dev/null | head -20 || true)

      if [[ -n "$endpoints" ]]; then
        while IFS= read -r line; do
          local method path
          method=$(echo "$line" | awk '{print $1}')
          path=$(echo "$line" | awk '{print $2}')

          # 경로 파라미터 치환 ({id} → 1, {:id} → 1)
          path=$(echo "$path" | sed -E 's/\{[^}]+\}/1/g; s/:([a-zA-Z_]+)/1/g')

          endpoint_total=$((endpoint_total + 1))

          # 단일 curl로 body + status code 동시 수집
          local http_code resp_tmp
          resp_tmp=$(mktemp)
          http_code=$(curl -s -w "%{http_code}" --max-time 5 -o "$resp_tmp" "http://localhost:${port}${path}" 2>/dev/null || echo "000")

          # 2xx/3xx/401/403 = PASS (서버 응답 정상), 404/405/5xx/000 = FAIL
          if [[ "$http_code" =~ ^(2[0-9]{2}|3[0-9]{2}|401|403)$ ]]; then
            # 응답 body 필드 검증 (2xx 응답만 — 빈 객체/빈 배열 탐지)
            local body_check="ok"
            if [[ "$http_code" =~ ^2 ]]; then
              local resp_type resp_len
              resp_type=$(jq -r 'type' "$resp_tmp" 2>/dev/null || echo "unknown")
              if [[ "$resp_type" == "object" ]]; then
                resp_len=$(jq 'keys | length' "$resp_tmp" 2>/dev/null || echo "0")
                [[ "$resp_len" == "0" ]] && body_check="empty_object"
              elif [[ "$resp_type" == "array" ]]; then
                resp_len=$(jq 'length' "$resp_tmp" 2>/dev/null || echo "0")
                [[ "$resp_len" == "0" ]] && body_check="empty_array"
              fi
            fi
            rm -f "$resp_tmp"

            if [[ "$body_check" == "empty_object" ]]; then
              echo "  [WARN] GET $path → HTTP $http_code but response is empty object {}"
              endpoint_pass=$((endpoint_pass + 1))
              endpoint_results=$(echo "$endpoint_results" | jq --arg m "$method" --arg p "$path" --arg c "$http_code" '. + [{"method": $m, "path": $p, "status": ($c | tonumber), "result": "warn", "detail": "empty_object"}]')
            elif [[ "$body_check" == "empty_array" ]]; then
              echo "  [WARN] GET $path → HTTP $http_code response is empty array [] (may be no data)"
              endpoint_pass=$((endpoint_pass + 1))
              endpoint_results=$(echo "$endpoint_results" | jq --arg m "$method" --arg p "$path" --arg c "$http_code" '. + [{"method": $m, "path": $p, "status": ($c | tonumber), "result": "warn", "detail": "empty_array"}]')
            else
              echo "  [PASS] GET $path → HTTP $http_code"
              endpoint_pass=$((endpoint_pass + 1))
              endpoint_results=$(echo "$endpoint_results" | jq --arg m "$method" --arg p "$path" --arg c "$http_code" '. + [{"method": $m, "path": $p, "status": ($c | tonumber), "result": "pass"}]')
            fi
          else
            rm -f "$resp_tmp"
            echo "  [FAIL] GET $path → HTTP $http_code"
            endpoint_fail=$((endpoint_fail + 1))
            endpoint_results=$(echo "$endpoint_results" | jq --arg m "$method" --arg p "$path" --arg c "$http_code" '. + [{"method": $m, "path": $p, "status": ($c | tonumber), "result": "fail"}]')
          fi
        done <<< "$endpoints"

        # empty_object/empty_array 경고 수 집계
        local endpoint_warn
        endpoint_warn=$(echo "$endpoint_results" | jq '[.[] | select(.result == "warn")] | length' 2>/dev/null || echo "0")
        echo "[smoke-check] Endpoints: $endpoint_pass/$endpoint_total passed ($endpoint_fail failed, $endpoint_warn warnings)"
        if [[ "$endpoint_warn" -gt 0 ]] && [[ "$endpoint_warn" -eq "$endpoint_pass" ]] && [[ "$endpoint_fail" -eq 0 ]]; then
          echo "[smoke-check] WARNING: ALL endpoints returned empty responses — likely stub implementation"
        fi
      else
        echo "[smoke-check] WARNING: No GET endpoints found in $spec_file — endpoint verification skipped"
        echo "[smoke-check] (mutating endpoints POST/PUT/PATCH/DELETE are excluded from smoke-check to avoid side effects)"
      fi
    fi
  fi

  # 결과 판정
  local ts result
  ts=$(timestamp)
  if [[ "$success" == "true" ]] && [[ "$endpoint_fail" -eq 0 ]]; then
    result="pass"
    echo "[smoke-check] PASS"
  elif [[ "$success" == "true" ]] && [[ "$endpoint_fail" -gt 0 ]]; then
    result="soft_fail"
    echo "[smoke-check] SOFT_FAIL ($endpoint_fail endpoint(s) returned 5xx)"
  else
    result="soft_fail"
    echo "[smoke-check] SOFT_FAIL (server did not respond within ${timeout}s)"
    echo "Server log (last 5 lines):"
    tail -5 "$SERVER_LOG" 2>/dev/null || true
  fi

  # --strict 모드: soft_fail → fail 승격
  if [[ "$strict" == "true" ]] && [[ "$result" == "soft_fail" ]]; then
    result="fail"
    echo "[smoke-check] STRICT MODE: soft_fail upgraded to FAIL"
  fi

  _cleanup_server
  trap - EXIT INT TERM

  # 결과 기록 (엔드포인트 검증 결과 포함)
  local endpoint_json
  endpoint_json=$(jq -n \
    --argjson total "$endpoint_total" \
    --argjson pass "$endpoint_pass" \
    --argjson fail "$endpoint_fail" \
    --argjson details "$endpoint_results" \
    '{"total": $total, "pass": $pass, "fail": $fail, "details": $details}')

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg cmd "$start_cmd" --argjson port "$port" --arg result "$result" \
      --argjson strict "$strict" --argjson endpoints "$endpoint_json" \
      '.smokeCheck = {"timestamp": $ts, "command": $cmd, "port": $port, "result": $result, "strict": $strict, "endpoints": $endpoints}'
  else
    jq -n --arg ts "$ts" --arg cmd "$start_cmd" --argjson port "$port" --arg result "$result" \
      --argjson strict "$strict" --argjson endpoints "$endpoint_json" \
      '{"smokeCheck": {"timestamp": $ts, "command": $cmd, "port": $port, "result": $result, "strict": $strict, "endpoints": $endpoints}}' > "$VERIFICATION_FILE"
  fi

  echo "=== SMOKE CHECK: ${result^^} ==="
  if [[ "$result" == "soft_fail" ]] || [[ "$result" == "fail" ]]; then
    append_gate_history "smoke-check" "fail" "{\"result\":\"$result\",\"port\":$port,\"endpoint_fail\":$endpoint_fail}"
    return 1
  fi
  append_gate_history "smoke-check" "pass" "{\"port\":$port,\"endpoint_pass\":$endpoint_pass,\"endpoint_total\":$endpoint_total}"
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

# ─── doc-consistency: 문서 간 일관성 검사 ───

cmd_doc_consistency() {
  local docs_dir="${1:-.}"

  echo "=== Document Consistency Check ==="
  echo "Scanning: $docs_dir"

  local issues=0

  # 1. 데이터 모델 용어 추출 및 교차 검증
  echo ""
  echo "[1] Data Model Terms"
  local models
  models=$(grep -rh -oE '#{2,3}\s+[A-Za-z0-9_]+\s?(Model|Schema|Table|Entity|Type|Interface)' "$docs_dir"/*.md 2>/dev/null | sed 's/^#*\s*//' | sort -u || true)
  if [[ -n "$models" ]]; then
    while IFS= read -r model; do
      local count
      count=$(grep -rl "$model" "$docs_dir"/*.md 2>/dev/null | wc -l)
      if [[ "$count" -eq 1 ]]; then
        echo "  WARNING: '$model' only referenced in 1 document"
        ((issues++)) || true
      fi
    done <<< "$models"
  else
    echo "  No model definitions found"
  fi

  # 2. API 엔드포인트 일관성
  echo ""
  echo "[2] API Endpoints"
  local endpoints
  endpoints=$(grep -rhoE '(GET|POST|PUT|PATCH|DELETE)\s+/[A-Za-z0-9_/{}\:.-]+' "$docs_dir"/*.md 2>/dev/null | sort -u || true)
  if [[ -n "$endpoints" ]]; then
    local ep_count
    ep_count=$(echo "$endpoints" | wc -l)
    echo "  Found $ep_count unique endpoints"

    local paths
    paths=$(echo "$endpoints" | awk '{print $2}' | sort | uniq -d)
    if [[ -n "$paths" ]]; then
      echo "  Multi-method paths (verify intentional):"
      echo "$paths" | while read -r p; do
        echo "    $p: $(echo "$endpoints" | grep "$p" | awk '{print $1}' | tr '\n' ' ')"
      done
    fi
  else
    echo "  No API endpoints found"
  fi

  # 3. 용어 일관성 (camelCase vs snake_case 혼용)
  echo ""
  echo "[3] Naming Convention"
  local camel snake
  camel=$(grep -rhoE '[a-z]+[A-Z][a-zA-Z]*' "$docs_dir"/*.md 2>/dev/null | sort -u | head -10 || true)
  snake=$(grep -rhoE '[a-z]+_[a-z_]+' "$docs_dir"/*.md 2>/dev/null | sort -u | head -10 || true)
  if [[ -n "$camel" ]] && [[ -n "$snake" ]]; then
    echo "  Mixed conventions detected (may be intentional):"
    echo "  camelCase samples: $(echo "$camel" | head -3 | tr '\n' ', ')"
    echo "  snake_case samples: $(echo "$snake" | head -3 | tr '\n' ', ')"
  else
    echo "  Consistent naming or insufficient data"
  fi

  # 4. 상호 참조 검증
  echo ""
  echo "[4] Cross-references"
  local refs
  refs=$(grep -rhoE '(참조|see|ref):\s*[A-Za-z0-9_-]+\.md' "$docs_dir"/*.md 2>/dev/null || true)
  if [[ -n "$refs" ]]; then
    while read -r ref; do
      local target
      target=$(echo "$ref" | grep -oE '[A-Za-z0-9_-]+\.md')
      if [[ ! -f "$docs_dir/$target" ]]; then
        echo "  BROKEN REF: $ref -> $docs_dir/$target not found"
        ((issues++)) || true
      fi
    done <<< "$refs"
  else
    echo "  No explicit cross-references found"
  fi

  # 5. 수치+단위 교차 일관성 (같은 단위가 다른 파일에서 다른 값)
  echo ""
  echo "[5] Numeric Consistency"
  local -a all_doc_files=()
  while IFS= read -r -d '' df; do
    all_doc_files+=("$df")
  done < <(find "$docs_dir" -maxdepth 2 -name "*.md" -print0 2>/dev/null)
  [[ -f "overview.md" ]] && all_doc_files+=("overview.md")
  [[ -f "SPEC.md" ]] && all_doc_files+=("SPEC.md")

  if [[ ${#all_doc_files[@]} -gt 0 ]]; then
    # 수치+단위 패턴 추출: "100MB", "30s", "5000ms", "10개", "3분" 등
    local numeric_values
    # 수치와 단위를 명시 분리: "100MB" → "100 MB", "30s" → "30 s"
    numeric_values=$(grep -hoE '[0-9]+\s*(MB|KB|GB|TB|ms|s|초|분|시간|개|items|connections|requests|bytes|B)' -- "${all_doc_files[@]}" 2>/dev/null \
      | sed -E 's/([0-9]+)\s*/\1 /' | sort || true)
    if [[ -n "$numeric_values" ]]; then
      # 단위별로 distinct 값 수 비교
      local unit_conflicts
      unit_conflicts=$(echo "$numeric_values" | awk '{print $2}' | sort -u | while read -r unit; do
        local values
        values=$(echo "$numeric_values" | awk -v u="$unit" '$2==u {print $1}' | sort -un)
        local val_count
        val_count=$(echo "$values" | wc -l | tr -d ' ')
        if [[ "$val_count" -gt 1 ]]; then
          echo "  WARNING: Multiple values for '$unit': $(echo "$values" | tr '\n' ', ' | sed 's/,$//')"
        fi
      done)
      if [[ -n "$unit_conflicts" ]]; then
        echo "$unit_conflicts"
        local conflict_count
        conflict_count=$(echo "$unit_conflicts" | grep -c "WARNING" || echo "0")
        issues=$((issues + conflict_count))
      else
        echo "  No numeric inconsistencies found"
      fi
    else
      echo "  No numeric+unit patterns found"
    fi
  else
    echo "  No documentation files to check"
  fi

  echo ""
  echo "=== Issues found: $issues ==="
  append_gate_history "doc-consistency" "$([ "$issues" -eq 0 ] && echo "pass" || echo "warn")" "{\"issues\":$issues}"
  [[ "$issues" -eq 0 ]] && return 0 || return 1
}

# ─── doc-code-check: SPEC/문서 vs 실제 코드 매칭 ───

cmd_doc_code_check() {
  local docs_dir="${1:-docs}"

  echo "=== Doc-Code Consistency Check ==="

  local issues=0

  # 1. 라우트/엔드포인트 매칭
  echo ""
  echo "[1] Route Matching"
  local doc_routes
  # SPEC 파일 후보 탐색 (다양한 경로 지원)
  local spec_for_check=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_for_check="$candidate"; break; }
  done
  doc_routes=$(grep -rhoE '(GET|POST|PUT|PATCH|DELETE)\s+/[A-Za-z0-9_/{}\:.-]+' "$docs_dir"/*.md ${spec_for_check:+"$spec_for_check"} 2>/dev/null | sort -u || true)
  if [[ -n "$doc_routes" ]]; then
    while IFS= read -r route; do
      local method path
      method=$(echo "$route" | awk '{print $1}')
      path=$(echo "$route" | awk '{print $2}' | sed 's/{[^}]*}//g' | sed 's|//|/|g' | sed 's|/$||')
      # path 존재 확인 + HTTP 메서드 매칭 (대소문자 무시)
      local found method_lower
      method_lower=$(echo "$method" | tr '[:upper:]' '[:lower:]')
      found=$(grep -Frl "$path" src/ app/ lib/ server/ api/ routes/ 2>/dev/null | head -1 || true)
      if [[ -z "$found" ]]; then
        echo "  MISSING: $method $path (not found in code)"
        ((issues++)) || true
      else
        # 메서드도 같은 파일에 존재하는지 확인 (get/post/put/patch/delete 또는 GET/POST 등)
        if grep -qiE "(${method}|\.${method_lower}|'${method}'|\"${method}\")" "$found" 2>/dev/null; then
          echo "  OK: $method $path -> $found"
        else
          echo "  WARN: $path found in $found but HTTP method '$method' not confirmed"
        fi
      fi
    done <<< "$doc_routes"
  else
    echo "  No routes in docs to verify"
  fi

  # 2. 모델/스키마 매칭
  echo ""
  echo "[2] Model Matching"
  local doc_models
  doc_models=$(grep -rhoE '(model|schema|table|interface|type)\s+[A-Za-z0-9_]+' "$docs_dir"/*.md ${spec_for_check:+"$spec_for_check"} 2>/dev/null | awk '{print $2}' | sort -u || true)
  if [[ -n "$doc_models" ]]; then
    while IFS= read -r model; do
      local found
      found=$(grep -rl "class $model\|interface $model\|type $model\|model $model\|table.*$model" src/ app/ lib/ server/ prisma/ 2>/dev/null | head -1 || true)
      if [[ -z "$found" ]]; then
        echo "  MISSING: model $model (not found in code)"
        ((issues++)) || true
      else
        echo "  OK: $model -> $found"
      fi
    done <<< "$doc_models"
  else
    echo "  No models in docs to verify"
  fi

  # 3. 테스트 존재 여부
  echo ""
  echo "[3] Test Coverage"
  local -a test_dirs_arr=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && test_dirs_arr+=("$d")
  done < <(find . -type d \( -name "test" -o -name "tests" -o -name "__tests__" -o -name "spec" \) 2>/dev/null | head -5)
  if [[ ${#test_dirs_arr[@]} -gt 0 ]]; then
    local test_count
    test_count=$(find "${test_dirs_arr[@]}" -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "test_*" \) 2>/dev/null | wc -l)
    echo "  Test files found: $test_count"
  else
    echo "  WARNING: No test directories found"
    ((issues++)) || true
  fi

  echo ""
  echo "=== Issues found: $issues ==="
  [[ "$issues" -eq 0 ]] && return 0 || return 1
}

# ─── e2e-gate: E2E 테스트 프레임워크 감지 + 실행 ───

cmd_e2e_gate() {
  require_jq

  # --strict 플래그 파싱: 프레임워크 미감지 시 exit 1 (FAIL) 대신 exit 2 (SKIP)
  local strict_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) strict_mode=true; shift ;;
      --progress-file) PROGRESS_FILE="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  echo "=== E2E Test Gate ==="
  [[ "$strict_mode" == "true" ]] && echo "[e2e] Strict mode enabled"

  local e2e_cmd="" e2e_framework=""

  # 프로젝트 유형 + E2E 프레임워크 자동 감지
  if [[ -f "package.json" ]]; then
    # Web 프로젝트: Playwright > Cypress
    if ls playwright.config.* 2>/dev/null | head -1 >/dev/null 2>&1; then
      e2e_framework="playwright"
      e2e_cmd="npx playwright test --reporter=line"
    elif ls cypress.config.* 2>/dev/null | head -1 >/dev/null 2>&1; then
      e2e_framework="cypress"
      e2e_cmd="npx cypress run --reporter spec"
    # API E2E: supertest (e2e/ 디렉토리 + supertest 의존성)
    elif [[ -d "e2e" ]] && grep -q '"supertest"' package.json 2>/dev/null; then
      e2e_framework="supertest"
      if grep -q '"vitest"' package.json 2>/dev/null; then
        e2e_cmd="npx vitest run e2e/"
      else
        e2e_cmd="npx jest --testPathPattern=e2e"
      fi
    fi
  elif [[ -f "pubspec.yaml" ]]; then
    # Flutter 프로젝트
    if [[ -d "integration_test" ]]; then
      e2e_framework="flutter_integration_test"
      e2e_cmd="flutter test integration_test/"
    elif [[ -d ".maestro" ]]; then
      e2e_framework="maestro"
      e2e_cmd="maestro test .maestro/"
    fi
  elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
    # Python API E2E
    if [[ -d "e2e" ]] || [[ -d "tests/e2e" ]]; then
      e2e_framework="pytest"
      if [[ -d "e2e" ]]; then
        e2e_cmd="pytest e2e/ -v"
      else
        e2e_cmd="pytest tests/e2e/ -v"
      fi
    fi
  elif [[ -f "go.mod" ]]; then
    # Go API E2E
    if [[ -d "e2e" ]] || [[ -d "tests/e2e" ]]; then
      e2e_framework="go_test"
      if [[ -d "e2e" ]]; then
        e2e_cmd="go test ./e2e/... -v"
      else
        e2e_cmd="go test ./tests/e2e/... -v"
      fi
    fi
  fi

  # 프레임워크 미감지 시: --strict이면 exit 1 (FAIL), 아니면 exit 2 (SKIP)
  if [[ -z "$e2e_cmd" ]]; then
    if [[ "$strict_mode" == "true" ]]; then
      echo "[e2e] FAIL (no E2E framework detected — strict mode)"
    else
      echo "[e2e] SKIP (no E2E framework detected)"
    fi

    # verification.json에 e2e 키 병합
    if [[ -f "$VERIFICATION_FILE" ]]; then
      jq_inplace "$VERIFICATION_FILE" '.e2e = {"command": null, "framework": null, "exitCode": null, "summary": "no_e2e_framework"}'
    else
      echo '{"e2e": {"command": null, "framework": null, "exitCode": null, "summary": "no_e2e_framework"}}' | jq '.' > "$VERIFICATION_FILE"
    fi

    if [[ "$strict_mode" == "true" ]]; then
      echo "=== E2E GATE FAILED (strict: no framework) ==="
      append_gate_history "e2e-gate" "fail" '{"reason":"no framework","strict":true}'
      return 1
    else
      echo "=== E2E SKIPPED (no framework) ==="
      append_gate_history "e2e-gate" "skip" '{"reason":"no framework"}'
      return 2
    fi
  fi

  echo "[e2e] Framework: $e2e_framework"
  echo "[e2e] Running: $e2e_cmd"

  local output exit_code
  output=$(eval "$e2e_cmd" 2>&1) && exit_code=0 || exit_code=$?

  local summary
  if [[ $exit_code -eq 0 ]]; then
    summary="pass"
    echo "[e2e] PASS (exit 0)"
  else
    summary=$(echo "$output" | tail -1 | head -c 200)
    echo "[e2e] FAIL (exit $exit_code)"
    echo "$output" | tail -10
  fi

  # verification.json에 e2e 키 병합 (기존 데이터 보존)
  local e2e_result
  e2e_result=$(jq -n \
    --arg cmd "$e2e_cmd" \
    --arg fw "$e2e_framework" \
    --argjson ec "$exit_code" \
    --arg sum "$summary" \
    '{"command": $cmd, "framework": $fw, "exitCode": $ec, "summary": $sum}')

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson e2e "$e2e_result" '.e2e = $e2e'
  else
    echo "{}" | jq --argjson e2e "$e2e_result" '.e2e = $e2e' > "$VERIFICATION_FILE"
  fi

  echo ""
  echo "E2E results merged into $VERIFICATION_FILE"

  # progress 파일 DoD 업데이트 (e2e_pass 필드가 존재하는 경우)
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    local has_e2e_pass
    has_e2e_pass=$(jq '.dod | has("e2e_pass")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    if [[ "$has_e2e_pass" == "true" ]]; then
      jq_inplace "$PROGRESS_FILE" --argjson ec "$exit_code" --arg ev "e2e-gate at $(timestamp)" '
        .dod.e2e_pass.checked = ($ec == 0)
        | .dod.e2e_pass.evidence = (if $ec == 0 then "e2e pass " + $ev else "e2e fail " + $ev end)
      '
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    echo "=== E2E GATE PASSED ==="
    append_gate_history "e2e-gate" "pass" "{\"framework\":\"$e2e_framework\",\"exitCode\":0}"
    return 0
  else
    echo "=== E2E GATE FAILED ==="
    append_gate_history "e2e-gate" "fail" "{\"framework\":\"$e2e_framework\",\"exitCode\":$exit_code}"
    return 1
  fi
}

# ─── design-polish-gate: 디자인 폴리싱 WCAG 체크 + 스크린샷 캡처 ───

cmd_design_polish_gate() {
  local strict=false

  # --strict 플래그 파싱
  local dp_args=()
  for arg in "$@"; do
    if [[ "$arg" == "--strict" ]]; then
      strict=true
    else
      dp_args+=("$arg")
    fi
  done
  set -- "${dp_args[@]}"

  local strict_label=""
  [[ "$strict" == "true" ]] && strict_label=" [STRICT]"
  echo "=== Design Polish Gate${strict_label} ==="
  require_jq

  # SKIP 분기 공통 기록 헬퍼 (verification.json + DoD 동시 업데이트)
  _dp_record_skip() {
    local reason="$1"
    local ts
    ts=$(timestamp)
    if [[ -f "$VERIFICATION_FILE" ]]; then
      jq_inplace "$VERIFICATION_FILE" --arg ts "$ts" --arg r "$reason" \
        '.designPolish = {"timestamp": $ts, "result": "skip", "reason": $r}'
    else
      jq -n --arg ts "$ts" --arg r "$reason" \
        '{"designPolish": {"timestamp": $ts, "result": "skip", "reason": $r}}' > "$VERIFICATION_FILE"
    fi
    # DoD에도 SKIP 기록
    if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
      local has_dq
      has_dq=$(jq '.dod | has("design_quality")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
      if [[ "$has_dq" == "true" ]]; then
        jq_inplace "$PROGRESS_FILE" --arg ev "SKIP: $reason" '
          .dod.design_quality.checked = true
          | .dod.design_quality.evidence = $ev
        '
      fi
    fi
  }

  # design-polish 플러그인 경로 감지
  local dp_root=""
  for dp in "$HOME/.claude/plugins/marketplaces/design-polish" \
            "$HOME/.claude/plugins/design-polish"; do
    if [[ -f "$dp/scripts/search.cjs" ]]; then
      dp_root="$dp"
      break
    fi
  done

  if [[ -z "$dp_root" ]]; then
    echo "[design-polish-gate] SKIP (design-polish plugin not installed)"
    _dp_record_skip "plugin not installed"
    echo "=== DESIGN POLISH GATE: SKIP ==="
    return 2
  fi

  echo "[design-polish-gate] Plugin found: $dp_root"

  # puppeteer 의존성 확인
  if ! command -v npx >/dev/null 2>&1; then
    echo "[design-polish-gate] SKIP (npx not available — puppeteer requires Node.js)"
    _dp_record_skip "npx not available"
    echo "=== DESIGN POLISH GATE: SKIP ==="
    return 2
  fi

  # capture.cjs 존재 확인
  if [[ ! -f "$dp_root/scripts/capture.cjs" ]]; then
    echo "[design-polish-gate] SKIP (capture.cjs not found in plugin)"
    _dp_record_skip "capture.cjs not found"
    echo "=== DESIGN POLISH GATE: SKIP ==="
    return 2
  fi

  # Before/After 비교를 위해 기존 스크린샷을 before-*로 보존
  for f in .design-polish/screenshots/current-*.png; do
    [[ -f "$f" ]] && cp "$f" "${f/current-/before-}"
  done

  # Stale 아티팩트 정리 (이전 실행 결과가 판정을 왜곡하지 않도록)
  rm -f .design-polish/accessibility/wcag-report*.json 2>/dev/null || true
  rm -f .design-polish/screenshots/current-*.png 2>/dev/null || true

  # 서버 시작 (공통 헬퍼 사용)
  local port="${1:-3000}"
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    die "design-polish-gate: port must be a positive integer, got '$port'"
  fi
  if [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    die "design-polish-gate: port must be 1-65535, got '$port'"
  fi

  local start_cmd
  start_cmd=$(_detect_start_cmd)

  if [[ -z "$start_cmd" ]]; then
    echo "[design-polish-gate] SKIP (no start/dev script — cannot capture screenshots)"
    _dp_record_skip "no start/dev script"
    echo "=== DESIGN POLISH GATE: SKIP ==="
    return 2
  fi

  echo "[design-polish-gate] Starting server: $start_cmd"

  if ! _start_and_wait_server "$start_cmd" "$port" 15 "design-polish-gate"; then
    _cleanup_server
    trap - EXIT INT TERM
    if [[ "$strict" == "true" ]]; then
      echo "[design-polish-gate] STRICT MODE: server failed to start → FAIL"
      local ts
      ts=$(timestamp)
      if [[ -f "$VERIFICATION_FILE" ]]; then
        jq_inplace "$VERIFICATION_FILE" --arg ts "$ts" \
          '.designPolish = {"timestamp": $ts, "result": "fail", "reason": "server failed to start (strict mode)"}'
      else
        jq -n --arg ts "$ts" \
          '{"designPolish": {"timestamp": $ts, "result": "fail", "reason": "server failed to start (strict mode)"}}' > "$VERIFICATION_FILE"
      fi
      if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
        local has_dq
        has_dq=$(jq '.dod | has("design_quality")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
        if [[ "$has_dq" == "true" ]]; then
          jq_inplace "$PROGRESS_FILE" '
            .dod.design_quality.checked = false
            | .dod.design_quality.evidence = "FAIL: server failed to start (strict mode)"
          '
        fi
      fi
      echo "=== DESIGN POLISH GATE: FAIL ==="
      return 1
    fi
    echo "[design-polish-gate] SKIP (server failed to start)"
    _dp_record_skip "server failed to start"
    echo "=== DESIGN POLISH GATE: SKIP ==="
    return 2
  fi

  echo "[design-polish-gate] Server ready on port $port"

  # capture.cjs 실행 (WCAG + 스크린샷, 포트 전달)
  local capture_exit=0
  echo "[design-polish-gate] Running capture: BASE_URL=http://localhost:$port node $dp_root/scripts/capture.cjs --wcag /"
  BASE_URL="http://localhost:$port" node "$dp_root/scripts/capture.cjs" --wcag / 2>&1 && capture_exit=0 || capture_exit=$?

  # 서버 프로세스 정리 (공통 헬퍼)
  _cleanup_server
  trap - EXIT INT TERM

  # WCAG 리포트 요약
  local wcag_violations=0
  local wcag_summary="no report"
  local wcag_report_missing=false
  if [[ -f ".design-polish/accessibility/wcag-report.json" ]] || [[ -f ".design-polish/accessibility/wcag-report-main.json" ]]; then
    local wcag_file=".design-polish/accessibility/wcag-report.json"
    [[ -f "$wcag_file" ]] || wcag_file=".design-polish/accessibility/wcag-report-main.json"
    wcag_violations=$(jq '[.violations // [] | .[]] | length' "$wcag_file" 2>/dev/null || echo "0")
    wcag_summary="$wcag_violations violations found"
    echo "[design-polish-gate] WCAG: $wcag_summary"
  else
    echo "[design-polish-gate] WARNING: WCAG report not generated"
    wcag_report_missing=true
    wcag_summary="report not generated"
  fi

  # 스크린샷 확인
  if [[ -f ".design-polish/screenshots/current-main.png" ]]; then
    echo "[design-polish-gate] Screenshot captured: .design-polish/screenshots/current-main.png"
  else
    echo "[design-polish-gate] WARNING: Screenshot not captured"
  fi

  # verification.json에 결과 기록
  local ts result
  ts=$(timestamp)
  if [[ "$capture_exit" -ne 0 ]]; then
    result="soft_fail"
  elif [[ "$wcag_report_missing" == "true" ]]; then
    result="soft_fail"
  elif [[ "$wcag_violations" -gt 0 ]]; then
    result="soft_fail"
  else
    result="pass"
  fi

  # --strict 모드: soft_fail → fail 승격 (WCAG 위반 시 하드 게이트로 동작)
  if [[ "$strict" == "true" ]] && [[ "$result" == "soft_fail" ]]; then
    result="fail"
    echo "[design-polish-gate] STRICT MODE: soft_fail upgraded to FAIL"
  fi

  # health-score 리그레션 데이터 수집
  local hs_score=0 hs_diff=0 hs_status="unknown"
  if [[ -f ".design-polish/health-score.json" ]]; then
    hs_score=$(jq '.score // 0' .design-polish/health-score.json 2>/dev/null || echo "0")
    hs_diff=$(jq '.regression.diff // 0' .design-polish/health-score.json 2>/dev/null || echo "0")
    hs_status=$(jq -r '.regression.status // "unknown"' .design-polish/health-score.json 2>/dev/null || echo "unknown")
    echo "[design-polish-gate] Health Score: $hs_score (diff: $hs_diff, status: $hs_status)"
  fi

  # Before/After 스크린샷 경로 수집
  local has_before="false" has_after="false"
  [[ -f ".design-polish/screenshots/before-main.png" ]] && has_before="true"
  [[ -f ".design-polish/screenshots/current-main.png" ]] && has_after="true"

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --argjson violations "$wcag_violations" --arg result "$result" --arg summary "$wcag_summary" \
      --argjson hs_score "$hs_score" --argjson hs_diff "$hs_diff" --arg hs_status "$hs_status" \
      --argjson has_before "$has_before" --argjson has_after "$has_after" \
      '.designPolish = {
        "timestamp": $ts, "wcagViolations": $violations, "result": $result, "summary": $summary,
        "healthScore": {"score": $hs_score, "diff": $hs_diff, "status": $hs_status},
        "screenshots": {"before": (if $has_before then ".design-polish/screenshots/before-main.png" else null end), "after": (if $has_after then ".design-polish/screenshots/current-main.png" else null end)}
      }'
  else
    jq -n --arg ts "$ts" --argjson violations "$wcag_violations" --arg result "$result" --arg summary "$wcag_summary" \
      --argjson hs_score "$hs_score" --argjson hs_diff "$hs_diff" --arg hs_status "$hs_status" \
      --argjson has_before "$has_before" --argjson has_after "$has_after" \
      '{"designPolish": {
        "timestamp": $ts, "wcagViolations": $violations, "result": $result, "summary": $summary,
        "healthScore": {"score": $hs_score, "diff": $hs_diff, "status": $hs_status},
        "screenshots": {"before": (if $has_before then ".design-polish/screenshots/before-main.png" else null end), "after": (if $has_after then ".design-polish/screenshots/current-main.png" else null end)}
      }}' > "$VERIFICATION_FILE"
  fi

  # DoD design_quality 갱신
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    local has_dq
    has_dq=$(jq '.dod | has("design_quality")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    if [[ "$has_dq" == "true" ]]; then
      # pass/skip/soft_fail은 비차단 → checked=true, fail/hard_fail은 차단 → checked=false
      local dq_checked="true"
      [[ "$result" == "hard_fail" || "$result" == "fail" ]] && dq_checked="false"
      jq_inplace "$PROGRESS_FILE" \
        --argjson checked "$dq_checked" --arg ev "design-polish-gate: $result ($wcag_summary)" \
        '.dod.design_quality.checked = $checked | .dod.design_quality.evidence = $ev'
    fi
  fi

  echo "=== DESIGN POLISH GATE: ${result^^} ==="
  if [[ "$result" == "fail" ]]; then
    return 1
  elif [[ "$result" == "soft_fail" ]]; then
    return 1
  fi
  return 0
}

# ─── placeholder-check: TODO/placeholder/FIXME 잔존 감지 (HARD_FAIL) ───

cmd_placeholder_check() {
  echo "=== Placeholder Check ==="

  # 검색 대상 디렉토리 결정
  local search_dirs=()
  for d in src lib app server client pages components routes services controllers handlers; do
    [[ -d "$d" ]] && search_dirs+=("$d")
  done

  if [[ ${#search_dirs[@]} -eq 0 ]]; then
    echo "[placeholder-check] SKIP (no source directories found)"
    append_gate_history "placeholder-check" "skip" '{"reason":"no source directories"}'
    return 0
  fi

  # placeholder 패턴 검색 (테스트 파일 + HTML placeholder 속성 제외)
  local found_lines
  found_lines=$(grep -rnE \
    "TODO.*(연동|integration|implement|실제|real)|FIXME.*(연동|integration|implement)" \
    "${search_dirs[@]}" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.py" --include="*.go" --include="*.dart" --include="*.java" \
    2>/dev/null | grep -vE "(test|spec|__test__|__tests__|\.test\.|\.spec\.)" || true)

  # placeholder 키워드는 HTML 속성(placeholder=, placeholder:)을 제외하고 검색
  local placeholder_lines
  placeholder_lines=$(grep -rnE "placeholder" \
    "${search_dirs[@]}" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    --include="*.py" --include="*.go" --include="*.dart" --include="*.java" \
    2>/dev/null \
    | grep -vE "(test|spec|__test__|__tests__|\.test\.|\.spec\.)" \
    | grep -vE "(placeholder=|placeholder:|placeholder\"|placeholderText|placeholder\s*\()" \
    || true)

  if [[ -n "$placeholder_lines" ]]; then
    found_lines="${found_lines}${found_lines:+$'\n'}${placeholder_lines}"
  fi

  # 두 grep 결과의 중복 제거
  if [[ -n "$found_lines" ]]; then
    found_lines=$(echo "$found_lines" | sort -u)
  fi

  local count=0
  if [[ -n "$found_lines" ]]; then
    count=$(echo "$found_lines" | wc -l | tr -d ' ')
  fi

  echo "[placeholder-check] Found $count placeholder(s) in source code"

  # verification.json에 결과 기록
  local ts result
  ts=$(timestamp)
  if [[ "$count" -gt 0 ]]; then
    result="fail"
    echo "$found_lines" | head -10
    [[ "$count" -gt 10 ]] && echo "  ... and $((count - 10)) more"
  else
    result="pass"
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg result "$result" --argjson count "$count" \
      '.placeholderCheck = {"timestamp": $ts, "result": $result, "count": $count}'
  elif [[ -n "$VERIFICATION_FILE" ]]; then
    jq -n --arg ts "$ts" --arg result "$result" --argjson count "$count" \
      '{"placeholderCheck": {"timestamp": $ts, "result": $result, "count": $count}}' > "$VERIFICATION_FILE"
  fi

  echo "=== PLACEHOLDER CHECK: ${result^^} ==="
  if [[ "$result" == "fail" ]]; then
    append_gate_history "placeholder-check" "fail" "{\"count\":$count}"
    return 1
  fi
  append_gate_history "placeholder-check" "pass" '{"count":0}'
  return 0
}

# ─── external-service-check: 외부 서비스 스텁 검증 (HARD_FAIL) ───

cmd_external_service_check() {
  echo "=== External Service Check ==="

  # SPEC.md에서 외부 서비스 키워드 추출
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done

  if [[ -z "$spec_file" ]]; then
    echo "[external-service-check] SKIP (no SPEC.md found)"
    return 0
  fi

  # 서비스별 키워드 → SDK/config 패턴 매핑
  local -A service_keywords=(
    ["payment"]="stripe|toss|portone|iamport|paypal|braintree"
    ["oauth"]="nextauth|passport|oauth|google-auth|kakao.*auth|naver.*login"
    ["email"]="nodemailer|sendgrid|ses|mailgun|postmark|resend"
    ["sms"]="twilio|sens|aligo|coolsms"
    ["storage"]="s3|cloudinary|uploadthing|multer.*s3"
    ["push"]="firebase.*messaging|fcm|onesignal|expo.*notification"
  )

  local total_services=0 missing_services=0 missing_list=""

  for service in "${!service_keywords[@]}"; do
    # SPEC.md에 해당 서비스가 구체적으로 언급되는지 확인 (서비스별 키워드)
    local spec_pattern
    case "$service" in
      payment) spec_pattern="결제|payment|pay|billing|checkout|주문.*완료" ;;
      oauth)   spec_pattern="소셜.*로그인|social.*login|OAuth|카카오.*로그인|네이버.*로그인|구글.*로그인|SSO" ;;
      email)   spec_pattern="이메일|email|메일.*발송|mail.*send|인증.*메일|verification.*email" ;;
      sms)     spec_pattern="SMS|문자|인증.*번호|verification.*code.*sms" ;;
      storage) spec_pattern="파일.*업로드|file.*upload|이미지.*저장|image.*storage|S3" ;;
      push)    spec_pattern="푸시.*알림|push.*notification|FCM|알림.*발송" ;;
    esac

    if grep -qiE "$spec_pattern" "$spec_file" 2>/dev/null; then
      total_services=$((total_services + 1))
      local sdk_pattern="${service_keywords[$service]}"

      # 소스 코드에서 실제 SDK import/require/config 존재 확인
      local found_sdk=false
      for d in src lib app server client pages components; do
        if [[ -d "$d" ]]; then
          if grep -rqlE "$sdk_pattern" "$d" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.go" 2>/dev/null; then
            found_sdk=true
            break
          fi
        fi
      done

      # externalServiceStubs 레코드 확인 (SKILL.md의 스키마 기반 스텁 허용 경로)
      if [[ "$found_sdk" == "false" ]] && [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
        local has_stub
        has_stub=$(jq -r --arg svc "$service" '.phases.phase_2.externalServiceStubs // [] | map(select(.service == $svc)) | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
        if [[ "$has_stub" -gt 0 ]]; then
          found_sdk=true
          echo "  [PASS] $service: schema-based stub recorded in progress (externalServiceStubs)"
        fi
      fi

      if [[ "$found_sdk" == "false" ]]; then
        missing_services=$((missing_services + 1))
        missing_list="${missing_list}  - ${service}: SPEC에 명시되었으나 SDK/config 미발견\n"
        echo "  [FAIL] $service: specified in SPEC but no SDK/config found in source"
      else
        echo "  [PASS] $service: SDK/config found"
      fi
    fi
  done

  # verification.json에 결과 기록
  local ts result
  ts=$(timestamp)

  if [[ "$total_services" -eq 0 ]]; then
    result="skip"
    echo "[external-service-check] SKIP (no external services detected in SPEC)"
  elif [[ "$missing_services" -gt 0 ]]; then
    result="fail"
    echo "[external-service-check] Services: $((total_services - missing_services))/$total_services verified"
    printf '%b\n' "$missing_list"
  else
    result="pass"
    echo "[external-service-check] Services: $total_services/$total_services verified"
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg result "$result" --argjson total "$total_services" --argjson missing "$missing_services" \
      '.externalServiceCheck = {"timestamp": $ts, "result": $result, "totalServices": $total, "missingServices": $missing}'
  elif [[ -n "$VERIFICATION_FILE" ]]; then
    jq -n --arg ts "$ts" --arg result "$result" --argjson total "$total_services" --argjson missing "$missing_services" \
      '{"externalServiceCheck": {"timestamp": $ts, "result": $result, "totalServices": $total, "missingServices": $missing}}' > "$VERIFICATION_FILE"
  fi

  # ─── 외부 CLI 도구 감지 (SPEC에서 추출) ───
  if [[ -n "$spec_file" ]]; then
    # SPEC에서 자주 사용되는 외부 CLI 도구 키워드 매핑
    local -A tool_keywords=(
      ["ffmpeg"]="ffmpeg|FFmpeg|영상.*변환|video.*convert|transcode"
      ["imagemagick"]="imagemagick|ImageMagick|convert.*image|이미지.*변환|이미지.*리사이즈"
      ["puppeteer"]="puppeteer|Puppeteer|headless.*browser|스크린샷.*캡처"
      ["chromium"]="chromium|Chromium|chrome.*headless"
      ["wkhtmltopdf"]="wkhtmltopdf|PDF.*변환|html.*to.*pdf"
      ["graphviz"]="graphviz|dot.*graph|다이어그램.*생성"
      ["redis-cli"]="redis|Redis|캐시.*서버"
      ["docker"]="docker|Docker|컨테이너"
    )

    local tool_missing=0 tool_total=0
    for tool in "${!tool_keywords[@]}"; do
      local pattern="${tool_keywords[$tool]}"
      if grep -qiE "$pattern" "$spec_file" 2>/dev/null; then
        tool_total=$((tool_total + 1))
        if command -v "$tool" >/dev/null 2>&1; then
          local tool_ver
          tool_ver=$("$tool" --version 2>&1 | head -1 | head -c 80 || echo "unknown")
          echo "  [PASS] CLI tool '$tool': installed ($tool_ver)"
        else
          tool_missing=$((tool_missing + 1))
          echo "  [WARN] CLI tool '$tool': mentioned in SPEC but not found in PATH"
        fi
      fi
    done

    if [[ "$tool_total" -gt 0 ]]; then
      echo "[external-service-check] CLI tools: $((tool_total - tool_missing))/$tool_total detected"
      if [[ "$tool_missing" -gt 0 ]]; then
        echo "  ⚠ $tool_missing tool(s) not installed — install before Phase 2 implementation"
      fi
    fi
  fi

  echo "=== EXTERNAL SERVICE CHECK: ${result^^} ==="
  if [[ "$result" == "fail" ]]; then
    return 1
  fi
  return 0
}

# ─── service-test-check: 서비스/라우트 통합 테스트 존재 확인 (HARD_FAIL) ───

cmd_service_test_check() {
  echo "=== Service Test Check ==="
  require_jq

  # projectScope 확인 (fail-closed: progress 없으면 FAIL)
  if [[ -z "$PROGRESS_FILE" ]] || [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "[service-test-check] FAIL (progress file not found — cannot determine projectScope)"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  local has_backend
  has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend // "null"' "$PROGRESS_FILE" 2>/dev/null || echo "null")

  if [[ "$has_backend" == "null" ]]; then
    echo "[service-test-check] FAIL (projectScope.hasBackend is not defined — run Phase 0 first)"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  if [[ "$has_backend" != "true" ]]; then
    echo "[service-test-check] SKIP (hasBackend is false)"
    return 0
  fi

  # 테스트 디렉토리에서 서비스/라우트 관련 테스트 파일 검색 (중복 제거)
  local test_files=0
  local search_pattern="(service|route|controller|handler|api|endpoint)"

  # 전체 프로젝트에서 테스트 파일을 한 번만 검색
  local all_test_files=""
  for d in test tests __tests__; do
    if [[ -d "$d" ]]; then
      all_test_files+=$(find "$d" -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" \) 2>/dev/null)
      all_test_files+=$'\n'
    fi
  done
  # src 내부 인라인 테스트 파일
  if [[ -d "src" ]]; then
    all_test_files+=$(find src -type f \( -name "*.test.*" -o -name "*.spec.*" \) 2>/dev/null)
  fi

  if [[ -n "$all_test_files" ]]; then
    test_files=$(echo "$all_test_files" | sort -u | grep -iE "$search_pattern" | wc -l | tr -d ' ')
  fi

  echo "[service-test-check] Found $test_files service/route test file(s)"

  if [[ "$test_files" -eq 0 ]]; then
    echo "[service-test-check] WARNING: hasBackend=true but no service/route tests found"
    echo "  Expected: test files matching pattern *service*|*route*|*controller*|*handler*|*api*|*endpoint*"
    echo "  Searched: test/ tests/ __tests__/ src/**/*.test.* src/**/*.spec.*"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  echo "=== SERVICE TEST CHECK: PASS ==="
  return 0
}

# ─── integration-smoke: 프론트↔백엔드 연동 검증 (HARD_FAIL) ───

cmd_integration_smoke() {
  echo "=== Integration Smoke ==="
  require_jq

  # projectScope 확인 (fail-closed: progress 없으면 FAIL)
  if [[ -z "$PROGRESS_FILE" ]] || [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "[integration-smoke] FAIL (progress file not found — cannot determine projectScope)"
    echo "=== INTEGRATION SMOKE: FAIL ==="
    return 1
  fi

  local has_frontend has_backend
  has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend // "null"' "$PROGRESS_FILE" 2>/dev/null || echo "null")
  has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend // "null"' "$PROGRESS_FILE" 2>/dev/null || echo "null")

  if [[ "$has_frontend" == "null" ]] || [[ "$has_backend" == "null" ]]; then
    echo "[integration-smoke] FAIL (projectScope not defined — run Phase 0 first)"
    echo "=== INTEGRATION SMOKE: FAIL ==="
    return 1
  fi

  if [[ "$has_frontend" != "true" ]] || [[ "$has_backend" != "true" ]]; then
    echo "[integration-smoke] SKIP (requires hasFrontend=true AND hasBackend=true)"
    return 0
  fi

  local checks_total=0 checks_pass=0 checks_fail=0

  # 1. .env.example에 API URL 관련 환경 변수 존재 확인
  checks_total=$((checks_total + 1))
  if [[ -f ".env.example" ]]; then
    if grep -qiE "(API_URL|BASE_URL|BACKEND_URL|SERVER_URL|NEXT_PUBLIC_API|VITE_API)" ".env.example" 2>/dev/null; then
      echo "  [PASS] .env.example contains API URL variable"
      checks_pass=$((checks_pass + 1))
    else
      echo "  [FAIL] .env.example exists but no API URL variable (API_URL, BASE_URL, etc.)"
      checks_fail=$((checks_fail + 1))
    fi
  else
    echo "  [FAIL] .env.example not found"
    checks_fail=$((checks_fail + 1))
  fi

  # 2. 프론트엔드 코드에서 API 호출 패턴 존재 확인
  checks_total=$((checks_total + 1))
  local api_call_found=false
  local fe_dirs=("src" "app" "pages" "components" "client")
  for d in "${fe_dirs[@]}"; do
    if [[ -d "$d" ]]; then
      if grep -rqlE "(fetch\(|axios\.|api\.|useQuery|useMutation|trpc\.|\.get\(|\.post\()" "$d" \
        --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.vue" --include="*.svelte" 2>/dev/null; then
        api_call_found=true
        break
      fi
    fi
  done

  if [[ "$api_call_found" == "true" ]]; then
    echo "  [PASS] Frontend API call patterns found"
    checks_pass=$((checks_pass + 1))
  else
    echo "  [FAIL] No API call patterns found in frontend code"
    checks_fail=$((checks_fail + 1))
  fi

  # 3. CORS 설정 확인 (백엔드)
  checks_total=$((checks_total + 1))
  local cors_found=false
  local be_dirs=("src" "server" "lib" "app")
  for d in "${be_dirs[@]}"; do
    if [[ -d "$d" ]]; then
      if grep -rqlE "(cors|CORS|Access-Control-Allow-Origin|@CrossOrigin)" "$d" \
        --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.java" 2>/dev/null; then
        cors_found=true
        break
      fi
    fi
  done

  if [[ "$cors_found" == "true" ]]; then
    echo "  [PASS] CORS configuration found in backend"
    checks_pass=$((checks_pass + 1))
  else
    echo "  [FAIL] No CORS configuration found in backend code"
    checks_fail=$((checks_fail + 1))
  fi

  # 4. 백엔드 서버 기동 확인 (smoke-check 재사용)
  checks_total=$((checks_total + 1))
  local start_cmd
  start_cmd=$(_detect_start_cmd)
  if [[ -n "$start_cmd" ]]; then
    local port="${1:-3000}"
    if _start_and_wait_server "$start_cmd" "$port" 15 "integration-smoke"; then
      echo "  [PASS] Backend server started successfully"
      checks_pass=$((checks_pass + 1))
    else
      echo "  [FAIL] Backend server failed to start"
      checks_fail=$((checks_fail + 1))
    fi
    _cleanup_server
    trap - EXIT INT TERM
  else
    echo "  [FAIL] No start command detected for backend"
    checks_fail=$((checks_fail + 1))
  fi

  # 결과 기록
  local ts result
  ts=$(timestamp)
  if [[ "$checks_fail" -eq 0 ]]; then
    result="pass"
  else
    result="fail"
  fi

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" \
      --arg ts "$ts" --arg result "$result" --argjson total "$checks_total" --argjson pass "$checks_pass" --argjson fail "$checks_fail" \
      '.integrationSmoke = {"timestamp": $ts, "result": $result, "checks": {"total": $total, "pass": $pass, "fail": $fail}}'
  else
    jq -n --arg ts "$ts" --arg result "$result" --argjson total "$checks_total" --argjson pass "$checks_pass" --argjson fail "$checks_fail" \
      '{"integrationSmoke": {"timestamp": $ts, "result": $result, "checks": {"total": $total, "pass": $pass, "fail": $fail}}}' > "$VERIFICATION_FILE"
  fi

  echo "[integration-smoke] Checks: $checks_pass/$checks_total passed"
  echo "=== INTEGRATION SMOKE: ${result^^} ==="
  if [[ "$result" == "fail" ]]; then
    return 1
  fi
  return 0
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

  echo "=== Recovery Info ==="
  echo "Progress: $PROGRESS_FILE"

  # 전체 상태
  local status
  status=$(jq -r '.status // "unknown"' "$PROGRESS_FILE")
  echo "Status: $status"

  if [[ "$status" == "completed" ]]; then
    echo "All phases completed. No recovery needed. Cleaning up progress file."
    rm -f "$PROGRESS_FILE"
    rm -f ".claude-verification.json"
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
      --warnings)    warnings="${2:-}"; shift 2 ;;
      --approach)    approach="${2:-}"; shift 2 ;;
      --iteration)   iteration="${2:?--iteration requires value}"; shift 2 ;;
      --decision)    decisions+=("${2:?--decision requires value}"); shift 2 ;;
      *) die "Unknown option: $1. Usage: handoff-update --phase <p> --completed <c> --next-steps <n> [--warnings <w>] [--approach <a>] [--iteration <i>] [--decision <d>]..." ;;
    esac
  done

  # 최소 필수 인수
  [[ -n "$next_steps" ]] || die "handoff-update requires at least --next-steps"

  # handoff 객체가 없으면 생성
  local has_handoff
  has_handoff=$(jq 'has("handoff")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  if [[ "$has_handoff" != "true" ]]; then
    jq_inplace "$PROGRESS_FILE" '.handoff = {}'
  fi

  # 각 필드 업데이트 (제공된 것만)
  if [[ -n "$next_steps" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg v "$next_steps" '.handoff.nextSteps = $v'
  fi
  if [[ -n "$phase" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg v "$phase" '.handoff.currentPhase = $v'
  fi
  if [[ -n "$completed" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg v "$completed" '.handoff.completedInThisIteration = $v'
  fi
  if [[ -n "$warnings" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg v "$warnings" '.handoff.warnings = $v'
  fi
  if [[ -n "$approach" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg v "$approach" '.handoff.currentApproach = $v'
  fi
  if [[ -n "$iteration" ]]; then
    jq_inplace "$PROGRESS_FILE" --argjson v "$iteration" '.handoff.lastIteration = $v'
  fi
  if [[ ${#decisions[@]} -gt 0 ]]; then
    local decisions_json
    decisions_json=$(printf '%s\n' "${decisions[@]}" | jq -R . | jq -s .)
    jq_inplace "$PROGRESS_FILE" --argjson v "$decisions_json" '.handoff.keyDecisions = $v'
  fi

  echo "OK: handoff updated"
  jq '.handoff' "$PROGRESS_FILE"
}

# ─── implementation-depth: stub/빈 함수 탐지 (SOFT gate) ───

cmd_implementation_depth() {
  echo "=== Implementation Depth Check ==="

  local threshold
  threshold=$(config_get '.quality.stubThreshold' '5')
  local scan_dir=""

  # 인수 파싱
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold)
        threshold="${2:?--threshold requires a number}"
        if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
          die "implementation-depth: --threshold must be a non-negative integer, got '$threshold'"
        fi
        shift 2 ;;
      --dir)
        scan_dir="${2:?--dir requires a path}"
        if [[ "$scan_dir" == /* ]]; then
          die "implementation-depth: --dir must be a relative path, got '$scan_dir'"
        fi
        if [[ "$scan_dir" == *..* ]]; then
          die "implementation-depth: --dir must not contain '..', got '$scan_dir'"
        fi
        shift 2 ;;
      *) shift ;;
    esac
  done

  # 프로젝트 언어 감지
  local lang="unknown"
  if [[ -f "package.json" ]] || [[ -f "tsconfig.json" ]]; then
    lang="js"
  elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    lang="python"
  elif [[ -f "go.mod" ]]; then
    lang="go"
  elif [[ -f "Cargo.toml" ]]; then
    lang="rust"
  elif [[ -f "pubspec.yaml" ]]; then
    lang="dart"
  fi

  # 소스 디렉토리 탐지
  local src_dirs=()
  if [[ -n "$scan_dir" ]]; then
    src_dirs=("$scan_dir")
  else
    for d in src app lib server pages components client routes controllers services; do
      [[ -d "$d" ]] && src_dirs+=("$d")
    done
  fi

  if [[ ${#src_dirs[@]} -eq 0 ]]; then
    echo "[IMPL-DEPTH] SKIP: No source directories found"
    append_gate_history "implementation-depth" "skip" '{"reason":"no source dirs"}'
    return 2
  fi

  local src_count=0 test_count=0
  local src_findings="" test_findings=""

  # 테스트 디렉토리/파일 패턴
  local test_exclude_pattern='(test|spec|__test__|__tests__|\.test\.|\.spec\.|_test\.)'

  case "$lang" in
    js)
      # JS/TS: 빈 함수 body (한 줄 함수 제외 — 화살표 함수의 한줄 리턴은 정상)
      # 빈 블록: { } 또는 {\n}
      local empty_fns
      empty_fns=$(grep -rnE '(function\s+\w+|=>)\s*\{\s*\}' "${src_dirs[@]}" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 2>/dev/null | grep -vE "$test_exclude_pattern" || true)
      if [[ -n "$empty_fns" ]]; then
        local count
        count=$(echo "$empty_fns" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${empty_fns}\n"
      fi

      # stub 함수: body가 return 리터럴 하나뿐 (함수 전체가 { return X } 패턴)
      # res.json() / res.send() 에 리터럴만 전달하는 패턴
      local stub_responses
      stub_responses=$(grep -rnE 'res\.(json|send)\(\s*(\{\s*\}|\[\s*\])\s*\)' "${src_dirs[@]}" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 2>/dev/null | grep -vE "$test_exclude_pattern" || true)
      if [[ -n "$stub_responses" ]]; then
        local count
        count=$(echo "$stub_responses" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${stub_responses}\n"
      fi

      # 빈 인터페이스/타입 (TypeScript)
      local empty_types
      empty_types=$(grep -rnE '(interface|type)\s+\w+\s*(\{[\s]*\}|=\s*\{\s*\})' "${src_dirs[@]}" --include='*.ts' --include='*.tsx' 2>/dev/null | grep -vE "$test_exclude_pattern" || true)
      if [[ -n "$empty_types" ]]; then
        local count
        count=$(echo "$empty_types" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${empty_types}\n"
      fi

      # 테스트: skip된 테스트
      local skipped_tests
      skipped_tests=$(grep -rnE '(test|it|describe)\.(skip|todo)\(' "${src_dirs[@]}" test/ __tests__/ tests/ 2>/dev/null --include='*.test.*' --include='*.spec.*' --include='*_test.*' || true)
      if [[ -n "$skipped_tests" ]]; then
        local count
        count=$(echo "$skipped_tests" | wc -l)
        test_count=$((test_count + count))
        test_findings="${test_findings}${skipped_tests}\n"
      fi

      # 테스트: assertion 없는 테스트 블록 (test/it 호출이 있는 파일에서 expect/assert가 없는 것)
      local test_files_no_assert
      test_files_no_assert=""
      for tf in $(find "${src_dirs[@]}" test/ __tests__/ tests/ -name '*.test.*' -o -name '*.spec.*' 2>/dev/null); do
        if grep -qE '(test|it)\(' "$tf" 2>/dev/null && ! grep -qE '(expect|assert|should|toBe|toEqual|toHave|toContain|toThrow|toMatch)' "$tf" 2>/dev/null; then
          test_count=$((test_count + 1))
          test_files_no_assert="${test_files_no_assert}${tf}: no assertions found\n"
        fi
      done
      test_findings="${test_findings}${test_files_no_assert}"
      ;;

    python)
      # Python: pass-only 함수
      local pass_fns
      pass_fns=$(grep -rnB1 '^\s*pass\s*$' "${src_dirs[@]}" --include='*.py' 2>/dev/null | grep -E 'def\s' | grep -vE "$test_exclude_pattern" || true)
      if [[ -n "$pass_fns" ]]; then
        local count
        count=$(echo "$pass_fns" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${pass_fns}\n"
      fi

      # Python: skip된 테스트
      local py_skipped
      py_skipped=$(grep -rnE '@pytest\.mark\.skip|@unittest\.skip' "${src_dirs[@]}" test/ tests/ 2>/dev/null --include='*.py' || true)
      if [[ -n "$py_skipped" ]]; then
        local count
        count=$(echo "$py_skipped" | wc -l)
        test_count=$((test_count + count))
        test_findings="${test_findings}${py_skipped}\n"
      fi
      ;;

    go)
      # Go: 빈 함수 body
      local go_empty
      go_empty=$(grep -rnE 'func\s.*\{\s*\}' "${src_dirs[@]}" --include='*.go' 2>/dev/null | grep -vE '_test\.go' || true)
      if [[ -n "$go_empty" ]]; then
        local count
        count=$(echo "$go_empty" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${go_empty}\n"
      fi

      # Go: skip된 테스트
      local go_skipped
      go_skipped=$(grep -rnE 't\.Skip\(' "${src_dirs[@]}" --include='*_test.go' 2>/dev/null || true)
      if [[ -n "$go_skipped" ]]; then
        local count
        count=$(echo "$go_skipped" | wc -l)
        test_count=$((test_count + count))
        test_findings="${test_findings}${go_skipped}\n"
      fi
      ;;

    *)
      echo "[IMPL-DEPTH] WARN: Unsupported language ($lang), running generic checks only"
      # Generic: 빈 블록 패턴
      local generic_empty
      generic_empty=$(grep -rnE '\{\s*\}' "${src_dirs[@]}" 2>/dev/null | grep -vE '(node_modules|\.git|dist|build|\.lock|\.json)' | grep -vE "$test_exclude_pattern" | head -20 || true)
      if [[ -n "$generic_empty" ]]; then
        local count
        count=$(echo "$generic_empty" | wc -l)
        src_count=$((src_count + count))
        src_findings="${src_findings}${generic_empty}\n"
      fi
      ;;
  esac

  local total_count=$((src_count + test_count))

  # 결과 출력
  if [[ $src_count -gt 0 ]]; then
    echo "[IMPL-DEPTH] Source file stubs: $src_count findings"
    printf '%b' "$src_findings" | head -20
  fi
  if [[ $test_count -gt 0 ]]; then
    echo "[IMPL-DEPTH] Test file issues: $test_count findings"
    printf '%b' "$test_findings" | head -20
  fi

  # verification.json 기록 (없으면 생성)
  local _impl_result
  _impl_result=$(if [[ $((src_count + test_count)) -ge $threshold ]]; then echo "fail"; elif [[ $((src_count + test_count)) -gt 0 ]]; then echo "warn"; else echo "pass"; fi)
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson sc "$src_count" --argjson tc "$test_count" --argjson th "$threshold" --arg r "$_impl_result" '
      .implementationDepth = {"srcStubs": $sc, "testIssues": $tc, "threshold": $th, "result": $r}
    '
  else
    jq -n --argjson sc "$src_count" --argjson tc "$test_count" --argjson th "$threshold" --arg r "$_impl_result" '
      {"implementationDepth": {"srcStubs": $sc, "testIssues": $tc, "threshold": $th, "result": $r}}
    ' > "$VERIFICATION_FILE"
  fi

  # DoD 업데이트
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    local has_dod
    has_dod=$(jq 'has("dod")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    if [[ "$has_dod" == "true" ]]; then
      local result_str="pass"
      [[ $total_count -ge $threshold ]] && result_str="fail"
      jq_inplace "$PROGRESS_FILE" --arg r "$result_str" --argjson sc "$src_count" --argjson tc "$test_count" '
        .dod.impl_depth_pass //= {"checked":false,"evidence":null}
        | .dod.impl_depth_pass.checked = ($r == "pass")
        | .dod.impl_depth_pass.evidence = "src stubs: \($sc), test issues: \($tc)"
      '
    fi
  fi

  # 판정
  local details
  details=$(jq -n --argjson sc "$src_count" --argjson tc "$test_count" --argjson th "$threshold" --arg l "$lang" '{"srcStubs":$sc,"testIssues":$tc,"threshold":$th,"lang":$l}')

  if [[ $total_count -ge $threshold ]]; then
    echo ""
    echo "[IMPL-DEPTH] FAIL: $total_count findings >= threshold $threshold"
    append_gate_history "implementation-depth" "fail" "$details"
    return 1
  elif [[ $total_count -gt 0 ]]; then
    echo ""
    echo "[IMPL-DEPTH] WARN: $total_count findings (threshold: $threshold)"
    append_gate_history "implementation-depth" "warn" "$details"
    return 0
  else
    echo ""
    echo "[IMPL-DEPTH] PASS: No stub implementations detected"
    append_gate_history "implementation-depth" "pass" "$details"
    return 0
  fi
}

# ─── test-quality: 테스트 품질 검증 (SOFT gate) ───

cmd_test_quality() {
  echo "=== Test Quality Check ==="

  # 테스트 디렉토리 탐지 (src 내 테스트 파일도 포함하되 US 커버리지는 테스트 파일만 대상)
  local test_dirs=()
  for d in test tests __tests__ spec; do
    [[ -d "$d" ]] && test_dirs+=("$d")
  done
  # src 내 테스트 파일도 포함 (*.test.*, *.spec.* 패턴만)
  if [[ -d "src" ]]; then
    local src_test_count
    src_test_count=$(find src -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "test_*" \) 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$src_test_count" -gt 0 ]]; then
      test_dirs+=("src")
    fi
  fi

  if [[ ${#test_dirs[@]} -eq 0 ]]; then
    echo "[TEST-QUALITY] SKIP: No test directories found"
    append_gate_history "test-quality" "skip" '{"reason":"no test dirs"}'
    return 2
  fi

  # 언어 감지
  local lang="unknown"
  if [[ -f "package.json" ]] || [[ -f "tsconfig.json" ]]; then
    lang="js"
  elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
    lang="python"
  elif [[ -f "go.mod" ]]; then
    lang="go"
  fi

  local total_tests=0 assertion_tests=0 skipped_tests=0

  case "$lang" in
    js)
      # 테스트 파일 수집
      local test_files
      test_files=$(find "${test_dirs[@]}" -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' \) 2>/dev/null || true)

      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        # test/it 호출 수
        local tc
        tc=$(grep -cE '^\s*(test|it)\s*\(' "$tf" 2>/dev/null || echo "0")
        total_tests=$((total_tests + tc))

        # assertion 줄 수 기반 비율 (파일 단위가 아닌 assertion 밀도)
        local ac
        ac=$(grep -cE '(expect|assert|should|toBe|toEqual|toHave|toContain|toThrow|toMatch)' "$tf" 2>/dev/null || echo "0")
        # assertion 줄이 테스트 수 이상이면 전량 커버, 아니면 비례 배분
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        # skip 수
        local sc
        sc=$(grep -cE '(test|it|describe)\.(skip|todo)\(' "$tf" 2>/dev/null || echo "0")
        skipped_tests=$((skipped_tests + sc))
      done <<< "$test_files"
      ;;

    python)
      local test_files
      test_files=$(find "${test_dirs[@]}" -type f \( -name 'test_*.py' -o -name '*_test.py' \) 2>/dev/null || true)

      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        local tc
        tc=$(grep -cE '^\s*def test_|^\s*async def test_' "$tf" 2>/dev/null || echo "0")
        total_tests=$((total_tests + tc))

        local ac
        ac=$(grep -cE '(assert |self\.assert|pytest\.raises)' "$tf" 2>/dev/null || echo "0")
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        local sc
        sc=$(grep -cE '@pytest\.mark\.skip|@unittest\.skip' "$tf" 2>/dev/null || echo "0")
        skipped_tests=$((skipped_tests + sc))
      done <<< "$test_files"
      ;;

    go)
      local test_files
      test_files=$(find "${test_dirs[@]}" -type f -name '*_test.go' 2>/dev/null || true)

      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        local tc
        tc=$(grep -cE '^func Test' "$tf" 2>/dev/null || echo "0")
        total_tests=$((total_tests + tc))

        local ac
        ac=$(grep -cE '(t\.(Error|Fatal|Fail|Assert)|assert\.|require\.)' "$tf" 2>/dev/null || echo "0")
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        local sc
        sc=$(grep -cE 't\.Skip\(' "$tf" 2>/dev/null || echo "0")
        skipped_tests=$((skipped_tests + sc))
      done <<< "$test_files"
      ;;

    *)
      echo "[TEST-QUALITY] WARN: Unsupported language ($lang), skipping detailed analysis"
      append_gate_history "test-quality" "skip" '{"reason":"unsupported language"}'
      return 2
      ;;
  esac

  if [[ $total_tests -eq 0 ]]; then
    echo "[TEST-QUALITY] WARN: No test functions found"
    append_gate_history "test-quality" "warn" '{"totalTests":0}'
    return 0
  fi

  # 비율 계산
  local assertion_ratio=0 skip_ratio=0
  assertion_ratio=$(( (assertion_tests * 100) / total_tests ))
  skip_ratio=$(( (skipped_tests * 100) / total_tests ))

  echo "[TEST-QUALITY] Total tests: $total_tests"
  echo "[TEST-QUALITY] Tests with assertions: $assertion_tests ($assertion_ratio%)"
  echo "[TEST-QUALITY] Skipped tests: $skipped_tests ($skip_ratio%)"

  # US-* 커버리지 (SPEC 존재 시)
  local us_total=0 us_covered=0 us_ratio=0
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done

  if [[ -n "$spec_file" ]]; then
    local us_ids
    us_ids=$(grep -oE 'US-(F|B)-[0-9]+' "$spec_file" 2>/dev/null | sort -u || true)
    if [[ -n "$us_ids" ]]; then
      us_total=$(echo "$us_ids" | wc -l)
      # US 커버리지는 테스트 파일만 대상 (프로덕션 코드의 US-* 주석 제외)
      # 테스트 파일에서 US ID를 1회 추출하여 집합화 (NUL 안전 — 직접 파이프)
      local covered_us_set
      covered_us_set=$(find "${test_dirs[@]}" -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "test_*" \) -print0 2>/dev/null \
        | xargs -0 grep -hoE 'US-(F|B)-[0-9]+' 2>/dev/null | sort -u || true)
      if [[ -n "$covered_us_set" ]]; then
        while IFS= read -r us; do
          if echo "$covered_us_set" | grep -qF "$us" 2>/dev/null; then
            us_covered=$((us_covered + 1))
          fi
        done <<< "$us_ids"
      fi
      [[ $us_total -gt 0 ]] && us_ratio=$(( (us_covered * 100) / us_total ))
      echo "[TEST-QUALITY] US coverage: $us_covered / $us_total ($us_ratio%)"
    fi
  fi

  # verification.json 기록 (없으면 생성)
  local _tq_json
  _tq_json=$(jq -n --argjson tt "$total_tests" --argjson at "$assertion_tests" --argjson ar "$assertion_ratio" \
    --argjson st "$skipped_tests" --argjson sr "$skip_ratio" \
    --argjson ust "$us_total" --argjson usc "$us_covered" --argjson usr "$us_ratio" '{
      "totalTests": $tt, "assertionTests": $at, "assertionRatio": $ar,
      "skippedTests": $st, "skipRatio": $sr,
      "usTotal": $ust, "usCovered": $usc, "usRatio": $usr
    }')
  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --argjson tq "$_tq_json" '.testQuality = $tq'
  else
    jq -n --argjson tq "$_tq_json" '{"testQuality": $tq}' > "$VERIFICATION_FILE"
  fi

  # 판정 (SOFT gate) — 임계값을 설정 파일에서 로드
  local min_assertion_pct max_skip_pct
  min_assertion_pct=$(config_get '.quality.assertionRatio' '0.7' | awk '{printf "%d", $1 * 100}')
  max_skip_pct=$(config_get '.quality.skipRatio' '0.2' | awk '{printf "%d", $1 * 100}')

  local issues=0
  [[ $assertion_ratio -lt $min_assertion_pct ]] && { echo "[TEST-QUALITY] WARN: Assertion ratio $assertion_ratio% < $min_assertion_pct%"; issues=$((issues + 1)); }
  [[ $skip_ratio -gt $max_skip_pct ]] && { echo "[TEST-QUALITY] WARN: Skip ratio $skip_ratio% > $max_skip_pct%"; issues=$((issues + 1)); }

  local details
  details=$(jq -n --argjson tt "$total_tests" --argjson ar "$assertion_ratio" --argjson sr "$skip_ratio" --argjson usr "$us_ratio" \
    '{"totalTests":$tt,"assertionRatio":$ar,"skipRatio":$sr,"usRatio":$usr}')

  if [[ $issues -gt 0 ]]; then
    echo ""
    echo "[TEST-QUALITY] WARN: $issues quality issues found"
    append_gate_history "test-quality" "warn" "$details"
    return 0
  else
    echo ""
    echo "[TEST-QUALITY] PASS: Test quality acceptable"
    append_gate_history "test-quality" "pass" "$details"
    return 0
  fi
}

# ─── page-render-check: 프론트엔드 페이지 렌더링 검증 (Playwright 기반) ───

cmd_page_render_check() {
  echo "=== Page Render Check ==="

  local port="3000"
  local strict=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) strict=true; shift ;;
      --port)
        port="${2:?--port requires a number}"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
          die "page-render-check: --port must be a positive integer, got '$port'"
        fi
        if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
          die "page-render-check: --port must be 1-65535, got '$port'"
        fi
        shift 2 ;;
      *) shift ;;
    esac
  done

  # 프론트엔드 프로젝트 확인
  local has_frontend="false"
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend // false' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  fi
  if [[ "$has_frontend" == "false" ]]; then
    # 자동 감지
    for d in pages app components client src/pages src/app; do
      [[ -d "$d" ]] && has_frontend="true" && break
    done
  fi

  if [[ "$has_frontend" != "true" ]]; then
    echo "[page-render] SKIP: Not a frontend project"
    append_gate_history "page-render-check" "skip" '{"reason":"not frontend"}'
    return 2
  fi

  # Playwright 설치 확인
  if ! command -v npx >/dev/null 2>&1; then
    echo "[page-render] SKIP: npx not available"
    append_gate_history "page-render-check" "skip" '{"reason":"npx not available"}'
    return 2
  fi

  # 페이지 경로 추출 (SPEC 또는 progress에서)
  local page_routes="/"
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done

  if [[ -n "$spec_file" ]]; then
    local extracted
    extracted=$(grep -oE '(경로|path|route)[:\s]*/[a-zA-Z0-9/_-]+' "$spec_file" 2>/dev/null | grep -oE '/[a-zA-Z0-9/_-]+' | sort -u | head -10 || true)
    if [[ -n "$extracted" ]]; then
      page_routes="$extracted"
    fi
  fi

  # 서버 시작
  local start_cmd
  start_cmd=$(_detect_start_cmd)
  if [[ -z "$start_cmd" ]]; then
    echo "[page-render] SKIP: No start command detected"
    append_gate_history "page-render-check" "skip" '{"reason":"no start command"}'
    return 2
  fi

  echo "[page-render] Starting server: $start_cmd"
  if ! _start_and_wait_server "$start_cmd" "$port" 15 "page-render"; then
    echo "[page-render] FAIL: Server did not start"
    _cleanup_server
    append_gate_history "page-render-check" "fail" '{"reason":"server start failed"}'
    return 1
  fi

  # Playwright 렌더링 검증 스크립트 생성 (임시)
  local tmp_script
  tmp_script=$(mktemp --suffix=.mjs)
  cat > "$tmp_script" << 'PLAYWRIGHT_SCRIPT'
import { chromium } from 'playwright';

const BASE = process.env.BASE_URL || 'http://localhost:3000';
const routes = (process.env.PAGE_ROUTES || '/').split('\n').filter(r => r.trim());

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (e) {
    console.log('[page-render] Playwright chromium not installed, attempting install...');
    const { execSync } = await import('child_process');
    execSync('npx playwright install chromium', { stdio: 'inherit' });
    browser = await chromium.launch({ headless: true });
  }

  const context = await browser.newContext();
  const page = await context.newPage();

  const errors = [];
  const consoleErrors = [];

  page.on('pageerror', err => errors.push(err.message));
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  let totalPages = 0, passPages = 0, failPages = 0;
  const results = [];

  for (const route of routes) {
    totalPages++;
    errors.length = 0;
    consoleErrors.length = 0;

    try {
      const resp = await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle', timeout: 10000 });
      const status = resp?.status() || 0;
      const bodyText = await page.evaluate(() => document.body?.innerText?.trim() || '');
      const bodyLen = bodyText.length;

      const issues = [];
      if (status >= 400) issues.push(`HTTP ${status}`);
      if (bodyLen === 0) issues.push('empty page (no text content)');
      if (errors.length > 0) issues.push(`${errors.length} JS error(s)`);
      if (consoleErrors.length > 0) issues.push(`${consoleErrors.length} console.error(s)`);

      if (issues.length === 0) {
        console.log(`  [PASS] ${route} — HTTP ${status}, ${bodyLen} chars`);
        passPages++;
        results.push({ route, status, result: 'pass' });
      } else {
        console.log(`  [FAIL] ${route} — ${issues.join(', ')}`);
        failPages++;
        results.push({ route, status, result: 'fail', issues });
        if (errors.length > 0) errors.forEach(e => console.log(`    JS Error: ${e}`));
        if (consoleErrors.length > 0) consoleErrors.forEach(e => console.log(`    Console Error: ${e}`));
      }
    } catch (e) {
      console.log(`  [FAIL] ${route} — ${e.message}`);
      failPages++;
      results.push({ route, status: 0, result: 'fail', issues: [e.message] });
    }
  }

  await browser.close();

  console.log(`\n[page-render] Results: ${passPages}/${totalPages} passed, ${failPages} failed`);
  console.log(JSON.stringify({ total: totalPages, pass: passPages, fail: failPages, results }));

  process.exit(failPages > 0 ? 1 : 0);
})();
PLAYWRIGHT_SCRIPT

  # 시그널 시 임시 파일 정리 보장
  trap "rm -f '$tmp_script'; _cleanup_server; trap - EXIT INT TERM" EXIT INT TERM

  # 실행
  echo "[page-render] Checking pages: $(echo "$page_routes" | tr '\n' ' ')"
  local output exit_code
  output=$(PAGE_ROUTES="$page_routes" BASE_URL="http://localhost:${port}" node "$tmp_script" 2>&1) && exit_code=0 || exit_code=$?
  echo "$output"

  rm -f "$tmp_script"
  _cleanup_server
  trap - EXIT INT TERM

  # 실행 실패 시 fail-closed (codex ERR-HIGH-3: SKIP 오분류 방지)
  if [[ $exit_code -ne 0 ]]; then
    # JSON 결과가 출력되었는지 확인 — 없으면 게이트 자체 실패
    if ! echo "$output" | grep -q '^{'; then
      echo "[page-render] FAIL: Playwright/Node execution failed (exit $exit_code, no result JSON)"
      append_gate_history "page-render-check" "fail" "{\"reason\":\"execution_failed\",\"exitCode\":$exit_code}"
      return 1
    fi
  fi

  # 결과 파싱
  local total_pages=0 pass_pages=0 fail_pages=0
  local json_line
  json_line=$(echo "$output" | grep '^{' | tail -1 || true)
  if [[ -n "$json_line" ]]; then
    total_pages=$(echo "$json_line" | jq '.total // 0' 2>/dev/null || echo "0")
    pass_pages=$(echo "$json_line" | jq '.pass // 0' 2>/dev/null || echo "0")
    fail_pages=$(echo "$json_line" | jq '.fail // 0' 2>/dev/null || echo "0")
  fi

  # verification.json 기록
  local result_str="pass"
  [[ $fail_pages -gt 0 ]] && result_str="fail"
  [[ $total_pages -eq 0 && $exit_code -eq 0 ]] && result_str="skip"
  [[ $total_pages -eq 0 && $exit_code -ne 0 ]] && result_str="fail"

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --arg r "$result_str" --argjson tp "$total_pages" --argjson pp "$pass_pages" --argjson fp "$fail_pages" '
      .pageRender = {"result": $r, "totalPages": $tp, "passPages": $pp, "failPages": $fp}
    '
  else
    jq -n --arg r "$result_str" --argjson tp "$total_pages" --argjson pp "$pass_pages" --argjson fp "$fail_pages" '
      {"pageRender": {"result": $r, "totalPages": $tp, "passPages": $pp, "failPages": $fp}}
    ' > "$VERIFICATION_FILE"
  fi

  # 판정
  local details
  details=$(jq -n --argjson tp "$total_pages" --argjson pp "$pass_pages" --argjson fp "$fail_pages" --arg r "$result_str" \
    '{"totalPages":$tp,"passPages":$pp,"failPages":$fp,"result":$r}')

  if [[ $fail_pages -gt 0 ]]; then
    echo ""
    echo "[page-render] FAIL: $fail_pages/$total_pages pages have issues"
    append_gate_history "page-render-check" "fail" "$details"
    if [[ "$strict" == "true" ]]; then
      return 1
    else
      return 0  # SOFT gate: WARN
    fi
  elif [[ $total_pages -eq 0 ]]; then
    echo ""
    echo "[page-render] SKIP: No pages to check"
    append_gate_history "page-render-check" "skip" "$details"
    return 2
  else
    echo ""
    echo "[page-render] PASS: All $total_pages pages render correctly"
    append_gate_history "page-render-check" "pass" "$details"
    return 0
  fi
}

# ─── functional-flow: 핵심 플로우 검증 (프로젝트 유형별) ───

cmd_functional_flow() {
  echo "=== Functional Flow Check ==="

  # 프로젝트 유형 판단
  local project_type="unknown"
  local has_frontend="false" has_backend="false"

  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend // false' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend // false' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  fi

  # 자동 감지 (progress 파일 없는 경우)
  if [[ "$has_frontend" == "false" ]] && [[ "$has_backend" == "false" ]]; then
    [[ -d "pages" ]] || [[ -d "app" ]] || [[ -d "components" ]] || [[ -d "client" ]] && has_frontend="true"
    [[ -d "server" ]] || [[ -d "routes" ]] || [[ -d "controllers" ]] || [[ -d "api" ]] && has_backend="true"
    # scripts.start 또는 scripts.dev가 있으면 실행 가능한 서버 (backend)
    [[ -f "package.json" ]] && jq -e '.scripts.start // .scripts.dev' package.json >/dev/null 2>&1 && has_backend="true"
  fi

  if [[ "$has_frontend" == "true" ]] && [[ "$has_backend" == "true" ]]; then
    project_type="fullstack"
  elif [[ "$has_backend" == "true" ]]; then
    project_type="api"
  elif [[ "$has_frontend" == "true" ]]; then
    project_type="frontend"
  elif [[ -f "package.json" ]] && jq -e '.bin' package.json >/dev/null 2>&1; then
    project_type="cli"
  elif [[ -f "package.json" ]] && jq -e '.exports // .main' package.json >/dev/null 2>&1; then
    project_type="library"
  fi

  echo "[FLOW] Detected project type: $project_type"

  local all_pass=true
  local flow_results=""
  local flows_executed=0

  # API smoke 스크립트 실행
  run_smoke_script() {
    local script="$1" label="$2"
    if [[ ! -f "$script" ]]; then
      echo "[FLOW] SKIP: $script not found"
      return 2
    fi
    if [[ ! -x "$script" ]]; then
      chmod +x "$script" 2>/dev/null || true
    fi

    echo "[FLOW] Running $label: $script"
    local output exit_code
    output=$(bash "$script" 2>&1) && exit_code=0 || exit_code=$?

    flows_executed=$((flows_executed + 1))
    if [[ $exit_code -eq 0 ]]; then
      echo "[FLOW] $label: PASS"
      flow_results="${flow_results}${label}: pass; "
    else
      echo "[FLOW] $label: FAIL (exit $exit_code)"
      echo "$output" | tail -10
      all_pass=false
      flow_results="${flow_results}${label}: fail; "
    fi
    return $exit_code
  }

  case "$project_type" in
    api|backend)
      run_smoke_script "tests/api-smoke.sh" "API Smoke" || true
      ;;
    frontend)
      if [[ -f "tests/ui-smoke.sh" ]]; then
        run_smoke_script "tests/ui-smoke.sh" "UI Smoke" || true
      elif [[ -f "tests/ui-smoke.spec.ts" ]] || [[ -f "tests/ui-smoke.spec.js" ]]; then
        echo "[FLOW] Running Playwright UI smoke..."
        local output exit_code
        output=$(npx playwright test tests/ui-smoke.spec.* --reporter=list 2>&1) && exit_code=0 || exit_code=$?
        flows_executed=$((flows_executed + 1))
        if [[ $exit_code -eq 0 ]]; then
          echo "[FLOW] UI Smoke: PASS"
          flow_results="UI Smoke: pass"
        else
          echo "[FLOW] UI Smoke: FAIL"
          echo "$output" | tail -10
          all_pass=false
          flow_results="UI Smoke: fail"
        fi
      else
        echo "[FLOW] SKIP: No UI smoke script found"
        append_gate_history "functional-flow" "skip" '{"reason":"no ui smoke script","type":"frontend"}'
        return 2
      fi
      ;;
    fullstack)
      run_smoke_script "tests/api-smoke.sh" "API Smoke" || true
      if [[ -f "tests/ui-smoke.sh" ]]; then
        run_smoke_script "tests/ui-smoke.sh" "UI Smoke" || true
      elif [[ -f "tests/ui-smoke.spec.ts" ]] || [[ -f "tests/ui-smoke.spec.js" ]]; then
        echo "[FLOW] Running Playwright UI smoke..."
        local output exit_code
        output=$(npx playwright test tests/ui-smoke.spec.* --reporter=list 2>&1) && exit_code=0 || exit_code=$?
        flows_executed=$((flows_executed + 1))
        if [[ $exit_code -eq 0 ]]; then
          echo "[FLOW] UI Smoke: PASS"
          flow_results="${flow_results}UI Smoke: pass; "
        else
          echo "[FLOW] UI Smoke: FAIL"
          echo "$output" | tail -10
          all_pass=false
          flow_results="${flow_results}UI Smoke: fail; "
        fi
      fi
      ;;
    library|cli)
      run_smoke_script "tests/lib-smoke.sh" "Lib Smoke" || true
      ;;
    *)
      echo "[FLOW] SKIP: Unknown project type, no smoke scripts to run"
      append_gate_history "functional-flow" "skip" '{"reason":"unknown project type"}'
      return 2
      ;;
  esac

  # flows_executed == 0 판정을 먼저 수행 (verification/DoD 기록보다 선행)
  if [[ $flows_executed -eq 0 ]]; then
    local details
    details=$(jq -n --arg pt "$project_type" '{"projectType":$pt,"flows":"none","result":"skip"}')
    # SKIP 시 DoD는 checked=false로 기록
    if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
      local has_dod
      has_dod=$(jq 'has("dod")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
      if [[ "$has_dod" == "true" ]]; then
        jq_inplace "$PROGRESS_FILE" '.dod.functional_flow_pass //= {"checked":false,"evidence":null} | .dod.functional_flow_pass.checked = false | .dod.functional_flow_pass.evidence = "skip: no smoke scripts"'
      fi
    fi
    if [[ -f "$VERIFICATION_FILE" ]]; then
      jq_inplace "$VERIFICATION_FILE" --arg pt "$project_type" '.functionalFlow = {"result": "skip", "projectType": $pt, "details": "no smoke scripts"}'
    else
      jq -n --arg pt "$project_type" '{"functionalFlow": {"result": "skip", "projectType": $pt, "details": "no smoke scripts"}}' > "$VERIFICATION_FILE"
    fi
    echo ""
    echo "[FLOW] SKIP: No smoke scripts found for project type '$project_type'"
    append_gate_history "functional-flow" "skip" "$details"
    return 2
  fi

  # verification.json + DoD 기록 (flows_executed > 0 확인 후)
  local result_str="pass"
  [[ "$all_pass" != "true" ]] && result_str="fail"

  if [[ -f "$VERIFICATION_FILE" ]]; then
    jq_inplace "$VERIFICATION_FILE" --arg r "$result_str" --arg fr "$flow_results" --arg pt "$project_type" '
      .functionalFlow = {"result": $r, "projectType": $pt, "details": $fr}
    '
  else
    jq -n --arg r "$result_str" --arg fr "$flow_results" --arg pt "$project_type" '
      {"functionalFlow": {"result": $r, "projectType": $pt, "details": $fr}}
    ' > "$VERIFICATION_FILE"
  fi

  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    local has_dod
    has_dod=$(jq 'has("dod")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    if [[ "$has_dod" == "true" ]]; then
      jq_inplace "$PROGRESS_FILE" --arg r "$result_str" --arg fr "$flow_results" '
        .dod.functional_flow_pass //= {"checked":false,"evidence":null}
        | .dod.functional_flow_pass.checked = ($r == "pass")
        | .dod.functional_flow_pass.evidence = $fr
      '
    fi
  fi

  local details
  details=$(jq -n --arg pt "$project_type" --arg fr "$flow_results" --arg r "$result_str" '{"projectType":$pt,"flows":$fr,"result":$r}')

  if [[ "$all_pass" == "true" ]]; then
    echo ""
    echo "[FLOW] ALL FLOWS PASSED ($flows_executed flow(s) executed)"
    append_gate_history "functional-flow" "pass" "$details"
    return 0
  else
    echo ""
    echo "[FLOW] SOME FLOWS FAILED: $flow_results"
    append_gate_history "functional-flow" "fail" "$details"
    return 1
  fi
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

# ─── doc-size-check: 문서 크기 가드 (30KB 경고) ───

cmd_doc_size_check() {
  local docs_dir="${1:-docs}"
  local threshold_kb="${2:-$(config_get '.docs.maxSizeKB' '30')}"

  # 입력 검증: threshold_kb는 양의 정수
  if ! [[ "$threshold_kb" =~ ^[0-9]+$ ]] || [[ "$threshold_kb" -lt 1 ]]; then
    die "doc-size-check: threshold_kb must be a positive integer, got '$threshold_kb'"
  fi

  echo "=== Document Size Check (threshold: ${threshold_kb}KB) ==="

  if [[ ! -d "$docs_dir" ]]; then
    echo "[doc-size-check] SKIP (no $docs_dir directory)"
    return 0
  fi

  local oversized=0 total=0 oversized_list=""

  while IFS= read -r -d '' file; do
    total=$((total + 1))
    local size_bytes
    size_bytes=$(wc -c < "$file" 2>/dev/null || echo "0")
    local threshold_bytes=$((threshold_kb * 1024))
    local size_kb=$(( (size_bytes + 1023) / 1024 ))  # 올림

    if [[ "$size_bytes" -gt "$threshold_bytes" ]]; then
      oversized=$((oversized + 1))
      oversized_list="${oversized_list}  - $(basename "$file"): ${size_kb}KB (>${threshold_kb}KB)\n"
      echo "  [WARN] $(basename "$file"): ${size_kb}KB exceeds ${threshold_kb}KB — consider splitting"
    fi
  done < <(find "$docs_dir" -maxdepth 2 -name "*.md" -print0 2>/dev/null)

  local result="pass"
  if [[ "$oversized" -gt 0 ]]; then
    result="warn"
    echo ""
    echo "[doc-size-check] $oversized/$total documents exceed ${threshold_kb}KB"
    echo "Recommendation: split large documents by feature (1 document = 1 feature, ≤${threshold_kb}KB)"
  else
    echo "[doc-size-check] All $total documents within ${threshold_kb}KB limit"
  fi

  append_gate_history "doc-size-check" "$result" \
    "{\"total\":$total,\"oversized\":$oversized,\"thresholdKB\":$threshold_kb}"

  echo "=== DOC SIZE CHECK: ${result^^} ==="
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
    append_gate_history "docker-build-check" "pass" "{\"dockerfile\":\"$dockerfile\"}"
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

# ─── ambiguity-check: TBD/모호 표현 탐지 (SOFT gate) ───

cmd_ambiguity_check() {
  local docs_dir="${1:-docs}"
  echo "=== Ambiguity Check ==="

  # 스캔 대상 파일 수집: docs/ + 프로젝트 루트 .md
  local scan_files=()
  for f in overview.md SPEC.md spec.md README.md; do
    [[ -f "$f" ]] && scan_files+=("$f")
  done
  if [[ -d "$docs_dir" ]]; then
    while IFS= read -r -d '' f; do
      scan_files+=("$f")
    done < <(find "$docs_dir" -maxdepth 2 -name "*.md" -print0 2>/dev/null)
  fi

  if [[ ${#scan_files[@]} -eq 0 ]]; then
    echo "[ambiguity-check] SKIP (no documentation files found)"
    append_gate_history "ambiguity-check" "skip" '{"reason":"no docs"}'
    return 0
  fi

  # 모호 표현 패턴 (한국어 + 영어)
  local pattern='\bTBD\b|\bTODO\b|\bFIXME\b|to be decided|to be determined|미정|추후 결정|추후|as needed|if appropriate|적절한|등등|나중에|optionally|필요 시|Phase [0-9]에서 추가|later phase'

  local total_matches=0 match_output=""

  # 단일 grep으로 전체 스캔 (코드 블록 제외 후)
  for f in "${scan_files[@]}"; do
    # awk로 fenced code block(``` ... ```) 내부 제거
    local filtered
    filtered=$(awk '/^```/{skip=!skip; next} !skip{print NR": "$0}' "$f" 2>/dev/null || true)
    local matches
    matches=$(echo "$filtered" | grep -iE "$pattern" | head -20 || true)
    if [[ -n "$matches" ]]; then
      local count
      count=$(echo "$matches" | wc -l | tr -d ' ')
      total_matches=$((total_matches + count))
      match_output="${match_output}--- $f ($count matches) ---\n$matches\n\n"
    fi
  done

  local result="pass"
  if [[ "$total_matches" -gt 0 ]]; then
    result="warn"
    printf '%b' "$match_output"
    echo "[ambiguity-check] WARN: $total_matches ambiguous/deferred expressions found"
    echo "  All TBD/TODO markers must be replaced with concrete decisions before Phase 2."
  else
    echo "[ambiguity-check] All documentation has concrete decisions (no TBD/TODO)"
  fi

  append_gate_history "ambiguity-check" "$result" "{\"matches\":$total_matches}"
  echo "=== AMBIGUITY CHECK: ${result^^} ==="
}

# ─── spec-completeness: 기획 문서 완전성 검사 (HARD gate) ───

cmd_spec_completeness() {
  echo "=== Spec Completeness Check ==="
  require_jq
  require_progress

  local critical=0 major=0 minor=0
  local issues=""

  # projectScope 로드 (fail-closed: 누락/타입 오류 시 CRITICAL)
  local has_frontend="false" has_backend="false"
  local scope_valid
  scope_valid=$(jq -r '
    .phases.phase_0.outputs.projectScope
    | if type == "object" and has("hasFrontend") and has("hasBackend")
         and (.hasFrontend | type == "boolean") and (.hasBackend | type == "boolean")
      then "valid" else "invalid" end
  ' "$PROGRESS_FILE" 2>/dev/null || echo "invalid")
  if [[ "$scope_valid" != "valid" ]]; then
    critical=$((critical + 1))
    issues="${issues}CRITICAL: projectScope missing or malformed in progress file (need {hasFrontend: bool, hasBackend: bool})\n"
  else
    has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  fi

  # ── 공통 검사 ──

  # overview.md 존재 + 빈 섹션 검사
  if [[ ! -f "overview.md" ]]; then
    critical=$((critical + 1))
    issues="${issues}CRITICAL: overview.md not found\n"
  else
    local empty_sections
    empty_sections=$(awk '/^##/ {title=$0; getline; if (/^$/ || /^##/) print title}' overview.md 2>/dev/null | head -10 || true)
    if [[ -n "$empty_sections" ]]; then
      local count
      count=$(echo "$empty_sections" | wc -l | tr -d ' ')
      major=$((major + count))
      issues="${issues}MAJOR: overview.md has $count empty section(s):\n$empty_sections\n"
    fi
  fi

  # SPEC.md 존재
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done
  if [[ -z "$spec_file" ]]; then
    critical=$((critical + 1))
    issues="${issues}CRITICAL: SPEC.md not found (searched: SPEC.md, docs/SPEC.md, docs/api-spec.md, spec.md)\n"
  else
    # US-* ID 존재
    local us_count
    us_count=$(grep -oE 'US-(F|B)-[0-9]+' "$spec_file" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$us_count" -eq 0 ]]; then
      major=$((major + 1))
      issues="${issues}MAJOR: No User Story IDs (US-F-*/US-B-*) in $spec_file\n"
    fi

    # Acceptance Criteria 존재 (US가 있는데 AC가 없는 경우)
    if [[ "$us_count" -gt 0 ]]; then
      local ac_count
      ac_count=$({ grep -iE 'acceptance criteria|인수 기준|완료 조건|AC:' "$spec_file" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [[ "$ac_count" -eq 0 ]]; then
        major=$((major + 1))
        issues="${issues}MAJOR: User Stories exist but no Acceptance Criteria found in $spec_file\n"
      fi
    fi
  fi

  # test-plan.md 존재
  local has_test_plan=false
  for tp in "docs/test-plan.md" "test-plan.md"; do
    [[ -f "$tp" ]] && { has_test_plan=true; break; }
  done
  if [[ "$has_test_plan" == "false" ]]; then
    major=$((major + 1))
    issues="${issues}MAJOR: test-plan.md not found (Test Strategist output required)\n"
  fi

  # TBD/모호 표현 (ambiguity-check 직접 스캔 — cmd 호출 대신 인라인으로 결과 수집)
  local ambiguity_matches=0
  local ambiguity_pattern='TBD|TODO|FIXME|to be decided|to be determined|미정|추후 결정|추후|as needed|if appropriate|적절한|등등|나중에|optionally|필요 시|Phase [0-9]에서 추가|later phase'
  local ambiguity_files=()
  for af in overview.md SPEC.md spec.md; do
    [[ -f "$af" ]] && ambiguity_files+=("$af")
  done
  if [[ -d "docs" ]]; then
    while IFS= read -r -d '' af; do
      ambiguity_files+=("$af")
    done < <(find docs -maxdepth 2 -name "*.md" -print0 2>/dev/null)
  fi
  if [[ ${#ambiguity_files[@]} -gt 0 ]]; then
    # 코드 블록 제외: ``` 사이 라인 스킵
    ambiguity_matches=$({ for af in "${ambiguity_files[@]}"; do
      awk '/^```/{skip=!skip; next} !skip{print}' "$af" 2>/dev/null
    done; } | grep -icE "$ambiguity_pattern" || true)
    # grep -c가 0매치 시 빈 문자열 또는 "0"을 반환; 정수 보정
    ambiguity_matches=$(echo "$ambiguity_matches" | tr -d '[:space:]')
    [[ -z "$ambiguity_matches" || ! "$ambiguity_matches" =~ ^[0-9]+$ ]] && ambiguity_matches=0
  fi
  if [[ "$ambiguity_matches" -gt 0 ]]; then
    major=$((major + 1))
    issues="${issues}MAJOR: $ambiguity_matches TBD/ambiguous expressions in documentation\n"
  fi

  # ── hasBackend 검사 ──
  if [[ "$has_backend" == "true" ]] && [[ -n "$spec_file" ]]; then
    # API Contract 섹션
    if ! grep -qiE 'API Contract|API 계약|엔드포인트|Endpoint' "$spec_file" 2>/dev/null; then
      critical=$((critical + 1))
      issues="${issues}CRITICAL: Backend project but no API Contract section in $spec_file\n"
    fi

    # Data Model 섹션
    if ! grep -qiE 'Data Model|데이터 모델|DB Schema|스키마' "$spec_file" 2>/dev/null; then
      critical=$((critical + 1))
      issues="${issues}CRITICAL: Backend project but no Data Model section in $spec_file\n"
    fi

    # 에러 포맷 정의 (MAJOR)
    if ! grep -qiE 'Error Response|에러 응답|에러 포맷|error format' "$spec_file" 2>/dev/null; then
      major=$((major + 1))
      issues="${issues}MAJOR: Backend project but no standard error response format defined\n"
    fi

    # 상태 전이 테이블 (status 필드가 있는 경우)
    if grep -qiE 'status.*CHECK|status.*ENUM|상태.*필드' "$spec_file" 2>/dev/null; then
      if ! grep -qiE 'State Machine|상태 전이|State Transition|from.*→.*to|from.*->.*to' "$spec_file" 2>/dev/null; then
        major=$((major + 1))
        issues="${issues}MAJOR: Status fields found but no state transition table defined\n"
      fi
    fi
  fi

  # ── hasFrontend 검사 ──
  if [[ "$has_frontend" == "true" ]] && [[ -n "$spec_file" ]]; then
    # Frontend Pages 섹션
    if ! grep -qiE 'Frontend Pages|프론트엔드.*페이지|화면.*목록|Pages.*Components' "$spec_file" 2>/dev/null; then
      critical=$((critical + 1))
      issues="${issues}CRITICAL: Frontend project but no Frontend Pages section in $spec_file\n"
    fi
  fi

  # ── Fullstack 검사 ──
  if [[ "$has_frontend" == "true" ]] && [[ "$has_backend" == "true" ]] && [[ -n "$spec_file" ]]; then
    # 데이터 흐름 추적 (MINOR — 권장)
    if ! grep -qiE 'Data Flow|데이터 흐름|Flow Trace|플로우 추적' "$spec_file" 2>/dev/null; then
      minor=$((minor + 1))
      issues="${issues}MINOR: Fullstack project — consider adding data flow traces for critical paths\n"
    fi
  fi

  # ── NFR (MINOR) ──
  if [[ -n "$spec_file" ]]; then
    if ! grep -qiE 'Non-Functional|비기능|성능.*요구|Performance.*Requirement' "$spec_file" 2>/dev/null; then
      minor=$((minor + 1))
      issues="${issues}MINOR: No non-functional requirements section\n"
    fi
  fi

  # ── 결과 출력 ──
  echo ""
  if [[ -n "$issues" ]]; then
    printf '%b\n' "$issues"
  fi

  echo "┌─────────────────────────────────────┐"
  echo "│ CRITICAL: $critical  MAJOR: $major  MINOR: $minor"
  echo "└─────────────────────────────────────┘"

  local result="pass"
  if [[ "$critical" -gt 0 ]]; then
    result="fail"
  elif [[ "$major" -gt 0 ]]; then
    result="warn"
  fi

  append_gate_history "spec-completeness" "$result" \
    "{\"critical\":$critical,\"major\":$major,\"minor\":$minor}"

  echo "=== SPEC COMPLETENESS: ${result^^} ==="

  if [[ "$critical" -gt 0 ]]; then
    echo "BLOCKED: $critical CRITICAL issue(s) must be resolved before Phase 2."
    return 1
  fi
  return 0
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

# ─── 메인 디스패치 ───

main() {
  local subcmd="${1:-help}"
  shift || true

  # --progress-file를 글로벌로 파싱
  parse_progress_file_arg "$@"
  set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

  case "$subcmd" in
    init)              cmd_init "$@" ;;
    init-config)       cmd_init_config "$@" ;;
    init-ralph)        cmd_init_ralph "$@" ;;
    status)            cmd_status "$@" ;;
    update-step)       cmd_update_step "$@" ;;
    # 하위 호환: update-phase도 update-step으로 처리
    update-phase)      cmd_update_step "$@" ;;
    quality-gate)      cmd_quality_gate "$@" ;;
    vuln-scan)         cmd_vuln_scan "$@" ;;
    secret-scan)       cmd_secret_scan "$@" ;;
    artifact-check)    cmd_artifact_check "$@" ;;
    smoke-check)       cmd_smoke_check "$@" ;;
    record-error)      cmd_record_error "$@" ;;
    check-tools)       cmd_check_tools "$@" ;;
    find-debug-code)   cmd_find_debug_code "$@" ;;
    doc-consistency)   cmd_doc_consistency "$@" ;;
    doc-code-check)    cmd_doc_code_check "$@" ;;
    e2e-gate)           cmd_e2e_gate "$@" ;;
    design-polish-gate) cmd_design_polish_gate "$@" ;;
    placeholder-check)  cmd_placeholder_check "$@" ;;
    external-service-check) cmd_external_service_check "$@" ;;
    service-test-check) cmd_service_test_check "$@" ;;
    integration-smoke)  cmd_integration_smoke "$@" ;;
    implementation-depth) cmd_implementation_depth "$@" ;;
    test-quality)      cmd_test_quality "$@" ;;
    page-render-check) cmd_page_render_check "$@" ;;
    functional-flow)   cmd_functional_flow "$@" ;;
    skip-phases)       cmd_skip_phases "$@" ;;
    doc-size-check)    cmd_doc_size_check "$@" ;;
    checkpoint)        cmd_checkpoint "$@" ;;
    docker-build-check) cmd_docker_build_check "$@" ;;
    ambiguity-check)   cmd_ambiguity_check "$@" ;;
    spec-completeness) cmd_spec_completeness "$@" ;;
    add-dod-key)       cmd_add_dod_key "$@" ;;
    recover)           cmd_recover "$@" ;;
    handoff-update)    cmd_handoff_update "$@" ;;
    help|--help|-h)
      echo "Usage: shared-gate.sh <subcommand> [--progress-file <path>] [args]"
      echo ""
      echo "Subcommands:"
      echo "  init [--template <type>] [project] [req]  - Initialize progress JSON"
      echo "    Templates: full-auto, plan, implement, review, polish, e2e, doc-check"
      echo "  init-config                                  - Initialize .claude-auto-config.json"
      echo "  init-ralph <promise> <progress_file> [max] - Create Ralph Loop file"
      echo "  status                                     - Show current status"
      echo "  update-step <step> <status>                - Transition step state"
      echo "  quality-gate                               - Run build/type/lint/test (+ env manifest)"
      echo "  vuln-scan                                  - Dependency vulnerability scan (auto-detect)"
      echo "  secret-scan                                - Scan for hardcoded secrets (HARD_FAIL)"
      echo "  artifact-check                             - Check build artifact exists (SOFT_FAIL)"
      echo "  smoke-check [port] [timeout] [--max-retries N] [--backoff S] - Server start + healthcheck (SOFT_FAIL)"
      echo "  record-error --file <f> --type <t> --msg <m> [--level L0-L5] [--action '...']"
      echo "                                             - Record error + escalation tracking"
      echo "    --level L0-L5    Error level (L0=env, L1=build, L2=type, L3=runtime, L4=quality, L5=user)"
      echo "    --action '...'   Description of attempted fix"
      echo "    --result pass|fail  Result of the action"
      echo "    --reset-count    Reset attempt counter (on escalation level change)"
      echo "    Exit codes: 0=continue, 1=escalate, 2=codex needed, 3=user intervention"
      echo "  check-tools                                - Check codex/gemini availability"
      echo "  find-debug-code [dir]                      - Find debug code"
      echo "  doc-consistency [docs_dir]                 - Check doc consistency"
      echo "  doc-code-check [docs_dir]                  - Check doc-code matching"
      echo "  e2e-gate                                   - Run E2E tests (auto-detect framework)"
      echo "  design-polish-gate                         - WCAG check + screenshot capture (SOFT_FAIL)"
      echo "  implementation-depth [--threshold N] [--dir D] - Detect stub/empty implementations (SOFT)"
      echo "  test-quality                               - Check test assertion ratio, skip ratio, US coverage (SOFT)"
      echo "  page-render-check [--port N] [--strict]    - Playwright page render check (blank/errors/404)"
      echo "  functional-flow                            - Run project-type-specific smoke scripts (api/frontend/fullstack)"
      echo "  skip-phases <N>                              - Skip Phase 0~(N-1), start from Phase N"
      echo "  doc-size-check [docs_dir] [threshold_kb]     - Check doc sizes (default 30KB, SOFT)"
      echo "  checkpoint create|list|suggest-rollback       - Git checkpoint management"
      echo "  docker-build-check                           - Dockerfile build verification"
      echo "  ambiguity-check [docs_dir]                   - Scan for TBD/TODO/ambiguous language (SOFT)"
      echo "  spec-completeness                            - Planning doc completeness check (HARD on CRITICAL)"
      echo "  add-dod-key <key>                          - Add DoD key dynamically (idempotent)"
      echo "  recover                                     - Show recovery info (handoff + next steps)"
      echo "  handoff-update --next-steps <s> [--phase <p>] [--completed <c>] [--warnings <w>]"
      echo "                                             - Update handoff fields atomically"
      echo ""
      echo "Global options:"
      echo "  --progress-file <path>  Specify progress file (auto-detected if omitted)"
      ;;
    *)
      die "Unknown subcommand: $subcmd. Run with 'help' for usage."
      ;;
  esac
}

main "$@"
