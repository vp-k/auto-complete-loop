# Auto Complete Loop

AI coding completion framework. Built-in Ralph Loop + DoD/SPEC/TDD/Fresh Context Verification to ensure AI finishes the job.

## Installation

```bash
claude plugins install /path/to/auto-complete-loop
```

## Quick Start

```bash
# Build a full project from one sentence (solo - no codex/gemini needed)
/full-auto-solo Make a community site with auth, posts, and comments

# Build with codex code review (requires codex-cli)
/full-auto Make a todo app with categories and due dates

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
| **3-Way** | codex-cli + gemini-cli | Strongest - 3 independent AI perspectives |

### Command Matrix

| Feature | Solo | 2-Way (codex) | 3-Way (codex+gemini) |
|---------|------|--------------|---------------------|
| **Full project** | `/full-auto-solo` | `/full-auto` | `/full-auto-teams` |
| **Code review** | `/code-review-loop-solo` | `/code-review-loop` | `/code-review-loop-gemini` |
| **Planning docs** | `/plan-docs-auto-solo` | `/plan-docs-auto` | `/plan-docs-auto-gemini` |
| **Release polish** | `/polish-for-release-solo` | `/polish-for-release` | `/polish-for-release-gemini` |

### How Solo Mode Works

Claude plays multiple roles by **explicitly switching perspectives** per pass:

**Code Review (3-pass sequential)**:
```
Pass 1 [Security + Error Expert]   SEC, ERR only
Pass 2 [Data + Performance Expert] DATA, PERF only
Pass 3 [SPEC Compliance Expert]    IMPL, CODE only
```
Each pass reads the code fresh with a single focused lens. Prevents perspective contamination.

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

### "Prepare for user interviews"
```bash
/interview-prep docs/overview.md
```

### "Analyze completed project"
```bash
/post-analysis
/post-analysis --only metrics
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
| `/code-review-loop-gemini [opts] <scope>` | 3-way: codex + gemini |
| `/code-review-loop-solo [opts] <scope>` | Claude 3-pass multi-perspective |

Options: `--rounds N` (default 3), `--goal "condition"`, `--interactive`

### Planning
| Command | Description |
|---------|-------------|
| `/plan-docs-auto <def> <docs>` | Doc refinement with codex debate |
| `/plan-docs-auto-gemini <def> <docs>` | 3-way: codex + gemini + Claude |
| `/plan-docs-auto-solo <def> <docs>` | Claude self-debate (writer vs. critic) |

### Release
| Command | Description |
|---------|-------------|
| `/polish-for-release [def] [docs]` | Pre-release polish with codex |
| `/polish-for-release-gemini [def] [docs]` | 3-way advisory |
| `/polish-for-release-solo [def] [docs]` | Claude dual-role (executor + verifier) |

### Utilities
| Command | Description |
|---------|-------------|
| `/check-docs [dir]` | Doc consistency check |
| `/add-e2e [dir]` | Add E2E tests from docs or code analysis |
| `/interview-prep <path>` | Generate interview scripts (The Mom Test) |
| `/interview-summary <file>` | Extract patterns from interview transcripts |
| `/post-analysis [--only X]` | Metrics / Retrospective / Launch / Competitive |

## Architecture

### Full-Auto Pipeline (5 Phases)

```
Phase 0: PM Planning      User approval (only interaction point)
    |  API list, data models, key flows, page list
    v
Phase 1: Doc Planning     Document refinement + smoke script generation
    |  SPEC.md, tests/api-smoke.sh
    |  Hard gate: smoke scripts must exist
    v
Phase 2: Implementation   TDD coding + per-document depth check
    |  implementation-depth after each document
    v
Phase 3: Code Review      Multi-perspective (codex / solo 3-pass)
    |  IMPL: STUB/SCHEMA/MISSING/HARDCODE/FLOW
    v
Phase 4: Verification     All quality gates + Launch Readiness
```

### Quality Gates (14)

| Gate | Type | Catches |
|------|------|---------|
| `quality-gate` | HARD | Build/typecheck/lint/test failures |
| `implementation-depth` | SOFT | Stub functions, empty bodies |
| `test-quality` | SOFT | Empty/skipped tests, low assertion coverage |
| `functional-flow` | SOFT | Smoke script failures |
| `page-render-check` | SOFT | Blank pages, console errors, 404s |
| `smoke-check` | SOFT/HARD | Server startup failures, empty responses |
| `e2e-gate` | SOFT/HARD | E2E test failures |
| `secret-scan` | HARD | Leaked credentials |
| `vuln-scan` | HARD | Dependency vulnerabilities |
| `placeholder-check` | HARD | TODO/FIXME left in code |
| `external-service-check` | HARD | Missing SDK/config for declared services |
| `service-test-check` | HARD | No backend tests |
| `integration-smoke` | HARD | Frontend cannot reach backend |
| `design-polish-gate` | SOFT | WCAG accessibility violations |

### Core Mechanisms

**Ralph Loop**: Stop Hook blocks session exit until all conditions met. Prevents false completion.

**Gate History**: Every gate execution recorded. 3 consecutive same-gate failures trigger warning.

**Error Escalation (L0-L5)**: Immediate fix, different method, codex analysis, different approach, scope reduction, user intervention.

**IMPL Code Review**: Reviews code against SPEC.md (STUB/SCHEMA/MISSING/HARDCODE/FLOW).
