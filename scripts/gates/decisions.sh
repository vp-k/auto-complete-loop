# gates/decisions.sh — 결정 기록 단일 출처 (record-decision / assumption-review)
#
# 철학: "이유 없는 결정은 잘못된 결정이다."
# 어떤 채널(ADR·provenance 마커·CLARIFICATIONS·severityAdjustments·인라인 판단)로 내려진
# 결정이든, 그 사실 자체는 append-only 로그 한 곳(.claude/acl-decisions.jsonl)에 모인다.
# 판정(이유 유무·iteration별 기록 존재)은 스크립트와 stop-hook이 결정론적으로 하고,
# 모델은 what/why/alternatives를 채우기만 한다.

DECISIONS_FILE=".claude/acl-decisions.jsonl"

# --why 최소 길이 (공백 제거 후 문자 수). 이 아래는 사유로 인정하지 않는다.
DECISION_WHY_MIN_LEN=10

# 락 디렉토리를 스테일로 간주하는 경과 시간(초). 이보다 오래된 락은 회수하고 재획득한다.
DECISION_LOCK_STALE_SEC=30

# 락 획득 대기 틱 수(1틱 = 0.1s). 50 틱 = 최대 5초 대기 후 fail-closed.
DECISION_LOCK_WAIT_TICKS=50

# 유니코드 문자 수 계산 (bash ${#var}는 로케일에 따라 바이트를 셀 수 있어 jq로 결정론화)
_decision_charlen() {
  printf '%s' "$1" | jq -Rs 'length' 2>/dev/null || echo 0
}

# 현재 iteration 추정: ralph-loop frontmatter > progress.handoff.lastIteration > 0
# stop-hook이 frontmatter의 iteration을 기준으로 검사하므로 같은 출처를 우선한다.
_decision_default_iteration() {
  local it
  it=$(ralph_current_iteration)
  if [[ ! "$it" =~ ^[0-9]+$ ]] && [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "${PROGRESS_FILE:-}" ]]; then
    it=$(jq -r '.handoff.lastIteration // empty' "$PROGRESS_FILE" 2>/dev/null || true)
  fi
  [[ "$it" =~ ^[0-9]+$ ]] || it=0
  printf '%s' "$it"
}

# 현재 실행 식별자(runId) — progress 파일의 runId가 유일한 출처.
# init이 실행마다 새로 발급하므로 결정 레코드에 함께 박으면, 이전 실행이 남긴 기록이
# 다음 실행의 "이번 iteration 결정 있음" 검사를 대신 통과시키는 일이 불가능해진다.
# v4.20 이하 progress에는 키가 없어 빈 문자열 → iteration만 보는 하위호환 경로.
_decision_current_run_id() {
  local pf="${PROGRESS_FILE:-}" rid=""
  if [[ -z "$pf" ]] || [[ ! -f "$pf" ]]; then
    pf=$(detect_progress_file 2>/dev/null || true)
  fi
  if [[ -n "$pf" ]] && [[ -f "$pf" ]]; then
    rid=$(jq -r '.runId // empty' "$pf" 2>/dev/null || true)
  fi
  printf '%s' "$rid"
}

_decision_default_phase() {
  local ph=""
  if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "${PROGRESS_FILE:-}" ]]; then
    ph=$(jq -r '.currentPhase // .currentStep // empty' "$PROGRESS_FILE" 2>/dev/null || true)
  fi
  printf '%s' "$ph"
}

# 로그의 유효 레코드 수 (id 채번 기준 — 파싱 불가 시 라인 수로 폴백)
_decision_count() {
  [[ -f "$DECISIONS_FILE" ]] || { echo 0; return 0; }
  local n
  n=$(jq -s 'length' "$DECISIONS_FILE" 2>/dev/null || true)
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    # jq 파싱 실패 폴백: 레코드는 항상 1줄 1 JSON 객체이므로 '{'로 시작하는 줄만 센다
    # (wc -l은 파일 끝 개행 유무·빈 줄까지 세어 실제 레코드 수와 어긋나고, id 채번이 충돌한다)
    n=$(grep -c '^{' "$DECISIONS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  echo "$n"
}

# --supersedes 대상 검증 (v4.26.0). 문제가 있으면 오류 문구를, 없으면 빈 문자열을 출력한다.
# 락을 쥔 뒤에 호출한다: 검사와 append 사이에 다른 프로세스가 같은 결정을 먼저 뒤집는 경합을 막는다.
# 로그를 파싱하지 못하면 대상을 확인할 수 없으므로 오류로 본다(fail-closed).
_decision_supersede_error() {
  local target="$1" msg
  if [[ ! -f "$DECISIONS_FILE" ]]; then
    printf '%s' "--supersedes $target: 결정 로그에 없는 id다. record-decision --list --all로 확인하라."
    return 0
  fi
  # 같은 결정을 두 번 뒤집으면 어느 쪽이 유효한지 갈라지므로 막고, 체인의 현재 결정을 알려준다.
  # 체인 추적은 깊이 상한을 둔다 (로그는 쓰기 가드로 보호되지만 손상된 로그에서 무한 재귀하지 않게).
  if ! msg=$(jq -rn --arg t "$target" '
      [inputs] as $all
      | def succ($i): ($all | map(select(.supersedes == $i)) | .[0].id);
        def latest($i; $d): succ($i) as $n | if $n == null or $d > 1000 then $i else latest($n; $d + 1) end;
      ($all | map(select(.id == $t))) as $hit
      | if ($hit | length) == 0 then
          "--supersedes \($t): 결정 로그에 없는 id다. record-decision --list --all로 확인하라."
        elif ($hit[0].kind // "decision") != "decision" then
          "--supersedes \($t): kind=none 레코드는 결정이 아니므로 뒤집을 대상이 아니다."
        elif succ($t) != null then
          "--supersedes \($t): 이미 \(succ($t))가 뒤집은 결정이다. 지금 유효한 결정은 \(latest($t; 0))다. 그 id를 --supersedes로 지정하라."
        else "" end' "$DECISIONS_FILE" 2>/dev/null); then
    printf '%s' "--supersedes $target: 결정 로그($DECISIONS_FILE)를 읽지 못해 대상을 확인할 수 없다."
    return 0
  fi
  printf '%s' "$msg"
}

# want_run: 현재 실행으로 좁힐 runId. 빈 문자열이면 전체(하위호환·--all).
# 뒤집힘 표시는 필터 전에 전체 로그에서 만든다 — --last나 runId로 잘라도 옛 결정의 표시가 사라지지 않게.
_decision_list() {
  local want_iter="${1:-}" want_last="${2:-}" want_run="${3:-}"
  if [[ ! -f "$DECISIONS_FILE" ]]; then
    echo "결정 기록 없음 ($DECISIONS_FILE)"
    return 0
  fi
  local filter='[inputs] as $all | ($all | map(select(.supersedes != null) | {key: .supersedes, value: .id}) | from_entries) as $sup | $all'
  if [[ -n "$want_run" ]]; then
    filter="$filter | map(select(.runId == $(jq -Rn --arg v "$want_run" '$v')))"
  fi
  if [[ -n "$want_iter" ]]; then
    [[ "$want_iter" =~ ^[0-9]+$ ]] || die "--iteration must be a non-negative integer, got '$want_iter'"
    filter="$filter | map(select(.iteration == $want_iter))"
  fi
  if [[ -n "$want_last" ]]; then
    [[ "$want_last" =~ ^[0-9]+$ ]] || die "--last must be a non-negative integer, got '$want_last'"
    filter="$filter | .[-${want_last}:]"
  fi
  filter="$filter"' | .[] | "\(.id)\(if $sup[.id // ""] then " [superseded by \($sup[.id // ""])]" else "" end)\(if .supersedes then " (supersedes \(.supersedes))" else "" end) [it=\(.iteration) \(.scope)/\(.source) rev=\(.reversible)] \(.what) — \(.why)"'
  jq -rn "$filter" "$DECISIONS_FILE" 2>/dev/null || true
  return 0
}

# ─── record-decision: 결정 1건 기록 (append-only) ───

cmd_record_decision() {
  require_jq

  local what="" why="" reversible="yes" scope="other" src="inline"
  local phase="" iteration="" kind="decision" supersedes=""
  local alternatives=()
  local list_mode="false" list_iteration="" list_last="" list_all="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)         list_mode="true"; shift ;;
      --all)          list_all="true"; shift ;;
      --last)         list_last="${2:?--last requires value}"; shift 2 ;;
      --none)         kind="none"; shift ;;
      --what)         what="${2:?--what requires value}"; shift 2 ;;
      --why)          why="${2:?--why requires value}"; shift 2 ;;
      --alternatives) alternatives+=("${2:?--alternatives requires value}"); shift 2 ;;
      --reversible)   reversible="${2:?--reversible requires value}"; shift 2 ;;
      --scope)        scope="${2:?--scope requires value}"; shift 2 ;;
      --source)       src="${2:?--source requires value}"; shift 2 ;;
      --phase)        phase="${2:?--phase requires value}"; shift 2 ;;
      --iteration)    iteration="${2:?--iteration requires value}"; list_iteration="$2"; shift 2 ;;
      --supersedes)   supersedes="${2:?--supersedes requires value}"; shift 2 ;;
      *) die "Unknown option: $1. Usage: record-decision --what <s> --why <s> [--alternatives <s>]... [--reversible yes|no] [--scope <s>] [--source <s>] [--phase <p>] [--iteration <n>] [--supersedes D-NNNN] | --none --why <s> | --list [--iteration N] [--last N] [--all]" ;;
    esac
  done

  if [[ "$list_mode" == "true" ]]; then
    # 기본은 현재 실행(runId)만 — 이전 실행의 결정을 이번 실행의 근거로 착각하지 않게 한다.
    # --all로 전체 이력을 본다. runId가 없는 progress(v4.20 이하)면 자동으로 전체.
    local list_run=""
    [[ "$list_all" == "true" ]] || list_run=$(_decision_current_run_id)
    _decision_list "$list_iteration" "$list_last" "$list_run"
    return 0
  fi

  # ── 값 검증 (fail-closed) ──
  if [[ "$kind" == "decision" ]]; then
    [[ -n "$what" ]] || die "record-decision requires --what (결정 내용). 결정이 없는 iteration이면 --none --why '<이유>'를 사용하라."
  else
    [[ -n "$what" ]] || what="(이번 iteration에 기록할 결정 없음)"
  fi
  # --supersedes: 형식은 여기서, 대상 존재·중복은 락을 쥔 뒤 로그로 확인한다.
  if [[ -n "$supersedes" ]]; then
    [[ "$kind" == "decision" ]] || die "--supersedes는 --none과 함께 쓸 수 없다. 결정을 뒤집었다면 그것도 결정이므로 --what으로 기록하라."
    [[ "$supersedes" =~ ^D-[0-9]{4,}$ ]] || die "--supersedes must be a decision id (D-NNNN), got '$supersedes'"
  fi

  local why_stripped why_len
  why_stripped=$(printf '%s' "$why" | tr -d '[:space:]')
  why_len=$(_decision_charlen "$why_stripped")
  [[ "$why_len" =~ ^[0-9]+$ ]] || why_len=0
  if (( why_len < DECISION_WHY_MIN_LEN )); then
    echo "ERROR: 이유 없는 결정은 기록할 수 없다 — --why는 공백 제외 ${DECISION_WHY_MIN_LEN}자 이상이어야 한다 (현재 ${why_len}자)." >&2
    echo "  왜 이 선택인가·무엇과 비교했는가를 그대로 적어라. '필요해서', 'OK' 같은 표현은 사유가 아니다." >&2
    exit 1
  fi

  case "$reversible" in
    yes|no) ;;
    *) die "--reversible must be yes|no, got '$reversible'" ;;
  esac
  case "$scope" in
    interview|planning|implementation|review|escalation|other) ;;
    *) die "--scope must be one of: interview|planning|implementation|review|escalation|other (got '$scope')" ;;
  esac
  case "$src" in
    adr|provenance|clarification|severity|scope-reduction|inline) ;;
    *) die "--source must be one of: adr|provenance|clarification|severity|scope-reduction|inline (got '$src')" ;;
  esac
  if [[ -n "$iteration" ]] && [[ ! "$iteration" =~ ^[0-9]+$ ]]; then
    die "--iteration must be a non-negative integer, got '$iteration'"
  fi

  [[ -n "$iteration" ]] || iteration=$(_decision_default_iteration)
  [[ -n "$phase" ]] || phase=$(_decision_default_phase)
  local run_id
  run_id=$(_decision_current_run_id)

  # ── 원자적 append (id 채번 경합 방지: mkdir 스핀락) ──
  mkdir -p .claude 2>/dev/null || die "cannot create .claude directory"
  local lockdir="${DECISIONS_FILE}.lock.d" lockmeta="${DECISIONS_FILE}.lock.d/owner"
  local locked="false" i _lk_pid _lk_ts _now
  for ((i = 0; i < DECISION_LOCK_WAIT_TICKS; i++)); do
    if mkdir "$lockdir" 2>/dev/null; then
      locked="true"
      printf '%s %s\n' "$$" "$(date -u '+%s' 2>/dev/null || echo 0)" > "$lockmeta" 2>/dev/null || true
      break
    fi
    # 스테일 락 회수 — 죽은 프로세스가 남긴 디렉토리가 영구히 락을 막지 않게 한다.
    # (기존에는 2초 뒤 무조건 lock 없이 append로 넘어가 id 채번 경합이 그대로 열려 있었다)
    _lk_pid=""; _lk_ts=""
    if [[ -f "$lockmeta" ]]; then
      read -r _lk_pid _lk_ts < "$lockmeta" 2>/dev/null || true
    fi
    [[ "$_lk_ts" =~ ^[0-9]+$ ]] || _lk_ts=0
    if (( _lk_ts == 0 )); then
      # owner 메타가 아직 없다 — 죽은 락이 아니라 다른 프로세스가 mkdir 직후 메타를 쓰기 전인
      # 찰나일 수 있다(그때 회수하면 둘 다 락을 쥐고 id 채번이 충돌한다). 디렉토리 mtime으로
      # 나이를 재고, 그것도 못 얻으면 회수하지 않고 기다린다(fail-closed).
      _lk_ts=$(stat -c %Y "$lockdir" 2>/dev/null || stat -f %m "$lockdir" 2>/dev/null || echo 0)
      [[ "$_lk_ts" =~ ^[0-9]+$ ]] || _lk_ts=0
    fi
    _now=$(date -u '+%s' 2>/dev/null || echo 0)
    if [[ -d "$lockdir" ]] && (( _lk_ts > 0 && _now > 0 && _now - _lk_ts > DECISION_LOCK_STALE_SEC )); then
      echo "WARNING: record-decision: stale lock 회수 (pid=${_lk_pid:-unknown}, age>${DECISION_LOCK_STALE_SEC}s)" >&2
      rm -f "$lockmeta" 2>/dev/null || true
      rmdir "$lockdir" 2>/dev/null || true
      continue
    fi
    sleep 0.1
  done
  # fail-closed: 락을 못 잡으면 D-NNNN 채번이 경합하므로 기록하지 않고 종료한다.
  # (기존에는 경고만 남기고 무락 append 해서 동일 번호 중복이 가능했다)
  if [[ "$locked" != "true" ]]; then
    die "record-decision: lock busy for $DECISIONS_FILE (waited $((DECISION_LOCK_WAIT_TICKS / 10))s) — 기록하지 않았다. 다른 프로세스의 record-decision이 끝나기를 기다려 재시도하라. 멈춘 프로세스가 남긴 락이면 ${DECISION_LOCK_STALE_SEC}s 후 자동 회수된다."
  fi

  if [[ -n "$supersedes" ]]; then
    local sup_err
    sup_err=$(_decision_supersede_error "$supersedes")
    if [[ -n "$sup_err" ]]; then
      rm -f "$lockmeta" 2>/dev/null || true
      rmdir "$lockdir" 2>/dev/null || true
      die "$sup_err 기록하지 않았다."
    fi
  fi

  local next_num id line
  next_num=$(_decision_count)
  next_num=$((next_num + 1))
  id=$(printf 'D-%04d' "$next_num")

  local alt_json
  if ((${#alternatives[@]} > 0)); then
    alt_json=$(printf '%s\n' "${alternatives[@]}" | jq -Rn '[inputs]')
  else
    alt_json='[]'
  fi

  if line=$(jq -cn \
      --arg id "$id" --arg ts "$(timestamp)" --arg phase "$phase" \
      --argjson iteration "$iteration" --arg kind "$kind" \
      --arg what "$what" --arg why "$why" --argjson alternatives "$alt_json" \
      --arg reversible "$reversible" --arg scope "$scope" --arg source "$src" \
      --arg runId "$run_id" --arg sup "$supersedes" \
      '{id:$id, ts:$ts, runId:$runId, phase:$phase, iteration:$iteration, kind:$kind, what:$what, why:$why, alternatives:$alternatives, reversible:$reversible, scope:$scope, source:$source}
       + (if $sup == "" then {} else {supersedes:$sup} end)' 2>/dev/null); then
    printf '%s\n' "$line" >> "$DECISIONS_FILE"
  else
    [[ "$locked" == "true" ]] && { rm -f "$lockmeta" 2>/dev/null; rmdir "$lockdir" 2>/dev/null; }
    die "failed to build decision record JSON"
  fi
  [[ "$locked" == "true" ]] && { rm -f "$lockmeta" 2>/dev/null; rmdir "$lockdir" 2>/dev/null; }

  # ── 관측 이벤트 (베스트에포트) ──
  log_event "decision.recorded" "$(jq -cn --arg id "$id" --arg scope "$scope" --arg kind "$kind" \
    --argjson iteration "$iteration" --arg sup "$supersedes" \
    '{id:$id, scope:$scope, kind:$kind, iteration:$iteration} + (if $sup == "" then {} else {supersedes:$sup} end)')" 2>/dev/null || true

  # ── progress.handoff.keyDecisions 미러 (append, kind=none은 제외) ──
  # 뒤집은 결정이면 옛 항목 앞에 표시를 붙인다. handoff만 읽는 다음 iteration이 죽은 결정을 따르지 않게.
  if [[ -n "${PROGRESS_FILE:-}" ]] && [[ -f "${PROGRESS_FILE:-}" ]]; then
    if [[ "$kind" == "decision" ]] && [[ -n "$supersedes" ]]; then
      jq_inplace "$PROGRESS_FILE" --arg entry "$id: $what — $why [supersedes $supersedes]" \
        --arg t "$supersedes" --arg id "$id" \
        '.handoff //= {}
         | .handoff.keyDecisions = (((.handoff.keyDecisions // [])
             | map(if (type == "string" and startswith($t + ": ")) then "[superseded by \($id)] " + . else . end))
             + [$entry])'
    elif [[ "$kind" == "decision" ]]; then
      jq_inplace "$PROGRESS_FILE" --arg entry "$id: $what — $why" \
        '.handoff //= {} | .handoff.keyDecisions = ((.handoff.keyDecisions // []) + [$entry])'
    fi
  else
    echo "WARNING: progress 파일이 없어 handoff.keyDecisions 미러를 건너뛴다 (결정 로그와 이벤트에는 기록됨)." >&2
  fi

  echo "✅ 결정 기록: $id [scope=$scope source=$src reversible=$reversible iteration=$iteration${supersedes:+ supersedes=$supersedes}]"
  echo "   what: $what"
  echo "   why : $why"
  return 0
}

# ─── assumption-review: 착수 전 assumption 일괄 확인 결과 기록 ───
# pm-planning Step 0-0.6이 모델이 채택한 safe assumption을 표로 한 번에 보여주고
# 승인/수정받은 뒤 호출한다. stop-hook(full-auto·plan-docs-full)이
# progress.assumptionReview.status 존재를 fail-closed로 요구한다 (키 부재 = 단계 통째 스킵).

cmd_assumption_review() {
  require_jq
  require_progress

  local status="" count="" note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="${2:?--status requires value}"; shift 2 ;;
      --count)  count="${2:?--count requires value}"; shift 2 ;;
      --note)   note="${2:?--note requires value}"; shift 2 ;;
      *) die "Unknown option: $1. Usage: assumption-review --status confirmed|none|escalated --count <N> [--note <s>]" ;;
    esac
  done

  case "$status" in
    confirmed|none|escalated) ;;
    *) die "--status must be one of: confirmed|none|escalated (got '${status:-<empty>}')" ;;
  esac
  [[ -n "$count" ]] || count=0
  [[ "$count" =~ ^[0-9]+$ ]] || die "--count must be a non-negative integer, got '$count'"
  if [[ "$status" == "none" ]] && (( count != 0 )); then
    die "--status none은 assumption이 0건일 때만 쓴다 (--count $count). 확인을 받았으면 confirmed를 쓰라."
  fi
  if [[ "$status" == "confirmed" ]] && (( count == 0 )); then
    die "--status confirmed인데 --count 0이다. assumption이 0건이면 --status none을 쓰라."
  fi

  # confirmed는 자기신고가 아니라 기록으로 증명한다 —
  # pm-planning Step 0-0.6은 승인받은 assumption 항목마다 record-decision --scope interview를
  # 남기게 되어 있으므로, 그 건수와 --count가 다르면 "표를 보여주지 않고 숫자만 적은" 경우다.
  if [[ "$status" == "confirmed" ]]; then
    local measured run_id
    run_id=$(_decision_current_run_id)
    measured=0
    if [[ -f "$DECISIONS_FILE" ]]; then
      # 뒤집힌 interview 결정은 빼고 센다 — 사용자가 고친 assumption은 새 결정 1건으로 남는다.
      measured=$(jq -s --arg run "$run_id" \
        '. as $all | ($all | map(.supersedes // empty)) as $gone
         | [$all[] | select(.scope == "interview" and .kind == "decision")
              | select($run == "" or (.runId // "") == $run)
              | select(.id as $i | ($gone | index($i)) == null)] | length' \
        "$DECISIONS_FILE" 2>/dev/null || echo 0)
    fi
    [[ "$measured" =~ ^[0-9]+$ ]] || measured=0
    if (( measured != count )); then
      echo "ERROR: assumption-review --count $count 와 실제 결정 기록 ${measured}건이 다르다 (scope=interview${run_id:+, runId=$run_id})." >&2
      echo "  승인받은 assumption 항목마다 'record-decision --scope interview --source provenance --what ... --why ...'를" >&2
      echo "  먼저 남긴 뒤, 그 건수와 같은 값으로 --count를 적어라 (자기신고 숫자는 증거가 아니다)." >&2
      echo "  현재 기록 조회: bash scripts/shared-gate.sh record-decision --list" >&2
      exit 1
    fi
    echo "   교차 검증: scope=interview 결정 기록 ${measured}건 = --count $count"
  fi

  jq_inplace "$PROGRESS_FILE" --arg s "$status" --argjson c "$count" --arg ts "$(timestamp)" --arg n "$note" \
    '.assumptionReview = {status: $s, count: $c, confirmedAt: $ts, note: $n}'

  log_event "assumption.review" "$(jq -cn --arg s "$status" --argjson c "$count" '{status:$s, count:$c}')" 2>/dev/null || true

  echo "✅ assumptionReview: status=$status count=$count"
  return 0
}
