.PHONY: test test-utils test-admin test-progress lint help

test:
	bats tests/

test-utils:
	bats tests/utils.bats

test-admin:
	bats tests/admin.bats

test-progress:
	bats tests/progress.bats

lint:
	@command -v shellcheck >/dev/null 2>&1 && shellcheck scripts/shared-gate.sh scripts/lib/*.sh scripts/gates/*.sh || echo "shellcheck not installed — run 'apt install shellcheck' or 'brew install shellcheck'"

help:
	@echo "Available targets:"
	@echo "  test          — Run all BATS tests"
	@echo "  test-utils    — Run utils tests only"
	@echo "  test-admin    — Run admin tests only"
	@echo "  test-progress — Run progress tests only"
	@echo "  lint          — Run shellcheck on all scripts"
	@echo "  help          — Show this help"
