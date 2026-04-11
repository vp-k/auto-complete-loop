# gates/security.sh — 취약점 스캔, 시크릿 스캔, 플레이스홀더 체크

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

# ─── external-service-check: SPEC.md 기반 외부 서비스 SDK/config 존재 확인 (HARD_FAIL) ───

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

      local found_sdk=false
      for d in src lib app server client pages components; do
        if [[ -d "$d" ]]; then
          if grep -rqlE "$sdk_pattern" "$d" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.go" 2>/dev/null; then
            found_sdk=true
            break
          fi
        fi
      done

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

  echo "=== EXTERNAL SERVICE CHECK: ${result^^} ==="
  if [[ "$result" == "fail" ]]; then
    return 1
  fi
  return 0
}
