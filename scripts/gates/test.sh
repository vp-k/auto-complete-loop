# gates/test.sh — E2E 게이트, 구현 깊이 검사, 테스트 품질 검사

# ─── e2e-gate: E2E 테스트 프레임워크 감지 + 실행 ───

cmd_e2e_gate() {
  require_jq

  # --strict 플래그 파싱: 프레임워크 미감지 시 exit 1 (FAIL) 대신 exit 2 (SKIP)
  local strict_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) strict_mode=true; shift ;;
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
    # SOFT → HARD 승격: 직전 실행도 fail/warn이면 이번엔 하드 실패 (soft_gate_escalation은 append 전에 호출)
    if soft_gate_escalation "implementation-depth" "warn"; then
      echo "[implementation-depth] ESCALATED: 연속 실패 → HARD 승격, pass까지 유지 (규칙은 적는 게 아니라 강제되어야 한다)"
      # 증거 정합: verification.json의 result도 fail로 재기록 (게이트 판정과 일치)
      [[ -f "$VERIFICATION_FILE" ]] && jq_inplace "$VERIFICATION_FILE" '.implementationDepth.result = "fail" | .implementationDepth.escalated = true'
      append_gate_history "implementation-depth" "fail" "$(jq -c '. + {"escalated":true}' <<< "$details")"
      return 1
    fi
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
        # 주의: grep -c는 무매치 시 "0"을 출력하고 exit 1이므로 `|| echo 0`을 쓰면 "0\n0"이 된다
        tc=$(grep -cE '^\s*(test|it)\s*\(' "$tf" 2>/dev/null || true); tc=${tc:-0}
        total_tests=$((total_tests + tc))

        # assertion 줄 수 기반 비율 (파일 단위가 아닌 assertion 밀도)
        local ac
        ac=$(grep -cE '(expect|assert|should|toBe|toEqual|toHave|toContain|toThrow|toMatch)' "$tf" 2>/dev/null || true); ac=${ac:-0}
        # assertion 줄이 테스트 수 이상이면 전량 커버, 아니면 비례 배분
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        # skip 수
        local sc
        sc=$(grep -cE '(test|it|describe)\.(skip|todo)\(' "$tf" 2>/dev/null || true); sc=${sc:-0}
        skipped_tests=$((skipped_tests + sc))
      done <<< "$test_files"
      ;;

    python)
      local test_files
      test_files=$(find "${test_dirs[@]}" -type f \( -name 'test_*.py' -o -name '*_test.py' \) 2>/dev/null || true)

      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        local tc
        tc=$(grep -cE '^\s*def test_|^\s*async def test_' "$tf" 2>/dev/null || true); tc=${tc:-0}
        total_tests=$((total_tests + tc))

        local ac
        ac=$(grep -cE '(assert |self\.assert|pytest\.raises)' "$tf" 2>/dev/null || true); ac=${ac:-0}
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        local sc
        sc=$(grep -cE '@pytest\.mark\.skip|@unittest\.skip' "$tf" 2>/dev/null || true); sc=${sc:-0}
        skipped_tests=$((skipped_tests + sc))
      done <<< "$test_files"
      ;;

    go)
      local test_files
      test_files=$(find "${test_dirs[@]}" -type f -name '*_test.go' 2>/dev/null || true)

      while IFS= read -r tf; do
        [[ -z "$tf" ]] && continue
        local tc
        tc=$(grep -cE '^func Test' "$tf" 2>/dev/null || true); tc=${tc:-0}
        total_tests=$((total_tests + tc))

        local ac
        ac=$(grep -cE '(t\.(Error|Fatal|Fail|Assert)|assert\.|require\.)' "$tf" 2>/dev/null || true); ac=${ac:-0}
        if [[ $ac -ge $tc ]] && [[ $tc -gt 0 ]]; then
          assertion_tests=$((assertion_tests + tc))
        else
          assertion_tests=$((assertion_tests + ac))
        fi

        local sc
        sc=$(grep -cE 't\.Skip\(' "$tf" 2>/dev/null || true); sc=${sc:-0}
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
    # SOFT → HARD 승격: 직전 실행도 fail/warn이면 이번엔 하드 실패
    if soft_gate_escalation "test-quality" "warn"; then
      echo "[test-quality] ESCALATED: 연속 실패 → HARD 승격, pass까지 유지 (규칙은 적는 게 아니라 강제되어야 한다)"
      append_gate_history "test-quality" "fail" '{"totalTests":0,"escalated":true}'
      return 1
    fi
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
    # SOFT → HARD 승격: 직전 실행도 fail/warn이면 이번엔 하드 실패 (soft_gate_escalation은 append 전에 호출)
    if soft_gate_escalation "test-quality" "warn"; then
      echo "[test-quality] ESCALATED: 연속 실패 → HARD 승격, pass까지 유지 (규칙은 적는 게 아니라 강제되어야 한다)"
      append_gate_history "test-quality" "fail" "$(jq -c '. + {"escalated":true}' <<< "$details")"
      return 1
    fi
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

# ─── service-test-check: 백엔드 서비스/라우트 통합 테스트 존재 확인 (HARD_FAIL) ───

cmd_service_test_check() {
  echo "=== Service Test Check ==="
  require_jq

  # verification.json 기록 헬퍼 — 계약: serviceTestCheck {result: pass|fail|skip}
  _stc_record() {
    record_verification "serviceTestCheck" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --arg reason "${2:-}" \
          '{timestamp:$ts,result:$r} + (if $reason != "" then {reason:$reason} else {} end)')"
  }

  if [[ -z "$PROGRESS_FILE" ]] || [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "[service-test-check] FAIL (progress file not found — cannot determine projectScope)"
    append_gate_history "service-test-check" "fail" '{"reason":"no progress file"}'
    _stc_record "fail" "no progress file"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  local has_backend
  # 주의: jq의 `//`는 false를 falsy로 취급하므로 has() 기반으로 읽는다 (hasBackend=false가 "null"로 오판되는 버그 방지)
  has_backend=$(jq -r '.phases.phase_0.outputs.projectScope | if type == "object" and has("hasBackend") then (.hasBackend | tostring) else "null" end' "$PROGRESS_FILE" 2>/dev/null || echo "null")

  if [[ "$has_backend" == "null" ]]; then
    echo "[service-test-check] FAIL (projectScope.hasBackend is not defined — run Phase 0 first)"
    append_gate_history "service-test-check" "fail" '{"reason":"projectScope undefined"}'
    _stc_record "fail" "projectScope.hasBackend undefined"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  if [[ "$has_backend" != "true" ]]; then
    echo "[service-test-check] SKIP (hasBackend is false)"
    append_gate_history "service-test-check" "skip" '{"reason":"hasBackend=false"}'
    _stc_record "skip" "hasBackend=false"
    return 0
  fi

  local test_files=0
  local search_pattern="(service|route|controller|handler|api|endpoint)"

  local all_test_files=""
  for d in test tests __tests__; do
    if [[ -d "$d" ]]; then
      all_test_files+=$(find "$d" -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" \) 2>/dev/null)
      all_test_files+=$'\n'
    fi
  done
  if [[ -d "src" ]]; then
    all_test_files+=$(find src -type f \( -name "*.test.*" -o -name "*.spec.*" \) 2>/dev/null)
  fi

  if [[ -n "$all_test_files" ]]; then
    # grep 무매치(exit 1) 시 pipefail로 게이트가 기록 없이 즉사하는 것 방지
    test_files=$(echo "$all_test_files" | sort -u | { grep -iE "$search_pattern" || true; } | wc -l | tr -d ' ')
  fi

  echo "[service-test-check] Found $test_files service/route test file(s)"

  if [[ "$test_files" -eq 0 ]]; then
    echo "[service-test-check] WARNING: hasBackend=true but no service/route tests found"
    echo "  Expected: test files matching pattern *service*|*route*|*controller*|*handler*|*api*|*endpoint*"
    echo "  Searched: test/ tests/ __tests__/ src/**/*.test.* src/**/*.spec.*"
    append_gate_history "service-test-check" "fail" '{"testFiles":0}'
    _stc_record "fail" "hasBackend=true but no service/route tests"
    echo "=== SERVICE TEST CHECK: FAIL ==="
    return 1
  fi

  append_gate_history "service-test-check" "pass" "{\"testFiles\":$test_files}"
  _stc_record "pass"
  echo "=== SERVICE TEST CHECK: PASS ==="
  return 0
}

# ─── live-testing-gate: progress의 live 테스트 finding에서 open LIVE-CRITICAL/HIGH 계수 (HARD_FAIL) ───
# 스키마 근거:
#   - commands/code-review-loop.md 7단계: 미해결 finding을 progress의 `live_testing_issues` 배열에 기록
#   - findingHistory(최상위 또는 phases.phase_3.findingHistory)에 LIVE-{SEVERITY}-{번호} 항목 기록
#   - dod.live_testing: live 테스트 수행/SKIP 증거
# live 기록이 전혀 없으면 result=skip (라이브러리 프로젝트 등 live 테스트 비대상).

cmd_live_testing_gate() {
  echo "=== Live Testing Gate ==="
  require_jq

  # verification.json 기록 헬퍼 — 계약: liveTesting {result: pass|fail|skip, criticalOpen: N, highOpen: N}
  _ltg_record() {
    record_verification "liveTesting" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson c "$2" --argjson h "$3" --arg reason "${4:-}" \
          '{timestamp:$ts,result:$r,criticalOpen:$c,highOpen:$h} + (if $reason != "" then {reason:$reason} else {} end)')"
  }

  if [[ -z "$PROGRESS_FILE" ]] || [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "[live-testing-gate] SKIP (no progress file — cannot locate live testing records)"
    append_gate_history "live-testing-gate" "skip" '{"reason":"no progress file"}'
    _ltg_record "skip" 0 0 "no progress file"
    return 0
  fi

  # live 테스트 기록 존재 여부 + open LIVE-CRITICAL/HIGH 계수 (단일 jq 패스)
  local counts
  counts=$(jq '
    def norm: if type == "object" then . elif type == "string" then {id: .} else empty end;
    def live_items:
      [ ((.live_testing_issues // []) | .[] | norm),
        ((.findingHistory // []) | .[] | norm | select((.id // "") | startswith("LIVE-"))),
        ((.phases.phase_3.findingHistory // []) | .[] | norm | select((.id // "") | startswith("LIVE-"))) ];
    (live_items) as $items
    | ($items | map(select((.status // "open") == "open"))) as $open
    | {
        evidence: (has("live_testing_issues")
                   or (($items | length) > 0)
                   or ((.dod.live_testing // null) != null)),
        critical: ($open | map(select(((.severity // "") == "CRITICAL")
                                      or ((.id // "") | test("^LIVE-CRITICAL")))) | length),
        high:     ($open | map(select(((.severity // "") == "HIGH")
                                      or ((.id // "") | test("^LIVE-HIGH")))) | length)
      }
  ' "$PROGRESS_FILE" 2>/dev/null || echo '{"evidence":false,"critical":0,"high":0}')

  local has_evidence critical_open high_open
  has_evidence=$(echo "$counts" | jq -r '.evidence')
  critical_open=$(echo "$counts" | jq -r '.critical')
  high_open=$(echo "$counts" | jq -r '.high')
  [[ "$critical_open" =~ ^[0-9]+$ ]] || critical_open=0
  [[ "$high_open" =~ ^[0-9]+$ ]] || high_open=0

  if [[ "$has_evidence" != "true" ]]; then
    echo "[live-testing-gate] SKIP (no live testing records in $PROGRESS_FILE — library project or live testing not applicable)"
    append_gate_history "live-testing-gate" "skip" '{"reason":"no live records"}'
    _ltg_record "skip" 0 0 "no live testing records"
    return 0
  fi

  echo "[live-testing-gate] Open LIVE findings: CRITICAL=$critical_open, HIGH=$high_open"

  if [[ $((critical_open + high_open)) -gt 0 ]]; then
    echo "[live-testing-gate] FAIL: unresolved LIVE-CRITICAL/HIGH finding(s) remain"
    echo "  Fix open findings (live-testing SKILL Step 4.5) and mark them status=fixed in $PROGRESS_FILE"
    append_gate_history "live-testing-gate" "fail" "{\"criticalOpen\":$critical_open,\"highOpen\":$high_open}"
    _ltg_record "fail" "$critical_open" "$high_open"
    echo "=== LIVE TESTING GATE: FAIL ==="
    return 1
  fi

  append_gate_history "live-testing-gate" "pass" '{"criticalOpen":0,"highOpen":0}'
  _ltg_record "pass" 0 0
  # DoD 갱신: dod.live_testing은 이 게이트가 유일한 기록자 (모델 직접 세팅 금지)
  jq_inplace "$PROGRESS_FILE" --arg ev "live-testing-gate PASS at $(timestamp) (open LIVE-CRITICAL/HIGH: 0)" '
    if (.dod | has("live_testing")) then
      .dod.live_testing = {checked: true, evidence: $ev}
    else . end'
  echo "=== LIVE TESTING GATE: PASS ==="
  return 0
}

# ─── layer-coverage: projectScope 대비 실제 파일시스템 아티팩트 대조 (HARD_FAIL) ───
# stop-hook이 .qualityDimensions.layerCoverage.result를 하드 게이트로 검사한다.
# 이 서브커맨드가 해당 키의 유일한 스크립트 기록자 (자기신고 금지).
# projectScope 정보가 없으면 result=skip.

cmd_layer_coverage() {
  echo "=== Layer Coverage Check ==="
  require_jq

  # 기록 헬퍼 — 계약: layerCoverage {result: pass|fail|skip, layers: {...}}
  # stop-hook:295가 .qualityDimensions.layerCoverage를 읽으므로 qualityDimensions 하위에 기록.
  _lc_record() {
    record_verification_qd "layerCoverage" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson layers "$2" --arg ev "$3" \
          '{timestamp:$ts,result:$r,layers:$layers,evidence:$ev}')"
  }

  # projectScope 로드 — 정보 없으면 skip
  local scope_valid="invalid"
  if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    scope_valid=$(jq -r '
      .phases.phase_0.outputs.projectScope
      | if type == "object" and has("hasFrontend") and has("hasBackend")
           and (.hasFrontend | type == "boolean") and (.hasBackend | type == "boolean")
        then "valid" else "invalid" end
    ' "$PROGRESS_FILE" 2>/dev/null || echo "invalid")
  fi

  if [[ "$scope_valid" != "valid" ]]; then
    echo "[layer-coverage] SKIP (projectScope not defined in progress file — cannot determine required layers)"
    append_gate_history "layer-coverage" "skip" '{"reason":"no projectScope"}'
    _lc_record "skip" '{"reason":"no projectScope"}' "projectScope missing"
    return 0
  fi

  local has_frontend has_backend
  has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend' "$PROGRESS_FILE")
  has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend' "$PROGRESS_FILE")
  echo "[layer-coverage] projectScope: hasFrontend=$has_frontend, hasBackend=$has_backend"

  local fail=0 issues=""

  # ── 프론트엔드: 페이지/컴포넌트 파일 계수 ──
  local fe_count=0
  local -a fe_dirs=()
  for d in src app pages components client public views; do
    [[ -d "$d" ]] && fe_dirs+=("$d")
  done
  if [[ ${#fe_dirs[@]} -gt 0 ]]; then
    fe_count=$(find "${fe_dirs[@]}" -type f \
      \( -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.html" \
         -o -name "page.*" -o -name "layout.*" \) \
      ! -path "*/node_modules/*" ! -name "*.test.*" ! -name "*.spec.*" 2>/dev/null | wc -l | tr -d ' ')
  fi
  [[ -f "index.html" ]] && fe_count=$((fe_count + 1))
  [[ "$fe_count" =~ ^[0-9]+$ ]] || fe_count=0

  # ── 백엔드: 서버 진입점 + 라우트/컨트롤러/핸들러 파일 계수 ──
  local be_entry="false" be_route_count=0
  # 진입점: 관례적 파일명 또는 package.json start/dev 스크립트
  for f in server.js server.ts server.mjs server.py app.js app.ts app.py main.py main.go main.rs \
           src/server.js src/server.ts src/app.js src/app.ts src/main.ts src/main.js src/index.ts src/index.js \
           server/index.js server/index.ts cmd/main.go; do
    [[ -f "$f" ]] && { be_entry="true"; break; }
  done
  if [[ "$be_entry" == "false" ]] && [[ -f "package.json" ]]; then
    jq -e '.scripts.start // .scripts.dev' package.json >/dev/null 2>&1 && be_entry="true"
  fi
  local -a be_dirs=()
  for d in src app server api routes controllers handlers services lib; do
    [[ -d "$d" ]] && be_dirs+=("$d")
  done
  if [[ ${#be_dirs[@]} -gt 0 ]]; then
    be_route_count=$(find "${be_dirs[@]}" -type f \
      \( -iname "*route*" -o -iname "*controller*" -o -iname "*handler*" -o -iname "*endpoint*" -o -iname "*service*" \) \
      \( -name "*.ts" -o -name "*.js" -o -name "*.mjs" -o -name "*.py" -o -name "*.go" -o -name "*.java" -o -name "*.rb" -o -name "*.rs" \) \
      ! -path "*/node_modules/*" ! -name "*.test.*" ! -name "*.spec.*" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$be_route_count" =~ ^[0-9]+$ ]] || be_route_count=0
    # 파일명 관례가 없는 프레임워크(Flask 단일 app.py 등) 폴백: 라우트 등록 패턴 grep
    if [[ "$be_route_count" -eq 0 ]]; then
      local route_pattern_files
      # grep 무매치(exit 1)가 pipefail로 게이트를 기록 없이 죽이지 않도록 가드
      route_pattern_files=$({ grep -rlE '(app|router|r|e)\.(get|post|put|patch|delete|use)\(|@(app|router|bp)\.(get|post|put|patch|delete|route)|HandleFunc\(|@(Get|Post|Put|Patch|Delete)Mapping|@(Controller|RestController)' \
        "${be_dirs[@]}" --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.java" 2>/dev/null || true; } | head -50 | wc -l | tr -d ' ')
      [[ "$route_pattern_files" =~ ^[0-9]+$ ]] || route_pattern_files=0
      be_route_count=$route_pattern_files
    fi
  fi

  # ── 테스트 디렉토리 존재 ──
  local test_dir_count=0
  for d in test tests __tests__ spec e2e; do
    [[ -d "$d" ]] && test_dir_count=$((test_dir_count + 1))
  done
  if [[ -d "src" ]]; then
    local src_tests
    src_tests=$(find src -type f \( -name "*.test.*" -o -name "*.spec.*" \) 2>/dev/null | head -1 || true)
    [[ -n "$src_tests" ]] && test_dir_count=$((test_dir_count + 1))
  fi

  # ── 판정 ──
  if [[ "$has_frontend" == "true" ]] && [[ "$fe_count" -eq 0 ]]; then
    fail=1
    issues="${issues}  - hasFrontend=true but 0 page/component files found\n"
  fi
  if [[ "$has_backend" == "true" ]]; then
    if [[ "$be_entry" != "true" ]]; then
      fail=1
      issues="${issues}  - hasBackend=true but no server entry point found (server.*/app.*/main.* or package.json start script)\n"
    fi
    if [[ "$be_route_count" -eq 0 ]]; then
      fail=1
      issues="${issues}  - hasBackend=true but 0 route/controller/handler files found\n"
    fi
  fi

  local layers_json
  layers_json=$(jq -n \
    --argjson hf "$has_frontend" --argjson hb "$has_backend" \
    --argjson fe "$fe_count" --argjson be_entry "$([[ "$be_entry" == "true" ]] && echo true || echo false)" \
    --argjson be_routes "$be_route_count" --argjson tests "$test_dir_count" \
    '{hasFrontend:$hf,hasBackend:$hb,frontendFiles:$fe,backendEntry:$be_entry,backendRouteFiles:$be_routes,testDirs:$tests}')

  local evidence="frontend: $fe_count files, backend entry: $be_entry, backend routes: $be_route_count files, test dirs: $test_dir_count"
  echo "[layer-coverage] $evidence"

  if [[ "$fail" -eq 1 ]]; then
    echo "[layer-coverage] FAIL: required layers missing:"
    printf '%b' "$issues"
    echo "  Return to Phase 2 and implement the missing layer(s)."
    append_gate_history "layer-coverage" "fail" "$layers_json"
    _lc_record "fail" "$layers_json" "$evidence"
    echo "=== LAYER COVERAGE: FAIL ==="
    return 1
  fi

  append_gate_history "layer-coverage" "pass" "$layers_json"
  _lc_record "pass" "$layers_json" "$evidence"
  echo "=== LAYER COVERAGE: PASS ==="
  return 0
}
