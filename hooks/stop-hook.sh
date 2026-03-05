#!/usr/bin/env bash
# Auto Complete Loop - 커스텀 Stop Hook
# Ralph Loop의 stop-hook.sh를 기반으로 .claude-progress.json / .claude-verification.json 검증 추가
#
# 동작:
# 1. .claude/ralph-loop.local.md 상태 파일 확인 (없으면 정상 종료)
# 2. 프론트매터에서 iteration, max_iterations, completion_promise 파싱
# 3. max_iterations 도달 시 종료
# 4. <promise>TEXT</promise> 감지 시:
#    a. progress 파일에서 모든 문서/단계 completed 확인
#    b. .claude-verification.json에서 모든 exitCode 0 확인
#    c. dod 체크리스트가 모두 checked 확인 (비어있지 않아야 함)
#    d. 모든 조건 충족 시에만 종료, 아니면 루프 계속
# 5. 조건 미충족 시 iteration 증가 후 루프 계속

set -euo pipefail

RALPH_STATE_FILE=".claude/ralph-loop.local.md"

# 임시 파일 정리 trap
TEMP_FILES=()
cleanup() {
  for f in "${TEMP_FILES[@]}"; do
    rm -f "$f"
  done
}
trap cleanup EXIT

# 상태 파일이 없으면 정상 종료 허용
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# 프론트매터 파싱 (--- 사이의 YAML)
FRONTMATTER=$(awk '/^---$/{i++; if(i==2) exit; next} i==1{print}' "$RALPH_STATE_FILE")

# CR 문자 제거 (Windows CRLF 대응)
ITERATION=$(echo "$FRONTMATTER" | grep "^iteration:" | sed 's/iteration: *//' | tr -d '\r')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep "^max_iterations:" | sed 's/max_iterations: *//' | tr -d '\r')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep "^completion_promise:" | sed 's/completion_promise: *//' | sed 's/^"//' | sed 's/"$//' | tr -d '\r')
PROGRESS_FILE_FROM_FRONTMATTER=$(echo "$FRONTMATTER" | grep "^progress_file:" | sed 's/progress_file: *//' | sed 's/^"//' | sed 's/"$//' | tr -d '\r' || true)

# 데이터 검증
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Ralph loop state file is corrupted. Removing and allowing stop."
  rm -f "$RALPH_STATE_FILE" ".claude/ralph-loop-failure-history.local"
  exit 0
fi

# max_iterations 도달 확인
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Ralph loop: Max iterations ($MAX_ITERATIONS) reached."
  rm -f "$RALPH_STATE_FILE" ".claude/ralph-loop-failure-history.local"
  exit 0
fi

# 트랜스크립트에서 마지막 assistant 메시지 추출
TRANSCRIPT_PATH=""
if [[ -n "${CLAUDE_HOOK_INPUT:-}" ]]; then
  TRANSCRIPT_PATH=$(echo "$CLAUDE_HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
fi

LAST_OUTPUT=""
if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  # JSONL에서 마지막 assistant 메시지 추출
  LAST_ASSISTANT_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1 || true)
  if [[ -n "$LAST_ASSISTANT_LINE" ]]; then
    LAST_OUTPUT=$(echo "$LAST_ASSISTANT_LINE" | jq -r '
      if .message.content then
        [.message.content[] | select(.type == "text") | .text] | join("\n")
      else
        ""
      end
    ' 2>/dev/null || true)
  fi
fi

# 완료 Promise 검사
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # 먼저 <promise> 태그 존재 여부를 grep으로 확인 (perl 불필요)
  PROMISE_TEXT=""
  if [[ -n "$LAST_OUTPUT" ]] && echo "$LAST_OUTPUT" | grep -q '<promise>' 2>/dev/null; then
    # sed로 promise 태그 내용 추출 (단일 라인 + 멀티라인 대응)
    PROMISE_TEXT=$(echo "$LAST_OUTPUT" | sed -n 's/.*<promise>\(.*\)<\/promise>.*/\1/p' | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    # Promise 감지 -> 추가 검증 수행
    VERIFICATION_PASSED="true"
    FAILURE_REASONS=""

    # 1. progress 파일 검증 (존재하는 경우)
    # 프론트매터에 지정된 파일만 검증. 미지정 시 기존 glob 폴백 (하위 호환)
    VERIFIED_PROGRESS_FILES=()
    if [[ -n "${PROGRESS_FILE_FROM_FRONTMATTER:-}" ]] && [[ -f "$PROGRESS_FILE_FROM_FRONTMATTER" ]]; then
      PROGRESS_FILES_TO_CHECK=("$PROGRESS_FILE_FROM_FRONTMATTER")
    else
      PROGRESS_FILES_TO_CHECK=()
      for pf in .claude-*progress*.json; do
        [[ -f "$pf" ]] && PROGRESS_FILES_TO_CHECK+=("$pf")
      done
    fi
    for PROGRESS_FILE in "${PROGRESS_FILES_TO_CHECK[@]}"; do
      VERIFIED_PROGRESS_FILES+=("$PROGRESS_FILE")
      if [[ -f "$PROGRESS_FILE" ]]; then
        # documents 배열이 있는 경우: 모든 문서가 completed인지 확인
        HAS_DOCUMENTS=$(jq 'has("documents")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
        if [[ "$HAS_DOCUMENTS" = "true" ]]; then
          DOC_COUNT=$(jq '.documents | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
          if [[ "$DOC_COUNT" -eq 0 ]]; then
            VERIFICATION_PASSED="false"
            FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: documents array is empty. "
          else
            ALL_COMPLETED=$(jq '[.documents[].status] | all(. == "completed")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
            if [[ "$ALL_COMPLETED" != "true" ]]; then
              VERIFICATION_PASSED="false"
              FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: not all documents completed. "
            fi
          fi
        fi

        # steps 배열이 있는 경우: 모든 단계가 completed인지 확인
        HAS_STEPS=$(jq 'has("steps")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
        if [[ "$HAS_STEPS" = "true" ]]; then
          STEP_COUNT=$(jq '.steps | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
          if [[ "$STEP_COUNT" -eq 0 ]]; then
            VERIFICATION_PASSED="false"
            FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: steps array is empty. "
          else
            ALL_STEPS_COMPLETED=$(jq '[.steps[].status] | all(. == "completed")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
            if [[ "$ALL_STEPS_COMPLETED" != "true" ]]; then
              VERIFICATION_PASSED="false"
              FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: not all steps completed. "
            fi
          fi
        fi

        # dod 필드가 있는 경우: 비어있지 않고 모든 항목이 checked인지 확인
        HAS_DOD=$(jq 'has("dod")' "$PROGRESS_FILE" 2>/dev/null || echo "false")
        if [[ "$HAS_DOD" = "true" ]]; then
          DOD_COUNT=$(jq '.dod | to_entries | length' "$PROGRESS_FILE" 2>/dev/null || echo "0")
          if [[ "$DOD_COUNT" -gt 0 ]]; then
            ALL_DOD_CHECKED=$(jq '[.dod | to_entries[].value.checked] | all(. == true)' "$PROGRESS_FILE" 2>/dev/null || echo "false")
            if [[ "$ALL_DOD_CHECKED" != "true" ]]; then
              VERIFICATION_PASSED="false"
              FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: DoD checklist not all checked. "
            fi
          fi
          # dod가 빈 객체이면 검증 건너뜀 (DoD 미설정 상태)
        fi
      fi
    done

    # 2. .claude-verification.json 검증 (존재하는 경우)
    if [[ -f ".claude-verification.json" ]]; then
      # exitCode 필드들 수집 (존재하는 항목만)
      ALL_VERIFIED=$(jq '
        [to_entries[] | select(.value | type == "object" and has("exitCode") and .exitCode != null) | .value.exitCode]
        | if length == 0 then true
          else all(. == 0)
          end
      ' .claude-verification.json 2>/dev/null || echo "false")

      if [[ "$ALL_VERIFIED" != "true" ]]; then
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: verification incomplete or exitCodes not all 0. "
      fi
    fi

    # 검증 결과에 따른 분기
    if [[ "$VERIFICATION_PASSED" = "true" ]]; then
      echo "Auto Complete Loop: Promise verified. All conditions met."
      rm -f "$RALPH_STATE_FILE" ".claude/ralph-loop-failure-history.local"
      # 검증 완료된 progress 파일 정리
      for pf in "${VERIFIED_PROGRESS_FILES[@]}"; do
        rm -f "$pf"
      done
      rm -f ".claude-verification.json"
      exit 0
    else
      echo "Auto Complete Loop: Promise detected but verification failed: ${FAILURE_REASONS}Continuing loop..."

      # 무한 루프 감지: 동일 실패 해시가 3회 연속 시 강제 탈출
      FAILURE_HISTORY_FILE=".claude/ralph-loop-failure-history.local"
      CURRENT_FAILURE_HASH=$(echo "$FAILURE_REASONS" | md5sum | cut -d' ' -f1)
      REPEAT_COUNT=0
      if [[ -f "$FAILURE_HISTORY_FILE" ]]; then
        REPEAT_COUNT=$(grep -c "^${CURRENT_FAILURE_HASH}$" "$FAILURE_HISTORY_FILE" 2>/dev/null || echo "0")
      fi
      echo "$CURRENT_FAILURE_HASH" >> "$FAILURE_HISTORY_FILE"
      REPEAT_COUNT=$((REPEAT_COUNT + 1))

      if [[ $REPEAT_COUNT -ge 3 ]]; then
        echo "Auto Complete Loop: Same failure repeated ${REPEAT_COUNT} times. Breaking loop."
        rm -f "$RALPH_STATE_FILE" "$FAILURE_HISTORY_FILE"
        exit 0
      fi
      # 아래의 루프 계속 로직으로 진행
    fi
  fi
fi

# 루프 계속: iteration 증가 + 프롬프트 재전달
NEXT_ITERATION=$((ITERATION + 1))

# 프롬프트 텍스트 추출 (두 번째 --- 이후)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

# iteration 업데이트
TEMP_FILE=$(mktemp)
TEMP_FILES+=("$TEMP_FILE")
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# JSON 출력으로 stop 차단 및 프롬프트 되돌림
SYSTEM_MSG="Auto Complete Loop iteration $NEXT_ITERATION | $(date '+%H:%M:%S')"
if [[ -n "${FAILURE_REASONS:-}" ]]; then
  SYSTEM_MSG="${SYSTEM_MSG} | Verification failed: ${FAILURE_REASONS}"
fi

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'
