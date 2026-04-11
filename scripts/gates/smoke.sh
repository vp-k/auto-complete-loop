# gates/smoke.sh — 서버 기동 검증, 통합 스모크, 기능 흐름 검증

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

# ─── integration-smoke: 프론트-백엔드 API 통합 스모크 ───

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
