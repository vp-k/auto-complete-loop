#!/usr/bin/env bash
# PreToolUse:Write|Edit - 통합 파일 보호 가드
# 1. 진행 상태 파일 수정 경고 (warn)
# 2. 동결된 인수 테스트 보호 (tests/acceptance/ + .manifest.json 존재 시 block)
# 3. 기획 문서 보호 (full-auto Phase 2+ block)
# 4. CLAUDE.md 보호 (full-auto Phase 2+ block)
#
# 입력: stdin JSON { "tool_input": { "file_path": "..." } }
# 출력: {"decision": "block"|"approve", "reason": "..."} 또는 {"decision": "approve"}

# --- 공통 boilerplate (bash-guards.sh 패턴 준수) ---

set -euo pipefail

# jq 미설치 시 fail-closed
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 파일 보호를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

INPUT=$(cat)

# JSON 파싱 실패 시 fail-closed
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 파일 보호를 검증할 수 없어 차단합니다."}'
  exit 0
}

# 파일 경로가 비어있으면 통과 (도구가 file_path를 사용하지 않는 경우) — 무출력 (권한 판정 유보)
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

FILENAME=$(basename "$FILE_PATH")

# ─── 승인 unlock 토큰 (acceptance-unlock 발급) ───
# 토큰이 존재하면 SPEC.md / tests/acceptance/** 편집을 한시적으로 허용한다.
# 배경: 이 가드가 동결 후 SPEC/인수 테스트를 영구 차단하는 동안, 스킬이 정한 정상 해결
# 절차는 "사용자 승인 → SPEC 갱신 → --approved-by-user 재동결"이었다. 승인을 받아도 고칠
# 도구가 없어 절차 자체가 실행 불가한 모순이 있었다. 토큰은 그 승인의 기계 판독 가능한
# 증거이며, 재동결(acceptance-freeze --approved-by-user)이 토큰을 소비해 문을 닫는다.
# 토큰이 남아 있으면 acceptance-gate 가 FAIL 하고 stop-hook 이 완주를 차단하므로,
# 이 완화는 "열어둔 채 빠져나가기"로 악용될 수 없다. 토큰 파일 자체는 아래 Guard 1 에서
# Edit/Write 하드 차단(Bash 경유는 bash-guards.sh 검사 5)하므로 손으로 위조할 수도 없다.
# overview.md / docs/specs / docs/plans / CLAUDE.md 는 토큰과 무관하게 그대로 차단된다.
ACCEPTANCE_UNLOCK_TOKEN=".claude/acceptance-unlock.json"
UNLOCK_ACTIVE="false"
UNLOCK_REASON=""
if [[ -f "$ACCEPTANCE_UNLOCK_TOKEN" ]]; then
  UNLOCK_ACTIVE="true"
  UNLOCK_REASON=$(jq -r '.reason // ""' "$ACCEPTANCE_UNLOCK_TOKEN" 2>/dev/null || echo "")
fi

# --- Guard 1: 진행 상태/증거 파일 보호 ---
# 신뢰 모델: 훅과 게이트 스크립트가 같은 권한 환경에서 실행되므로 완전 차단은
# 불가능하다. 이 가드는 우발적/1차 시도를 막고, 우회 흔적은 감사 가능하게
# 남기는 목적이다. (Bash 경유 조작은 bash-guards.sh 검사 3이 담당)

# .claude-verification.json: 게이트 스크립트 전용 증거 파일 → 직접 수정 하드 차단
if [[ "$FILENAME" == ".claude-verification.json" ]]; then
  echo '{"decision": "block", "reason": "verification.json은 게이트 스크립트 전용 증거 파일 — 직접 수정 금지. 결과를 바꾸려면 해당 게이트를 재실행하라 (shared-gate.sh <gate>)"}'
  exit 0
fi

# acceptance-unlock.json: acceptance-unlock 서브커맨드 전용 승인 토큰 → 직접 생성/수정 하드 차단
# (토큰을 손으로 만들면 아래 UNLOCK 완화가 사용자 승인 없이 열린다 — 발급은 스크립트만,
#  소비는 acceptance-freeze --approved-by-user 만. Bash 경유는 bash-guards.sh 검사 5가 담당)
if [[ "$FILENAME" == "acceptance-unlock.json" ]]; then
  echo '{"decision": "block", "reason": "acceptance-unlock.json은 승인 토큰 — 직접 생성/수정 금지. 동결 해제는 사용자 승인 후 shared-gate.sh acceptance-unlock --approved-by-user --reason <사유> 로만 발급하고, 재동결(acceptance-freeze --approved-by-user)이 토큰을 소비한다."}'
  exit 0
fi

# ralph-loop.local.md: stop-hook 전용 루프 상태 파일 → 모델 수정 하드 차단
# (실전 검증 실측: 모델이 파일을 재작성/삭제해 최종 락을 우회 — 삭제는 사용자의 탈출구)
if [[ "$FILENAME" == "ralph-loop.local.md" ]]; then
  echo '{"decision": "block", "reason": "Ralph 루프 상태 파일은 stop-hook 전용 — 모델이 수정하면 최종 검증 락을 우회하게 되므로 금지. 생성은 shared-gate.sh init-ralph로만, 강제 종료(삭제)는 AskUserQuestion으로 사용자에게 요청하라."}'
  exit 0
fi

# 경고 경로: decision 없이 systemMessage만 출력 (권한 판정 유보 — approve로 프롬프트 우회 금지)
case "$FILENAME" in
  .claude-quality-baseline.json)
    jq -n --arg m "WARNING: ${FILENAME}을 수정하려 합니다. 이 파일은 품질 게이트 상태를 추적합니다. shared-gate.sh를 통한 정당한 수정인지 확인하세요." '{"systemMessage": $m}'
    exit 0
    ;;
esac

if [[ "$FILENAME" =~ ^\.claude-.*-progress\.json$ ]]; then
  jq -n --arg m "WARNING: ${FILENAME}을 수정하려 합니다. 이 파일은 워크플로우 진행 상태를 추적합니다. shared-gate.sh를 통한 정당한 수정인지 확인하세요." '{"systemMessage": $m}'
  exit 0
fi

# --- Guard 2: 동결된 인수 테스트 보호 (Phase 무관 하드 차단) ---
# tests/acceptance/ 하위(.manifest.json 포함) 파일이 대상이고, 동결 manifest가
# 존재하면 차단. manifest 부재 = 동결 전(Phase 1 생성 중)이므로 허용.
# 의도적으로 워크플로우 활성 여부(progress 파일 존재)와 무관하게 영구 적용된다 —
# 완주 후 유지보수 세션에서도 인수 기준 변경은 승인 재동결 절차를 거쳐야 한다
# (Guards 3&4가 progress 존재를 조건으로 하는 것과 다른 점은 의도된 비대칭).

if [[ "$FILE_PATH" == *"/tests/acceptance/"* ]] || [[ "$FILE_PATH" == "tests/acceptance/"* ]] \
|| [[ "$FILE_PATH" == *"\\tests\\acceptance\\"* ]] || [[ "$FILE_PATH" == "tests\\acceptance\\"* ]]; then
  if [[ -f "tests/acceptance/.manifest.json" ]]; then
    # 타 도구 오탐 방지: 우리 동결 manifest 스키마(hashAlgo + files)인지 검증.
    # 다른 도구가 만든 .manifest.json이면 이 가드는 관여하지 않는다.
    _OURS_MANIFEST=$(jq 'has("hashAlgo") and has("files")' "tests/acceptance/.manifest.json" 2>/dev/null || echo "false")
    if [[ "$_OURS_MANIFEST" == "true" ]]; then
      if [[ "$UNLOCK_ACTIVE" == "true" ]]; then
        # 승인 unlock 중 → 허용. decision 없이 systemMessage만 (권한 판정은 유보)
        jq -n --arg m "UNLOCK 중: 동결된 인수 테스트(${FILENAME}) 편집이 사용자 승인으로 한시 허용되었습니다 (사유: ${UNLOCK_REASON:-미기록}). 수정을 마치면 반드시 'shared-gate.sh acceptance-freeze --approved-by-user'로 재동결하세요 — 토큰이 남아 있으면 acceptance-gate가 FAIL하고 완주가 차단됩니다. 구현 편의를 위한 어서션 약화는 금지." '{"systemMessage": $m}'
        exit 0
      fi
      echo '{"decision": "block", "reason": "인수 테스트는 동결됨(선작성+동결 원칙). 스펙 변경이 필요하면 (1) 사용자 승인(AskUserQuestion) → (2) shared-gate.sh acceptance-unlock --approved-by-user --reason \"<사유>\" 로 동결 해제 → (3) SPEC/테스트 수정 → (4) shared-gate.sh acceptance-freeze --approved-by-user 로 재동결하라."}'
      exit 0
    fi
  fi
  # 동결 전(manifest 부재/타 도구 manifest) → 이 가드는 통과 (Phase 1에서 인수 테스트 생성 중).
  # 아래 기존 가드(기획 문서/CLAUDE.md)는 계속 적용된다 (회귀 방지).
fi

# --- Guard 3 & 4: Phase 기반 보호 대상 판별 ---

PROTECTION_TYPE=""

# CLAUDE.md 보호
if [[ "$FILENAME" == "CLAUDE.md" ]]; then
  PROTECTION_TYPE="claude_md"
fi

# 기획 문서 보호
if [[ -z "$PROTECTION_TYPE" ]]; then
  case "$FILENAME" in
    overview.md|SPEC.md)
      PROTECTION_TYPE="spec_doc"
      ;;
  esac
fi

if [[ -z "$PROTECTION_TYPE" ]]; then
  if [[ "$FILE_PATH" == *"/docs/specs/"* ]] || [[ "$FILE_PATH" == *"/docs/plans/"* ]] \
  || [[ "$FILE_PATH" == *"docs/specs/"* ]] || [[ "$FILE_PATH" == *"docs/plans/"* ]] \
  || [[ "$FILE_PATH" == *"\\docs\\specs\\"* ]] || [[ "$FILE_PATH" == *"\\docs\\plans\\"* ]]; then
    PROTECTION_TYPE="spec_doc"
  fi
fi

# 보호 대상이 아니면 통과 — 무출력 (권한 판정 유보)
if [[ -z "$PROTECTION_TYPE" ]]; then
  exit 0
fi

# unlock 토큰 유효 시 SPEC.md만 허용 (동결 대상은 SPEC 해시이므로 SPEC이 정확히 그 대상).
# overview.md / docs/specs / docs/plans / CLAUDE.md 는 계속 차단 — 승인 범위를 넘는다.
if [[ "$UNLOCK_ACTIVE" == "true" ]] && [[ "$FILENAME" == "SPEC.md" ]]; then
  jq -n --arg m "UNLOCK 중: SPEC.md 편집이 사용자 승인으로 한시 허용되었습니다 (사유: ${UNLOCK_REASON:-미기록}). 수정을 마치면 반드시 'shared-gate.sh acceptance-freeze --approved-by-user'로 재동결하세요 — 토큰이 남아 있으면 acceptance-gate가 FAIL하고 완주가 차단됩니다." '{"systemMessage": $m}'
  exit 0
fi

# --- Phase 판별 (1회만 실행, 결과 공유) ---

# full-auto(solo) / teams 워크플로우의 활성 progress 파일 탐지.
# 하드코딩 시 teams 워크플로우(.claude-full-auto-teams-progress.json)가 미보호되어
# SPEC.md/overview.md/docs가 구현 중 은밀히 재작성될 수 있으므로 두 이름을 모두 검사한다.
PROGRESS_FILE=""
for _pf in .claude-full-auto-progress.json .claude-full-auto-teams-progress.json; do
  if [[ -f "$_pf" ]]; then
    PROGRESS_FILE="$_pf"
    break
  fi
done
if [[ -z "$PROGRESS_FILE" ]]; then
  # full-auto 워크플로우가 아님 (어느 progress 파일도 없음) → 통과 (무출력)
  exit 0
fi

CURRENT_PHASE=$(jq -r '
  if has("currentPhase") then .currentPhase
  elif has("steps") then [.steps[] | select(.status == "in_progress") | .name] | first // empty
  else empty
  end' "$PROGRESS_FILE" 2>/dev/null) || {
  # progress 파일 파싱 실패 시 fail-closed (보호 대상 파일이므로)
  echo "{\"decision\": \"block\", \"reason\": \"progress 파일 파싱 실패. ${FILENAME} 수정을 차단합니다.\"}"
  exit 0
}

# Phase 판별 실패 시 fail-closed (보호 대상 파일이므로)
if [[ -z "$CURRENT_PHASE" ]]; then
  echo "{\"decision\": \"block\", \"reason\": \"현재 Phase를 판별할 수 없습니다. 안전을 위해 ${FILENAME} 수정을 차단합니다.\"}"
  exit 0
fi

# --- Phase 2, 3, 4에서 보호 대상 수정 차단 ---

case "$CURRENT_PHASE" in
  phase_2|phase_3|phase_4)
    if [[ "$PROTECTION_TYPE" == "claude_md" ]]; then
      echo "{\"decision\": \"block\", \"reason\": \"자동화 단계(${CURRENT_PHASE})에서 CLAUDE.md 수정이 차단되었습니다. CLAUDE.md는 사용자가 명시적으로 요청한 경우에만 수정하세요.\"}"
    else
      echo "{\"decision\": \"block\", \"reason\": \"구현 단계(${CURRENT_PHASE})에서 기획 문서(${FILENAME}) 수정이 차단되었습니다. 기획 문서는 Phase 0~1에서만 수정할 수 있습니다. 스코프 변경이 필요하면 SCOPE_REDUCTIONS.md에 기록하세요.\"}"
    fi
    exit 0
    ;;
esac

# Phase 0~1 → 통과 (무출력, 권한 판정 유보)
exit 0
