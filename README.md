# Auto Complete Loop

[한국어](README.ko.md)

AI coding completion framework. Built-in Ralph Loop + DoD/SPEC/TDD/Fresh Context Verification ensures AI completes tasks to the end.

## Installation

Install as a Claude Code plugin:
```bash
claude plugins install /path/to/auto-complete-loop
```

After installation, delete any same-named files in `~/.claude/commands/` (implement-docs-auto.md, plan-docs-auto-gemini.md, polish-for-release-gemini.md) to prevent conflicts.

## Commands

### `/implement-docs-auto <definition> <doclist>`
Implements planning documents as actual code. Ralph Loop auto-activates and iterates until completion.

### `/plan-docs-auto <definition> <doclist>`
Completes planning documents via 2-party auto-discussion (codex-cli, Claude Code).

### `/plan-docs-auto-gemini <definition> <doclist>`
Completes planning documents via 3-party auto-discussion (codex-cli, Gemini, Claude Code).

### `/polish-for-release [definition] [doclist]`
Pre-production release polishing. 2-party discussion with codex-cli and Claude Code.

### `/polish-for-release-gemini [definition] [doclist]`
Pre-production release polishing. 3-party discussion with codex-cli, Gemini, and Claude Code.

### `/code-review-loop [--rounds N | --goal "condition"] <scope>`
Automated iterative code review. codex-cli independently reviews from SEC/ERR/DATA/PERF/CODE perspectives, then Claude Code verifies/fixes.
- Default: 3 rounds of review → fix iteration
- `--rounds N`: N rounds of iteration
- `--goal "0 CRITICAL/HIGH"`: Iterate until goal met (max 10 rounds)

### `/code-review-loop-gemini [--rounds N | --goal "condition"] <scope>`
Automated iterative code review. codex-cli (SEC/ERR/DATA) + gemini-cli (PERF/CODE) 3-party independent review, then Claude Code verifies/fixes.
- Default: 3 rounds of review → fix iteration
- `--rounds N`: N rounds of iteration
- `--goal "0 CRITICAL/HIGH"`: Iterate until goal met (max 10 rounds)

### `/full-auto <requirements>`
Automated full project lifecycle.
- Phase 0: Requirements expansion + user approval (only interaction)
- Phase 1: codex discussion to complete planning docs
- Phase 2: TDD-based code implementation
- Phase 3: codex code review (3 rounds)
- Phase 4: Release verification and polishing

### `/check-docs [docs_dir]`
Document consistency verification. Validates doc↔doc consistency + doc↔code matching via scripts + AI, with auto-fix.
- Step 1: Script-based structural checks (doc-consistency + doc-code-check)
- Step 2: codex semantic validation (data models, APIs, terminology consistency)
- Step 3: Final confirmation (re-run scripts)

### `/add-e2e [docs_dir]`
Adds E2E tests to existing projects.
- With docs path: Document analysis → doc↔code consistency → scenario derivation
- Without args: Code analysis → core flow inference → regression prevention tests
- Auto framework selection: Web → Playwright, Flutter → integration_test, Mobile → Maestro

## Core Mechanisms

### Built-in Ralph Loop
- Stop Hook physically prevents session termination
- completion-promise + verification file (.claude-verification.json) prevents false completion
- Iteration-based task splitting prevents context exhaustion

### 5 Principles Integration
1. **DoD (Definition of Done)**: DONE.md template for clear completion criteria
2. **SPEC**: SPEC.md template for clear implementation criteria
3. **Ticket Splitting**: Split documents into independently verifiable tickets
4. **Fresh Context Verification**: Separate AI verifies in fresh context
5. **Handoff**: Context transfer (why/how) between iterations

## File Structure

```
auto-complete-loop/
├── .claude-plugin/plugin.json           # Plugin metadata
├── commands/
│   ├── implement-docs-auto.md           # Planning docs → code implementation
│   ├── plan-docs-auto.md               # Planning docs 2-party discussion
│   ├── plan-docs-auto-gemini.md         # Planning docs 3-party discussion (with gemini)
│   ├── polish-for-release.md            # Pre-release polishing (2-party)
│   ├── polish-for-release-gemini.md     # Pre-release polishing (3-party, with gemini)
│   ├── code-review-loop.md             # Auto iterative code review (2-party)
│   ├── code-review-loop-gemini.md       # Auto iterative code review (3-party, with gemini)
│   ├── full-auto.md                     # Plan → implement → review all-in-one
│   ├── add-e2e.md                       # Add E2E tests to existing project
│   └── check-docs.md                    # Document consistency check (doc↔doc + doc↔code)
├── hooks/
│   ├── hooks.json                       # Hook configuration
│   └── stop-hook.sh                     # Stop hook (Ralph Loop extension)
├── scripts/
│   └── shared-gate.sh                   # Universal quality gate + utilities
├── rules/shared-rules.md               # Common rules for all skills
├── templates/                           # DONE.md, SPEC.md templates
├── README.md                           # English
└── README.ko.md                        # Korean
```

## shared-gate.sh Subcommands

| Subcommand | Purpose |
|------------|---------|
| `init --template <type>` | Initialize progress JSON (full-auto/plan/implement/review/polish/e2e/doc-check) |
| `init-ralph <promise> <progress_file> [max]` | Create Ralph Loop files |
| `status` | Output current status summary |
| `update-step <step> <status>` | Step state transition (dynamic validation) |
| `quality-gate` | Run build/type/lint/test batch + record verification.json |
| `record-error --file --type --msg` | Error recurrence detection + errorHistory update |
| `check-tools` | Check codex/gemini CLI availability |
| `find-debug-code [dir]` | Find console.log/print/debugger |
| `doc-consistency [dir]` | Inter-document consistency check |
| `doc-code-check [dir]` | Document ↔ code matching |
| `e2e-gate` | E2E test framework detection + execution |

Global option: `--progress-file <path>` (auto-detected if not specified)
