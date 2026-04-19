#!/usr/bin/env bash
# shared-gate.sh — 모든 auto-complete-loop 스킬용 범용 품질 게이트 + 유틸리티
# 토큰 절약: Claude가 직접 하면 토큰 소비되는 반복 작업을 스크립트로 대체
#
# 모듈 구조:
#   lib/utils.sh      — 공통 유틸리티 (config_get, die, jq_inplace 등)
#   lib/progress.sh   — Progress 파일 관리, 스키마 마이그레이션, 게이트 이력
#   lib/server.sh     — 서버 시작/중지/헬스체크 유틸리티
#   gates/admin.sh    — 초기화, 상태 관리, 에러 추적, 체크포인트 등
#   gates/quality.sh  — 빌드/타입체크/린트/테스트 품질 게이트
#   gates/security.sh — 취약점/시크릿/플레이스홀더 검사
#   gates/smoke.sh    — 서버 기동, 통합 스모크, 기능 흐름 검증
#   gates/docs.sh     — 문서 일관성, 문서↔코드, 스펙 완전성
#   gates/test.sh     — E2E, 구현 깊이, 테스트 품질
#   gates/design.sh   — 디자인 폴리시(WCAG), 페이지 렌더링
#
# 서브커맨드:
#   init [--template <type>] [project] [requirement]  - progress JSON 초기화
#   init-ralph <promise> <progress_file> [max_iter]    - Ralph Loop 파일 생성
#   status [--progress-file <path>]                    - 현재 상태 요약 출력
#   update-step <step_name> <status> [--progress-file] - 단계 상태 전이
#   quality-gate [--progress-file <path>]              - 빌드/타입/린트/테스트 일괄 실행
#   e2e-gate [--progress-file <path>]                  - E2E 테스트 프레임워크 감지/실행
#   vuln-scan [--progress-file <path>]                  - 의존성 취약점 자동 검사 (언어별 감지)
#   secret-scan                                        - 시크릿 유출 스캔 (HARD_FAIL)
#   artifact-check                                     - 빌드 아티팩트 존재/크기 검증
#   smoke-check [--strict] [port] [timeout]             - 서버 기동 + 헬스체크 + 엔드포인트 검증 (--strict: FAIL 승격)
#   record-error --file <f> --type <t> --msg <m> [--level L0-L5] [--action "..."] - 에러 기록 + 에스컬레이션
#   check-tools                                         - codex/gemini CLI 존재 확인
#   find-debug-code [dir]                              - console.log/print/debugger 탐색
#   doc-consistency [docs_dir]                         - 문서 간 일관성 검사
#   doc-code-check [docs_dir]                          - 문서↔코드 매칭
#   design-polish-gate [--strict]                       - WCAG 체크 + 스크린샷 캡처 (--strict: FAIL 승격)
#   placeholder-check                                  - TODO/placeholder/FIXME 잔존 감지 (HARD_FAIL)
#   external-service-check                             - SPEC.md 기반 외부 서비스 SDK/config 존재 확인 (HARD_FAIL)
#   service-test-check                                 - 백엔드 서비스/라우트 통합 테스트 존재 확인 (HARD_FAIL)
#   integration-smoke                                  - 프론트↔백 연동 검증: API URL, CORS, 서버 기동 (HARD_FAIL)
#   implementation-depth [--threshold N] [--dir D]       - stub/빈 함수 탐지 (SOFT gate, 임계값 기반)
#   test-quality                                        - 테스트 assertion 비율/skip 비율/US 커버리지 (SOFT gate)
#   page-render-check [--port N] [--strict]             - 프론트엔드 페이지 렌더링 검증 (빈 페이지/console.error/404 탐지)
#   functional-flow                                     - 프로젝트 유형별 smoke 스크립트 실행 (api/frontend/fullstack/library)
#   recover                                            - 복구/재개 정보 자동 출력 (handoff + next steps)
#   handoff-update --next-steps <s> [--phase <p>] ...  - Handoff 필드 일괄 갱신

set -euo pipefail

# ─── 모듈 로드 ───

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/server.sh"

for _gate_file in "$SCRIPT_DIR/gates/"*.sh; do
  [[ -f "$_gate_file" ]] && source "$_gate_file"
done
unset _gate_file

# ─── 메인 디스패치 ───

main() {
  local subcmd="${1:-help}"
  shift || true

  # --progress-file를 글로벌로 파싱
  parse_progress_file_arg "$@"
  set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

  case "$subcmd" in
    init)              cmd_init "$@" ;;
    init-config)       cmd_init_config "$@" ;;
    init-ralph)        cmd_init_ralph "$@" ;;
    status)            cmd_status "$@" ;;
    update-step)       cmd_update_step "$@" ;;
    # 하위 호환: update-phase도 update-step으로 처리
    update-phase)      cmd_update_step "$@" ;;
    quality-gate)      cmd_quality_gate "$@" ;;
    vuln-scan)         cmd_vuln_scan "$@" ;;
    secret-scan)       cmd_secret_scan "$@" ;;
    artifact-check)    cmd_artifact_check "$@" ;;
    smoke-check)       cmd_smoke_check "$@" ;;
    record-error)      cmd_record_error "$@" ;;
    check-tools)       cmd_check_tools "$@" ;;
    find-debug-code)   cmd_find_debug_code "$@" ;;
    doc-consistency)   cmd_doc_consistency "$@" ;;
    doc-code-check)    cmd_doc_code_check "$@" ;;
    e2e-gate)           cmd_e2e_gate "$@" ;;
    design-polish-gate) cmd_design_polish_gate "$@" ;;
    placeholder-check)  cmd_placeholder_check "$@" ;;
    external-service-check) cmd_external_service_check "$@" ;;
    service-test-check) cmd_service_test_check "$@" ;;
    integration-smoke)  cmd_integration_smoke "$@" ;;
    implementation-depth) cmd_implementation_depth "$@" ;;
    test-quality)      cmd_test_quality "$@" ;;
    page-render-check) cmd_page_render_check "$@" ;;
    functional-flow)   cmd_functional_flow "$@" ;;
    skip-phases)       cmd_skip_phases "$@" ;;
    doc-size-check)    cmd_doc_size_check "$@" ;;
    checkpoint)        cmd_checkpoint "$@" ;;
    docker-build-check) cmd_docker_build_check "$@" ;;
    ambiguity-check)   cmd_ambiguity_check "$@" ;;
    clarification-gate) cmd_clarification_gate "$@" ;;
    spec-completeness) cmd_spec_completeness "$@" ;;
    add-dod-key)       cmd_add_dod_key "$@" ;;
    recover)           cmd_recover "$@" ;;
    handoff-update)    cmd_handoff_update "$@" ;;
    help|--help|-h)
      echo "Usage: shared-gate.sh <subcommand> [--progress-file <path>] [args]"
      echo ""
      echo "Subcommands:"
      echo "  init [--template <type>] [project] [req]  - Initialize progress JSON"
      echo "    Templates: full-auto, plan, implement, review, polish, e2e, doc-check"
      echo "  init-config                                  - Initialize .claude-auto-config.json"
      echo "  init-ralph <promise> <progress_file> [max] - Create Ralph Loop file"
      echo "  status                                     - Show current status"
      echo "  update-step <step> <status>                - Transition step state"
      echo "  quality-gate                               - Run build/type/lint/test (+ env manifest)"
      echo "  vuln-scan                                  - Dependency vulnerability scan (auto-detect)"
      echo "  secret-scan                                - Scan for hardcoded secrets (HARD_FAIL)"
      echo "  artifact-check                             - Check build artifact exists (SOFT_FAIL)"
      echo "  smoke-check [port] [timeout] [--max-retries N] [--backoff S] - Server start + healthcheck (SOFT_FAIL)"
      echo "  record-error --file <f> --type <t> --msg <m> [--level L0-L5] [--action '...']"
      echo "                                             - Record error + escalation tracking"
      echo "    --level L0-L5    Error level (L0=env, L1=build, L2=type, L3=runtime, L4=quality, L5=user)"
      echo "    --action '...'   Description of attempted fix"
      echo "    --result pass|fail  Result of the action"
      echo "    --reset-count    Reset attempt counter (on escalation level change)"
      echo "    Exit codes: 0=continue, 1=escalate, 2=codex needed, 3=user intervention"
      echo "  check-tools                                - Check codex/gemini availability"
      echo "  find-debug-code [dir]                      - Find debug code"
      echo "  doc-consistency [docs_dir]                 - Check doc consistency"
      echo "  doc-code-check [docs_dir]                  - Check doc-code matching"
      echo "  e2e-gate                                   - Run E2E tests (auto-detect framework)"
      echo "  design-polish-gate                         - WCAG check + screenshot capture (SOFT_FAIL)"
      echo "  implementation-depth [--threshold N] [--dir D] - Detect stub/empty implementations (SOFT)"
      echo "  test-quality                               - Check test assertion ratio, skip ratio, US coverage (SOFT)"
      echo "  page-render-check [--port N] [--strict]    - Playwright page render check (blank/errors/404)"
      echo "  functional-flow                            - Run project-type-specific smoke scripts (api/frontend/fullstack)"
      echo "  skip-phases <N>                              - Skip Phase 0~(N-1), start from Phase N"
      echo "  doc-size-check [docs_dir] [threshold_kb]     - Check doc sizes (default 30KB, SOFT)"
      echo "  checkpoint create|list|suggest-rollback       - Git checkpoint management"
      echo "  docker-build-check                           - Dockerfile build verification"
      echo "  ambiguity-check [docs_dir]                   - Scan for TBD/TODO/ambiguous language (SOFT)"
      echo "  clarification-gate [docs_dir]                - Block on unresolved [NEEDS-CLARIFICATION] tags (HARD_FAIL)"
      echo "  spec-completeness                            - Planning doc completeness check (HARD on CRITICAL)"
      echo "  add-dod-key <key>                          - Add DoD key dynamically (idempotent)"
      echo "  recover                                     - Show recovery info (handoff + next steps)"
      echo "  handoff-update --next-steps <s> [--phase <p>] [--completed <c>] [--warnings <w>]"
      echo "                                             - Update handoff fields atomically"
      echo ""
      echo "Global options:"
      echo "  --progress-file <path>  Specify progress file (auto-detected if omitted)"
      ;;
    *)
      die "Unknown subcommand: $subcmd. Run with 'help' for usage."
      ;;
  esac
}

main "$@"
