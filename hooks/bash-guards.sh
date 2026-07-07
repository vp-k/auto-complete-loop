#!/usr/bin/env bash
# PreToolUse:Bash - 통합 디스패처 (호출당 3회 프로세스 기동 오버헤드 제거)
# stdin을 1회만 읽고 command를 1회만 추출하여 아래 검사를 순차 실행한다:
#   1) block-no-verify  : --no-verify / git commit -n 차단 (pre-commit hook 보호)
#   2) commit-msg-guard : [auto] 커밋 메시지의 US-ID suffix 의무화
#   3) verification-write-guard : .claude-verification.json Bash 경유 쓰기 차단
# 첫 block에서 즉시 종료. 검사 순서·판정 결과는 기존 3개 훅과 동일.
#
# 입력: stdin JSON { "tool_input": { "command": "..." } }
# 출력: 차단 시 {"decision": "block", "reason": "..."}
#       통과 시 아무 출력 없이 exit 0 (권한 판정에 관여하지 않음 — approve 출력 금지)

set -euo pipefail

# jq 미설치 시 fail-closed
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 명령어를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

# 훅 입력: stdin 우선, 비어 있으면 CLAUDE_HOOK_INPUT 폴백 (목업/테스트 호환)
INPUT=$(cat 2>/dev/null || true)
if [[ -z "$INPUT" ]]; then
  INPUT="${CLAUDE_HOOK_INPUT:-}"
fi

# JSON 파싱 실패 시 fail-closed
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 명령어를 검증할 수 없어 차단합니다."}'
  exit 0
}

# command가 비어 있으면 검사할 것이 없음 → 무출력 통과
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ─── 공통 유틸 ───

block() {
  printf '{"decision": "block", "reason": %s}\n' "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

# 인용부 제거: 이스케이프된 따옴표 → 작은따옴표 문자열 → 큰따옴표 문자열 순으로 제거.
# 커밋 메시지 등 문자열 리터럴 안의 텍스트가 플래그 검사에 오탐되는 것을 방지.
strip_quotes() {
  printf '%s' "$1" | sed -E "s/\\\\[\"']//g; s/'[^']*'//g; s/\"[^\"]*\"//g"
}

# git global option(-C, -c, --git-dir, --work-tree)이 앞에 있어도 commit을 포함하면 검사
GIT_COMMIT_RE='git([[:space:]]+(-C[[:space:]]+\S+|-c[[:space:]]+\S+=\S+|--git-dir[[:space:]]+\S+|--work-tree[[:space:]]+\S+))*[[:space:]]+commit'

# ─── 검사 1: --no-verify / git commit -n 차단 (block-no-verify) ───

NO_VERIFY_MSG='--no-verify는 사용할 수 없습니다. pre-commit hook을 우회하면 품질 게이트가 무력화됩니다. hook 실패 시 근본 원인을 해결하세요.'

check_no_verify() {
  local stripped segs _seg
  # 인용부(커밋 메시지 등) 제거 후 명령 토큰 위치의 플래그만 검사
  # (예: git commit -m "docs: --no-verify 설명" 은 오탐하지 않음)
  stripped=$(strip_quotes "$COMMAND")

  # --no-verify: 토큰 위치(공백 경계)에서만 매칭
  if printf '%s' "$stripped" | grep -qE -- '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
    block "$NO_VERIFY_MSG"
  fi

  # git commit의 -n (short form of --no-verify) 차단
  # 주의: git push -n은 dry-run이므로 차단하지 않음
  # 오탐 방지: 명령을 구분자(;|&)로 세그먼트 분할 → git commit이 포함된
  # 세그먼트 안의 플래그만 검사 (후속 `grep -n` 등 다른 명령에 매칭 금지)
  segs=$(printf '%s\n' "$stripped" | tr ';|&' '\n')
  while IFS= read -r _seg; do
    if printf '%s' "$_seg" | grep -qE "$GIT_COMMIT_RE"; then
      if printf '%s' "$_seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n([[:space:]]|$)'; then
        block "$NO_VERIFY_MSG"
      fi
    fi
  done <<< "$segs"
  return 0
}

# ─── 검사 2: [auto] 커밋 메시지 US-ID suffix 의무화 (commit-msg-guard) ───

check_commit_msg() {
  # git commit 커맨드가 아니면 통과
  if ! printf '%s' "$COMMAND" | grep -qE "$GIT_COMMIT_RE"; then
    return 0
  fi

  # -m / --message 플래그가 없으면 (에디터 사용) 본 검사는 관여하지 않음
  if ! printf '%s' "$COMMAND" | grep -qE -- '(-m.|--message[[:space:]=])'; then
    return 0
  fi

  # [auto] 표식이 없으면 통과 (수동 커밋)
  if ! printf '%s' "$COMMAND" | grep -qE '\[auto\]'; then
    return 0
  fi

  # 면제 키워드 (스코프 전역 커밋은 US-ID 불필요)
  local exempt='스캐폴딩|scaffolding|infrastructure|E2E 프레임워크|E2E framework|최종 검증|폴리싱|polishing|Directive:|Rejected:|Consensus:|Scope-risk:'
  if printf '%s' "$COMMAND" | grep -qE "$exempt"; then
    return 0
  fi

  # US-F-### 또는 US-B-### 존재 체크
  if printf '%s' "$COMMAND" | grep -qE 'US-[FB]-[0-9]+'; then
    return 0
  fi

  block '[auto] 커밋 메시지에 User Story ID suffix가 누락되었습니다. 형식: `[auto] <내용> [US-F-###]` 또는 `[auto] <내용> [US-B-###]`. 여러 US 관련 시 쉼표 구분: [US-F-001,US-B-002]. 면제 대상(스캐폴딩/인프라/최종 검증/폴리싱/Directive 등)이면 해당 키워드를 메시지에 포함하세요.'
}

# ─── 검사 3: .claude-verification.json 쓰기 조작 차단 (verification-write-guard) ───
# 판정 규칙:
#   1. 명령에 파일명(word-boundary 매칭)이 없으면 통과
#      (부분일치 오탐 방지: .claude-verification.json.bak 등은 다른 파일로 취급)
#   2a. 파일명으로의 리다이렉트(>, >>, >|) → 차단
#   2b. 파일명이 "인용부 밖"에만 있으면: 인용부 제거본을 세그먼트(;|& 분할)로 나눠
#       파일명이 포함된 세그먼트에 쓰기 가능 명령이 있을 때만 차단.
#       파일명이 없는 세그먼트의 쓰기 명령은 파일을 지명할 수 없으므로 허용
#       (예: cat .claude-verification.json | python -m json.tool 은 읽기 전용 → 통과)
#       파일명이 인용부 "안"에 있으면 세그먼트 판별이 불가능하므로 기존 fail-closed
#       유지: 쓰기 가능 명령이 명령 어디에든 있으면 차단.
#   2c. 예외: xargs/parallel은 stdin을 "인자"로 전달하므로 파일명이 명령 어디에든
#       있으면 fail-closed 차단 (echo file | xargs rm 류 우회 방지)
#   3. 그 외 = 읽기 전용 참조 → 통과
# 신뢰 모델: 우발적/1차 시도 차단 + 우회 흔적 감사가 목적 (완전 차단 불가능).

VG_BLOCK_MSG='verification.json은 게이트 스크립트 전용 증거 파일 — 직접 수정 금지. 결과를 바꾸려면 해당 게이트를 재실행하라 (shared-gate.sh <gate>). 읽기 전용 참조(cat/grep/jq 조회, 파이프로 넘긴 뒤 파일명을 지명하지 않는 필터)는 허용되지만, 파일명과 같은 세그먼트에 쓰기 가능 명령이 있으면 안전을 위해 차단된다 (fail-closed).'

# 일반화: <파일 리터럴> <파일 regex 코어(이스케이프됨)> <차단 메시지>
# 규칙은 위 주석(1/2a/2b/2c/3)과 동일 — 보호 파일별로 재사용한다.
_check_file_write() {
  local file_lit="$1" file_core="$2" msg="$3"
  local target_re redir_re write_cmds_re segs _seg
  # word-boundary: 앞뒤가 파일명 구성문자(영숫자 . _ -)가 아니어야 매칭
  target_re="(^|[^A-Za-z0-9._-])${file_core}([^A-Za-z0-9._-]|\$)"

  # 규칙 1: 파일명이 없으면 무조건 통과 (shared-gate.sh 게이트 호출은 영향 없음)
  if ! printf '%s' "$COMMAND" | grep -qE "$target_re"; then
    return 0
  fi

  # 규칙 2a: 해당 파일명으로의 리다이렉트 (>, >>, >| — jq/echo/: > 등 모든 형태)
  redir_re='>[>|]?[[:space:]]*["'\'']?[^"'\''[:space:]<>|;&]*'"${file_core}"'([^A-Za-z0-9._-]|$|["'\''])'
  if printf '%s' "$COMMAND" | grep -qE "$redir_re"; then
    block "$msg"
  fi

  # 규칙 2c: stdin→인자 전달자(xargs/parallel)는 위치 무관 fail-closed
  if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]|;&(`])(xargs|parallel)([[:space:]]|$|["'\''])'; then
    block "$msg"
  fi

  # 규칙 2b: 파일명이 포함된 세그먼트에 쓰기 가능 명령 존재 시 차단
  write_cmds_re='(^|[[:space:]|;&(`])(tee|sed|mv|cp|rm|truncate|dd|sponge|install|rsync|shred|perl|awk|gawk|python[0-9.]*|node|deno|bun|ruby|php|eval|bash|sh|zsh|dash|ksh|touch)([[:space:]]|$|["'\''])'

  # 파일명이 인용부 안에 있는지 판별 (기존 fail-closed 규칙)
  local stripped occ_orig occ_stripped
  stripped=$(strip_quotes "$COMMAND")
  occ_orig=$(printf '%s' "$COMMAND" | grep -oF "$file_lit" | wc -l || true)
  occ_stripped=$(printf '%s' "$stripped" | grep -oF "$file_lit" | wc -l || true)
  if [[ "${occ_orig:-0}" -ne "${occ_stripped:-0}" ]]; then
    if printf '%s' "$COMMAND" | grep -qE "$write_cmds_re"; then
      block "$msg"
    fi
    return 0
  fi

  # 파일명이 전부 인용부 밖 → 세그먼트 분석
  segs=$(printf '%s\n' "$stripped" | tr ';|&' '\n')
  while IFS= read -r _seg; do
    printf '%s' "$_seg" | grep -qE "$target_re" || continue
    if printf '%s' "$_seg" | grep -qE "$write_cmds_re"; then
      block "$msg"
    fi
  done <<< "$segs"

  # 규칙 3: 읽기 전용 참조 → 통과
  return 0
}

check_verification_write() {
  _check_file_write '.claude-verification.json' '\.claude-verification\.json' "$VG_BLOCK_MSG"
}

# ─── 검사 4: Ralph 루프 상태 파일 보호 (최종 락 우회 방지) ───
# 실전 검증 실측: 모델이 promise 미인식 상황에서 rm -f로 ralph 파일을 삭제해
# 루프를 우회 종료했다. 파일 삭제는 "사용자의" 탈출구이며 모델의 것이 아니다.
RALPH_BLOCK_MSG='Ralph 루프 상태 파일(.claude/ralph-loop.local.md)은 stop-hook 전용 — 모델이 수정/삭제하면 최종 검증 락을 우회하게 되므로 금지. 루프를 끝내려면 (a) 완주 조건(게이트)을 충족시키거나 (b) 진퇴양난이면 AskUserQuestion으로 사용자에게 강제 종료(파일 삭제는 사용자 몫)를 요청하라. 읽기는 허용.'

check_ralph_write() {
  _check_file_write 'ralph-loop.local.md' 'ralph-loop\.local\.md' "$RALPH_BLOCK_MSG"
}

# ─── 순차 실행 (기존 hooks.json 등록 순서와 동일) ───
check_no_verify
check_commit_msg
check_verification_write
check_ralph_write

# 전 검사 통과 → 무출력 (권한 판정 유보)
exit 0
