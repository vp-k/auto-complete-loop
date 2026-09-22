# gates/readers.sh — 범위 추출 리더(doc-section) + 상한 실행기(run-capped)
#
# 목적: "긴 파일을 통째로 읽어 컨텍스트를 채우고, compact 뒤에 같은 파일을 다시 읽는" 순환을
#       차단이 아니라 "적게 읽어도 되는 경로"를 기본값으로 만들어 없앤다.
#   - 차단은 토큰을 줄이지 못한다(400줄을 막으면 200줄씩 두 번 읽는다). 필요한 부분만 내주는
#     경로가 있어야 통째로 읽을 이유가 사라진다.
#   - 두 서브커맨드 모두 jq 없이 동작한다(이벤트 기록만 jq 의존, 없으면 조용히 생략).
#
#   doc-section [--file <path>] [--list] [--max-lines N] [--context N] <query>
#     SPEC/설계 문서에서 필요한 섹션만 출력한다. 기본 파일은 SPEC 후보(SPEC.md/docs/SPEC.md/
#     docs/api-spec.md/spec.md). --list 는 제목 지도(줄번호 + 제목)만 출력해 이후 Read 의
#     offset/limit 좌표로 쓴다. <query> 는 제목 문자열(대소문자 무시)이나 ID(US-B-003, AC-F-001-2)
#     — 제목이 맞으면 그 제목부터 같은/상위 레벨의 다음 제목 전까지, 제목이 없으면 본문 grep(-C)로
#     폴백한다. 출력은 --max-lines(기본 200)로 상한. exit 0=매치, 1=없음, 2=파일 없음.
#
#   run-capped [--tail N] [--name <slug>] [--log-dir D] [--fail-lines N] [--keep N] -- <command...>
#     테스트/빌드 명령을 실행해 전체 출력은 로그 파일(.claude/acl-logs/<UTC>-<slug>.log)에 남기고
#     컨텍스트에는 요약만 낸다: 종료코드·줄수·로그 경로, 실패 패턴 줄(기본 40줄), tail(기본 30줄).
#     명령의 종료 코드를 그대로 반환한다(&& 체인 유지). 로그는 최근 --keep(기본 20)개만 보존하고
#     디렉토리 안에 자체 .gitignore(*) 를 둬 커밋되지 않게 한다.

# ─── 공통 ───

_rd_find_spec() {
  local c
  for c in "SPEC.md" "docs/SPEC.md" "docs/api-spec.md" "spec.md"; do
    if [[ -f "$c" ]]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

_rd_is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

_rd_count_lines() { wc -l < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

# awk 제목 판정: '#'×1~6 + 공백. 구간 반복({1,6})은 awk 구현마다 지원이 갈려 쓰지 않는다.
# 코드 펜스(```) 안의 '# 주석' 줄은 제목이 아니다 — 호출부가 fence 토글과 함께 쓴다.
RD_AWK_ISHEAD='function ishead(s,  n) { if (substr(s, 1, 1) != "#") return 0; match(s, /^#+/); n = RLENGTH; return (n <= 6 && substr(s, n + 1, 1) ~ /[ 	]/) }
'


# 사용법 오류는 exit 3 — doc-section 의 결과 계약(0 매치 / 1 없음 / 2 파일 없음)과 겹치지 않게 한다
_rd_usage() { echo "ERROR: $*" >&2; exit 3; }

# ─── doc-section ───

cmd_doc_section() {
  local file="" list="false" query="" max_lines=200 ctx=3

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)      file="${2:-}"; [[ -n "$file" ]] || _rd_usage "--file requires a path"; shift 2 ;;
      --file=*)    file="${1#--file=}"; shift ;;
      --list)      list="true"; shift ;;
      --max-lines) max_lines="${2:-}"; _rd_is_uint "$max_lines" && [[ "$max_lines" -ge 1 ]] || _rd_usage "--max-lines requires a positive integer"; shift 2 ;;
      --context)   ctx="${2:-}"; _rd_is_uint "$ctx" || _rd_usage "--context requires a non-negative integer"; shift 2 ;;
      --)          shift; query="$query${query:+ }$*"; break ;;
      -*)          _rd_usage "doc-section: unknown option '$1' (usage: doc-section [--file <path>] [--list] [--max-lines N] [--context N] <query>)" ;;
      *)           query="$query${query:+ }$1"; shift ;;
    esac
  done

  if [[ -z "$file" ]]; then
    file=$(_rd_find_spec) || {
      echo "[doc-section] ERROR: no SPEC file found (SPEC.md/docs/SPEC.md/docs/api-spec.md/spec.md) — use --file <path>" >&2
      return 2
    }
  fi
  if [[ ! -f "$file" ]]; then
    echo "[doc-section] ERROR: file not found: $file" >&2
    return 2
  fi

  local total headings
  total=$(_rd_count_lines "$file")

  # --list: 제목 지도만 (줄번호: 제목). 이후 Read offset/limit 의 좌표.
  if [[ "$list" == "true" ]]; then
    headings=$(awk "$RD_AWK_ISHEAD"'
      /^```/ { fence = !fence }
      !fence && ishead($0) { print NR ": " $0 }' "$file")
    if [[ -n "$headings" ]]; then printf '%s\n' "$headings"; fi
    local hn=0
    [[ -n "$headings" ]] && hn=$(printf '%s\n' "$headings" | wc -l | tr -d ' ')
    echo "[doc-section] file=$file lines=$total headings=$hn (Read offset=<줄번호> limit=<다음 제목 줄번호-줄번호> 로 섹션만 읽는다)"
    log_event "doc.section" "$(jq -cn --arg f "$file" --arg m "list" --argjson n "$total" '{file:$f, mode:$m, lines:$n}' 2>/dev/null || echo '{}')" || true
    return 0
  fi

  [[ -n "$query" ]] || _rd_usage "doc-section: <query> required (heading text or ID such as US-B-003), or --list"

  local q_lower
  q_lower=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')

  # 1차: 제목 매치 → 섹션 본문(제목 포함) 출력. 같은/상위 레벨 제목에서 종료.
  # 매치 수는 출력된 블록 수다 — 이미 열린 섹션 안의 하위 제목(예: "### Sub of US-002")은
  # 그 섹션에 포함되어 출력되므로 별도 매치로 세지 않는다 (계수와 출력이 한 awk 에서 나온다).
  local out printed truncated matches
  out=$(awk -v q="$q_lower" -v maxl="$max_lines" "$RD_AWK_ISHEAD"'
      function lvl(s) { match(s, /^#+/); return RLENGTH }
      BEGIN { inblk = 0; printed = 0; truncated = 0; blocks = 0; fence = 0 }
      /^```/ { fence = !fence }
      !fence && ishead($0) {
        if (inblk && lvl($0) <= curlvl) { inblk = 0 }
        if (!inblk && index(tolower($0), q) > 0) {
          inblk = 1; curlvl = lvl($0); blocks++
          if (blocks > 1 && printed < maxl) { print "---"; printed++ }
        }
      }
      inblk {
        if (printed < maxl) { print NR ": " $0; printed++ } else { truncated++ }
      }
      END { printf "\001%d %d %d\n", printed, truncated, blocks }' "$file")
  # 마지막 줄(\001 printed truncated blocks)을 분리
  local stat
  stat=$(printf '%s\n' "$out" | tail -n 1 | tr -d '\001')
  read -r printed truncated matches <<< "$stat"
  [[ "$matches" =~ ^[0-9]+$ ]] || matches=0

  if [[ "$matches" -gt 0 ]]; then
    printf '%s\n' "$out" | sed '$d'
    local note=""
    if [[ "$truncated" -gt 0 ]]; then
      note=" TRUNCATED(+${truncated} lines — --max-lines 를 올리거나 --list 로 좌표를 잡아 Read offset/limit 로 읽는다)"
    fi
    echo "[doc-section] file=$file mode=heading query=\"$query\" matches=$matches lines=$printed/$total${note}"
    log_event "doc.section" "$(jq -cn --arg f "$file" --arg m "heading" --arg q "$query" --argjson k "$matches" --argjson p "$printed" --argjson n "$total" \
      '{file:$f, mode:$m, query:$q, matches:$k, lines:$p, total:$n}' 2>/dev/null || echo '{}')" || true
    return 0
  fi

  # 2차: 제목 없음 → 본문 grep -C 폴백 (상한 적용)
  local hits gout gcount
  hits=$(grep -n -i -F -- "$query" "$file" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then
    echo "[doc-section] file=$file mode=none query=\"$query\" matches=0 lines=0/$total (--list 로 제목을 확인하라)"
    log_event "doc.section" "$(jq -cn --arg f "$file" --arg m "none" --arg q "$query" --argjson n "$total" '{file:$f, mode:$m, query:$q, matches:0, total:$n}' 2>/dev/null || echo '{}')" || true
    return 1
  fi
  gcount=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
  gout=$(grep -n -i -F -C "$ctx" -- "$query" "$file" 2>/dev/null | head -n "$max_lines" || true)
  printf '%s\n' "$gout"
  local glines
  glines=$(printf '%s\n' "$gout" | wc -l | tr -d ' ')
  echo "[doc-section] file=$file mode=grep query=\"$query\" matches=$gcount lines=$glines/$total (제목 매치 없음 — 본문 검색 결과, -C $ctx)"
  log_event "doc.section" "$(jq -cn --arg f "$file" --arg m "grep" --arg q "$query" --argjson k "$gcount" --argjson p "$glines" --argjson n "$total" \
    '{file:$f, mode:$m, query:$q, matches:$k, lines:$p, total:$n}' 2>/dev/null || echo '{}')" || true
  return 0
}

# ─── run-capped ───

# 실패 패턴: 언어/러너 공통의 실패·에러 표식. 넓게 잡되 요약은 --fail-lines 로 상한.
RUN_CAPPED_FAIL_RE='(FAIL|FAILED|Failed|failed|ERROR|Error|error\[|error:|Exception|Traceback|AssertionError|not ok|panic:|✗|✘|expected .* (received|got|to))'

cmd_run_capped() {
  local tail_n=30 name="" log_dir=".claude/acl-logs" fail_max=40 keep=20 cmd=""
  local -a argv=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail)       tail_n="${2:-}"; _rd_is_uint "$tail_n" || _rd_usage "--tail requires a non-negative integer"; shift 2 ;;
      --name)       name="${2:-}"; [[ -n "$name" ]] || _rd_usage "--name requires a value"; shift 2 ;;
      --log-dir)    log_dir="${2:-}"; [[ -n "$log_dir" ]] || _rd_usage "--log-dir requires a path"; shift 2 ;;
      --fail-lines) fail_max="${2:-}"; _rd_is_uint "$fail_max" || _rd_usage "--fail-lines requires a non-negative integer"; shift 2 ;;
      --keep)       keep="${2:-}"; _rd_is_uint "$keep" && [[ "$keep" -ge 1 ]] || _rd_usage "--keep requires a positive integer"; shift 2 ;;
      --)           shift; argv=("$@"); break ;;
      -*)           _rd_usage "run-capped: unknown option '$1' (usage: run-capped [--tail N] [--name <slug>] [--log-dir D] [--fail-lines N] [--keep N] -- <command...>)" ;;
      *)            argv=("$@"); break ;;
    esac
  done
  [[ ${#argv[@]} -gt 0 ]] || _rd_usage "run-capped: command required (run-capped -- npm test)"
  # 실행 방식 (인용·글롭 보존):
  #   인자 1개 → 셸 문자열로 해석 (bash -c) : run-capped -- 'npm test 2>&1'
  #   인자 2개+ → 그대로 execv (재파싱 없음)  : run-capped -- printf '[%s]\n' "foo bar"
  # 공백 연결 후 bash -c 재파싱은 인용을 잃어 "foo bar" 가 두 인자가 되고, 글롭이 두 파일로 펼쳐지면
  # 둘째 파일이 첫 스크립트의 위치 인자로 넘어가 red 가 exit 0 으로 보고되던 결함(v4.25.0 리뷰 HIGH-1).
  local exec_mode="argv"
  [[ ${#argv[@]} -eq 1 ]] && exec_mode="shell"
  cmd="${argv[*]}"

  mkdir -p "$log_dir" || _rd_usage "run-capped: cannot create log dir: $log_dir"
  # 로그 디렉토리는 커밋 대상이 아니다 — 자체 .gitignore 로 닫는다(NG: 테스트 출력을 레포에 싣지 않는다)
  [[ -f "$log_dir/.gitignore" ]] || printf '*\n' > "$log_dir/.gitignore" 2>/dev/null || true

  local slug
  if [[ -n "$name" ]]; then
    slug="$name"
  else
    slug=$(printf '%s' "$cmd" | awk '{print $1}')
    slug=$(basename "$slug")
  fi
  slug=$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40)
  [[ -n "$slug" ]] || slug="cmd"

  local ts log
  ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%S)
  log="$log_dir/${ts}-${slug}.log"
  [[ -e "$log" ]] && log="$log_dir/${ts}-${slug}-$$-${RANDOM}.log"

  # stdin 은 닫는다 — 입력을 기다리는 러너가 출력 0줄로 멈추는 것을 막는다 (타임아웃은 두지 않는다: 러너마다 다르다)
  local ec=0
  if [[ "$exec_mode" == "shell" ]]; then
    bash -c "${argv[0]}" > "$log" 2>&1 < /dev/null || ec=$?
  else
    "${argv[@]}" > "$log" 2>&1 < /dev/null || ec=$?
  fi

  local lines bytes
  lines=$(_rd_count_lines "$log")
  bytes=$(wc -c < "$log" 2>/dev/null | tr -d ' ' || echo 0)

  local cmd_show="$cmd"
  [[ ${#cmd_show} -gt 200 ]] && cmd_show="${cmd_show:0:200}…"
  echo "[run-capped] exit=$ec lines=$lines bytes=$bytes log=$log"
  echo "[run-capped] cmd: $cmd_show"

  local fails fcount=0
  if [[ "$fail_max" -gt 0 ]]; then
    fails=$(grep -a -n -E "$RUN_CAPPED_FAIL_RE" "$log" 2>/dev/null | head -n "$fail_max" || true)
    if [[ -n "$fails" ]]; then
      fcount=$(grep -a -c -E "$RUN_CAPPED_FAIL_RE" "$log" 2>/dev/null || echo 0)
      echo "--- failure lines (showing $(printf '%s\n' "$fails" | wc -l | tr -d ' ') of $fcount) ---"
      printf '%s\n' "$fails"
    fi
  fi

  if [[ "$tail_n" -gt 0 ]]; then
    if [[ "$lines" -gt "$tail_n" ]]; then
      if [[ "$fcount" -gt 0 ]]; then
        echo "--- tail $tail_n of $lines (full output: $log — 실패 원인은 위 failure lines 로, 더 필요하면 grep -n 으로 좁혀 읽는다) ---"
      else
        echo "--- tail $tail_n of $lines (full output: $log — 더 필요하면 grep -n 으로 좁혀 읽는다) ---"
      fi
    else
      echo "--- output ($lines lines) ---"
    fi
    tail -n "$tail_n" "$log"
  fi

  # 보존: 최근 keep 개만 (오래된 순 삭제)
  local old
  old=$(ls -1t "$log_dir"/*.log 2>/dev/null | tail -n +"$((keep + 1))" || true)
  if [[ -n "$old" ]]; then
    while IFS= read -r f; do [[ -n "$f" ]] && rm -f -- "$f"; done <<< "$old"
  fi

  log_event "run.capped" "$(jq -cn --arg s "$slug" --argjson ec "$ec" --argjson l "$lines" --argjson b "$bytes" --argjson f "$fcount" --arg log "$log" \
    '{name:$s, exit:$ec, lines:$l, bytes:$b, failureLines:$f, log:$log}' 2>/dev/null || echo '{}')" || true

  return "$ec"
}
