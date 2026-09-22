#!/usr/bin/env bats
# readers.bats — 컨텍스트 절약 읽기 서브커맨드 검증 (v4.25.0)
#   doc-section: 문서에서 제목/US-ID 섹션만 추출 (긴 SPEC 통째 읽기 대체)
#   run-capped : 명령 실행 후 전체 로그는 파일에, 컨텍스트엔 종료코드·실패 줄·tail 만

load test_helper

GATE="$SCRIPT_DIR/shared-gate.sh"

setup() {
  setup_temp_dir
  mkdir -p docs
  cat > docs/SPEC.md <<'EOF'
# SPEC

## US-001: Login

- AC-F-001-1 valid credentials → 200
- AC-F-001-2 invalid → 401

```
# not a heading (inside a fence)
```

## US-002: Signup

body2

### Sub of US-002

sub body

## Other

z
EOF
}
teardown() { teardown_temp_dir; }

# ─── doc-section ───

@test "doc-section --list: prints heading map with line numbers, ignores fenced '#'" {
  run bash "$GATE" doc-section --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"3: ## US-001: Login"* ]]
  [[ "$output" == *"12: ## US-002: Signup"* ]]
  [[ "$output" == *"16: ### Sub of US-002"* ]]
  [[ "$output" != *"not a heading"* ]]
  [[ "$output" == *"headings=5"* ]]
}

@test "doc-section <US-ID>: heading match prints section up to next same/higher-level heading, with line prefixes" {
  run bash "$GATE" doc-section US-002
  [ "$status" -eq 0 ]
  [[ "$output" == *"12: ## US-002: Signup"* ]]
  [[ "$output" == *"body2"* ]]
  [[ "$output" == *"### Sub of US-002"* ]]   # deeper heading stays inside the section
  [[ "$output" != *"## Other"* ]]            # next same-level heading ends it
  [[ "$output" != *"US-001"* ]]
  [[ "$output" == *"mode=heading"* ]]
  [[ "$output" == *"matches=1"* ]]
}

@test "doc-section: case-insensitive heading match" {
  run bash "$GATE" doc-section us-001
  [ "$status" -eq 0 ]
  [[ "$output" == *"## US-001: Login"* ]]
  [[ "$output" == *"AC-F-001-2"* ]]
}

@test "doc-section: no heading match falls back to grep -C (body search), exit 0" {
  run bash "$GATE" doc-section AC-F-001-2
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC-F-001-2"* ]]
  [[ "$output" == *"mode=grep"* ]]
}

@test "doc-section: nothing matches → exit 1 with mode=none" {
  run bash "$GATE" doc-section nothing-here-at-all
  [ "$status" -eq 1 ]
  [[ "$output" == *"mode=none"* ]]
  [[ "$output" == *"matches=0"* ]]
}

@test "doc-section: missing file → exit 2" {
  run bash "$GATE" doc-section --file docs/NOPE.md US-001
  [ "$status" -eq 2 ]
}

@test "doc-section: no SPEC candidate at all → exit 2" {
  rm docs/SPEC.md
  run bash "$GATE" doc-section US-001
  [ "$status" -eq 2 ]
}

@test "doc-section --max-lines: output is capped and marked TRUNCATED" {
  { echo "# Big"; echo "## US-009: Long"; for i in $(seq 1 50); do echo "line $i"; done; echo "## End"; } > docs/big.md
  run bash "$GATE" doc-section --file docs/big.md --max-lines 10 US-009
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRUNCATED"* ]]
  [[ "$output" != *"line 40"* ]]
}

@test "doc-section: query required" {
  run bash "$GATE" doc-section
  [ "$status" -ne 0 ]
}

@test "doc-section: records doc.section event" {
  run bash "$GATE" doc-section US-001
  [ "$status" -eq 0 ]
  grep -q '"event":"doc.section"' .claude/acl-events.jsonl
}

# ─── run-capped ───

@test "run-capped: exit code propagated, full log on disk, failure lines + tail in output" {
  run bash "$GATE" run-capped --tail 3 --name t1 -- 'for i in $(seq 1 50); do echo line $i; done; echo "FAIL: boom"; exit 3'
  [ "$status" -eq 3 ]
  [[ "$output" == *"[run-capped] exit=3"* ]]
  [[ "$output" == *"51:FAIL: boom"* ]]
  [[ "$output" == *"line 50"* ]]
  [[ "$output" != *"line 10"* ]]      # capped: not the whole log
  log=$(ls .claude/acl-logs/*-t1.log)
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 51 ]
  [ -f .claude/acl-logs/.gitignore ]
}

@test "run-capped: success path exit 0, no failure block" {
  run bash "$GATE" run-capped --tail 2 -- 'echo ok1; echo ok2; echo ok3'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[run-capped] exit=0"* ]]
  [[ "$output" != *"failure lines"* ]]
  [[ "$output" == *"ok3"* ]]
}

@test "run-capped: --fail-lines caps the failure summary" {
  run bash "$GATE" run-capped --tail 0 --fail-lines 2 -- 'for i in 1 2 3 4 5; do echo "ERROR $i"; done; exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"showing 2 of 5"* ]]
  [[ "$output" != *"ERROR 5"* ]]
}

@test "run-capped: --keep retention keeps only the newest logs" {
  for i in 1 2 3 4; do bash "$GATE" run-capped --keep 2 --name k$i -- "echo $i" >/dev/null; sleep 1; done
  n=$(ls .claude/acl-logs/*.log | wc -l | tr -d ' ')
  [ "$n" -eq 2 ]
  ls .claude/acl-logs/*-k4.log
}

@test "run-capped: command required" {
  run bash "$GATE" run-capped --tail 3
  [ "$status" -ne 0 ]
}

@test "run-capped: records run.capped event with exit and lines" {
  run bash "$GATE" run-capped --name ev -- 'echo x; exit 2'
  [ "$status" -eq 2 ]
  ev=$(grep '"event":"run.capped"' .claude/acl-events.jsonl | tail -1)
  [ "$(printf '%s' "$ev" | jq -r '.exit')" = "2" ]
  [ "$(printf '%s' "$ev" | jq -r '.name')" = "ev" ]
}

@test "dispatcher: doc-section and run-capped listed in help" {
  run bash "$GATE" help
  [[ "$output" == *"doc-section"* ]]
  [[ "$output" == *"run-capped"* ]]
}

# ─── v4.25.0 리뷰 반영: argv 보존 / usage exit 3 ───

@test "run-capped: multi-arg form preserves quoting (no bash -c re-parse)" {
  run bash "$GATE" run-capped --tail 5 -- printf '[%s]\n' "foo bar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[foo bar]"* ]]
  [[ "$output" != *"[foo]"* ]]
}

@test "run-capped: two acceptance files via glob → second is NOT swallowed as an argument (exit of the named script)" {
  mkdir -p tests/acceptance
  printf '#!/usr/bin/env bash\necho first; exit 1\n' > tests/acceptance/us-x-a.sh
  printf '#!/usr/bin/env bash\necho second; exit 0\n' > tests/acceptance/us-x-b.sh
  # 글롭이 두 파일로 펼쳐지면 bash 는 첫 파일만 실행한다 — 그 exit(1) 가 그대로 보고되어야 한다 (0 으로 세탁되지 않음)
  run bash "$GATE" run-capped -- bash tests/acceptance/us-x-*.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"first"* ]]
}

@test "run-capped: single-arg form is still a shell string (pipes/&&/exit codes work)" {
  run bash "$GATE" run-capped --tail 2 -- 'echo a && echo b | tr b c; exit 5'
  [ "$status" -eq 5 ]
  [[ "$output" == *"c"* ]]
}

@test "run-capped: stdin is closed (a runner waiting on input does not hang)" {
  run bash "$GATE" run-capped --tail 2 -- 'read -r x; echo "got=[$x]"'
  [ "$status" -ne 0 ] || [[ "$output" == *"got=[]"* ]]
}

@test "doc-section/run-capped: usage errors exit 3 (distinct from doc-section 1=no match / 2=missing file)" {
  run bash "$GATE" doc-section --max-lines abc US-001
  [ "$status" -eq 3 ]
  run bash "$GATE" run-capped --tail 3
  [ "$status" -eq 3 ]
}
