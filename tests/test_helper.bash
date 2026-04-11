# test_helper.bash — BATS 테스트 공통 setup/teardown

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

# 모든 모듈을 source
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/server.sh"
for _f in "$SCRIPT_DIR/gates/"*.sh; do
  [[ -f "$_f" ]] && source "$_f"
done
unset _f

# 테스트 전: 임시 디렉토리 생성
setup_temp_dir() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
}

# 테스트 후: 임시 디렉토리 정리
teardown_temp_dir() {
  cd /
  rm -rf "$TEST_DIR"
}

# progress 파일 경로를 shared-gate.sh 인터페이스로 실행
run_gate() {
  bash "$SCRIPT_DIR/shared-gate.sh" "$@"
}
