# Auto Complete Loop

**v4.4.0**

AI coding completion framework. Built-in Ralph Loop + DoD/SPEC/TDD/Fresh Context Verification to ensure AI finishes the job — with frozen acceptance tests, fail-closed quality gates, and a lesson memory loop that turns failures into next-run conditions.

## Installation

```bash
claude plugins install /path/to/auto-complete-loop
```

## Quick Start

```bash
# Build a full project from one sentence (solo - no codex needed)
/full-auto-solo Make a community site with auth, posts, and comments

# Build with codex code review (requires codex-cli)
/full-auto Make a todo app with categories and due dates

# One-line requirement → implementation-ready planning docs + frozen acceptance tests
/plan-docs-full A web dashboard where students track daily study goals

# Review existing code (solo)
/code-review-loop-solo --rounds 3 src/

# Review with codex
/code-review-loop --rounds 3 src/
```

## 3 Modes: Choose Your Setup

Every major command comes in **3 modes**. Pick the one that matches your environment:

| Mode | External AI | Best For |
|------|------------|----------|
| **Solo** | None | No setup needed. Claude switches roles for multi-perspective analysis |
| **2-Way** | codex-cli | Stronger review - codex provides independent perspective |
| **3-Way (dual)** | codex-cli ×2 (1차+2차) | Strongest - split-dimension independent review |

### Command Matrix

| Feature | Solo | 2-Way (codex) | 3-Way (dual, codex×2) |
|---------|------|--------------|---------------------|
| **Full project** | `/full-auto-solo` | `/full-auto` | `/full-auto-teams` |
| **Code review** | `/code-review-loop-solo` | `/code-review-loop` | `/code-review-loop-dual` |
| **Planning (PM + docs + gates)** | `/plan-docs-full --mode solo` | `/plan-docs-full` | `/plan-docs-full --mode dual` (`--mode teams` for Agent Teams) |
| **Planning docs (refine only)** | `/plan-docs-auto-solo` | `/plan-docs-auto` | `/plan-docs-auto-dual` |
| **Release polish** | `/polish-for-release-solo` | `/polish-for-release` | `/polish-for-release-dual` |

### How Solo Mode Works

Claude plays multiple roles with **strictly separated perspectives**:

**Code Review (3 parallel subagents; fallback: 3-pass sequential)**:
```
Agent 1 [Security + Error Expert]   SEC, ERR only   ┐
Agent 2 [Data + Performance Expert] DATA, PERF only ├─ run in parallel
Agent 3 [SPEC Compliance Expert]    CODE, IMPL only ┘
        → main Claude merges + dedups findings
```
Each agent reads the code fresh with a single focused lens. Prevents perspective contamination. If the Agent tool is unavailable, falls back to the same split as sequential passes.

**Planning Docs (self-debate)**:
```
[Writer]  Drafts the document
[Critic]  "How would this fail in production?"
[Writer]  Addresses critique
[Critic]  Repeats until no Critical/High issues remain
```

**Release Polish (dual-role)**:
```
[Executor] Analyzes and fixes
[Verifier] "Did this fix introduce new problems?"
```

## Use Cases

### "I have an idea, make it real"
```bash
/full-auto-solo Build a recipe sharing app with user profiles, recipe CRUD, and search
```
Runs 5 phases: PM Planning, Doc Planning, Implementation, Code Review, Verification.

### "Plan first, implement later"
```bash
/plan-docs-full A habit tracker with streaks and weekly reports
```
PM Planning + Doc Planning only, with **6 strict gates** (spec-completeness, doc-completeness, doc-consistency, definition-conflict, spec-to-tests, acceptance-freeze). Output: overview.md + planning docs + SPEC.md + smoke scripts + **frozen acceptance tests** (red at this point — TDD red→green). Then run `/full-auto --start-phase 2` or `/implement-docs-auto`.

### "Review my existing codebase"
```bash
# Quick 3-round review
/code-review-loop-solo --rounds 3 src/

# Until zero critical/high issues
/code-review-loop --goal "CRITICAL/HIGH 0" src/auth/

# Interactive mode
/code-review-loop --interactive src/
```

### "I have planning docs, implement them"
```bash
/implement-docs-auto overview.md README.md
```

### "Refine my planning docs before coding"
```bash
/plan-docs-auto-solo overview.md README.md
```

### "Polish before release"
```bash
/polish-for-release-solo
```

### "Add E2E tests to existing project"
```bash
/add-e2e docs/
```

## All Commands

### Project Lifecycle
| Command | Description |
|---------|-------------|
| `/full-auto <req>` | End-to-end automation (codex review) |
| `/full-auto-teams <req>` | End-to-end with Agent Teams 3-way review + Live Testing |
| `/full-auto-solo <req>` | End-to-end with Claude multi-perspective (no external AI) |
| `/implement-docs-auto <def> <docs>` | Implement planning docs to code |

### Code Review
| Command | Description |
|---------|-------------|
| `/code-review-loop [opts] <scope>` | Iterative review with codex |
| `/code-review-loop-dual [opts] <scope>` | 3-way: codex ×2 |
| `/code-review-loop-solo [opts] <scope>` | Claude 3-pass multi-perspective |

Options: `--rounds N` (default 3), `--goal "condition"`, `--interactive`

### Planning
| Command | Description |
|---------|-------------|
| `/plan-docs-full <req>` | One-line requirement → PM Planning + Doc Planning + SPEC + smoke scripts + frozen acceptance tests, 6 strict gates (`--mode solo\|codex\|teams\|dual`) |
| `/plan-docs-auto <def> <docs>` | Doc refinement with codex debate |
| `/plan-docs-auto-dual <def> <docs>` | 3-way: codex ×2 + Claude |
| `/plan-docs-auto-solo <def> <docs>` | Claude self-debate (writer vs. critic) |

### Release
| Command | Description |
|---------|-------------|
| `/polish-for-release [def] [docs]` | Pre-release polish with codex |
| `/polish-for-release-dual [def] [docs]` | 3-way advisory |
| `/polish-for-release-solo [def] [docs]` | Claude dual-role (executor + verifier) |

### Utilities
| Command | Description |
|---------|-------------|
| `/check-docs [dir]` | Doc consistency check |
| `/add-e2e [dir]` | Add E2E tests from docs or code analysis |

> ℹ️ 제품 발견 도구(`/interview-prep`, `/interview-summary`, `/post-analysis`)는 v4.0.0에서 별도 플러그인 [product-discovery](https://github.com/vp-k/product-discovery)로 분리되었습니다.

## Architecture

### Full-Auto Pipeline (5 Phases)

```
Phase 0: PM Planning      User approval (only interaction point)
    |  API list, data models, key flows, page list
    v
Phase 1: Doc Planning     Document refinement + smoke scripts + acceptance tests
    |  SPEC.md, tests/api-smoke.sh, tests/acceptance/ (frozen, red — TDD)
    |  Hard gates: spec-completeness, clarification-gate, smoke scripts must exist
    v
Phase 2: Implementation   TDD coding + per-document depth check
    |  implementation-depth after each document
    v
Phase 3: Code Review      Multi-perspective (codex / solo 3-pass)
    |  IMPL: STUB/SCHEMA/MISSING/HARDCODE/FLOW
    |  code-review-findings gate (0-finding rounds must still be recorded)
    v
Phase 4: Verification     runtime-gate + live-testing + acceptance-gate
    |  layer-coverage + verification-auditor + Launch Readiness
```

**Phase 4 in detail**: `runtime-gate` boots the server once and runs all 3 smoke checks (smoke-check + integration-smoke + functional-flow) in a single pass. The **live-testing** skill then drives the real app (browser/curl/Maestro) as a user, auto-fixing LIVE-CRITICAL/HIGH findings; `live-testing-gate` blocks completion while any remain open. `acceptance-gate` verifies the frozen acceptance tests' hash integrity and runs them — they must be **green** now (red→green). `layer-coverage` checks that every declared layer (frontend/backend) actually exists on the filesystem, and the **verification-auditor** cross-checks test coverage against the Test Plan.

### Acceptance Freeze & Gate (TDD red→green, 3중 방어선)

Planning (Phase 1 / `/plan-docs-full`) generates executable acceptance tests from SPEC's acceptance criteria into `tests/acceptance/` (with `run.sh`), then **freezes them by hash** (`acceptance-freeze` → `tests/acceptance/.manifest.json`). At freeze time the tests are **red — that is correct** (the app doesn't exist yet). Implementation must turn them green without touching them.

Three lines of defense keep the tests honest:

1. **protect-files-guard hook** — blocks any Edit/Write to frozen `tests/acceptance/**` during implementation
2. **acceptance-gate hash integrity** — even out-of-band tampering is detected against the frozen manifest, then `run.sh` is executed for real
3. **stop-hook (fail-closed)** — full-auto requires `acceptanceTests=pass` (skip is NOT accepted — `tests/acceptance/` is mandatory); plan-docs-full requires `acceptanceFreeze=pass`. Missing key = gate never ran = no completion

Spec changed legitimately? Only via user approval → SPEC update → `acceptance-freeze --approved-by-user` re-freeze.

### Lesson Memory Loop (기억 = 다음 실행 조건)

Memory is not storage — every lesson is written as a **condition for the next run**:

- **What gets recorded** (`.claude/acl-learnings.local.md`, `## LESSON` entries with a `다음 실행 조건:` line):
  - Error escalation reaching L3+ (root-cause analysis outcomes)
  - 3-strike loop escapes (same gate failing repeatedly → failing gate + fix command recorded)
  - Successful completion (key decisions/warnings extracted from progress handoff before cleanup)
- **How it comes back**: `session-start` hook injects the most recent LESSON entries into the next session's context, so the next run starts already knowing what broke and what to do about it
- **No loops**: identical "next-run conditions" are deduplicated before append

### Quality Gates

The ~40 `shared-gate.sh` subcommands include the following user-facing gates (see "Gate Enforcement Tiers" below for what actually blocks):

| Gate | Type | Catches |
|------|------|---------|
| `quality-gate` | HARD | Build/typecheck/lint/test failures (auto-records DoD `build_pass`/`test_pass`) |
| `runtime-gate` | HARD | One server boot → runs smoke-check + integration-smoke + functional-flow together (Phase 4) |
| `smoke-check` | HARD | Server startup failures (`soft_fail` = failure; server is "up" if it answers HTTP at all — 404 counts) |
| `acceptance-freeze` | HARD | Missing/unrunnable acceptance tests at planning exit (plan-docs-full) |
| `acceptance-gate` | HARD | Tampered or red acceptance tests at verification (full-auto; skip = fail) |
| `live-testing-gate` | HARD | Open LIVE-CRITICAL/HIGH findings from real-app testing |
| `layer-coverage` | HARD | Declared frontend/backend layers missing on filesystem |
| `code-review-findings` | HARD | Open CRITICAL/HIGH review findings; review never performed |
| `spec-completeness` | HARD | Missing SPEC sections, TBDs in core sections (auto-records plan-template DoD keys) |
| `clarification-gate` | HARD | `[NEEDS-CLARIFICATION]` tags left in docs |
| `doc-completeness` | HARD | API blocks below quantitative thresholds |
| `spec-to-tests` | HARD | SPEC endpoints without smoke coverage (plan-docs-full) |
| `definition-conflict` | SOFT | Non-Goals violations (each match must be adjudicated + recorded) |
| `doc-consistency` | WARN | Model/endpoint/naming drift across docs |
| `secret-scan` | HARD | Leaked credentials |
| `vuln-scan` | SOFT | Dependency vulnerabilities |
| `placeholder-check` | HARD | TODO/FIXME left in code |
| `external-service-check` | HARD | Missing SDK/config for declared services |
| `service-test-check` | HARD | No backend tests (full-auto) |
| `e2e-gate` | HARD | E2E test failures (auto-records DoD `e2e_pass`) |
| `implementation-depth` | SOFT* | Stub functions, empty bodies |
| `test-quality` | SOFT* | Empty/skipped tests, low assertion coverage |
| `page-render-check` | SOFT | Blank pages, console errors (non-strict records `soft_fail`, never blocks) |
| `artifact-check` | SOFT | Missing build artifact (`soft_fail`, never blocks) |
| `design-polish-gate` | SOFT | WCAG accessibility violations |

\* `implementation-depth` and `test-quality` **auto-escalate SOFT→HARD after 2 consecutive fails/warns** (exit 1 until a pass; the "no tests" warn of test-quality is exempt from escalation).

### Gate Enforcement Tiers

| Tier | Enforced by | Effect on failure |
|------|-------------|-------------------|
| **훅 강제 (하드)** | stop-hook (fail-closed) + protect-files-guard | Completion (promise) impossible until fixed; frozen files can't be edited. Workflow-scoped keys: `specToTests`/`acceptanceFreeze` (plan-docs-full only), `docCodeCheck`/`serviceTestCheck`/`acceptanceTests` (full-auto only) |
| **게이트 기록 (전이 차단)** | `shared-gate.sh` subcommands | Step/Phase transition blocked; results written to `.claude-verification.json` by the script only (model must never write it directly) |
| **자문 (SOFT)** | Warnings only | Proceed allowed; fix recommended. Only `implementation-depth`/`test-quality` escalate to HARD on repeat failure |

No override (including directorOverride) can bypass the 훅-강제 tier.

**Escape hatch**: to stop the Ralph Loop manually, delete `.claude/ralph-loop.local.md` — the stop-hook stops re-launching iterations immediately.

### Core Mechanisms

**Ralph Loop**: Stop Hook blocks session exit until all conditions met. Prevents false completion. `init-ralph` defaults to **max_iterations: 30** (runaway-loop protection). On non-plugin projects (no plugin progress files), the hooks stay out of the way.

**Gate History**: Every gate execution recorded. 3 consecutive same-gate failures trigger a recorded escape (with a LESSON entry) instead of an infinite loop.

**Error Escalation (L0-L5)**: Immediate fix → different method → codex analysis + roundtable → different approach → scope reduction → user intervention. L3+ escalations feed the lesson ledger.

**IMPL Code Review**: Reviews code against SPEC.md (STUB/SCHEMA/MISSING/HARDCODE/FLOW).

**DoD 기록 주체 원칙**: every DoD key is either auto-recorded by its owning gate (e.g., plan template's 5 keys ← spec-completeness/definition-conflict, `code_review_pass` ← code-review-findings, `live_testing` ← live-testing-gate) or has an explicit documented jq instruction — the model never invents `checked: true`.
