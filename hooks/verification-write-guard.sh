#!/usr/bin/env bash
# PreToolUse:Bash - .claude-verification.json 쓰기 조작 차단 (fail-closed)
# verification.json은 게이트 스크립트만 쓰는 증거 파일이다. Edit/Write는
# protect-files-guard.sh가 차단하지만, Bash 경유(jq 리다이렉트, sed -i, tee,
# mv/cp, truncate, 인터프리터 -e 등)는 이 훅이 차단한다.
#
# 판정 규칙:
#   1. 명령 문자열에 파일명이 아예 없으면 무조건 통과
#      (shared-gate.sh 게이트 호출은 명령에 파일명이 없으므로 영향 없음 — 오탐 방지의 핵심)
#   2. 파일명이 있고 쓰기 지시자(파일명으로의 리다이렉트, 쓰기 가능 명령어)가 있으면 차단
#   3. 판별이 애매하면 차단 (fail-closed) — 읽기 전용 참조(cat/grep/head/diff/jq 등
#      리다이렉트 없는 사용)만 통과
#
# 신뢰 모델: 훅과 게이트 스크립트가 같은 권한 환경에서 실행되므로 완전 차단은
# 불가능하다. 이 가드는 우발적/1차 시도를 막고, 우회 흔적은 감사 가능하게
# 남기는 목적이다.
#
# 입력: stdin JSON { "tool_input": { "command": "..." } }
# 출력: {"decision": "block", "reason": "..."} 또는 {"decision": "approve"}

set -euo pipefail

TARGET='.claude-verification.json'

BLOCK_MSG='{"decision": "block", "reason": "verification.json은 게이트 스크립트 전용 증거 파일 — 직접 수정 금지. 결과를 바꾸려면 해당 게이트를 재실행하라 (shared-gate.sh <gate>). 읽기 전용 참조(cat/grep/jq 조회)는 허용되지만, 쓰기 가능성이 있는 명령은 안전을 위해 차단된다 (fail-closed)."}'

# jq 미설치 시 fail-closed
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq가 설치되지 않아 명령어를 검증할 수 없습니다. jq를 설치하세요."}'
  exit 0
fi

INPUT=$(cat)

# JSON 파싱 실패 시 fail-closed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || {
  echo '{"decision": "block", "reason": "입력 JSON 파싱에 실패했습니다. 명령어를 검증할 수 없어 차단합니다."}'
  exit 0
}

# ── 규칙 1: 파일명이 없으면 무조건 통과 ──
if ! printf '%s' "$COMMAND" | grep -qF "$TARGET"; then
  echo '{"decision": "approve"}'
  exit 0
fi

# ── 규칙 2a: 해당 파일명으로의 리다이렉트 (>, >>, >| — jq/echo/: > 등 모든 형태) ──
# 예: jq '...' f > .claude-verification.json / echo x >> "./.claude-verification.json" / : > .claude-verification.json
REDIR_RE='>[>|]?[[:space:]]*["'\'']?[^"'\''[:space:]<>|;&]*\.claude-verification\.json'
if printf '%s' "$COMMAND" | grep -qE "$REDIR_RE"; then
  echo "$BLOCK_MSG"
  exit 0
fi

# ── 규칙 2b: 쓰기 가능 명령어 + 파일명 조합 (fail-closed) ──
# tee/sed(-i 여부 판별이 애매하므로 전부)/mv/cp(대상 위치 판별 애매)/rm/truncate/dd/
# sponge/perl/awk(인플레이스 가능) + python/node 등 인터프리터(-e/-c 임의 쓰기 가능) +
# bash/sh/xargs/eval 등 간접 실행 래퍼(내부 동작 판별 불가)
WRITE_CMDS_RE='(^|[[:space:]|;&(`])(tee|sed|mv|cp|rm|truncate|dd|sponge|install|rsync|shred|perl|awk|gawk|python[0-9.]*|node|deno|bun|ruby|php|xargs|eval|bash|sh|zsh|dash|ksh)([[:space:]]|$|["'\''])'
if printf '%s' "$COMMAND" | grep -qE "$WRITE_CMDS_RE"; then
  echo "$BLOCK_MSG"
  exit 0
fi

# ── 규칙 3: 리다이렉트 없음 + 쓰기 명령 없음 = 읽기 전용 참조 → 허용 ──
# 예: jq '.build' .claude-verification.json / cat .claude-verification.json / diff a .claude-verification.json
echo '{"decision": "approve"}'
