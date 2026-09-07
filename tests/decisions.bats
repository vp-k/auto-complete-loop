#!/usr/bin/env bats
# decisions.bats — 결정 기록 단일 출처(record-decision) + assumption 일괄 확인(assumption-review)

load test_helper

setup() { setup_temp_dir; }
teardown() { teardown_temp_dir; }

WHY_OK="세션 스토어 없이 수평 확장해야 하고 만료 규약이 SPEC에 이미 명시되어 있다"

# ─── --why 필수/최소 길이 ───

@test "record-decision: --why 없으면 거부 (이유 없는 결정은 기록 불가)" {
  run run_gate record-decision --what "JWT로 확정"
  [ "$status" -ne 0 ]
  [[ "$output" == *"이유 없는 결정은 기록할 수 없다"* ]]
  [ ! -f .claude/acl-decisions.jsonl ]
}

@test "record-decision: --why가 10자 미만이면 거부" {
  run run_gate record-decision --what "JWT로 확정" --why "필요해서"
  [ "$status" -ne 0 ]
  [[ "$output" == *"이유 없는 결정은 기록할 수 없다"* ]]
  [ ! -f .claude/acl-decisions.jsonl ]
}

@test "record-decision: 공백만으로 길이를 채울 수 없다" {
  run run_gate record-decision --what "x" --why "필요       함"
  [ "$status" -ne 0 ]
  [[ "$output" == *"이유 없는 결정은 기록할 수 없다"* ]]
}

@test "record-decision: --what 없으면 거부" {
  run run_gate record-decision --why "$WHY_OK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--what"* ]]
}

# ─── JSONL append + id 채번 ───

@test "record-decision: JSONL 한 줄을 append하고 필드를 전부 채운다" {
  run run_gate record-decision --what "인증을 JWT로 확정" --why "$WHY_OK" \
    --alternatives "서버 세션 쿠키" --reversible no --scope planning --source adr --iteration 3
  [ "$status" -eq 0 ]
  [ -f .claude/acl-decisions.jsonl ]

  run jq -r '.id' .claude/acl-decisions.jsonl
  [ "$output" = "D-0001" ]
  run jq -r '.what' .claude/acl-decisions.jsonl
  [ "$output" = "인증을 JWT로 확정" ]
  run jq -r '.kind' .claude/acl-decisions.jsonl
  [ "$output" = "decision" ]
  run jq -r '.reversible' .claude/acl-decisions.jsonl
  [ "$output" = "no" ]
  run jq -r '.scope' .claude/acl-decisions.jsonl
  [ "$output" = "planning" ]
  run jq -r '.source' .claude/acl-decisions.jsonl
  [ "$output" = "adr" ]
  run jq -r '.iteration' .claude/acl-decisions.jsonl
  [ "$output" = "3" ]
  run jq -r '.alternatives[0]' .claude/acl-decisions.jsonl
  [ "$output" = "서버 세션 쿠키" ]
  run jq -r '.ts' .claude/acl-decisions.jsonl
  [[ "$output" =~ ^[0-9]{4}- ]]
}

@test "record-decision: id는 순차 채번되고 기존 줄은 보존된다 (append-only)" {
  run_gate record-decision --what "첫 번째 결정" --why "$WHY_OK"
  run_gate record-decision --what "두 번째 결정" --why "$WHY_OK"
  run_gate record-decision --what "세 번째 결정" --why "$WHY_OK"

  run bash -c "wc -l < .claude/acl-decisions.jsonl | tr -d ' '"
  [ "$output" = "3" ]
  run jq -rs 'map(.id) | join(",")' .claude/acl-decisions.jsonl
  [ "$output" = "D-0001,D-0002,D-0003" ]
  run jq -rs '.[0].what' .claude/acl-decisions.jsonl
  [ "$output" = "첫 번째 결정" ]
}

@test "record-decision: alternatives 미지정 시 빈 배열 (set -u 안전)" {
  run run_gate record-decision --what "x 결정" --why "$WHY_OK"
  [ "$status" -eq 0 ]
  run jq -r '.alternatives | length' .claude/acl-decisions.jsonl
  [ "$output" = "0" ]
}

@test "record-decision: alternatives 반복 지정" {
  run_gate record-decision --what "x 결정" --why "$WHY_OK" \
    --alternatives "대안 A" --alternatives "대안 B"
  run jq -r '.alternatives | join("|")' .claude/acl-decisions.jsonl
  [ "$output" = "대안 A|대안 B" ]
}

# ─── enum 검증 ───

@test "record-decision: 잘못된 --reversible / --scope / --source 거부" {
  run run_gate record-decision --what "x" --why "$WHY_OK" --reversible maybe
  [ "$status" -ne 0 ]
  run run_gate record-decision --what "x" --why "$WHY_OK" --scope nope
  [ "$status" -ne 0 ]
  run run_gate record-decision --what "x" --why "$WHY_OK" --source nope
  [ "$status" -ne 0 ]
  [ ! -f .claude/acl-decisions.jsonl ]
}

# ─── 이벤트 로그 ───

@test "record-decision: decision.recorded 이벤트를 남긴다" {
  run_gate record-decision --what "인증 방식 확정" --why "$WHY_OK" --scope planning
  [ -f .claude/acl-events.jsonl ]
  run jq -rs 'map(select(.event == "decision.recorded")) | length' .claude/acl-events.jsonl
  [ "$output" = "1" ]
  run jq -rs 'map(select(.event == "decision.recorded"))[0].id' .claude/acl-events.jsonl
  [ "$output" = "D-0001" ]
}

# ─── handoff.keyDecisions 미러 ───

@test "record-decision: handoff.keyDecisions에 append한다 (치환이 아님)" {
  run_gate init --template full-auto "test" "req"
  run_gate handoff-update --progress-file .claude-full-auto-progress.json \
    --next-steps "다음" --decision "기존 요약"

  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --what "인증을 JWT로 확정" --why "$WHY_OK"

  run jq -r '.handoff.keyDecisions | length' .claude-full-auto-progress.json
  [ "$output" = "2" ]
  run jq -r '.handoff.keyDecisions[0]' .claude-full-auto-progress.json
  [ "$output" = "기존 요약" ]
  run jq -r '.handoff.keyDecisions[1]' .claude-full-auto-progress.json
  [[ "$output" == "D-0001: 인증을 JWT로 확정 — "* ]]
}

@test "record-decision: progress 파일이 없어도 로그는 남고 실패하지 않는다" {
  run run_gate record-decision --what "x 결정" --why "$WHY_OK"
  [ "$status" -eq 0 ]
  [ -f .claude/acl-decisions.jsonl ]
}

# ─── --none ───

@test "record-decision --none: why는 여전히 필수" {
  run run_gate record-decision --none
  [ "$status" -ne 0 ]
  [[ "$output" == *"이유 없는 결정은 기록할 수 없다"* ]]
}

@test "record-decision --none: kind=none으로 기록하되 keyDecisions는 건드리지 않는다" {
  run_gate init --template full-auto "test" "req"
  run run_gate record-decision --none --progress-file .claude-full-auto-progress.json \
    --why "문서 오탈자 수정만 수행했고 설계 선택지가 발생하지 않았다"
  [ "$status" -eq 0 ]
  run jq -r '.kind' .claude/acl-decisions.jsonl
  [ "$output" = "none" ]
  run jq -r '.handoff.keyDecisions | length' .claude-full-auto-progress.json
  [ "$output" = "0" ]
}

# ─── iteration 기본값 ───

@test "record-decision: --iteration 생략 시 ralph-loop frontmatter의 iteration을 쓴다" {
  mkdir -p .claude
  printf -- '---\niteration: 7\nmax_iterations: 50\n---\n\nbody\n' > .claude/ralph-loop.local.md
  run_gate record-decision --what "x 결정" --why "$WHY_OK"
  run jq -r '.iteration' .claude/acl-decisions.jsonl
  [ "$output" = "7" ]
}

@test "record-decision: frontmatter가 없으면 handoff.lastIteration을 쓴다" {
  run_gate init --template full-auto "test" "req"
  run_gate handoff-update --progress-file .claude-full-auto-progress.json --next-steps "n" --iteration 4
  run_gate record-decision --progress-file .claude-full-auto-progress.json --what "x 결정" --why "$WHY_OK"
  run jq -r '.iteration' .claude/acl-decisions.jsonl
  [ "$output" = "4" ]
}

@test "handoff-update: --iteration 생략 시 ralph-loop frontmatter의 iteration으로 lastIteration을 채운다" {
  run_gate init --template full-auto "test" "req"
  mkdir -p .claude
  printf -- '---\niteration: 5\nmax_iterations: 50\n---\n\nbody\n' > .claude/ralph-loop.local.md
  run_gate handoff-update --progress-file .claude-full-auto-progress.json --next-steps "n"
  run jq -r '.handoff.lastIteration' .claude-full-auto-progress.json
  [ "$output" = "5" ]
}

@test "handoff-update: frontmatter가 없고 --iteration도 없으면 lastIteration을 건드리지 않는다" {
  run_gate init --template full-auto "test" "req"
  run_gate handoff-update --progress-file .claude-full-auto-progress.json --next-steps "n" --iteration 2
  run_gate handoff-update --progress-file .claude-full-auto-progress.json --next-steps "m"
  run jq -r '.handoff.lastIteration' .claude-full-auto-progress.json
  [ "$output" = "2" ]
}

# ─── 결정 로그 직접 편집 차단 (Edit/Write — Bash 경유는 bash-guards.bats) ───

@test "protect-files-guard: .claude/acl-decisions.jsonl Edit/Write 하드 차단" {
  local out
  out=$(jq -n '{tool_input:{file_path:".claude/acl-decisions.jsonl"}}' | bash "$SCRIPT_DIR/../hooks/protect-files-guard.sh" 2>/dev/null || true)
  printf '%s' "$out" | grep -q '"decision": *"block"'
  printf '%s' "$out" | grep -q 'record-decision'
}

# ─── --list ───

@test "record-decision: 스테일 락(owner 메타 30초 초과)은 회수하고 기록한다" {
  mkdir -p .claude/acl-decisions.jsonl.lock.d
  printf '%s %s\n' 99999 "$(( $(date -u '+%s') - 100 ))" > .claude/acl-decisions.jsonl.lock.d/owner
  run run_gate record-decision --what "JWT로 확정" --why "$WHY_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale lock 회수"* ]]
  [ ! -d .claude/acl-decisions.jsonl.lock.d ]
  [ "$(grep -c '^{' .claude/acl-decisions.jsonl)" = "1" ]
}

@test "record-decision: owner 메타가 없는 방금 생긴 락은 회수하지 않고 fail-closed로 거부한다" {
  mkdir -p .claude/acl-decisions.jsonl.lock.d
  run run_gate record-decision --what "JWT로 확정" --why "$WHY_OK"
  # 락을 못 잡으면 D-NNNN 채번이 경합하므로 기록하지 않고 실패해야 한다
  [ "$status" -ne 0 ]
  [[ "$output" != *"stale lock 회수"* ]]
  [[ "$output" == *"lock busy"* ]]
  [[ "$output" == *"재시도"* ]]
  [ -d .claude/acl-decisions.jsonl.lock.d ]
  [ ! -f .claude/acl-decisions.jsonl ]
}

@test "record-decision --list: 기록이 없으면 안내만 하고 성공한다" {
  run run_gate record-decision --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"결정 기록 없음"* ]]
}

@test "record-decision --list: iteration 필터와 --last N" {
  run_gate record-decision --what "it1 결정" --why "$WHY_OK" --iteration 1
  run_gate record-decision --what "it2 결정 A" --why "$WHY_OK" --iteration 2
  run_gate record-decision --what "it2 결정 B" --why "$WHY_OK" --iteration 2

  run run_gate record-decision --list --iteration 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"it2 결정 A"* ]]
  [[ "$output" == *"it2 결정 B"* ]]
  [[ "$output" != *"it1 결정"* ]]

  run run_gate record-decision --list --last 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"it2 결정 B"* ]]
  [[ "$output" != *"it2 결정 A"* ]]
}

# ─── status 통합 ───

@test "status: 최근 결정 3건을 표시한다" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json --what "결정 1" --why "$WHY_OK"
  run_gate record-decision --progress-file .claude-full-auto-progress.json --what "결정 2" --why "$WHY_OK"

  run run_gate status --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent Decisions"* ]]
  [[ "$output" == *"결정 2"* ]]
}

# ─── init 템플릿: decisionLog.enabled ───

@test "init: full-auto 템플릿에 decisionLog.enabled=true가 들어간다" {
  run_gate init --template full-auto "test" "req"
  run jq -r '.decisionLog.enabled' .claude-full-auto-progress.json
  [ "$output" = "true" ]
}

@test "init: plan 템플릿에도 decisionLog.enabled=true가 들어간다" {
  run_gate init --template plan "test" "req"
  run bash -c "jq -r '.decisionLog.enabled' .claude-plan-progress.json"
  [ "$output" = "true" ]
}

# ─── assumption-review ───

@test "assumption-review: confirmed 기록" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope interview --source provenance --what "가정 1 승인" --why "$WHY_OK"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope interview --source provenance --what "가정 2 승인" --why "$WHY_OK"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json --status confirmed --count 2
  [ "$status" -eq 0 ]
  run jq -r '.assumptionReview.status' .claude-full-auto-progress.json
  [ "$output" = "confirmed" ]
  run jq -r '.assumptionReview.count' .claude-full-auto-progress.json
  [ "$output" = "2" ]
  run jq -r '.assumptionReview.confirmedAt' .claude-full-auto-progress.json
  [[ "$output" =~ ^[0-9]{4}- ]]
}

@test "assumption-review: none은 count 0에서만 허용" {
  run_gate init --template full-auto "test" "req"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json --status none --count 3
  [ "$status" -ne 0 ]
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json --status none --count 0
  [ "$status" -eq 0 ]
}

@test "assumption-review: confirmed인데 count 0이면 거부 (빈 확인 세탁 차단)" {
  run_gate init --template full-auto "test" "req"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json --status confirmed --count 0
  [ "$status" -ne 0 ]
}

@test "assumption-review: 잘못된 status 거부" {
  run_gate init --template full-auto "test" "req"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json --status ok --count 1
  [ "$status" -ne 0 ]
}

@test "assumption-review: assumption.review 이벤트를 남긴다" {
  run_gate init --template full-auto "test" "req"
  run_gate assumption-review --progress-file .claude-full-auto-progress.json --status escalated --count 0 \
    --note "비대화형"
  run jq -rs 'map(select(.event == "assumption.review")) | length' .claude/acl-events.jsonl
  [ "$output" = "1" ]
  run jq -r '.assumptionReview.note' .claude-full-auto-progress.json
  [ "$output" = "비대화형" ]
}

# ─── (e) --why 경계값: 정확히 10자는 통과, 9자는 거부 ───

@test "record-decision: --why가 정확히 10자면 통과한다 (경계값)" {
  run run_gate record-decision --what "경계값 결정" --why "일이삼사오육칠팔구십"
  [ "$status" -eq 0 ]
  run jq -r '.why' .claude/acl-decisions.jsonl
  [ "$output" = "일이삼사오육칠팔구십" ]
}

@test "record-decision: --why가 9자면 거부한다 (경계값)" {
  run run_gate record-decision --what "경계값 결정" --why "일이삼사오육칠팔구"
  [ "$status" -ne 0 ]
  [[ "$output" == *"이유 없는 결정은 기록할 수 없다"* ]]
  [ ! -f .claude/acl-decisions.jsonl ]
}

@test "record-decision: 공백은 길이에서 제외된다 (10자 + 공백 → 통과)" {
  run run_gate record-decision --what "경계값 결정" --why "일 이 삼 사 오 육 칠 팔 구 십"
  [ "$status" -eq 0 ]
}

# ─── (b) init 템플릿 7종 전부 decisionLog.enabled ───

@test "init: 템플릿 7종 전부 decisionLog.enabled=true + runId를 발급한다" {
  local t f
  # init은 기존 progress 파일을 자동 탐지해 재사용하므로 템플릿마다 빈 디렉토리에서 실행한다
  for t in full-auto:.claude-full-auto-progress.json \
           plan:.claude-plan-progress.json \
           implement:.claude-progress.json \
           review:.claude-review-loop-progress.json \
           polish:.claude-polish-progress.json \
           e2e:.claude-e2e-progress.json \
           doc-check:.claude-doc-check-progress.json; do
    f="${t#*:}"
    mkdir -p "$TEST_DIR/tpl-${t%%:*}"
    cd "$TEST_DIR/tpl-${t%%:*}"
    run run_gate init --template "${t%%:*}" "test" "req"
    [ "$status" -eq 0 ]
    [ -f "$f" ]
    run jq -r '.decisionLog.enabled' "$f"
    [ "$output" = "true" ]
    run jq -r '.runId' "$f"
    [[ "$output" =~ ^run-[0-9]{8}T[0-9]{6}Z-[0-9a-f]+$ ]]
    cd "$TEST_DIR"
  done
}

# ─── (h) runId 스탬핑 + 실행 간 격리 ───

@test "record-decision: progress의 runId를 레코드에 박는다" {
  run_gate init --template full-auto "test" "req"
  local rid
  rid=$(jq -r '.runId' .claude-full-auto-progress.json)
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --what "runId 스탬핑 확인" --why "$WHY_OK"
  run jq -r '.runId' .claude/acl-decisions.jsonl
  [ "$output" = "$rid" ]
}

@test "record-decision --list: 기본은 이번 run만, --all은 전부 보여준다" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --what "이전 run 결정" --why "$WHY_OK"

  # 새 run 시작 (init 재실행 → 새 runId 발급)
  rm -f .claude-full-auto-progress.json
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --what "이번 run 결정" --why "$WHY_OK"

  run run_gate record-decision --list --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"이번 run 결정"* ]]
  [[ "$output" != *"이전 run 결정"* ]]

  run run_gate record-decision --list --all --progress-file .claude-full-auto-progress.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"이번 run 결정"* ]]
  [[ "$output" == *"이전 run 결정"* ]]
}

# ─── (d) handoff-update --decision 하위호환 의미론 (치환이 아니라 append) ───

@test "handoff-update --decision: 반복 호출해도 기존 항목을 덮어쓰지 않는다" {
  run_gate init --template full-auto "test" "req"
  run_gate handoff-update --progress-file .claude-full-auto-progress.json \
    --next-steps "n1" --decision "결정 A"
  run_gate handoff-update --progress-file .claude-full-auto-progress.json \
    --next-steps "n2" --decision "결정 B"

  run jq -r '.handoff.keyDecisions | length' .claude-full-auto-progress.json
  [ "$output" = "2" ]
  run jq -r '.handoff.keyDecisions | join("|")' .claude-full-auto-progress.json
  [ "$output" = "결정 A|결정 B" ]
}

@test "handoff-update --decision: 결정 로그에는 남지 않고 NOTE로 record-decision을 안내한다" {
  run_gate init --template full-auto "test" "req"
  run run_gate handoff-update --progress-file .claude-full-auto-progress.json \
    --next-steps "n" --decision "요약만"
  [ "$status" -eq 0 ]
  [[ "$output" == *"record-decision"* ]]
  [ ! -f .claude/acl-decisions.jsonl ]
}

# ─── (f) assumption-review --count 교차 검증 ───

@test "assumption-review: confirmed --count가 interview 결정 기록 수와 다르면 거부" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope interview --source provenance --what "가정 1 승인" --why "$WHY_OK"

  run run_gate assumption-review --progress-file .claude-full-auto-progress.json \
    --status confirmed --count 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"실제 결정 기록 1건"* ]]
  run jq -r '.assumptionReview.status // "missing"' .claude-full-auto-progress.json
  [ "$output" = "missing" ]
}

@test "assumption-review: interview 이외 scope의 결정은 count에 잡히지 않는다" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope implementation --what "구현 결정" --why "$WHY_OK"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json \
    --status confirmed --count 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"실제 결정 기록 0건"* ]]
}

@test "assumption-review: 이전 run의 interview 결정은 이번 run의 count를 채우지 못한다" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope interview --source provenance --what "이전 run 가정" --why "$WHY_OK"

  rm -f .claude-full-auto-progress.json
  run_gate init --template full-auto "test" "req"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json \
    --status confirmed --count 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"실제 결정 기록 0건"* ]]
}

@test "assumption-review: count가 일치하면 교차 검증 결과를 출력하고 통과" {
  run_gate init --template full-auto "test" "req"
  run_gate record-decision --progress-file .claude-full-auto-progress.json \
    --scope interview --source provenance --what "가정 1 승인" --why "$WHY_OK"
  run run_gate assumption-review --progress-file .claude-full-auto-progress.json \
    --status confirmed --count 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"교차 검증"* ]]
  run jq -r '.assumptionReview.count' .claude-full-auto-progress.json
  [ "$output" = "1" ]
}
