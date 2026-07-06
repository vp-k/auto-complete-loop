# gates/errors.sh — 에러 기록 + 에스컬레이션(L0-L5) 추적, 디버그 코드 탐색

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
          # 레벨 문자열("L3")의 숫자부를 수치 비교 (사전순 비교는 두 자리 레벨에서 깨짐)
          try (if (.[0][1:] | tonumber) > (.[1][1:] | tonumber) then "backward" else "not" end) catch "not"
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

# ─── find-debug-code: 디버그 코드 탐색 ───

cmd_find_debug_code() {
  local search_dir="${1:-.}"

  echo "=== Debug Code Scan ==="
  echo "Scanning: $search_dir"

  local found=0

  # 언어별 디버그 패턴
  # JavaScript/TypeScript
  # (globstar 미설정 환경에서 `**` glob은 재귀하지 않으므로 find로만 감지)
  if find "$search_dir" -maxdepth 5 \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) 2>/dev/null | head -1 >/dev/null 2>&1; then
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
