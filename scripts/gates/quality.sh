# gates/quality.sh — 빌드/타입체크/린트/테스트 품질 게이트

# ─── quality-gate 결과 캐시 ───
# 같은 코드 상태(git 지문)에서 이미 pass한 게이트를 재실행하지 않는다.
# full-auto 한 런에서 Phase 2/3/4/live-testing이 각각 quality-gate를 호출하므로
# 코드 미변경 시 재실행은 낭비. 실패 결과는 캐시하지 않는다 (실패 후엔 항상 재실행).

# 캐시 파일 위치: git 레포면 .git/ 내부 (git add -A로도 커밋 불가능한 안전 위치).
# 캐시는 git 지문 기반이라 git 없는 환경에서는 어차피 비활성 — 폴백 경로는 형식상 유지.
quality_cache_file() {
  local gd
  gd=$(git rev-parse --git-dir 2>/dev/null) || { printf '%s' ".claude-quality-gate-cache.json"; return; }
  printf '%s/claude-quality-gate-cache.json' "$gd"
}

# 현재 코드 상태 지문: HEAD 커밋 해시 + working tree 상태 해시.
# 상태 해시 = porcelain(파일 목록/상태) + git diff HEAD(tracked 변경 "내용")
#            + untracked 파일 내용. porcelain만으로는 dirty 파일을 재수정해도
#            지문이 같아 stale pass 스킵이 발생하므로 내용까지 포함한다.
# git 미설치 / git 레포 아님 / 커밋 없음 → 실패 반환 → 캐시 기능 자동 비활성(항상 실행).
quality_fingerprint() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  local head state_hash
  head=$(git rev-parse HEAD 2>/dev/null) || return 1
  # 워크플로우 런타임 산출물(.claude-*)은 코드 상태가 아니므로 전 구간에서 제외
  # — 검증/베이스라인 파일 자신이 지문을 오염시켜 캐시 미스 나는 것 방지.
  # untracked 내용은 10MB 캡 (비정상적으로 큰 미추적 파일로 인한 지연 방지;
  # 파일 추가/삭제 자체는 porcelain 구간이 항상 감지).
  state_hash=$(
    {
      git status --porcelain 2>/dev/null | grep -vE '\.claude[-/]' || true
      git diff HEAD -- . ':(exclude).claude*' 2>/dev/null || true
      git ls-files --others --exclude-standard -z -- . ':(exclude).claude*' 2>/dev/null \
        | sort -z | xargs -0 -r cat 2>/dev/null | head -c 10485760 || true
    } | git hash-object --stdin 2>/dev/null
  ) || state_hash=""
  if [[ -z "$state_hash" ]]; then
    state_hash=$(
      {
        git status --porcelain 2>/dev/null | grep -vE '\.claude[-/]' || true
        git diff HEAD -- . ':(exclude).claude*' 2>/dev/null || true
      } | cksum | tr -s ' \t' '-'
    )
  fi
  [[ -n "$state_hash" ]] || return 1
  printf '%s-%s' "$head" "$state_hash"
}

# ─── quality-gate: 빌드/타입/린트/테스트 일괄 실행 ───
# Usage: quality-gate [--force]  (--force: 캐시 무시하고 강제 재실행)

cmd_quality_gate() {
  require_jq

  local force=false _arg
  for _arg in "$@"; do
    [[ "$_arg" == "--force" ]] && force=true
  done

  # 캐시 확인: 지문이 마지막 pass 시점과 동일하면 스킵
  local fingerprint="" cache_file
  cache_file=$(quality_cache_file)
  fingerprint=$(quality_fingerprint) || fingerprint=""
  if [[ "$force" != "true" ]] && [[ -n "$fingerprint" ]] && [[ -f "$cache_file" ]]; then
    local cached_fp cached_result
    cached_fp=$(jq -r '.fingerprint // empty' "$cache_file" 2>/dev/null || true)
    cached_result=$(jq -r '.result // empty' "$cache_file" 2>/dev/null || true)
    if [[ "$cached_fp" == "$fingerprint" ]] && [[ "$cached_result" == "pass" ]]; then
      # 스킵 가드: 캐시 스킵은 이전 pass의 부작용(verification 파일, progress DoD)이
      # 이미 반영돼 있을 때만 유효. 새 런(상태 파일 아카이브됨 / fresh progress)이면
      # 스킵 시 stop-hook 게이트가 영원히 미충족 상태로 stall하므로 실제 실행으로 폴백.
      local side_effects_ok=true
      [[ -f "$VERIFICATION_FILE" ]] || side_effects_ok=false
      if [[ "$side_effects_ok" == "true" ]] && [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
        local dod_ok
        dod_ok=$(jq '
          if has("dod") then
            ((if (.dod | has("build_pass")) then (.dod.build_pass.checked == true) else true end)
             and (if (.dod | has("test_pass")) then (.dod.test_pass.checked == true) else true end)
             and (if has("consistencyChecks") then (.consistencyChecks.code_quality.checked == true) else true end))
          else true end' "$PROGRESS_FILE" 2>/dev/null || echo "false")
        [[ "$dod_ok" == "true" ]] || side_effects_ok=false
      fi
      if [[ "$side_effects_ok" == "true" ]]; then
        echo "[quality-gate] SKIP (unchanged since last pass: ${fingerprint:0:12})"
        jq_inplace "$VERIFICATION_FILE" --arg ts "$(timestamp)" '.timestamp = $ts'
        append_gate_history "quality-gate" "pass" '{"cached":true}'
        return 0
      fi
      echo "[quality-gate] cache fingerprint matches but verification/DoD state is missing — running gates"
    fi
  fi

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
    write_json_atomic "$VERIFICATION_FILE" "$parsed_results"
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
  local coverage=$total_weight

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
    | write_json_atomic "$baseline_file"

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
    # 성공 시에만 지문 캐시 기록 (게이트 실행이 working tree를 바꿨을 수 있으므로 재계산)
    fingerprint=$(quality_fingerprint) || fingerprint=""
    if [[ -n "$fingerprint" ]]; then
      jq -n --arg fp "$fingerprint" --arg ts "$(timestamp)" \
        '{"fingerprint": $fp, "timestamp": $ts, "result": "pass"}' | write_json_atomic "$cache_file"
    fi
    echo "=== ALL GATES PASSED ==="
    return 0
  else
    # 실패는 캐시하지 않음 — stale pass 캐시가 남지 않도록 제거 (--force 실패 케이스 포함)
    rm -f "$cache_file"
    echo "=== GATE FAILED: ${gate_summary} ==="
    return 1
  fi
}
