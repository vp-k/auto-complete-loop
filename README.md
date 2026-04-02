# Auto Complete Loop

AI coding completion framework. Built-in Ralph Loop + DoD/SPEC/TDD/Fresh Context Verification to ensure AI finishes the job.

AI 코딩 완주 프레임워크. Ralph Loop 내장 + DoD/SPEC/TDD/Fresh Context Verification으로 AI가 끝까지 완성하도록 강제합니다.

## Installation

```bash
claude plugins install /path/to/auto-complete-loop
```

After installation, remove any conflicting files in `~/.claude/commands/` with the same names.

## Commands

### `/full-auto <requirement>` (Core)
End-to-end project automation. One-line requirement to planning, implementation, code review, and verification.

- **Phase 0: PM Planning** — Problem/Persona/JTBD/Priority/Assumptions/Pre-mortem/Success Criteria + user approval
- **Phase 1: Planning** — codex discussion to complete planning docs
- **Phase 2: Implementation** — TDD-based code implementation
- **Phase 3: Code Review** — codex code review (3 rounds, IMPL category for SPEC compliance)
- **Phase 4: Verification** — Release verification + polish + Launch Readiness

### `/full-auto-teams <requirement>`
End-to-end automation with Agent Teams. 3-way parallel code review + Live Testing.

### `/implement-docs-auto <definition> <doclist>`
Implement planning docs (fully automated). Claude implements directly, codex handles review/debugging only.

### `/plan-docs-auto <definition> <doclist>`
Planning doc refinement (2-way auto-discussion). codex-cli and Claude Code debate to optimal result.

### `/plan-docs-auto-gemini <definition> <doclist>`
Planning doc refinement (3-way). codex-cli, Gemini, and Claude Code debate to optimal result.

### `/polish-for-release [definition] [doclist]`
Pre-release polish (2-way auto-discussion). codex-cli and Claude Code prepare release readiness.

### `/code-review-loop [--rounds N | --goal "condition"] <scope>`
Iterative code review. codex-cli reviews all categories (SEC/ERR/DATA/PERF/CODE/IMPL) independently.

### `/code-review-loop-gemini [--rounds N | --goal "condition"] <scope>`
3-way independent review (codex-cli + gemini-cli).

### `/check-docs [docs_dir]`
Doc consistency check. Verify doc-to-doc and doc-to-code alignment with scripts + AI auto-fix.

### `/add-e2e [docs_dir]`
Add E2E tests to existing projects. Auto-generate scenarios from docs or code analysis.

### `/interview-prep <overview.md path>`
User interview preparation. Auto-generate persona-based interview scripts using The Mom Test principles.

### `/interview-summary <transcript>`
Interview transcript analysis. Extract patterns and derive requirements from user interview records.

### `/post-analysis [--only metrics|retro|launch|competitive]`
Post-project analysis. Run Metrics/Retrospective/Launch/Competitive analysis sequentially.

## Architecture

### Orchestrator + Phase Skill Separation

```
commands/full-auto.md        (Orchestrator — owns Ralph Loop, phase transitions, progress JSON, promise tags)
    └── Loads each phase skill via Read

skills/pm-planning/SKILL.md      Phase 0 — PM Planning
skills/doc-planning/SKILL.md     Phase 1 — Doc Planning
skills/implementation/SKILL.md   Phase 2 — Implementation
skills/code-review/SKILL.md      Phase 3 — Code Review
skills/verification/SKILL.md     Phase 4 — Verification + Launch Readiness
```

Standalone commands (`plan-docs-auto`, `implement-docs-auto`, `code-review-loop`) are maintained for independent use.

### Quality Gates

| Gate | Type | Description |
|------|------|-------------|
| `quality-gate` | HARD | Build/typecheck/lint/test (exit 0/1) |
| `implementation-depth` | SOFT | Detect stub/empty function bodies (threshold: 5) |
| `test-quality` | SOFT | Assertion ratio >= 70%, skip ratio <= 20%, US-* coverage |
| `functional-flow` | SOFT | Project-type-specific smoke script execution |
| `page-render-check` | SOFT | Playwright-based page render check (blank/console.error/404) |
| `secret-scan` | HARD | Credential detection |
| `smoke-check` | SOFT/HARD | Server startup + endpoint + response body validation |
| `e2e-gate` | SOFT/HARD | E2E framework detection + execution |
| `placeholder-check` | HARD | TODO/FIXME/placeholder detection |
| `design-polish-gate` | SOFT | WCAG accessibility + screenshot capture |
| `external-service-check` | HARD | SPEC-declared external service SDK/config verification |
| `service-test-check` | HARD | Backend route/service test file existence |
| `integration-smoke` | HARD | Frontend-backend integration (API URL, CORS, server) |
| `vuln-scan` | HARD | Dependency vulnerability scan |

### IMPL Code Review Category (Phase 3)
codex reviews code against SPEC.md with these sub-categories:
- **IMPL-STUB**: Empty function bodies, placeholder responses
- **IMPL-SCHEMA**: Response structure mismatch with SPEC
- **IMPL-MISSING**: Endpoints/pages defined in SPEC but not implemented
- **IMPL-HARDCODE**: Hardcoded mock data in production code
- **IMPL-FLOW**: Core user flows not actually connected

### Phase 1 → Phase 2 Transition Guards
- **Pre-mortem hard gate**: Blocking Tigers with empty mitigation block Phase 2 entry
- **Scope completeness gate**: projectScope.hasFrontend/hasBackend must have corresponding SPEC sections
- **Smoke script gate**: `tests/api-smoke.sh` or `tests/ui-smoke.spec.ts` must exist (Phase 1 output)

## Core Mechanisms

### Ralph Loop
- Stop Hook physically blocks session termination
- completion-promise + verification file prevents false completion
- Iteration-based work splitting prevents context exhaustion

### 5 Principles
1. **DoD (Definition of Done)**: DONE.md template for clear completion criteria
2. **SPEC**: SPEC.md template for clear implementation criteria
3. **Ticket splitting**: Documents split into independently verifiable tickets
4. **Fresh Context Verification**: Separate AI verifies in fresh context
5. **Handoff**: Context (why/how) transferred between iterations

## shared-gate.sh Subcommands

| Subcommand | Description |
|------------|-------------|
| `init --template <type>` | Initialize progress JSON |
| `init-ralph <promise> <file> [max]` | Create Ralph Loop file |
| `status` | Show current status (auto-migrates schema) |
| `update-step <step> <status>` | Transition step state |
| `quality-gate` | Run build/type/lint/test + record to verification.json |
| `implementation-depth` | Detect stub/empty implementations (SOFT, language-aware) |
| `test-quality` | Check assertion ratio, skip ratio, US-* coverage |
| `functional-flow` | Run project-type-specific smoke scripts |
| `page-render-check` | Playwright page render check (blank/errors/404) |
| `secret-scan` | Secret leak scan (HARD_FAIL) |
| `vuln-scan` | Dependency vulnerability scan |
| `smoke-check [--strict]` | Server startup + healthcheck + response body validation |
| `e2e-gate` | E2E test framework detection + execution |
| `design-polish-gate [--strict]` | WCAG check + screenshot capture |
| `placeholder-check` | TODO/FIXME detection (HARD_FAIL) |
| `external-service-check` | SPEC external service SDK/config (HARD_FAIL) |
| `service-test-check` | Backend test existence (HARD_FAIL) |
| `integration-smoke` | Frontend-backend integration (HARD_FAIL) |
| `record-error` | Error recording + L0-L5 escalation |
| `recover` | Recovery info (handoff + next steps) |
| `handoff-update` | Atomic handoff field update |

Global option: `--progress-file <path>` (auto-detected if omitted)
