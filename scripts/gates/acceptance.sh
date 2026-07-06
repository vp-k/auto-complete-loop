# gates/acceptance.sh — 인수 테스트 선작성+동결(freeze) + 실행 게이트
#
# 계약 (skills/rules 담당자와 공유):
#   tests/acceptance/.manifest.json:
#     { "frozenAt": ts, "gitHead": sha|null, "hashAlgo": "sha256sum|shasum|git-hash-object",
#       "files": { "<상대경로>": "<sha256>" },     # manifest 자신 제외, tests/acceptance/ 하위 전 파일
#       "refreezeHistory": [ { "at": ts, "gitHead": sha|null, "approvedByUser": true } ] }
#   verification.json 키:
#     acceptanceFreeze: { result: "pass"|"fail", files: N }
#     acceptanceTests:  { result: "pass"|"fail"|"skip", total: N, passed: N, failed: N, tamperedFiles?: [...] }
#   러너 규약: bash tests/acceptance/run.sh — 전부 통과 시에만 exit 0, 마지막 줄에
#     "ACCEPTANCE_RESULT: total=N passed=N failed=N" 출력

ACCEPTANCE_DIR="tests/acceptance"
ACCEPTANCE_MANIFEST="$ACCEPTANCE_DIR/.manifest.json"
ACCEPTANCE_RUNNER="$ACCEPTANCE_DIR/run.sh"

# ─── 해시 유틸 ───

# 사용 가능한 해시 도구 감지 (freeze 시 manifest.hashAlgo로 기록)
_acc_detect_hash_algo() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum"
  elif command -v git >/dev/null 2>&1; then
    echo "git-hash-object"
  else
    return 1
  fi
}

# manifest에 기록된 algo를 현재 환경에서 실행 가능한 도구로 해석.
# sha256sum ↔ shasum -a 256 은 동일한 SHA-256 다이제스트를 내므로 상호 대체 가능.
# git-hash-object는 다른 다이제스트(blob SHA)이므로 대체 불가.
_acc_resolve_algo() {
  local requested="$1"
  case "$requested" in
    sha256sum|shasum)
      if command -v "$requested" >/dev/null 2>&1; then
        echo "$requested"
      elif [[ "$requested" == "sha256sum" ]] && command -v shasum >/dev/null 2>&1; then
        echo "shasum"
      elif [[ "$requested" == "shasum" ]] && command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"
      else
        return 1
      fi
      ;;
    git-hash-object)
      command -v git >/dev/null 2>&1 && echo "git-hash-object" || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Usage: _acc_hash_file <algo> <file>
_acc_hash_file() {
  local algo="$1" f="$2"
  case "$algo" in
    sha256sum)       sha256sum "$f" | awk '{print $1}' ;;
    shasum)          shasum -a 256 "$f" | awk '{print $1}' ;;
    git-hash-object) git hash-object "$f" ;;
    *)               return 1 ;;
  esac
}

# tests/acceptance/ 하위 전 파일 목록 (manifest 제외, 정렬)
_acc_list_files() {
  find "$ACCEPTANCE_DIR" -type f ! -name .manifest.json 2>/dev/null | sort
}

# 파일 목록을 { "<경로>": "<hash>" } JSON으로 변환
# Usage: _acc_hash_files <algo> <<< "$file_list"
_acc_hash_files() {
  local algo="$1" files_json="{}" f h
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    h=$(_acc_hash_file "$algo" "$f") || return 1
    files_json=$(jq -n --argjson base "$files_json" --arg k "$f" --arg v "$h" '$base + {($k): $v}')
  done
  echo "$files_json"
}

_acc_git_head() {
  git rev-parse HEAD 2>/dev/null || true
}

# ─── acceptance-freeze: 인수 테스트 동결 (manifest 생성/갱신) ───
# Usage: acceptance-freeze [--approved-by-user]

cmd_acceptance_freeze() {
  echo "=== Acceptance Freeze ==="
  require_jq

  local approved_by_user=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --approved-by-user) approved_by_user=true; shift ;;
      *) shift ;;
    esac
  done

  # 기록 헬퍼 — 계약: acceptanceFreeze {result: pass|fail, files: N}
  _af_record() {
    record_verification "acceptanceFreeze" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson n "$2" --arg reason "${3:-}" \
          '{timestamp:$ts,result:$r,files:$n} + (if $reason != "" then {reason:$reason} else {} end)')"
  }

  _af_fail() {
    local reason="$1"
    echo "[acceptance-freeze] FAIL: $reason"
    _af_record "fail" 0 "$reason"
    append_gate_history "acceptance-freeze" "fail" "$(jq -n --arg r "$reason" '{reason:$r}')"
    echo "=== ACCEPTANCE FREEZE: FAIL ==="
    return 1
  }

  # 1. 디렉토리/파일/러너 존재 검증
  if [[ ! -d "$ACCEPTANCE_DIR" ]]; then
    _af_fail "$ACCEPTANCE_DIR/ not found — create acceptance tests from SPEC acceptance criteria first"
    return 1
  fi

  local file_list file_count
  file_list=$(_acc_list_files)
  file_count=$(printf '%s' "$file_list" | grep -c . || true)
  [[ "$file_count" =~ ^[0-9]+$ ]] || file_count=0

  if [[ "$file_count" -eq 0 ]]; then
    _af_fail "no files under $ACCEPTANCE_DIR/ — nothing to freeze"
    return 1
  fi

  if [[ ! -f "$ACCEPTANCE_RUNNER" ]]; then
    _af_fail "$ACCEPTANCE_RUNNER not found — runner is required (must print 'ACCEPTANCE_RESULT: total=N passed=N failed=N')"
    return 1
  fi

  # 2. 해시 계산
  local hash_algo
  hash_algo=$(_acc_detect_hash_algo) || {
    _af_fail "no hash tool available (need sha256sum, shasum, or git)"
    return 1
  }
  echo "[acceptance-freeze] Hash tool: $hash_algo, files: $file_count"

  local files_json
  files_json=$(_acc_hash_files "$hash_algo" <<< "$file_list") || {
    _af_fail "hashing failed with $hash_algo"
    return 1
  }

  local git_head history_json="[]"
  git_head=$(_acc_git_head)

  # 3/4. 신규 동결 vs 재동결 통제
  #
  # 세탁 방지 (H1): "manifest 존재"만으로 재동결을 판정하면 manifest를 rm으로 지운 뒤
  # 무승인 신규 동결로 세탁할 수 있다. 따라서:
  #  (a) 과거 동결 증거(manifest / verification.json acceptanceFreeze / progress gateHistory)가
  #      하나라도 있으면 재동결로 간주하고,
  #  (b) 구현 시작 후에는 신규 동결·재동결 모두 --approved-by-user를 요구한다.
  local prior_freeze="false"
  if [[ -f "$ACCEPTANCE_MANIFEST" ]]; then
    prior_freeze="true"
    history_json=$(jq '.refreezeHistory // []' "$ACCEPTANCE_MANIFEST" 2>/dev/null || echo "[]")
  else
    if [[ -f "$VERIFICATION_FILE" ]] && jq -e 'has("acceptanceFreeze")' "$VERIFICATION_FILE" >/dev/null 2>&1; then
      prior_freeze="true"
    elif [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
      local gh_count
      gh_count=$(jq '[.gateHistory[]? | tostring | select(contains("acceptance-freeze"))] | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
      [[ "$gh_count" =~ ^[0-9]+$ ]] && [[ "$gh_count" -gt 0 ]] && prior_freeze="true"
    fi
    if [[ "$prior_freeze" == "true" ]]; then
      echo "[acceptance-freeze] WARNING: manifest is missing but prior freeze evidence exists"
      echo "  (manifest 삭제 후 재동결 시도로 간주 — 재동결 통제를 적용합니다. refreezeHistory는 소실됨)"
    fi
  fi

  # 구현 시작 여부 판정 (M1: 템플릿 무관하게 보수적으로):
  #  - planning 전용 progress(.claude-plan-*, .claude-plan-docs-full*, .claude-doc-check-*) → 기획 단계
  #  - phase_2 상태가 있으면 pending일 때만 기획 단계
  #  - phase_2가 없는 비-planning progress(implement 템플릿 등) / progress 부재 → 구현 시작 후 (fail-closed)
  local impl_started="true" phase2_status="no-progress"
  local _af_pf="${PROGRESS_FILE:-}"
  if [[ -z "$_af_pf" ]] || [[ ! -f "$_af_pf" ]]; then
    _af_pf=$(detect_progress_file 2>/dev/null || true)
  fi
  if [[ -n "$_af_pf" ]] && [[ -f "$_af_pf" ]]; then
    case "$(basename "$_af_pf")" in
      .claude-plan-progress.json|.claude-plan-docs-full*progress*.json|.claude-doc-check-progress.json)
        impl_started="false"; phase2_status="planning-workflow" ;;
      *)
        phase2_status=$(jq -r '
          (.phases.phase_2.status
           // ([.steps[]? | select(.name == "phase_2") | .status] | first)
           // "missing")
        ' "$_af_pf" 2>/dev/null || echo "missing")
        # missing = phase_2가 없는 비-planning 템플릿(implement 등) → 보수적으로 구현 후 취급
        [[ "$phase2_status" == "pending" ]] && impl_started="false"
        ;;
    esac
  fi
  echo "[acceptance-freeze] prior freeze: $prior_freeze, phase_2 status: $phase2_status, implementation started: $impl_started"

  if [[ "$impl_started" == "true" ]] && [[ "$approved_by_user" != "true" ]]; then
    if [[ "$prior_freeze" == "true" ]]; then
      echo "[acceptance-freeze] REFUSED: 스펙 변경에 따른 재동결은 사용자 승인이 필요합니다."
    else
      echo "[acceptance-freeze] REFUSED: 구현 단계에서의 신규 동결은 사용자 승인이 필요합니다."
      echo "  (기획 단계에서 동결했어야 함 — 기존 프로젝트에 --start-phase로 진입한 경우에만 승인 하 생성)"
    fi
    echo "  AskUserQuestion으로 승인받은 뒤 --approved-by-user로 재실행하세요:"
    echo "    shared-gate.sh acceptance-freeze --approved-by-user"
    append_gate_history "acceptance-freeze" "fail" '{"reason":"freeze refused — user approval required after implementation started"}'
    echo "=== ACCEPTANCE FREEZE: REFUSED ==="
    return 1
  fi

  if [[ "$impl_started" == "true" ]]; then
    # 승인된 (재)동결 → refreezeHistory에 항목 추가
    history_json=$(jq -n --argjson base "$history_json" --arg at "$(timestamp)" --arg gh "$git_head" '
      $base + [{at:$at, gitHead:(if $gh == "" then null else $gh end), approvedByUser:true}]')
    echo "[acceptance-freeze] Approved freeze (recorded in refreezeHistory)"
  elif [[ "$prior_freeze" == "true" ]]; then
    echo "[acceptance-freeze] Planning-phase re-freeze (allowed, silent update)"
  fi

  # 5. manifest 기록
  jq -n \
    --arg at "$(timestamp)" \
    --arg gh "$git_head" \
    --arg algo "$hash_algo" \
    --argjson files "$files_json" \
    --argjson hist "$history_json" \
    '{frozenAt:$at, gitHead:(if $gh == "" then null else $gh end), hashAlgo:$algo, files:$files, refreezeHistory:$hist}' \
    > "$ACCEPTANCE_MANIFEST"

  _af_record "pass" "$file_count"
  append_gate_history "acceptance-freeze" "pass" "{\"files\":$file_count}"
  echo "[acceptance-freeze] Frozen $file_count file(s) into $ACCEPTANCE_MANIFEST"
  echo "=== ACCEPTANCE FREEZE: PASS ==="
  return 0
}

# ─── acceptance-gate: 무결성 검증 + 동결된 인수 테스트 실행 (HARD_FAIL) ───

cmd_acceptance_gate() {
  echo "=== Acceptance Gate ==="
  require_jq

  # 기록 헬퍼 — 계약: acceptanceTests {result, total, passed, failed, tamperedFiles?, reason?}
  # Usage: _ag_record <result> <total> <passed> <failed> [reason] [tampered_json_array]
  _ag_record() {
    record_verification "acceptanceTests" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson t "$2" --argjson p "$3" --argjson f "$4" \
            --arg reason "${5:-}" --argjson tampered "${6:-null}" \
          '{timestamp:$ts,result:$r,total:$t,passed:$p,failed:$f}
           + (if $reason != "" then {reason:$reason} else {} end)
           + (if $tampered != null then {tamperedFiles:$tampered} else {} end)')"
  }

  # 1. 디렉토리 부재 → skip (인수 테스트 비대상 워크플로우)
  if [[ ! -d "$ACCEPTANCE_DIR" ]]; then
    echo "[acceptance-gate] SKIP (no $ACCEPTANCE_DIR/ directory — no acceptance tests)"
    _ag_record "skip" 0 0 0 "no acceptance tests"
    append_gate_history "acceptance-gate" "skip" '{"reason":"no acceptance tests"}'
    return 0
  fi

  # 2. 미동결 → fail
  if [[ ! -f "$ACCEPTANCE_MANIFEST" ]]; then
    echo "[acceptance-gate] FAIL: acceptance tests not frozen — run 'shared-gate.sh acceptance-freeze'"
    _ag_record "fail" 0 0 0 "acceptance tests not frozen — run acceptance-freeze"
    append_gate_history "acceptance-gate" "fail" '{"reason":"not frozen"}'
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi

  # 3. 무결성 검증: manifest hashAlgo로 재해시 → 변경/삭제/추가 파일 산출
  local manifest_algo algo
  manifest_algo=$(jq -r '.hashAlgo // "sha256sum"' "$ACCEPTANCE_MANIFEST" 2>/dev/null || echo "sha256sum")
  algo=$(_acc_resolve_algo "$manifest_algo") || {
    echo "[acceptance-gate] FAIL: hash tool '$manifest_algo' (from manifest) is not available — cannot verify integrity"
    _ag_record "fail" 0 0 0 "hash tool $manifest_algo unavailable"
    append_gate_history "acceptance-gate" "fail" '{"reason":"hash tool unavailable"}'
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  }

  local manifest_files current_files
  manifest_files=$(jq '.files // {}' "$ACCEPTANCE_MANIFEST" 2>/dev/null || echo "{}")
  current_files=$(_acc_hash_files "$algo" <<< "$(_acc_list_files)") || {
    echo "[acceptance-gate] FAIL: re-hashing failed with $algo"
    _ag_record "fail" 0 0 0 "re-hashing failed"
    append_gate_history "acceptance-gate" "fail" '{"reason":"re-hashing failed"}'
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  }

  # 변경(해시 불일치)/삭제(manifest에만 존재)/추가(디스크에만 존재) 모두 탬퍼로 간주
  local tampered_json tampered_count
  tampered_json=$(jq -n --argjson old "$manifest_files" --argjson new "$current_files" '
    ([ ($old | keys[]) as $k | select(($new[$k] // null) != $old[$k]) | $k ]
     + [ ($new | keys[]) as $k | select(($old[$k] // null) == null) | $k ])
    | sort | unique')
  tampered_count=$(echo "$tampered_json" | jq 'length')

  if [[ "$tampered_count" -gt 0 ]]; then
    echo "[acceptance-gate] FAIL: acceptance tests were modified after freeze — revert or get user approval and re-freeze"
    echo "  Tampered files (modified/deleted/added):"
    echo "$tampered_json" | jq -r '.[] | "    - " + .'
    echo "  Remedy: revert the changes, or (with user approval) 'shared-gate.sh acceptance-freeze --approved-by-user'"
    _ag_record "fail" 0 0 0 "acceptance tests were modified after freeze — revert or get user approval and re-freeze" "$tampered_json"
    append_gate_history "acceptance-gate" "fail" "$(jq -n --argjson t "$tampered_json" '{reason:"tampered",tamperedFiles:$t}')"
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi
  echo "[acceptance-gate] Integrity OK ($(echo "$current_files" | jq 'length') file(s), algo: $algo)"

  # 4. 러너 실행
  # green 세탁 방지 (M2): 외부 URL 조향 env를 제거하고 실행 — 테스트가 목 서버로
  # 우회되지 않도록. 러너는 서버 기동/포트를 자체 통제해야 한다 (acceptance-tests-guide 참조).
  echo "[acceptance-gate] Running: bash $ACCEPTANCE_RUNNER (BASE_URL/API_URL 계열 env 무시)"
  local run_output run_ec
  run_output=$(env -u BASE_URL -u API_URL -u API_BASE_URL -u APP_URL -u SERVER_URL -u TEST_BASE_URL \
    bash "$ACCEPTANCE_RUNNER" 2>&1) && run_ec=0 || run_ec=$?
  echo "$run_output" | tail -15

  # ACCEPTANCE_RESULT 라인 파싱 (마지막 매치 채택)
  local result_line total=0 passed=0 failed=0 parsed="false"
  result_line=$(printf '%s\n' "$run_output" | grep -E '^ACCEPTANCE_RESULT: *total=[0-9]+ +passed=[0-9]+ +failed=[0-9]+' | tail -1 || true)
  if [[ -n "$result_line" ]]; then
    total=$(echo "$result_line" | sed -E 's/.*total=([0-9]+).*/\1/')
    passed=$(echo "$result_line" | sed -E 's/.*passed=([0-9]+).*/\1/')
    failed=$(echo "$result_line" | sed -E 's/.*failed=([0-9]+).*/\1/')
    if [[ "$total" =~ ^[0-9]+$ ]] && [[ "$passed" =~ ^[0-9]+$ ]] && [[ "$failed" =~ ^[0-9]+$ ]]; then
      parsed="true"
    else
      total=0; passed=0; failed=0
    fi
  fi

  # 판정: exit 0 + RESULT 라인 파싱 성공 + failed=0 일 때만 pass (fail-closed)
  if [[ "$parsed" != "true" ]]; then
    echo "[acceptance-gate] FAIL: runner did not print ACCEPTANCE_RESULT (runner contract violation; exit=$run_ec)"
    _ag_record "fail" "$total" "$passed" "$failed" "runner did not print ACCEPTANCE_RESULT"
    append_gate_history "acceptance-gate" "fail" "{\"reason\":\"no ACCEPTANCE_RESULT line\",\"exitCode\":$run_ec}"
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi

  echo "[acceptance-gate] Result: total=$total passed=$passed failed=$failed (exit=$run_ec)"

  if [[ "$run_ec" -ne 0 ]] || [[ "$failed" -gt 0 ]]; then
    local reason
    if [[ "$failed" -gt 0 ]]; then
      reason="$failed acceptance test(s) failed"
    else
      reason="runner exited non-zero ($run_ec)"
    fi
    echo "[acceptance-gate] FAIL: $reason"
    _ag_record "fail" "$total" "$passed" "$failed" "$reason"
    append_gate_history "acceptance-gate" "fail" "{\"total\":$total,\"passed\":$passed,\"failed\":$failed,\"exitCode\":$run_ec}"
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi

  _ag_record "pass" "$total" "$passed" "$failed"
  append_gate_history "acceptance-gate" "pass" "{\"total\":$total,\"passed\":$passed,\"failed\":0}"

  # 5. DoD 갱신: dod.acceptance_pass는 이 게이트가 유일한 기록자 (모델 직접 세팅 금지)
  if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg ev "acceptance-gate PASS at $(timestamp) (total=$total passed=$passed failed=0)" '
      if (.dod | has("acceptance_pass")) then
        .dod.acceptance_pass = {checked: true, evidence: $ev}
      else . end'
  fi

  echo "=== ACCEPTANCE GATE: PASS ==="
  return 0
}
