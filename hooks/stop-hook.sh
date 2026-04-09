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

# jq 의존성 사전 검증
if ! command -v jq &>/dev/null; then
  echo "Auto Complete Loop: ERROR - jq is required but not found. Install jq to use Ralph Loop."
  echo '{"decision": "approve"}'
  exit 0
fi

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
ITERATION=$(echo "$FRONTMATTER" | grep "^iteration:" | sed 's/iteration: *//' | tr -d '\r' || true)
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep "^max_iterations:" | sed 's/max_iterations: *//' | tr -d '\r' || true)
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep "^completion_promise:" | sed 's/completion_promise: *//' | sed 's/^"//' | sed 's/"$//' | tr -d '\r' || true)
PROGRESS_FILE_FROM_FRONTMATTER=$(echo "$FRONTMATTER" | grep "^progress_file:" | sed 's/progress_file: *//' | sed 's/^"//' | sed 's/"$//' | tr -d '\r' || true)

# progress_file 경로 검증 (경로 조작 방지)
if [[ -n "${PROGRESS_FILE_FROM_FRONTMATTER:-}" ]]; then
  if [[ "$PROGRESS_FILE_FROM_FRONTMATTER" == /* ]] || [[ "$PROGRESS_FILE_FROM_FRONTMATTER" == *..* ]]; then
    echo "Auto Complete Loop: WARNING - progress_file path rejected (path traversal): $PROGRESS_FILE_FROM_FRONTMATTER"
    PROGRESS_FILE_FROM_FRONTMATTER=""
  elif [[ ! "$PROGRESS_FILE_FROM_FRONTMATTER" =~ ^\.claude-.*progress.*\.json$ ]]; then
    echo "Auto Complete Loop: WARNING - progress_file rejected (pattern mismatch): $PROGRESS_FILE_FROM_FRONTMATTER"
    PROGRESS_FILE_FROM_FRONTMATTER=""
  fi
fi

# 데이터 검증
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Auto Complete Loop: WARNING - Ralph loop state file is corrupted (iteration=$ITERATION, max=$MAX_ITERATIONS)."
  echo "Auto Complete Loop: State file preserved at $RALPH_STATE_FILE for manual inspection."
  echo "Auto Complete Loop: To recover, fix or delete $RALPH_STATE_FILE manually."
  # fail-closed: 손상 상태에서 루프 중단하되 파일 보존
  rm -f ".claude/ralph-loop-failure-history.local"
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
    # sed로 promise 태그 내용 추출 (단일 라인 전용 — 규약상 항상 단일 라인)
    PROMISE_TEXT=$(echo "$LAST_OUTPUT" | sed -n 's/.*<promise>\(.*\)<\/promise>.*/\1/p' | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    # Promise 감지 -> 추가 검증 수행
    VERIFICATION_PASSED="true"
    FAILURE_REASONS=""

    # 1. progress 파일 검증 (존재하는 경우)
    # 프론트매터에 지정된 파일만 검증. 미지정 시 기존 glob 폴백 (하위 호환)
    VERIFIED_PROGRESS_FILES=()
    if [[ -n "${PROGRESS_FILE_FROM_FRONTMATTER:-}" ]]; then
      # frontmatter에 지정된 파일만 사용 (파일 부재 시 glob fallback 금지)
      if [[ -f "$PROGRESS_FILE_FROM_FRONTMATTER" ]]; then
        PROGRESS_FILES_TO_CHECK=("$PROGRESS_FILE_FROM_FRONTMATTER")
      else
        # 지정된 파일이 없으면 검증 실패 (증거 없이 통과 방지)
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}Specified progress file $PROGRESS_FILE_FROM_FRONTMATTER not found. "
        PROGRESS_FILES_TO_CHECK=()
      fi
    else
      # frontmatter 미지정 시 glob 폴백 (하위 호환)
      PROGRESS_FILES_TO_CHECK=()
      for pf in .claude-*progress*.json; do
        [[ -f "$pf" ]] && PROGRESS_FILES_TO_CHECK+=("$pf")
      done
      # fail-closed: glob 결과도 0개면 검증 실패 (progress 증거 없음)
      if [[ ${#PROGRESS_FILES_TO_CHECK[@]} -eq 0 ]]; then
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}No progress files found (frontmatter unset, glob empty). "
      fi
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
          else
            VERIFICATION_PASSED="false"
            FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: DoD is empty (no completion criteria defined). "
          fi
        fi

        # fail-closed: progress 파일에 documents/steps/dod 중 하나도 없으면 검증 실패
        if [[ "$HAS_DOCUMENTS" != "true" ]] && [[ "$HAS_STEPS" != "true" ]] && [[ "$HAS_DOD" != "true" ]]; then
          VERIFICATION_PASSED="false"
          FAILURE_REASONS="${FAILURE_REASONS}$PROGRESS_FILE: no documents, steps, or dod found (empty progress). "
        fi
      fi
    done

    # 2. .claude-verification.json 검증 (필수)
    if [[ ! -f ".claude-verification.json" ]]; then
      VERIFICATION_PASSED="false"
      FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json not found (quality gate evidence required). "
    elif [[ -f ".claude-verification.json" ]]; then
      # exitCode 기반 게이트 (build/typeCheck/lint/test): exitCode == 0
      ALL_EXITCODES_OK=$(jq '
        [to_entries[] | select(.value | type == "object" and has("exitCode") and .exitCode != null) | .value.exitCode]
        | if length == 0 then false
          else all(. == 0)
          end
      ' .claude-verification.json 2>/dev/null || echo "false")

      if [[ "$ALL_EXITCODES_OK" != "true" ]]; then
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: exitCode-based gates not all 0. "
      fi

      # result 기반 게이트 (secretScan/artifactCheck/smokeCheck/designPolish): result != "fail"
      ALL_RESULTS_OK=$(jq '
        [to_entries[] | select(.value | type == "object" and has("result") and .result != null) | .value.result]
        | if length == 0 then true
          else all(. == "pass" or . == "skip" or . == "soft_fail")
          end
      ' .claude-verification.json 2>/dev/null || echo "false")

      # fail-closed: verification.json에 exitCode 기반 게이트가 하나도 없으면 검증 불충분
      if [[ "$ALL_EXITCODES_OK" = "false" ]]; then
        HAS_ANY_GATE=$(jq '[to_entries[] | select(.value | type == "object" and has("exitCode"))] | length' .claude-verification.json 2>/dev/null || echo "0")
        if [[ "$HAS_ANY_GATE" = "0" ]]; then
          FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: no quality gate entries found (empty verification). "
        fi
      fi

      # qualityDimensions 필수 검사
      QD_EXISTS=$(jq 'has("qualityDimensions")' .claude-verification.json 2>/dev/null || echo "false")
      if [[ "$QD_EXISTS" != "true" ]]; then
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: qualityDimensions missing (Phase 4 verification required). "
      else
        # layerCoverage 하드 게이트: 필수 존재 + result=pass 필요
        LC_RESULT=$(jq '.qualityDimensions.layerCoverage.result // "missing"' .claude-verification.json 2>/dev/null || echo '"missing"')
        if [[ "$LC_RESULT" != '"pass"' ]]; then
          VERIFICATION_PASSED="false"
          FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: layerCoverage ${LC_RESULT} (must be pass). "
        fi

        # 나머지 차원은 소프트 — fail 시 경고만 (차단 안 함)
        QD_SOFT_FAIL=$(jq '
          [.qualityDimensions | to_entries[]
           | select(.key != "layerCoverage")
           | select(.value | type == "object" and has("result") and .result == "fail")
           | .key] | join(", ")
        ' .claude-verification.json 2>/dev/null || echo "")
        if [[ -n "$QD_SOFT_FAIL" ]]; then
          echo "WARNING: soft quality dimensions failed: ${QD_SOFT_FAIL} (not blocking)"
        fi
      fi

      # 필수 게이트 검증: test가 실행되었는지 확인 (SKIP이면 DoD와 일관성 검사)
      TEST_EXIT=$(jq '.test.exitCode // "missing"' .claude-verification.json 2>/dev/null || echo "missing")
      if [[ "$TEST_EXIT" = "null" ]] || [[ "$TEST_EXIT" = "missing" ]]; then
        # test가 SKIP된 경우: 모든 progress 파일의 dod.test_pass.checked를 검사
        for _pf in "${VERIFIED_PROGRESS_FILES[@]:-}"; do
          [[ -z "$_pf" ]] || [[ ! -f "$_pf" ]] && continue
          _test_dod=$(jq '.dod.test_pass.checked // false' "$_pf" 2>/dev/null || echo "false")
          if [[ "$_test_dod" = "true" ]]; then
            VERIFICATION_PASSED="false"
            FAILURE_REASONS="${FAILURE_REASONS}test was skipped but ${_pf}: dod.test_pass is checked=true (inconsistency). "
          fi
        done
      fi

      if [[ "$ALL_RESULTS_OK" != "true" ]]; then
        VERIFICATION_PASSED="false"
        FAILURE_REASONS="${FAILURE_REASONS}.claude-verification.json: result-based gates have failures (fail). "
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
      # 크로스 플랫폼 해시 (md5sum → md5 → sha256sum → cksum 폴백)
      if command -v md5sum &>/dev/null; then
        CURRENT_FAILURE_HASH=$(echo "$FAILURE_REASONS" | md5sum | cut -d' ' -f1)
      elif command -v md5 &>/dev/null; then
        CURRENT_FAILURE_HASH=$(echo "$FAILURE_REASONS" | md5)
      elif command -v sha256sum &>/dev/null; then
        CURRENT_FAILURE_HASH=$(echo "$FAILURE_REASONS" | sha256sum | cut -d' ' -f1)
      else
        CURRENT_FAILURE_HASH=$(echo "$FAILURE_REASONS" | cksum | cut -d' ' -f1)
      fi
      REPEAT_COUNT=0
      if [[ -f "$FAILURE_HISTORY_FILE" ]]; then
        REPEAT_COUNT=$(grep -c "^${CURRENT_FAILURE_HASH}$" "$FAILURE_HISTORY_FILE" 2>/dev/null || echo "0")
      fi
      echo "$CURRENT_FAILURE_HASH" >> "$FAILURE_HISTORY_FILE"
      REPEAT_COUNT=$((REPEAT_COUNT + 1))

      if [[ $REPEAT_COUNT -ge 3 ]]; then
        echo "Auto Complete Loop: WARNING - Same failure repeated ${REPEAT_COUNT} times. Breaking loop due to unresolvable verification failures."
        echo "Auto Complete Loop: Unresolved issues: ${FAILURE_REASONS}"
        echo "Auto Complete Loop: Progress files preserved for manual inspection."
        rm -f "$RALPH_STATE_FILE" "$FAILURE_HISTORY_FILE"
        # exit 0 to stop the loop, but progress files are NOT deleted (unlike success path)
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
