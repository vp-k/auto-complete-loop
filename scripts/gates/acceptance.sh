# gates/acceptance.sh — 인수 테스트 선작성+동결(freeze) + 실행 게이트
#
# 계약 (skills/rules 담당자와 공유):
#   tests/acceptance/.manifest.json:
#     { "frozenAt": ts, "gitHead": sha|null, "hashAlgo": "sha256sum|shasum|git-hash-object",
#       "files": { "<상대경로>": "<sha256>" },     # manifest 자신 제외, tests/acceptance/ 하위 전 파일
#       "specFile": { "path": "<SPEC 경로>", "hash": "<sha256>" } | null,  # v4.8.0+: SPEC 해시 동결
#       "refreezeHistory": [ { "at": ts, "gitHead": sha|null, "approvedByUser": true } ] }
#
#   SPEC 해시 동결 (v4.8.0): 동결 시점의 SPEC 파일 해시를 함께 기록하고 acceptance-gate가
#   대조한다. 게이트 통과 후 SPEC을 몰래 수정해 검증 압력을 낮추는 세탁("verify then edit")을
#   차단 — SPEC 변경은 사용자 승인 → `--approved-by-user` 재동결로만 가능 (Step 2-1.9의 기계적 강제).
#   specFile이 없는 구(pre-4.8) manifest는 SPEC 대조를 건너뛴다 (하위호환).
#   verification.json 키:
#     acceptanceFreeze: { result: "pass"|"fail", files: N }
#     acceptanceTests:  { result: "pass"|"fail"|"skip", total: N, passed: N, failed: N,
#                         tamperedFiles?: [...], addedFiles?: [...], flaky?: true, firstRun?: {...} }
#   러너 규약: bash tests/acceptance/run.sh — 전부 통과 시에만 exit 0, 마지막 줄에
#     "ACCEPTANCE_RESULT: total=N passed=N failed=N" 출력
#
#   승인 unlock 토큰 (v4.18.0): `.claude/acceptance-unlock.json`
#     { unlockedAt, reason, phase, specHashAtUnlock, hashAlgo, specPath }
#     동결 후 SPEC/인수 테스트를 고치려면 도구 자체가 막혀 있어 "승인받아도 고칠 수 없는"
#     교착이 있었다. acceptance-unlock 이 사용자 승인 하에 토큰을 만들고, protect-files-guard 가
#     토큰 존재 시 SPEC.md / tests/acceptance/** 편집을 허용한다. 토큰은 재동결 시 소비되며,
#     남아 있으면 acceptance-gate FAIL + stop-hook 차단(= 반드시 재동결로 닫아야 하는 열린 문).

ACCEPTANCE_DIR="tests/acceptance"
ACCEPTANCE_MANIFEST="$ACCEPTANCE_DIR/.manifest.json"
ACCEPTANCE_RUNNER="$ACCEPTANCE_DIR/run.sh"
ACCEPTANCE_UNLOCK_TOKEN=".claude/acceptance-unlock.json"

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
# 개행 정규화 (M6): CR(\r)을 제거한 내용을 해시한다. Linux(LF)에서 동결한 manifest를
# Windows Git Bash(autocrlf, CRLF)에서 검증할 때 원시 바이트 해시는 달라져 무고한
# tamper FAIL이 발생한다. freeze/verify가 모두 이 헬퍼를 거치므로 여기서 정규화하면
# 양측이 항상 동일한 입력을 해시한다.
_acc_hash_file() {
  local algo="$1" f="$2"
  case "$algo" in
    sha256sum)       tr -d '\r' < "$f" | sha256sum | awk '{print $1}' ;;
    shasum)          tr -d '\r' < "$f" | shasum -a 256 | awk '{print $1}' ;;
    git-hash-object) tr -d '\r' < "$f" | git hash-object --stdin ;;
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

# SPEC 파일 탐색 (spec-completeness/provenance-gate와 동일한 4-후보 우선순위)
_acc_find_spec() {
  local candidate
  for candidate in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    [[ -f "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

# ─── 현재 Phase 판별 (토큰 기록용, 베스트에포트) ───

_acc_current_phase() {
  local pf="${PROGRESS_FILE:-}"
  if [[ -z "$pf" ]] || [[ ! -f "$pf" ]]; then
    pf=$(detect_progress_file 2>/dev/null || true)
  fi
  [[ -n "$pf" ]] && [[ -f "$pf" ]] || { echo "unknown"; return 0; }
  jq -r '
    if has("currentPhase") and (.currentPhase != null) then .currentPhase
    elif has("steps") then ([.steps[]? | select(.status == "in_progress") | .name] | first // "unknown")
    else "unknown" end' "$pf" 2>/dev/null || echo "unknown"
}

# ─── acceptance-unlock: 승인 기반 동결 해제 토큰 발급 ───
# Usage: acceptance-unlock --approved-by-user --reason "<사유>" [--progress-file <p>]
#
# 왜 필요한가: protect-files-guard 는 동결 후 SPEC.md / tests/acceptance/** 의 Edit/Write 를
# 차단한다. 그런데 Step 2-1.9/2-1.10 이 정한 정상 해결 절차는 "사용자 승인 → SPEC 갱신 →
# --approved-by-user 재동결"이다. 승인을 받아도 고칠 도구가 없으면 절차 자체가 실행 불가다.
# 이 서브커맨드가 그 승인을 기계가 읽을 수 있는 토큰으로 만들어 가드를 한시적으로 연다.
# 토큰은 열린 문이므로 반드시 재동결(acceptance-freeze --approved-by-user)로 닫혀야 하며,
# 잔존 시 acceptance-gate FAIL + stop-hook 이 완주를 차단한다.

cmd_acceptance_unlock() {
  echo "=== Acceptance Unlock ==="
  require_jq

  local approved_by_user=false reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --approved-by-user) approved_by_user=true; shift ;;
      --reason) reason="${2:-}"; shift; shift || true ;;
      --reason=*) reason="${1#--reason=}"; shift ;;
      *) shift ;;
    esac
  done

  if [[ "$approved_by_user" != "true" ]]; then
    echo "[acceptance-unlock] REFUSED: 동결 해제는 사용자 승인이 필요합니다."
    echo "  절차: (1) AskUserQuestion 으로 '인수 테스트/SPEC 동결을 해제하고 스펙을 변경할까요?'를 질문"
    echo "        (2) 승인받으면 아래로 재실행"
    echo "            shared-gate.sh acceptance-unlock --approved-by-user --reason \"<변경이 필요한 이유>\""
    echo "        (3) SPEC/인수 테스트 수정"
    echo "        (4) shared-gate.sh acceptance-freeze --approved-by-user --reason \"<같은 사유>\" 로 재동결(토큰 소비)"
    echo "  승인 없이 스펙을 약화시키는 것은 금지됩니다 (구현 편의를 위한 완화는 스펙 변경이 아님)."
    echo "=== ACCEPTANCE UNLOCK: REFUSED ==="
    return 1
  fi

  if [[ -z "$reason" ]]; then
    echo "[acceptance-unlock] REFUSED: --reason \"<사유>\" 는 필수입니다 (무엇을 왜 바꾸는지 기록)."
    echo "=== ACCEPTANCE UNLOCK: REFUSED ==="
    return 1
  fi

  local phase spec_path="" spec_hash="" algo=""
  phase=$(_acc_current_phase)

  # 해제 시점의 SPEC 해시를 남긴다 — 재동결 시 '무엇이 실제로 바뀌었는지' 감사 가능.
  if algo=$(_acc_detect_hash_algo 2>/dev/null); then
    if spec_path=$(_acc_find_spec); then
      spec_hash=$(_acc_hash_file "$algo" "$spec_path" 2>/dev/null || echo "")
    fi
  fi

  mkdir -p "$(dirname "$ACCEPTANCE_UNLOCK_TOKEN")" 2>/dev/null || true
  jq -n --arg at "$(timestamp)" --arg r "$reason" --arg ph "$phase" \
        --arg sp "$spec_path" --arg sh "$spec_hash" --arg algo "$algo" '
    {unlockedAt:$at, reason:$r, phase:$ph,
     specPath:(if $sp == "" then null else $sp end),
     specHashAtUnlock:(if $sh == "" then null else $sh end),
     hashAlgo:(if $algo == "" then null else $algo end),
     approvedByUser:true}' | write_json_atomic "$ACCEPTANCE_UNLOCK_TOKEN"

  log_event "acceptance.unlock" "$(jq -cn --arg r "$reason" --arg ph "$phase" \
    '{reason:$r, phase:$ph, approvedByUser:true}' 2>/dev/null || echo '{}')" || true
  append_gate_history "acceptance-unlock" "pass" "$(jq -n --arg r "$reason" '{reason:$r}')" 2>/dev/null || true

  echo "[acceptance-unlock] 토큰 발급: $ACCEPTANCE_UNLOCK_TOKEN"
  echo "  phase=$phase, reason=$reason"
  echo "  → SPEC.md / tests/acceptance/** 편집이 한시적으로 허용됩니다."
  echo "  → 수정 후 반드시 재동결하세요 (토큰이 남아 있으면 acceptance-gate FAIL, 완주 차단):"
  echo "      shared-gate.sh acceptance-freeze --approved-by-user --reason \"$reason\""
  echo "=== ACCEPTANCE UNLOCK: PASS ==="
  return 0
}

# ─── acceptance-freeze: 인수 테스트 동결 (manifest 생성/갱신) ───
# Usage: acceptance-freeze [--approved-by-user] [--reason "<사유>"] [--approved-by "<주체>"]

cmd_acceptance_freeze() {
  echo "=== Acceptance Freeze ==="
  require_jq

  local approved_by_user=false reason="" approved_by=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --approved-by-user) approved_by_user=true; shift ;;
      --reason) reason="${2:-}"; shift; shift || true ;;
      --reason=*) reason="${1#--reason=}"; shift ;;
      --approved-by) approved_by="${2:-}"; shift; shift || true ;;
      --approved-by=*) approved_by="${1#--approved-by=}"; shift ;;
      *) shift ;;
    esac
  done

  # unlock 토큰(acceptance-unlock 발급): 존재하면 이 재동결이 그 토큰을 소비한다.
  # 토큰의 reason 을 기본 사유로 승계하고, 호출자가 --reason 을 주면 그것이 우선한다.
  local unlock_present="false" unlock_reason=""
  if [[ -f "$ACCEPTANCE_UNLOCK_TOKEN" ]]; then
    unlock_present="true"
    unlock_reason=$(jq -r '.reason // ""' "$ACCEPTANCE_UNLOCK_TOKEN" 2>/dev/null || echo "")
    [[ -z "$reason" ]] && reason="$unlock_reason"
  fi
  if [[ "$approved_by_user" == "true" ]]; then
    [[ -z "$approved_by" ]] && approved_by="user (AskUserQuestion)"
    if [[ "$unlock_present" != "true" ]]; then
      # 하위호환: 토큰 없이도 기존과 동일하게 동작한다(unlock 도입 전 절차/외부 호출자).
      # 다만 가드를 열지 않고 재동결하는 경로이므로 흔적을 남긴다.
      echo "[acceptance-freeze] WARNING: --approved-by-user 인데 unlock 토큰이 없습니다"
      echo "  (권장 절차: acceptance-unlock --approved-by-user --reason ... → 수정 → 이 재동결)"
    fi
  fi

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

  # 단독 실행 가능성 WARN: us-*.sh 가 있는데 공용 헬퍼(_helper.sh)가 없으면 구현 Phase 의 US 파일
  # 단독 실행(implementation SKILL Step 2-4)이 서버를 확보할 수 없어 전체 러너 우회를 유발한다.
  # 동결 전에 고치라는 신호 — 차단은 아니다 (헬퍼 구성은 스택마다 다르므로 존재만 본다).
  if printf '%s\n' "$file_list" | grep -qE '(^|/)us-[^/]*\.sh$' \
     && ! printf '%s\n' "$file_list" | grep -qE '(^|/)_helper\.sh$'; then
    echo "[acceptance-freeze] WARNING: us-*.sh exist but $ACCEPTANCE_DIR/_helper.sh is missing — 개별 US 테스트가 단독 실행 시 서버를 스스로 확보하지 못한다 (templates/acceptance-tests-guide.md '_helper.sh 필수' 참조). 동결 전에 추가하라." >&2
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

  # refreezeHistory 기록: 승인 동결이거나 unlock 토큰을 소비하는 동결이면 사유와 함께 남긴다.
  # (기획 단계라도 토큰을 소비했다면 '무엇을 왜 열고 닫았는지'가 이력에 남아야 한다)
  _af_bool() { [[ "$1" == "true" ]] && echo true || echo false; }
  if [[ "$impl_started" == "true" ]] || [[ "$unlock_present" == "true" ]]; then
    history_json=$(jq -n --argjson base "$history_json" --arg at "$(timestamp)" --arg gh "$git_head" \
      --argjson approved "$(_af_bool "$approved_by_user")" \
      --argjson unlocked "$(_af_bool "$unlock_present")" \
      --arg reason "$reason" --arg by "$approved_by" '
      $base + [ {at:$at, gitHead:(if $gh == "" then null else $gh end), approvedByUser:$approved}
                + (if $reason != "" then {reason:$reason} else {} end)
                + (if $by != "" then {approvedBy:$by} else {} end)
                + (if $unlocked then {unlockConsumed:true} else {} end) ]')
    echo "[acceptance-freeze] Approved freeze (recorded in refreezeHistory)${reason:+ — reason: $reason}"
    log_event "acceptance.refreeze" "$(jq -cn --arg pf "$prior_freeze" --arg r "$reason" \
      --argjson approved "$(_af_bool "$approved_by_user")" \
      --argjson unlocked "$(_af_bool "$unlock_present")" \
      '{priorFreeze: ($pf == "true"), approvedByUser: $approved, unlockConsumed: $unlocked, reason: $r}' \
      2>/dev/null || echo '{}')" || true
  elif [[ "$prior_freeze" == "true" ]]; then
    echo "[acceptance-freeze] Planning-phase re-freeze (allowed, silent update)"
  fi

  # 4.5. SPEC 해시 동결 (v4.8.0): 동결 시점의 SPEC 파일 해시를 manifest에 함께 기록.
  # SPEC 부재는 경고만 (SPEC 존재 강제는 spec-completeness 소관 — 여기서 이중 차단하지 않음)
  local spec_json="null" spec_path=""
  if spec_path=$(_acc_find_spec); then
    local spec_hash
    spec_hash=$(_acc_hash_file "$hash_algo" "$spec_path") || {
      _af_fail "SPEC hashing failed with $hash_algo ($spec_path)"
      return 1
    }
    spec_json=$(jq -n --arg p "$spec_path" --arg h "$spec_hash" '{path:$p, hash:$h}')
    echo "[acceptance-freeze] SPEC frozen: $spec_path"
  else
    echo "[acceptance-freeze] WARNING: no SPEC file found (SPEC.md/docs/SPEC.md/docs/api-spec.md/spec.md) — specFile=null (SPEC 해시 대조 비활성)"
  fi

  # 5. manifest 기록
  jq -n \
    --arg at "$(timestamp)" \
    --arg gh "$git_head" \
    --arg algo "$hash_algo" \
    --argjson files "$files_json" \
    --argjson spec "$spec_json" \
    --argjson hist "$history_json" \
    '{frozenAt:$at, gitHead:(if $gh == "" then null else $gh end), hashAlgo:$algo, files:$files, specFile:$spec, refreezeHistory:$hist}' \
    > "$ACCEPTANCE_MANIFEST"

  # 토큰 소비: 재동결이 성공했으므로 '열린 문'을 닫는다. 이 삭제가 없으면
  # acceptance-gate 와 stop-hook 이 계속 차단한다 (unlock 은 반드시 재동결로 끝난다).
  if [[ "$unlock_present" == "true" ]]; then
    rm -f "$ACCEPTANCE_UNLOCK_TOKEN"
    echo "[acceptance-freeze] unlock 토큰 소비됨 ($ACCEPTANCE_UNLOCK_TOKEN 삭제)"
    log_event "acceptance.unlock_consumed" "$(jq -cn --arg r "$reason" '{reason:$r}' 2>/dev/null || echo '{}')" || true
  fi

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

  # 기록 헬퍼 — 계약: acceptanceTests {result, total, passed, failed, tamperedFiles?, reason?, ...extra}
  # Usage: _ag_record <result> <total> <passed> <failed> [reason] [tampered_json_array] [extra_json_object]
  _ag_record() {
    record_verification "acceptanceTests" \
      "$(jq -n --arg ts "$(timestamp)" --arg r "$1" --argjson t "$2" --argjson p "$3" --argjson f "$4" \
            --arg reason "${5:-}" --argjson tampered "${6:-null}" --argjson extra "${7:-null}" \
          '{timestamp:$ts,result:$r,total:$t,passed:$p,failed:$f}
           + (if $reason != "" then {reason:$reason} else {} end)
           + (if $tampered != null then {tamperedFiles:$tampered} else {} end)
           + (if $extra != null then $extra else {} end)')"
  }

  # 0. unlock 토큰 잔존 → FAIL (열린 문은 재동결로만 닫힌다)
  # acceptance-unlock 은 SPEC/인수 테스트 편집을 한시 허용한다. 토큰이 남아 있다는 것은
  # 아직 재동결하지 않았다는 뜻이므로, 이 상태의 green 은 "동결된 기준에 대한 green"이 아니다.
  if [[ -f "$ACCEPTANCE_UNLOCK_TOKEN" ]]; then
    local _ag_ur
    _ag_ur=$(jq -r '.reason // "(no reason recorded)"' "$ACCEPTANCE_UNLOCK_TOKEN" 2>/dev/null || echo "(unreadable)")
    echo "[acceptance-gate] FAIL: unlock pending — re-freeze first ($ACCEPTANCE_UNLOCK_TOKEN 존재)"
    echo "  unlock reason: $_ag_ur"
    echo "  Remedy: SPEC/인수 테스트 수정을 마친 뒤 acceptance-freeze --approved-by-user 로 재동결하세요 (토큰 소비)."
    _ag_record "fail" 0 0 0 "unlock pending — re-freeze first"
    append_gate_history "acceptance-gate" "fail" '{"reason":"unlock pending"}'
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi

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

  # 변경(해시 불일치)/삭제(manifest에만 존재) = 탬퍼 → FAIL 유지
  # 추가(디스크에만 존재) = WARN 으로 강등 (v4.18.0)
  #   근거: 동결의 목적은 "구현이 자기 검증 기준을 약화시키지 못하게" 하는 것이다.
  #   추가 파일은 기존 동결 파일의 해시를 그대로 통과시키므로 기존 어서션을 약화시키지
  #   못한다 — run.sh(그 자체가 동결 대상)의 glob 이 추가 파일을 집어 실행하면 total 이
  #   늘고 어서션이 더해질 뿐이므로 total 증가는 정상이다. 반면 변경/삭제는 어서션을
  #   직접 약화시키므로 FAIL 을 유지한다.
  #   (잔여 위험: 기존 테스트가 "있으면 source" 형태로 신규 파일을 조건부 참조하는 경우.
  #    이는 addedFiles 기록으로 감사 가능하게 남긴다.)
  local tampered_json tampered_count added_json added_count
  tampered_json=$(jq -n --argjson old "$manifest_files" --argjson new "$current_files" '
    [ ($old | keys[]) as $k | select(($new[$k] // null) != $old[$k]) | $k ] | sort | unique')
  added_json=$(jq -n --argjson old "$manifest_files" --argjson new "$current_files" '
    [ ($new | keys[]) as $k | select(($old[$k] // null) == null) | $k ] | sort | unique')
  tampered_count=$(echo "$tampered_json" | jq 'length')
  added_count=$(echo "$added_json" | jq 'length')

  if [[ "$tampered_count" -gt 0 ]]; then
    echo "[acceptance-gate] FAIL: acceptance tests were modified after freeze — revert or get user approval and re-freeze"
    echo "  Tampered files (modified/deleted):"
    echo "$tampered_json" | jq -r '.[] | "    - " + .'
    echo "  Remedy: revert the changes, or (with user approval) acceptance-unlock --approved-by-user --reason ..."
    echo "          → 수정 → acceptance-freeze --approved-by-user"
    _ag_record "fail" 0 0 0 "acceptance tests were modified after freeze — revert or get user approval and re-freeze" "$tampered_json"
    append_gate_history "acceptance-gate" "fail" "$(jq -n --argjson t "$tampered_json" '{reason:"tampered",tamperedFiles:$t}')"
    echo "=== ACCEPTANCE GATE: FAIL ==="
    return 1
  fi

  local extra_json="null"
  if [[ "$added_count" -gt 0 ]]; then
    echo "[acceptance-gate] WARNING: $added_count file(s) added after freeze (WARN, not blocking — additions cannot weaken frozen assertions):" >&2
    echo "$added_json" | jq -r '.[] | "    + " + .'
    echo "  (감사 목적으로 acceptanceTests.addedFiles 에 기록됩니다. 인수 기준을 바꾸는 추가라면 재동결하세요.)" >&2
    extra_json=$(jq -cn --argjson a "$added_json" '{addedFiles:$a}')
  fi
  echo "[acceptance-gate] Integrity OK ($(echo "$current_files" | jq 'length') file(s), algo: $algo, added: $added_count)"

  # 3.5. SPEC 해시 대조 (v4.8.0): 동결 시점 SPEC과 현재 SPEC이 동일해야 한다.
  # 게이트 통과 후 SPEC을 수정해 검증 기준을 낮추는 세탁 차단 — 게이트 재실행으로도
  # 우회 불가 (해시 갱신은 --approved-by-user 재동결로만). pre-4.8 manifest(specFile 부재/null)는 skip.
  local spec_frozen_path spec_frozen_hash
  spec_frozen_path=$(jq -r '.specFile.path // ""' "$ACCEPTANCE_MANIFEST" 2>/dev/null || echo "")
  if [[ -n "$spec_frozen_path" ]]; then
    spec_frozen_hash=$(jq -r '.specFile.hash // ""' "$ACCEPTANCE_MANIFEST" 2>/dev/null || echo "")
    local spec_fail_reason=""
    if [[ ! -f "$spec_frozen_path" ]]; then
      spec_fail_reason="frozen SPEC file '$spec_frozen_path' is missing (deleted/moved after freeze)"
    else
      local spec_now_hash
      spec_now_hash=$(_acc_hash_file "$algo" "$spec_frozen_path" 2>/dev/null || echo "")
      if [[ -z "$spec_now_hash" ]] || [[ "$spec_now_hash" != "$spec_frozen_hash" ]]; then
        spec_fail_reason="SPEC ('$spec_frozen_path') was modified after freeze"
      fi
    fi
    if [[ -n "$spec_fail_reason" ]]; then
      echo "[acceptance-gate] FAIL: $spec_fail_reason"
      echo "  스펙 변경은 사용자 승인 없이는 불가합니다 (Step 2-1.9)."
      echo "  Remedy: SPEC을 동결 시점 내용으로 되돌리거나, 사용자 승인(AskUserQuestion) 후"
      echo "          acceptance-unlock --approved-by-user --reason ... 로 열고 수정한 뒤"
      echo "          acceptance-freeze --approved-by-user 로 재동결하세요."
      _ag_record "fail" 0 0 0 "$spec_fail_reason" "$(jq -cn --arg p "$spec_frozen_path" '[$p]')"
      append_gate_history "acceptance-gate" "fail" "$(jq -n --arg p "$spec_frozen_path" '{reason:"spec tampered",spec:$p}')"
      echo "=== ACCEPTANCE GATE: FAIL ==="
      return 1
    fi
    echo "[acceptance-gate] SPEC integrity OK ($spec_frozen_path)"
  else
    echo "[acceptance-gate] NOTE: manifest has no frozen SPEC (pre-4.8 freeze) — SPEC 대조 skip"
  fi

  # 4. 러너 실행 — 1회 자동 재시도 (v4.18.0)
  # 왜: flaky 1건(포트 경합·기동 타이밍 등)이 FAIL 로 굳으면 stop-hook 이 루프를 계속 돌려
  # iteration 예산을 소진시킨다. 재시도 1회로 비결정성을 배제하되, 2회째 green 이면
  # 조용히 통과시키지 않고 flaky=true + firstRun 을 남긴다 (문제를 숨기지 않는다).
  # 무결성 tamper 는 재시도 대상이 아니다 (위에서 이미 return — 재실행해도 결과가 같다).
  # green 세탁 방지 (M2): 외부 URL 조향 env를 제거하고 실행 — 테스트가 목 서버로
  # 우회되지 않도록. 러너는 서버 기동/포트를 자체 통제해야 한다 (acceptance-tests-guide 참조).
  local AG_OUT="" AG_EC=0 AG_TOTAL=0 AG_PASSED=0 AG_FAILED=0 AG_PARSED="false" AG_REASON=""

  _ag_run_once() {
    AG_OUT=""; AG_EC=0; AG_TOTAL=0; AG_PASSED=0; AG_FAILED=0; AG_PARSED="false"
    AG_OUT=$(env -u BASE_URL -u API_URL -u API_BASE_URL -u APP_URL -u SERVER_URL -u TEST_BASE_URL \
      bash "$ACCEPTANCE_RUNNER" 2>&1) && AG_EC=0 || AG_EC=$?
    echo "$AG_OUT" | tail -15

    # ACCEPTANCE_RESULT 라인 파싱 (마지막 매치 채택)
    local result_line
    result_line=$(printf '%s\n' "$AG_OUT" | grep -E '^ACCEPTANCE_RESULT: *total=[0-9]+ +passed=[0-9]+ +failed=[0-9]+' | tail -1 || true)
    if [[ -n "$result_line" ]]; then
      AG_TOTAL=$(echo "$result_line" | sed -E 's/.*total=([0-9]+).*/\1/')
      AG_PASSED=$(echo "$result_line" | sed -E 's/.*passed=([0-9]+).*/\1/')
      AG_FAILED=$(echo "$result_line" | sed -E 's/.*failed=([0-9]+).*/\1/')
      if [[ "$AG_TOTAL" =~ ^[0-9]+$ ]] && [[ "$AG_PASSED" =~ ^[0-9]+$ ]] && [[ "$AG_FAILED" =~ ^[0-9]+$ ]]; then
        AG_PARSED="true"
      else
        AG_TOTAL=0; AG_PASSED=0; AG_FAILED=0
      fi
    fi
  }

  # 판정: exit 0 + RESULT 라인 파싱 성공 + total>0 + failed=0 + passed==total 일 때만 pass (fail-closed).
  # 테스트가 실제로 돌았는지 강제 (H2): total=0(스텁 러너) / total>passed(일부 error로 미실행) 차단.
  _ag_eval() {
    AG_REASON=""
    if [[ "$AG_PARSED" != "true" ]]; then
      AG_REASON="runner did not print ACCEPTANCE_RESULT (runner contract violation; exit=$AG_EC)"
      return 1
    fi
    if [[ "$AG_TOTAL" -eq 0 ]]; then
      AG_REASON="no acceptance tests discovered (total=0) — runner ran zero tests"
      return 1
    fi
    if [[ "$AG_FAILED" -gt 0 ]]; then
      AG_REASON="$AG_FAILED acceptance test(s) failed"
      return 1
    fi
    if [[ "$AG_PASSED" -ne "$AG_TOTAL" ]]; then
      AG_REASON="passed<total (total=$AG_TOTAL passed=$AG_PASSED) — some tests did not pass (errored?)"
      return 1
    fi
    if [[ "$AG_EC" -ne 0 ]]; then
      AG_REASON="runner exited non-zero ($AG_EC)"
      return 1
    fi
    return 0
  }

  echo "[acceptance-gate] Running: bash $ACCEPTANCE_RUNNER (BASE_URL/API_URL 계열 env 무시) [attempt 1/2]"
  _ag_run_once
  echo "[acceptance-gate] Result: total=$AG_TOTAL passed=$AG_PASSED failed=$AG_FAILED (exit=$AG_EC)"

  local flaky_extra="null"
  if ! _ag_eval; then
    local first_reason="$AG_REASON" first_run_json
    first_run_json=$(jq -cn --argjson t "$AG_TOTAL" --argjson p "$AG_PASSED" --argjson f "$AG_FAILED" \
      --argjson ec "$AG_EC" --arg r "$first_reason" \
      '{total:$t,passed:$p,failed:$f,exitCode:$ec,reason:$r}')
    echo "[acceptance-gate] WARNING: attempt 1 failed ($first_reason) — retrying once to rule out flakiness" >&2
    echo "[acceptance-gate] Running: bash $ACCEPTANCE_RUNNER [attempt 2/2]"
    _ag_run_once
    echo "[acceptance-gate] Result: total=$AG_TOTAL passed=$AG_PASSED failed=$AG_FAILED (exit=$AG_EC)"

    if _ag_eval; then
      # 2회째 green → soft_fail 로 기록한다 (pass 아님). 재시도의 목적은 "1회 실패가 환경 노이즈인지
      # 테스트 결함인지"를 분리하는 것이지 green 을 만들어 주는 것이 아니다. stop-hook 은
      # acceptanceTests=pass 만 허용하므로 이 기록은 완주를 차단하고, 비결정성을 제거한 뒤
      # 게이트를 재실행해 1회차에 green 이 나야 pass 가 된다 (읽는 게이트 없는 flaky:true 표식이
      # 조용한 통과가 되던 공백 봉쇄).
      flaky_extra=$(jq -cn --argjson fr "$first_run_json" '{flaky:true, firstRun:$fr}')
      echo "[acceptance-gate] FLAKY: attempt 1 failed but attempt 2 passed — 인수 테스트가 비결정적이다 (soft_fail)"
      echo "  first run: $first_reason"
      echo "  시간·순서·포트 의존을 제거하고 acceptance-gate 를 재실행하라. 1회차 green 이어야 pass 로 기록된다."
      _ag_record "soft_fail" "$AG_TOTAL" "$AG_PASSED" "$AG_FAILED" "flaky: attempt 1 failed ($first_reason), attempt 2 passed — non-deterministic acceptance tests" "null" "$flaky_extra"
      append_gate_history "acceptance-gate" "soft_fail" \
        "$(jq -cn --argjson t "$AG_TOTAL" --argjson p "$AG_PASSED" --argjson fr "$first_run_json" \
            '{total:$t,passed:$p,failed:0,flaky:true,firstRun:$fr}')"
      log_event "acceptance.flaky" "$(jq -cn --argjson fr "$first_run_json" '{firstRun:$fr}' 2>/dev/null || echo "{}")" || true
      echo "=== ACCEPTANCE GATE: SOFT_FAIL (flaky) ==="
      return 1
    else
      echo "[acceptance-gate] FAIL: $AG_REASON (2회 연속 실패 — flaky 아님)"
      _ag_record "fail" "$AG_TOTAL" "$AG_PASSED" "$AG_FAILED" "$AG_REASON" "null" \
        "$(jq -cn --argjson fr "$first_run_json" '{retried:true, firstRun:$fr}')"
      append_gate_history "acceptance-gate" "fail" \
        "$(jq -cn --argjson t "$AG_TOTAL" --argjson p "$AG_PASSED" --argjson f "$AG_FAILED" \
            --argjson ec "$AG_EC" --arg r "$AG_REASON" \
            '{total:$t,passed:$p,failed:$f,exitCode:$ec,reason:$r,retried:true}')"
      echo "=== ACCEPTANCE GATE: FAIL ==="
      return 1
    fi
  fi

  # 여기 도달 = 1회차 green (재시도 없음). extra: addedFiles(WARN)
  _ag_record "pass" "$AG_TOTAL" "$AG_PASSED" "$AG_FAILED" "" "null" "$extra_json"
  append_gate_history "acceptance-gate" "pass" \
    "$(jq -cn --argjson t "$AG_TOTAL" --argjson p "$AG_PASSED" --argjson a "$added_json" \
        '{total:$t,passed:$p,failed:0,addedFiles:$a}')"

  # 5. DoD 갱신: dod.acceptance_pass는 이 게이트가 유일한 기록자 (모델 직접 세팅 금지)
  if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "$PROGRESS_FILE" ]]; then
    jq_inplace "$PROGRESS_FILE" --arg ev "acceptance-gate PASS at $(timestamp) (total=$AG_TOTAL passed=$AG_PASSED failed=0)" '
      if (.dod | has("acceptance_pass")) then
        .dod.acceptance_pass = {checked: true, evidence: $ev}
      else . end'
  fi

  echo "=== ACCEPTANCE GATE: PASS ==="
  return 0
}
