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

  # SPEC 파일 후보 탐색 (다양한 경로 지원)
  local spec_for_check=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_for_check="$candidate"; break; }
  done

  # 검사할 문서가 전혀 없으면 SKIP (라이브러리/문서 없는 프로젝트 — 계약: result skip)
  local _dcc_has_docs=false
  compgen -G "$docs_dir/*.md" > /dev/null 2>&1 && _dcc_has_docs=true
  [[ -n "$spec_for_check" ]] && _dcc_has_docs=true
  if [[ "$_dcc_has_docs" == "false" ]]; then
    echo "[doc-code-check] SKIP (no documentation files found in $docs_dir and no SPEC.md)"
    append_gate_history "doc-code-check" "skip" '{"reason":"no docs"}'
    record_verification "docCodeCheck" \
      "$(jq -n --arg ts "$(timestamp)" '{timestamp:$ts,result:"skip",reason:"no docs"}')"
    return 0
  fi

  # 1. 라우트/엔드포인트 매칭
  echo ""
  echo "[1] Route Matching"
  local doc_routes
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
  local _dcc_result="pass"
  [[ "$issues" -gt 0 ]] && _dcc_result="fail"
  append_gate_history "doc-code-check" "$_dcc_result" "{\"issues\":$issues}"
  record_verification "docCodeCheck" \
    "$(jq -n --arg ts "$(timestamp)" --arg r "$_dcc_result" --argjson n "$issues" '{timestamp:$ts,result:$r,issues:$n}')"
  [[ "$issues" -eq 0 ]] && return 0 || return 1
}

# ─── clarification-gate: [NEEDS-CLARIFICATION] 잔존 검사 (HARD_FAIL) ───

cmd_clarification_gate() {
  local docs_dir="${1:-docs}"
  echo "=== Clarification Gate ==="

  local scan_files=()
  for f in overview.md SPEC.md spec.md README.md; do
    # 대소문자 무시 파일시스템에서 SPEC.md/spec.md 이중 집계 방지
    [[ "$f" == "spec.md" && -f "SPEC.md" ]] && continue
    [[ -f "$f" ]] && scan_files+=("$f")
  done
  if [[ -d "$docs_dir" ]]; then
    while IFS= read -r -d '' f; do
      scan_files+=("$f")
    done < <(find "$docs_dir" -maxdepth 3 -name "*.md" -print0 2>/dev/null)
  fi

  if [[ ${#scan_files[@]} -eq 0 ]]; then
    # 문서가 전혀 없으면 skip 기록 — full-auto/plan-docs-full의 stop-hook은 pass만 허용하므로
    # 기획 문서 부재 상태의 완주를 fail-closed로 차단한다 (docCodeCheck의 skip 계약과 대칭)
    echo "[clarification-gate] SKIP (no documentation files found)"
    append_gate_history "clarification-gate" "skip" '{"reason":"no docs"}'
    record_verification "clarificationGate" \
      "$(jq -n --arg ts "$(timestamp)" '{timestamp:$ts,result:"skip",remaining:0,reason:"no docs"}')"
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
    record_verification "clarificationGate" \
      "$(jq -n --arg ts "$(timestamp)" --argjson n "$total" '{timestamp:$ts,result:"fail",remaining:$n}')"
    echo "=== CLARIFICATION GATE: HARD_FAIL ==="
    return 1
  fi

  echo "[clarification-gate] All [NEEDS-CLARIFICATION] tags resolved"
  append_gate_history "clarification-gate" "$result" '{"unresolved":0}'
  record_verification "clarificationGate" \
    "$(jq -n --arg ts "$(timestamp)" '{timestamp:$ts,result:"pass",remaining:0}')"
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
    # 빈 섹션 = 헤더 이후 다음 헤더(또는 EOF)까지 비어있지 않은 본문 라인이 하나도 없는 경우.
    # 헤더 직후의 빈 줄은 표준 마크다운 관행이므로 다음 비어있지 않은 줄까지 확인한다 (오탐 방지).
    local empty_sections
    empty_sections=$(awk '
      /^##/ { if (h != "" && !content) print h; h = $0; content = 0; next }
      NF > 0 { content = 1 }
      END { if (h != "" && !content) print h }
    ' overview.md 2>/dev/null | head -10 || true)
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
    # grep 무매치(exit 1)가 pipefail로 게이트를 기록 없이 죽이지 않도록 가드
    us_count=$({ grep -oE 'US-(F|B)-[0-9]+' "$spec_file" 2>/dev/null || true; } | wc -l | tr -d ' ')
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

  # TBD/모호 표현 검사 — 별도 서브커맨드 없이 여기서 직접 인라인 스캔 (코드 블록 제외)
  # H8: 핵심 섹션(API Contract / Data Model / 유저스토리·AC) 내부의 모호 표현은 CRITICAL로 승격
  local ambiguity_matches=0 core_matches=0
  # 주의: TBD/TODO/FIXME는 word-boundary 필수 — 'JTBD'(Jobs To Be Done) 등의 오탐 방지.
  # '적절한'/'필요 시'는 일상 한국어에서 오탐이 다수라 패턴에서 제외.
  local ambiguity_pattern='\bTBD\b|\bTODO\b|\bFIXME\b|to be decided|to be determined|미정|추후 결정|추후|as needed|if appropriate|등등|나중에|optionally|Phase [0-9]에서 추가|later phase'
  local ambiguity_files=()
  for af in overview.md SPEC.md spec.md; do
    # 대소문자 무시 파일시스템(Windows/macOS)에서 SPEC.md와 spec.md가 같은 파일로 이중 집계되는 것 방지
    [[ "$af" == "spec.md" && -f "SPEC.md" ]] && continue
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

  # 핵심 섹션 내부 모호 표현 계상 (spec 파일 대상):
  # 핵심 헤딩(API Contract/Data Model/유저스토리/AC)부터 같은/상위 레벨의 비-핵심 헤딩 전까지 캡처.
  # '### GET /path' 형태의 엔드포인트 서브헤딩은 API Contract의 일부로 간주하여 캡처를 끊지 않는다.
  if [[ -n "$spec_file" ]]; then
    local core_section_re='API Contract|API 계약|엔드포인트|Endpoint|Data Model|데이터 모델|DB Schema|스키마|User Stor|유저 ?스토리|사용자 스토리|Acceptance Criteria|인수 기준|완료 조건'
    core_matches=$(awk -v core_re="$core_section_re" '
      /^```/ { inblock = !inblock; next }
      inblock { next }
      /^#+[ \t]/ {
        match($0, /^#+/); lvl = RLENGTH
        if (capture && lvl <= cap_lvl) capture = 0
        if ($0 ~ core_re || $0 ~ /^#+[ \t]+(GET|POST|PUT|PATCH|DELETE)[ \t]+\//) {
          capture = 1; cap_lvl = lvl
        }
        next
      }
      capture { print }
    ' "$spec_file" 2>/dev/null | grep -icE "$ambiguity_pattern" || true)
    core_matches=$(echo "$core_matches" | tr -d '[:space:]')
    [[ -z "$core_matches" || ! "$core_matches" =~ ^[0-9]+$ ]] && core_matches=0
  fi

  if [[ "$core_matches" -gt 0 ]]; then
    critical=$((critical + 1))
    issues="${issues}CRITICAL: $core_matches TBD/ambiguous expression(s) inside core sections (API Contract / Data Model / User Stories / AC) of ${spec_file}\n"
  fi
  local non_core_matches=$((ambiguity_matches - core_matches))
  [[ "$non_core_matches" -lt 0 ]] && non_core_matches=0
  if [[ "$non_core_matches" -gt 0 ]]; then
    major=$((major + 1))
    issues="${issues}MAJOR: $non_core_matches TBD/ambiguous expressions in documentation (outside core sections)\n"
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

  # verification.json 기록 (stop-hook 하드락 증거) — 계약: result pass|fail, critical N
  local v_result="pass"
  [[ "$critical" -gt 0 ]] && v_result="fail"
  record_verification "specCompleteness" \
    "$(jq -n --arg ts "$(timestamp)" --arg r "$v_result" \
        --argjson c "$critical" --argjson mj "$major" --argjson mn "$minor" \
        '{timestamp:$ts,result:$r,critical:$c,major:$mj,minor:$mn}')"

  # DoD 자동 기록 (plan 템플릿 계약): 이 게이트가 user_story/data_model/api_contract/error_scenarios의
  # 스크립트 기록자다 (code-review-findings의 dod.code_review_pass 기록 패턴 준수).
  # PASS(critical=0) 시 존재하는 키만 checked:true — 미기록 시 plan 워크플로우가 소프트 데드락에 빠진다.
  if [[ "$critical" -eq 0 ]] && [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    jq_inplace "$PROGRESS_FILE" \
      --arg ev "spec-completeness PASS at $(timestamp) (critical: 0, major: $major, minor: $minor)" '
      reduce ("user_story", "data_model", "api_contract", "error_scenarios") as $k (.;
        if (((.dod // {}) | objects | has($k)) // false) then .dod[$k] = {checked: true, evidence: $ev} else . end)'
  fi

  echo "=== SPEC COMPLETENESS: ${result^^} ==="

  if [[ "$critical" -gt 0 ]]; then
    echo "BLOCKED: $critical CRITICAL issue(s) must be resolved before Phase 2."
    return 1
  fi
  return 0
}

# ─── doc-completeness: 구현자가 추가 판단 없이 코딩 가능한 수준의 정량 검증 (HARD_FAIL) ───
# spec-completeness가 다루지 않는 API 블록 단위의 정량 임계값을 강제한다:
#   - 각 API Contract 블록은 Request:, Response 200:, Response 4xx, 테스트 케이스 항목 ≥3건을 모두 가져야 함
#   - overview.md의 필수 헤더 섹션이 비어있지 않아야 함

cmd_doc_completeness() {
  local docs_dir="${1:-docs}"
  echo "=== Doc Completeness Check ==="

  local hard_fail=0 issues=""

  # progress 파일에서 projectScope 로드 — 잘못된 형식이면 fail-closed (HARD_FAIL)
  # cmd_spec_completeness와 동일 패턴: 파일 자체가 없으면 생략, 있는데 형식 오류면 차단
  local has_frontend="false" has_backend="false"
  if [[ -n "${PROGRESS_FILE:-}" && -f "$PROGRESS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    local scope_valid
    scope_valid=$(jq -r '
      .phases.phase_0.outputs.projectScope
      | if type == "object" and has("hasFrontend") and has("hasBackend")
           and (.hasFrontend | type == "boolean") and (.hasBackend | type == "boolean")
        then "valid" else "invalid" end
    ' "$PROGRESS_FILE" 2>/dev/null || echo "invalid")
    if [[ "$scope_valid" != "valid" ]]; then
      hard_fail=$((hard_fail + 1))
      issues="${issues}HARD_FAIL: projectScope missing or malformed in $PROGRESS_FILE (need {hasFrontend: bool, hasBackend: bool})\n"
    else
      has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
      has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    fi
  fi

  # ── 1. overview.md 필수 헤더 ──
  if [[ ! -f "overview.md" ]]; then
    hard_fail=$((hard_fail + 1))
    issues="${issues}HARD_FAIL: overview.md not found\n"
  else
    local required_headers=("Problem Statement" "페르소나|Persona|Target Users" "Core Jobs|JTBD" "Non-Goals" "기술 스택|Tech Stack")
    for header_pattern in "${required_headers[@]}"; do
      if ! grep -qE "^##+ +($header_pattern)" overview.md; then
        hard_fail=$((hard_fail + 1))
        issues="${issues}HARD_FAIL: overview.md missing required section matching: $header_pattern\n"
      fi
    done
  fi

  # ── 2. SPEC.md 탐색 ──
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done

  if [[ -z "$spec_file" ]]; then
    hard_fail=$((hard_fail + 1))
    issues="${issues}HARD_FAIL: SPEC.md not found\n"
  fi

  # ── 3. SPEC.md API 블록 정량 검증 (hasBackend=true일 때) ──
  if [[ -n "$spec_file" && "$has_backend" == "true" ]]; then
    # 각 API 블록: '### METHOD /path' 헤더부터 다음 ### 또는 ## 까지
    # awk로 블록 단위 검사
    local block_report
    block_report=$(awk '
      BEGIN { current=""; req=0; res200=0; res4xx=0; tc=0; in_tc=0 }
      /^### +(GET|POST|PUT|PATCH|DELETE) +\// {
        if (current != "") {
          if (req==0)    print current "|missing Request:"
          if (res200==0) print current "|missing Response 2xx:"
          if (res4xx==0) print current "|missing any Response 4xx"
          if (tc<3)      print current "|insufficient test cases (" tc "<3)"
        }
        current=$0; req=0; res200=0; res4xx=0; tc=0; in_tc=0
        next
      }
      /^### / || /^## / {
        if (current != "") {
          if (req==0)    print current "|missing Request:"
          if (res200==0) print current "|missing Response 2xx:"
          if (res4xx==0) print current "|missing any Response 4xx"
          if (tc<3)      print current "|insufficient test cases (" tc "<3)"
          current=""
        }
        in_tc=0
        next
      }
      current != "" {
        if ($0 ~ /(^|[[:space:]])(- )?(Request|요청)( body)?:/)             req=1
        # 성공 응답은 200 리터럴 강제 대신 2xx 전체 허용 (201 Created, 204 No Content 등)
        if ($0 ~ /(^|[[:space:]])(- )?Response +2[0-9][0-9]:/)               res200=1
        if ($0 ~ /(^|[[:space:]])(- )?Response +4[0-9][0-9]/)                res4xx=1
        # 테스트 케이스 라벨: 헤더 형식(#### 테스트 케이스), 리스트 형식(- 테스트 케이스:),
        # 줄 끝 단독 모두 지원. 옵셔널 콜론.
        if ($0 ~ /(^|[[:space:]>#-])(테스트 케이스|Test Cases?|Tests)[[:space:]]*:?[[:space:]]*$/) { in_tc=1; next }
        # 빈 줄 만나면 in_tc 종료 — 같은 블록 내 별도 리스트 오집계 방지
        if (in_tc==1 && $0 ~ /^[[:space:]]*$/)                                { in_tc=0; next }
        if (in_tc==1 && $0 ~ /^[[:space:]]*-/)                                tc++
        # 비-리스트, 비-빈줄 라인 만나면 in_tc 종료
        if (in_tc==1 && $0 !~ /^[[:space:]]*-/ && $0 !~ /^[[:space:]]*$/)     in_tc=0
      }
      END {
        if (current != "") {
          if (req==0)    print current "|missing Request:"
          if (res200==0) print current "|missing Response 2xx:"
          if (res4xx==0) print current "|missing any Response 4xx"
          if (tc<3)      print current "|insufficient test cases (" tc "<3)"
        }
      }
    ' "$spec_file" 2>/dev/null || true)

    if [[ -n "$block_report" ]]; then
      while IFS= read -r line; do
        hard_fail=$((hard_fail + 1))
        issues="${issues}HARD_FAIL: ${spec_file} ${line}\n"
      done <<< "$block_report"
    fi
  fi

  # ── 4. SPEC.md US-* ID 존재 (hasFrontend 또는 hasBackend) ──
  if [[ -n "$spec_file" ]]; then
    local us_count
    # 주의: `|| echo "0"`은 grep -c가 무매치 시 자체적으로 "0"을 출력하고 exit 1이라 "0\n0"이 됐었다
    us_count=$(grep -coE 'US-(F|B)-[0-9]+' "$spec_file" 2>/dev/null || true)
    us_count=$(echo "$us_count" | tr -d '[:space:]')
    [[ -z "$us_count" || ! "$us_count" =~ ^[0-9]+$ ]] && us_count=0
    if [[ "$us_count" -eq 0 ]]; then
      hard_fail=$((hard_fail + 1))
      issues="${issues}HARD_FAIL: ${spec_file} has no US-F-*/US-B-* IDs\n"
    fi
  fi

  # ── 5. hasFrontend=true일 때 Pages & Components 표 ──
  if [[ -n "$spec_file" && "$has_frontend" == "true" ]]; then
    if ! grep -qE '(Frontend Pages|Pages.*Components|페이지.*컴포넌트|화면.*목록)' "$spec_file" 2>/dev/null; then
      hard_fail=$((hard_fail + 1))
      issues="${issues}HARD_FAIL: hasFrontend=true but no Pages & Components section in $spec_file\n"
    fi
  fi

  # ── 결과 출력 ──
  echo ""
  if [[ -n "$issues" ]]; then
    printf '%b' "$issues"
  fi

  local result="pass"
  if [[ "$hard_fail" -gt 0 ]]; then
    result="hard_fail"
    echo ""
    echo "[doc-completeness] HARD_FAIL: $hard_fail blocking issue(s)"
    echo "  All issues must be resolved — implementer cannot proceed without these."
    append_gate_history "doc-completeness" "$result" "{\"blocking\":$hard_fail}"
    record_verification "docCompleteness" \
      "$(jq -n --arg ts "$(timestamp)" --argjson n "$hard_fail" '{timestamp:$ts,result:"fail",blocking:$n}')"
    echo "=== DOC COMPLETENESS: HARD_FAIL ==="
    return 1
  fi

  echo "[doc-completeness] All planning documents pass quantitative thresholds"
  append_gate_history "doc-completeness" "$result" '{"blocking":0}'
  record_verification "docCompleteness" \
    "$(jq -n --arg ts "$(timestamp)" '{timestamp:$ts,result:"pass",blocking:0}')"
  echo "=== DOC COMPLETENESS: PASS ==="
  return 0
}

# ─── definition-conflict: overview.md Non-Goals 침범 탐지 (SOFT_FAIL) ───
# 자연어 매칭은 false-positive가 있으므로 SOFT_FAIL — Claude가 각 매치를 검토 후 progress에 기록.

cmd_definition_conflict() {
  local docs_dir="${1:-docs}"
  echo "=== Definition Conflict Check ==="

  # DoD 자동 기록 (plan 템플릿 계약): 이 게이트가 dod.no_definition_conflict의 스크립트 기록자다.
  # SOFT 게이트라 pass/warn/skip 모두 exit 0 (통과) — 통과한 모든 종결 경로에서 기록해야
  # plan 워크플로우의 dod.no_definition_conflict가 소프트 데드락에 빠지지 않는다.
  # Usage: _dc_record_dod <evidence>
  _dc_record_dod() {
    local ev="$1"
    if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]] && command -v jq >/dev/null 2>&1; then
      jq_inplace "$PROGRESS_FILE" --arg ev "$ev (definition-conflict at $(timestamp))" '
        if (((.dod // {}) | objects | has("no_definition_conflict")) // false)
        then .dod.no_definition_conflict = {checked: true, evidence: $ev}
        else . end'
    fi
  }

  if [[ ! -f "overview.md" ]]; then
    echo "[definition-conflict] SKIP (overview.md not found)"
    append_gate_history "definition-conflict" "skip" '{"reason":"no overview.md"}'
    _dc_record_dod "N/A: overview.md not found"
    return 0
  fi

  # Non-Goals 섹션 추출 (## Non-Goals 부터 다음 ## 까지)
  local non_goals
  non_goals=$(awk '
    /^##+ +Non-Goals/ { capture=1; next }
    /^##/ && capture==1 { capture=0 }
    capture==1 && /^[[:space:]]*-/ { print }
  ' overview.md 2>/dev/null || true)

  if [[ -z "$non_goals" ]]; then
    echo "[definition-conflict] No Non-Goals section content found in overview.md"
    append_gate_history "definition-conflict" "skip" '{"reason":"no non-goals"}'
    _dc_record_dod "N/A: no Non-Goals section content in overview.md"
    return 0
  fi

  # 키워드 추출: 각 라인에서 길이 ≥3 토큰을 분리 (한글/영문/숫자)
  # 불용어 제외 (단순 명사/동사/형용사만 키워드로 사용)
  # 한글: 조사/공통명사/일반동사 / 영어: 관사/조동사/일반동사/공통명사
  local stopwords='^(the|and|for|not|with|that|this|will|from|have|has|had|are|was|were|but|all|any|its|none|use|user|users|data|api|app|service|when|then|than|into|over|under|here|there|should|must|can|may|need|like|via|also|same|other|both|each|some|none|more|less|much|many|such|own|new|old|good|best|true|false|null|등|또는|그리고|않는다|않는|않고|할|수|것|등을|등이|또한|기타|모든|일부|미지원|지원|사용|위한|대한|통해|관련|포함|제공|기능|구현|적용|반영|위해|되는|이다|있다|없다|않음|함|것은|이는|그러나|혹은|또한|위해|대해|에서|에게|으로|으로서|으로써|에는|에만|에서는|위에서)$'
  local keywords
  keywords=$(echo "$non_goals" \
    | sed -E 's/[^[:alnum:][:space:]가-힣]/ /g' \
    | tr -s '[:space:]' '\n' \
    | awk 'length($0)>=3' \
    | grep -ivE "$stopwords" \
    | sort -u || true)

  if [[ -z "$keywords" ]]; then
    echo "[definition-conflict] No usable keywords extracted from Non-Goals"
    append_gate_history "definition-conflict" "skip" '{"reason":"no keywords"}'
    _dc_record_dod "N/A: no usable keywords extracted from Non-Goals"
    return 0
  fi

  # 스캔 대상 파일 (overview.md 자체는 제외)
  local -a scan_files=()
  for f in SPEC.md spec.md README.md; do
    [[ -f "$f" ]] && scan_files+=("$f")
  done
  if [[ -d "$docs_dir" ]]; then
    while IFS= read -r -d '' f; do
      scan_files+=("$f")
    done < <(find "$docs_dir" -maxdepth 2 -name "*.md" -print0 2>/dev/null)
  fi

  if [[ ${#scan_files[@]} -eq 0 ]]; then
    echo "[definition-conflict] No documents to scan"
    append_gate_history "definition-conflict" "skip" '{"reason":"no docs"}'
    _dc_record_dod "N/A: no documents to scan"
    return 0
  fi

  local total_matches=0 match_output=""
  while IFS= read -r kw; do
    [[ -z "$kw" ]] && continue
    # awk index() 기반 substring 매칭 — Windows git-bash의 grep -F core dump 회피
    # 한/영 혼용 키워드, 정규식 메타문자 안전, 다중 파일 동시 처리
    local hits
    hits=$(awk -v kw="$kw" '
      index($0, kw) > 0 { printf "%s:%d:%s\n", FILENAME, FNR, $0 }
    ' "${scan_files[@]}" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
      local count
      count=$(echo "$hits" | wc -l | tr -d ' ')
      total_matches=$((total_matches + count))
      match_output="${match_output}\n[Non-Goals keyword: $kw]\n${hits}\n"
    fi
  done <<< "$keywords"

  local result="pass"
  if [[ "$total_matches" -gt 0 ]]; then
    result="warn"
    printf '%b' "$match_output"
    echo ""
    echo "[definition-conflict] WARN: $total_matches potential Non-Goals violations"
    echo "  Each match requires manual review:"
    echo "    (a) intentional explicit exception with documented rationale, or"
    echo "    (b) remove the violating content."
    echo "  Record decision under progress.phases.phase_1.outputs.nonGoalsAudit"
  else
    echo "[definition-conflict] No Non-Goals violations detected"
  fi

  append_gate_history "definition-conflict" "$result" "{\"matches\":$total_matches}"
  if [[ "$result" == "pass" ]]; then
    _dc_record_dod "definition-conflict PASS (0 Non-Goals violations)"
  else
    _dc_record_dod "definition-conflict SOFT PASS with WARN ($total_matches potential match(es) — manual review recorded under nonGoalsAudit)"
  fi
  echo "=== DEFINITION CONFLICT: ${result^^} ==="
  return 0
}

# ─── spec-to-tests: SPEC.md 엔드포인트 ↔ tests/api-smoke.sh 1:1 매핑 (HARD_FAIL) ───

cmd_spec_to_tests() {
  echo "=== Spec-to-Tests Mapping Check ==="

  # verification.json 기록 헬퍼 — 계약: specToTests {result: pass|fail}
  _stt_record() {
    record_verification "specToTests" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --arg reason "${2:-}" \
          '{timestamp:$ts,result:$r} + (if $reason != "" then {reason:$reason} else {} end)')"
  }

  # progress 파일에서 projectScope 로드 — 잘못된 형식이면 fail-closed (HARD_FAIL)
  local has_frontend="false" has_backend="false"
  if [[ -n "${PROGRESS_FILE:-}" && -f "$PROGRESS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    local scope_valid
    scope_valid=$(jq -r '
      .phases.phase_0.outputs.projectScope
      | if type == "object" and has("hasFrontend") and has("hasBackend")
           and (.hasFrontend | type == "boolean") and (.hasBackend | type == "boolean")
        then "valid" else "invalid" end
    ' "$PROGRESS_FILE" 2>/dev/null || echo "invalid")
    if [[ "$scope_valid" != "valid" ]]; then
      echo "[spec-to-tests] HARD_FAIL: projectScope missing or malformed in $PROGRESS_FILE"
      echo "  Need {hasFrontend: bool, hasBackend: bool}"
      append_gate_history "spec-to-tests" "hard_fail" '{"reason":"invalid projectScope"}'
      _stt_record "fail" "invalid projectScope"
      echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
      return 1
    fi
    has_frontend=$(jq -r '.phases.phase_0.outputs.projectScope.hasFrontend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
    has_backend=$(jq -r '.phases.phase_0.outputs.projectScope.hasBackend' "$PROGRESS_FILE" 2>/dev/null || echo "false")
  fi

  # hasBackend=false면 ui-smoke 또는 lib-smoke 존재만 확인하고 종료
  if [[ "$has_backend" != "true" ]]; then
    if [[ "$has_frontend" == "true" ]]; then
      if [[ ! -f tests/ui-smoke.sh && ! -f tests/ui-smoke.spec.ts && ! -f tests/ui-smoke.spec.js ]]; then
        echo "[spec-to-tests] HARD_FAIL: hasFrontend=true but no tests/ui-smoke.*"
        append_gate_history "spec-to-tests" "hard_fail" '{"reason":"missing ui-smoke"}'
        _stt_record "fail" "missing ui-smoke"
        echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
        return 1
      fi
      echo "[spec-to-tests] hasFrontend=true, ui-smoke present (mapping check skipped — UI flows are validated by doc-planning Step 1-7)"
    else
      if [[ ! -f tests/lib-smoke.sh ]]; then
        echo "[spec-to-tests] HARD_FAIL: library/CLI but no tests/lib-smoke.sh"
        append_gate_history "spec-to-tests" "hard_fail" '{"reason":"missing lib-smoke"}'
        _stt_record "fail" "missing lib-smoke"
        echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
        return 1
      fi
      echo "[spec-to-tests] library/CLI lib-smoke present"
    fi
    append_gate_history "spec-to-tests" "pass" '{"hasBackend":false}'
    _stt_record "pass"
    echo "=== SPEC-TO-TESTS: PASS ==="
    return 0
  fi

  # ── hasBackend=true: SPEC.md ↔ api-smoke.sh 매핑 ──
  local spec_file=""
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { spec_file="$candidate"; break; }
  done

  if [[ -z "$spec_file" ]]; then
    echo "[spec-to-tests] HARD_FAIL: SPEC.md not found"
    append_gate_history "spec-to-tests" "hard_fail" '{"reason":"no spec"}'
    _stt_record "fail" "no spec"
    echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
    return 1
  fi

  if [[ ! -f tests/api-smoke.sh ]]; then
    echo "[spec-to-tests] HARD_FAIL: hasBackend=true but tests/api-smoke.sh missing"
    append_gate_history "spec-to-tests" "hard_fail" '{"reason":"missing api-smoke"}'
    _stt_record "fail" "missing api-smoke"
    echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
    return 1
  fi

  # SPEC.md에서 엔드포인트 추출: '### METHOD /path' 형식
  local spec_endpoints
  spec_endpoints=$(grep -oE '^### +(GET|POST|PUT|PATCH|DELETE) +/[A-Za-z0-9_/{}\:.-]+' "$spec_file" 2>/dev/null \
    | sed -E 's/^### +//' | sort -u || true)

  if [[ -z "$spec_endpoints" ]]; then
    echo "[spec-to-tests] HARD_FAIL: no '### METHOD /path' endpoints in $spec_file"
    append_gate_history "spec-to-tests" "hard_fail" '{"reason":"no endpoints"}'
    _stt_record "fail" "no endpoints"
    echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
    return 1
  fi

  # api-smoke.sh의 curl 호출 라인 추출 (path 변수 치환은 텍스트 그대로 유지)
  # 각 라인은 '-X METHOD' (없으면 GET 기본값) + path를 포함한다고 가정
  local smoke_lines
  smoke_lines=$(grep -nE '\bcurl\b' tests/api-smoke.sh 2>/dev/null || true)

  local missing=0 missing_list=""
  while IFS= read -r ep; do
    [[ -z "$ep" ]] && continue
    local method path
    method=$(echo "$ep" | awk '{print $1}')
    path=$(echo "$ep" | awk '{print $2}')

    # path templating 처리: '/users/{id}' → 세그먼트 단위 매칭
    # 정규식 escape를 피하고 awk index() 기반 substring 매칭 사용
    # 예: '/users/{id}/posts' → ['/users/', '/posts'] 두 토막 모두 포함되면 매치
    # prefix collision 방지: 마지막 세그먼트가 영숫자로 끝나면 다음 char도 영숫자가 아니어야 함
    # ('/api/goal' vs '/api/goalsX' 구분)
    local matched=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # path의 모든 비-{} 세그먼트가 line 내에서 순서대로 나타나고
      # 마지막 세그먼트 직후가 word boundary인지 awk로 확인
      if awk -v p="$path" -v line="$line" '
        BEGIN {
          # path를 {...} 기준으로 분할
          n = 0
          rem = p
          while (match(rem, /\{[^}]+\}/) > 0) {
            seg = substr(rem, 1, RSTART - 1)
            if (length(seg) > 0) { n++; segs[n] = seg }
            rem = substr(rem, RSTART + RLENGTH)
          }
          if (length(rem) > 0) { n++; segs[n] = rem }
          if (n == 0) { exit 1 }  # path가 전부 {}로만 구성되면 비정상

          # 세그먼트를 line 내에서 순서대로 매칭 (각 매치 후 그 뒤를 계속 검색)
          search_from = 1
          for (i = 1; i <= n; i++) {
            tail = substr(line, search_from)
            pos = index(tail, segs[i])
            if (pos == 0) { exit 1 }

            # 마지막 세그먼트인 경우 word boundary 검증
            if (i == n) {
              abs_end = search_from + pos - 1 + length(segs[i])
              next_char = substr(line, abs_end, 1)
              last_seg_char = substr(segs[i], length(segs[i]), 1)
              # 마지막 세그먼트가 영숫자/언더스코어로 끝나는데
              # 다음 문자도 영숫자/언더스코어이면 prefix collision → reject
              if (last_seg_char ~ /[A-Za-z0-9_]/ && next_char ~ /[A-Za-z0-9_]/) { exit 1 }
            }

            search_from = search_from + pos - 1 + length(segs[i])
          }
          exit 0
        }
      '; then
        # path 매치됨 — 메서드 매치 확인
        if [[ "$method" == "GET" ]]; then
          if ! echo "$line" | grep -qiE -- '-X +(POST|PUT|PATCH|DELETE)'; then
            matched=1; break
          fi
        else
          if echo "$line" | grep -qiE -- "-X +${method}([^A-Za-z]|$)"; then
            matched=1; break
          fi
        fi
      fi
    done <<< "$smoke_lines"

    if [[ $matched -eq 0 ]]; then
      missing=$((missing + 1))
      missing_list="${missing_list}  - $ep\n"
    fi
  done <<< "$spec_endpoints"

  echo ""
  if [[ "$missing" -gt 0 ]]; then
    echo "Endpoints in SPEC.md not covered by tests/api-smoke.sh:"
    printf '%b' "$missing_list"
    echo "[spec-to-tests] HARD_FAIL: $missing endpoint(s) lack smoke coverage"
    append_gate_history "spec-to-tests" "hard_fail" "{\"missing\":$missing}"
    _stt_record "fail" "$missing endpoint(s) lack smoke coverage"
    echo "=== SPEC-TO-TESTS: HARD_FAIL ==="
    return 1
  fi

  local total_eps
  total_eps=$(echo "$spec_endpoints" | wc -l | tr -d ' ')
  echo "[spec-to-tests] All $total_eps SPEC endpoints covered by tests/api-smoke.sh"
  append_gate_history "spec-to-tests" "pass" "{\"endpoints\":$total_eps}"
  _stt_record "pass"
  echo "=== SPEC-TO-TESTS: PASS ==="
  return 0
}
