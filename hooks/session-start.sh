#!/usr/bin/env bash
# SessionStart - Ralph Loop 자동 복구
# 세션 시작 시 progress 파일이 있으면 recover 정보를 컨텍스트에 주입
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_GATE="${PLUGIN_ROOT}/scripts/shared-gate.sh"

# shared-gate.sh 존재 확인
if [[ ! -f "$SHARED_GATE" ]]; then
  exit 0
fi

# 고아 .tmp 정리 — atomic write 중간 산물은 절대 재개 정보가 아님, 무조건 삭제
# (jq_inplace는 mktemp를 쓰지만 과거 버전이나 외부 도구가 남긴 잔재를 청소)
for _orphan in .claude-*-progress.json.tmp .claude-*.tmp; do
  if [[ -f "$_orphan" ]]; then
    rm -f "$_orphan"
  fi
done

# ─── Lesson 주입: 기억은 저장이 아니라 다음 실행 조건 ───
# stop-hook.sh(3-strike/완주)와 errors.sh(에스컬레이션)가 기록한 LESSON 중
# 최근 5개(tail 기준)를 세션 시작 컨텍스트로 주입한다.
# learnings 파일이 없거나 LESSON 항목이 없으면 아무 것도 추가하지 않음 (기존 동작 그대로).
LEARNINGS_FILE=".claude/acl-learnings.local.md"
LESSONS_SECTION=""
if [[ -f "$LEARNINGS_FILE" ]] && grep -q '^## LESSON |' "$LEARNINGS_FILE" 2>/dev/null; then
  # LESSON 블록(헤더 + '- ' 라인)만 수집, 최근 5개만 유지
  # (파일이 커도 tail 5개만 주입 — 파일 자체는 사용자 자산이므로 정리하지 않음)
  LESSONS_BLOCK=$(awk '
    /^## LESSON \|/ { inles=1; n++; buf[n]=$0; next }
    /^## /          { inles=0; next }
    inles && /^- /  { buf[n]=buf[n] "\n" $0 }
    END {
      if (n == 0) exit
      start = (n > 5) ? n - 4 : 1
      for (i = start; i <= n; i++) { print buf[i]; if (i < n) print "" }
    }
  ' "$LEARNINGS_FILE" 2>/dev/null || true)
  if [[ -n "$LESSONS_BLOCK" ]]; then
    LESSONS_SECTION=$(printf '## 과거 실수 — 다음 실행 조건 (acl-learnings)\n이전 세션에서 기록된 교훈. 같은 실수를 반복하지 마라:\n%s\n전체는 .claude/acl-learnings.local.md 참조.' "$LESSONS_BLOCK")
  fi
fi

# ─── 교차 실행 반복 감지 (acl-events.jsonl 소비) ───
# acl-learnings/LESSON과 달리 events는 성공 시에도 유지(append-only)되므로,
# stop-hook의 stuck-pattern(성공 시 failure-history가 초기화되어 교차 실행을 놓침)이
# 못 보는 "여러 실행에 걸친 반복 실패"를 여기서 집계해 다음 세션에 경고로 주입한다.
# 관측 데이터 → 실행 조건 전환: 근본 원인 제거 없이 같은 접근을 반복하지 못하게 한다.
ACL_EVENTS_FILE=".claude/acl-events.jsonl"
CROSSRUN_SECTION=""
if command -v jq &>/dev/null && [[ -f "$ACL_EVENTS_FILE" ]]; then
  # -rs 슬럽: 한 줄이라도 깨지면 전체 실패 → 2>/dev/null||true 로 관측 전용 폴백(무주입)
  CROSSRUN_LINES=$(jq -rs '
    (if length > 200 then .[-200:] else . end) as $ev
    | ( [ $ev[] | select(.event=="error.recorded") | .type // empty ]
        | group_by(.) | map({t:.[0], n:length}) | map(select(.n>=3)) ) as $errs
    | ( [ $ev[] | select(.event=="gate.ambiguity.mismatch") ] | length ) as $mm
    | ( [ $ev[] | select(.event=="escalation.level" and ((.to=="L4") or (.to=="L5"))) ] | length ) as $esc
    | ( [ $errs[] | "반복 오류 [\(.t)] ×\(.n)회 — 근본 원인 미제거 신호" ]
        + (if $mm>0 then ["명확성 세탁(ambiguity mismatch) ×\($mm)회 — 인터뷰 신고가 문서에 미반영"] else [] end)
        + (if $esc>0 then ["심층 에스컬레이션(L4/L5) ×\($esc)회 — 과거 접근이 반복 실패"] else [] end)
      ) | .[]
  ' "$ACL_EVENTS_FILE" 2>/dev/null || true)
  if [[ -n "$CROSSRUN_LINES" ]]; then
    CROSSRUN_SECTION=$(printf '## 교차 실행 반복 경고 (acl-events)\n여러 실행에 걸쳐 반복된 신호다. 같은 접근을 반복하기 전에 근본 원인을 먼저 제거하라:\n%s' \
      "$(printf '%s\n' "$CROSSRUN_LINES" | sed 's/^/- /')")
  fi
fi

# 두 메모리 섹션 병합 — 다운스트림 주입 지점은 LESSONS_SECTION만 참조하므로 여기에 합친다
if [[ -n "$CROSSRUN_SECTION" ]]; then
  if [[ -n "$LESSONS_SECTION" ]]; then
    LESSONS_SECTION=$(printf '%s\n\n%s' "$LESSONS_SECTION" "$CROSSRUN_SECTION")
  else
    LESSONS_SECTION="$CROSSRUN_SECTION"
  fi
fi

# 우리 progress 스키마인지 판별 (타 도구의 .claude-*progress*.json 오탐 방지)
# 실제 템플릿(scripts/gates/init.sh)은 schemaVersion/dod/handoff/documents 중
# 최소 하나를 항상 포함한다. 아니면 우리 파일이 아님 → 건드리지 않는다.
is_our_progress_file() {
  local _f="$1" _ours
  command -v jq &>/dev/null || return 1
  _ours=$(jq 'has("schemaVersion") or has("dod") or has("handoff") or has("documents")' "$_f" 2>/dev/null || echo "false")
  [[ "$_ours" == "true" ]]
}

# progress 파일 탐지 — scripts/lib/progress.sh의 detect_progress_file을 단일 출처로 사용
PROGRESS_FILE=""
if [[ -f "${PLUGIN_ROOT}/scripts/lib/progress.sh" ]]; then
  # shellcheck source=../scripts/lib/progress.sh
  source "${PLUGIN_ROOT}/scripts/lib/progress.sh"
  PROGRESS_FILE=$(detect_progress_file || true)
fi

# 탐지된 파일이 우리 스키마가 아니면 복구 대상에서 제외 (타 도구 파일 오탐 방지)
if [[ -n "$PROGRESS_FILE" ]] && [[ -f "$PROGRESS_FILE" ]] && ! is_our_progress_file "$PROGRESS_FILE"; then
  PROGRESS_FILE=""
fi

# progress 파일 없으면 복구 불필요 — 단, 프로젝트 컨텍스트 주입 (A5)
if [[ -z "$PROGRESS_FILE" ]]; then
  CONTEXT_HINTS=""
  [[ -f ".claude/acl-learnings.local.md" ]] && CONTEXT_HINTS="${CONTEXT_HINTS}\n- .claude/acl-learnings.local.md (이전 워크플로우 학습 내역)"
  [[ -f "overview.md" ]] && CONTEXT_HINTS="${CONTEXT_HINTS}\n- overview.md (프로젝트 정의 문서)"
  for _spec in SPEC.md docs/SPEC.md; do
    [[ -f "$_spec" ]] && { CONTEXT_HINTS="${CONTEXT_HINTS}\n- ${_spec} (기술 사양)"; break; }
  done

  # 출력 조건: 문서 힌트가 있거나(기존), LESSON/교차 실행 경고가 있으면(신규) 주입.
  # 후자 단독 케이스: overview/SPEC/learnings 없이 events만 남은 fresh 세션에서도
  # 교차 실행 반복 경고를 반드시 전달해야 하므로 CONTEXT_HINTS 없이도 emit 한다.
  CTX_MSG=""
  if [[ -n "$CONTEXT_HINTS" ]]; then
    CTX_MSG=$(printf '[Project Context] 이전 작업 컨텍스트가 감지되었습니다. 참고할 문서:%b' "$CONTEXT_HINTS")
  fi
  if [[ -n "$LESSONS_SECTION" ]]; then
    if [[ -n "$CTX_MSG" ]]; then
      CTX_MSG=$(printf '%s\n\n%s' "$CTX_MSG" "$LESSONS_SECTION")
    else
      CTX_MSG="$LESSONS_SECTION"
    fi
  fi
  if [[ -n "$CTX_MSG" ]]; then
    jq -n --arg ctx "$CTX_MSG" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }'
  fi
  exit 0
fi

# jq 필요
if ! command -v jq &>/dev/null; then
  exit 0
fi

# completed 상태 progress 파일 일괄 정리 (glob 기반 — 신규/구 파일명 모두 커버)
# .claude-*-progress.json: 하이픈 포함 형식 (.claude-full-auto-progress.json 등)
# .claude-progress.json:  하이픈 없는 단독 형식 (glob *-가 빈 문자열 매치 못 하므로 별도 명시)
# 동시에 active(in_progress) 존재 여부 추적 → verification.json 보존 판단
HAS_ACTIVE=0
for f in .claude-*-progress.json .claude-progress.json; do
  [[ -f "$f" ]] || continue
  # 타 도구가 만든 동명 패턴 파일은 삭제/정리 대상이 아님 — 스키마 검증 후 아니면 skip
  if ! is_our_progress_file "$f"; then
    continue
  fi
  _status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null || echo "unknown")
  case "$_status" in
    completed) rm -f "$f" ;;
    in_progress) HAS_ACTIVE=1 ;;
    *) echo "WARN: $f has unrecognized status='$_status' — leaving in place for manual inspection" >&2 ;;
  esac
done

# 첫 매치였던 PROGRESS_FILE도 위 루프에서 처리되었으므로 다시 상태 확인
if [[ ! -f "$PROGRESS_FILE" ]]; then
  # PROGRESS_FILE이 completed로 정리되었음
  if [[ "$HAS_ACTIVE" -eq 0 ]]; then
    rm -f ".claude-verification.json"
  fi
  # 복구할 진행 건은 없지만 LESSON이 있으면 실행 조건으로 주입
  if [[ -n "$LESSONS_SECTION" ]]; then
    jq -n --arg ctx "$LESSONS_SECTION" '{
      "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": $ctx
      }
    }'
  fi
  exit 0
fi

# recover 실행하여 컨텍스트 수집
RECOVER_STDERR=$(mktemp 2>/dev/null || echo "/tmp/acl-recover-$$")
RECOVER_OUTPUT=$(bash "$SHARED_GATE" recover --progress-file "$PROGRESS_FILE" 2>"$RECOVER_STDERR" || true)
if [[ -s "$RECOVER_STDERR" ]]; then
  RECOVER_OUTPUT="${RECOVER_OUTPUT}\n[recover warning] $(head -3 "$RECOVER_STDERR")"
fi
rm -f "$RECOVER_STDERR"

if [[ -z "$RECOVER_OUTPUT" ]]; then
  exit 0
fi

# Ralph Loop 상태 파일 확인
HAS_RALPH=false
[[ -f ".claude/ralph-loop.local.md" ]] && HAS_RALPH=true

# 모든 동적 값을 jq로 안전하게 JSON 생성
RALPH_RAW=""
if [[ "$HAS_RALPH" == "true" ]]; then
  # RALPH_INFO는 \\n prefix가 포함된 문자열이므로 실제 개행으로 변환
  RALPH_RAW=$(printf '\n[Ralph Loop] iteration=%s/%s, promise=%s' \
    "$(sed -n 's/^iteration: *\([0-9]*\)/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")" \
    "$(sed -n 's/^max_iterations: *\([0-9]*\)/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")" \
    "$(sed -n 's/^completion_promise: *"\(.*\)"/\1/p' ".claude/ralph-loop.local.md" 2>/dev/null || echo "?")")
fi

ACTION_LINE=$(printf '\n\n[Action] Read %s → handoff.nextSteps 확인 → 이어서 진행' "$PROGRESS_FILE")

FULL_CONTEXT=$(printf '[Auto-Recovery] 진행 중인 작업이 감지되었습니다. progress 파일을 먼저 읽고 handoff.nextSteps를 따르세요.\n\n%s%s%s' \
  "$RECOVER_OUTPUT" "$RALPH_RAW" "$ACTION_LINE")

# 최근 LESSON을 복구 컨텍스트에 병합 (기존 JSON 출력 구조는 그대로 — 문자열에만 병합)
if [[ -n "$LESSONS_SECTION" ]]; then
  FULL_CONTEXT=$(printf '%s\n\n%s' "$FULL_CONTEXT" "$LESSONS_SECTION")
fi

# jq로 안전하게 JSON 생성 (모든 특수문자 자동 이스케이프)
jq -n --arg ctx "$FULL_CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
