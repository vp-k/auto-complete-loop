# gates/docs.sh — 문서 일관성, 문서↔코드 매칭, 문서 크기, 모호성, 스펙 완전성 검사

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

# ─── doc-size-check: 문서 크기 검증 ───

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

# ─── ambiguity-check: TBD/TODO 모호 표현 스캔 ───

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

# ─── clarification-gate: [NEEDS-CLARIFICATION] 잔존 검사 (HARD_FAIL) ───

cmd_clarification_gate() {
  local docs_dir="${1:-docs}"
  echo "=== Clarification Gate ==="

  local scan_files=()
  for f in overview.md SPEC.md spec.md README.md; do
    [[ -f "$f" ]] && scan_files+=("$f")
  done
  if [[ -d "$docs_dir" ]]; then
    while IFS= read -r -d '' f; do
      scan_files+=("$f")
    done < <(find "$docs_dir" -maxdepth 3 -name "*.md" -print0 2>/dev/null)
  fi

  if [[ ${#scan_files[@]} -eq 0 ]]; then
    echo "[clarification-gate] SKIP (no documentation files found)"
    append_gate_history "clarification-gate" "skip" '{"reason":"no docs"}'
    return 0
  fi

  local total=0 output=""
  for f in "${scan_files[@]}"; do
    local filtered
    filtered=$(awk '/^```/{skip=!skip; next} !skip{print NR": "$0}' "$f" 2>/dev/null || true)
    local matches
    matches=$(echo "$filtered" | grep -E '\[NEEDS-CLARIFICATION' | head -20 || true)
    if [[ -n "$matches" ]]; then
      local count
      count=$(echo "$matches" | wc -l | tr -d ' ')
      total=$((total + count))
      output="${output}--- $f ($count tags) ---\n$matches\n\n"
    fi
  done

  local result="pass"
  if [[ "$total" -gt 0 ]]; then
    result="hard_fail"
    printf '%b' "$output"
    echo "[clarification-gate] HARD_FAIL: $total unresolved [NEEDS-CLARIFICATION] tags"
    echo "  Phase 2 진입 차단. 모든 태그를 사용자 답변으로 치환해야 한다."
    echo "  프로토콜: templates/doc-planning-common.md → [NEEDS-CLARIFICATION] 태그 프로토콜"
    append_gate_history "clarification-gate" "$result" "{\"unresolved\":$total}"
    echo "=== CLARIFICATION GATE: HARD_FAIL ==="
    return 1
  fi

  echo "[clarification-gate] All [NEEDS-CLARIFICATION] tags resolved"
  append_gate_history "clarification-gate" "$result" '{"unresolved":0}'
  echo "=== CLARIFICATION GATE: PASS ==="
  return 0
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
