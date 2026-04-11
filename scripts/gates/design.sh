# gates/design.sh — 디자인 폴리시 게이트(WCAG), 페이지 렌더링 검증

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

# ─── page-render-check: 페이지 렌더링 검증 (Playwright) ───

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
