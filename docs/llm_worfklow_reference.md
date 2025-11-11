# 🧠 LLM Workflow Reference

A compact, end-to-end framework for managing projects with coding agents.  
Optimized for minimal context, clarity, and live plan evolution.

---

## ⚙️ 1. Plan Generation (from Spec)
**Input:** Per-feature `FEATURE_spec.md` — defines intent, requirements, and constraints for a single feature or slice.  

**Task:** Create a matching per-feature `FEATURE_plan.md` — the single evolving source of truth for that feature through implementation. Use a clear, consistent `FEATURE` prefix (e.g., `auth-login_plan.md`).

**Plan structure:**
- **Overview:** purpose, goals, and scope.  
- **Architecture & Design:** main components, data flow, and interfaces.  
- **Implementation Steps:** ordered, actionable milestones (each independently completable).  
- **Test Plan:** initial testing strategy (functional coverage, edge cases, validation).  
- **Inline Delta Markers:** use ✅ or `[done]` for progress tracking.

**Guidelines:**
Keep it concise, declarative, and implementation-oriented.  
No meta commentary or verbosity — the plan should read like a live roadmap.

---

## 🔄 2. Plan Update (during Implementation)
**Input:** Current per-feature `FEATURE_plan.md` and recent changes for that feature.

**Task:** Revise the plan so it accurately reflects current reality.

**Guidelines:**
- Update completion markers beside finished tasks.  
- Adjust architecture or steps to match actual implementation.  
- Remove obsolete ideas or branches.  
- Keep entries brief but clear enough for another engineer or LLM to continue seamlessly.  
- Update test plan for new behaviors or edge cases.  

The plan must always represent the *current truth*, not a log or discussion.

---

## 📘 3. Documentation Conversion (after Completion)
**Input:** Finalized per-feature `FEATURE_plan.md`.  

**Task:** Produce concise, clean developer documentation (`FEATURE_docs.md`) for that feature, suitable for README or internal wiki.

**Include:**
- Purpose and scope.  
- Architecture overview.  
- Implementation summary.  
- Testing and validation approach.  
- Completion status and future improvements.  

Keep technical tone and Markdown formatting.  
Exclude process chatter or outdated deltas unless they explain design rationale.

---

## 🧩 Micro-Format Templates

All artifacts are maintained on a per-feature basis using a consistent prefix, e.g.:
- `auth-login_spec.md`
- `auth-login_plan.md`
- `auth-login_docs.md`

Use kebab-case for `FEATURE` names unless your repo has a different convention.

### `FEATURE_spec.md` (per-feature)
Defines what and why for a single feature — stable once approved. Keep one spec per feature.

```markdown
# Spec: [Feature Name]

## Purpose
Describe the problem and intended solution.

## Requirements
- Functional:
  - [Core features]
- Non-functional:
  - [Performance, platform, or resource limits]

## Context
Dependencies, integrations, and assumptions.

## Constraints
External APIs, frameworks, or boundaries.

## Acceptance Criteria
- [Condition 1]
- [Condition 2]
````

---

### `FEATURE_plan.md` (per-feature)

The living document for a single feature — evolves throughout development.

```markdown
# Plan: [Feature Name]

## Overview
Purpose, goals, and current status.

## Architecture & Design
- Core components:
  - [Component A] — [brief description]
  - [Component B] — [brief description]
- Data flow:
  - [Summarize interactions and dependencies]

## Implementation Steps
1. [Step 1] — [done|pending]
2. [Step 2] — [done|pending]
3. [Step 3] — [done|pending]

## Test Plan
- **Functional tests:** [main cases]
- **Edge cases:** [list key boundaries]
- **Validation:** [criteria for correctness]

## Notes
Optional section for trade-offs or rationale.

✅ Use inline markers for progress and keep outdated info pruned.
```

---

### `FEATURE_docs.md` (per-feature)

Final deliverable for a single feature — polished developer documentation.

```markdown
# [Feature Name]

## Purpose
[Summarize what this does and why it exists.]

## Architecture
[Describe structure, major components, and interactions.]

## Implementation Summary
[Outline main logic and design choices.]

## Testing
[Summarize test approach and key outcomes.]

## Status
✅ Completed on [date]  
[Optional: future work or improvements]
```

---

## 🗂️ Usage Notes

- Keep this file (`llm_workflow_reference.md`) in the repo root or `/docs/`.
- Reference it once in each agent guide (`agents.md`, `CLAUDE.md`, etc.):
  
  > See `llm_workflow_reference.md` for the standard LLM planning and documentation process.

- Never embed the full text into agent configs — link only.
- Maintain per-feature artifacts:
  - One `FEATURE_spec.md` per feature (what/why).
  - One `FEATURE_plan.md` per feature — the single evolving source of truth for that feature; all other artifacts derive from it.
  - One `FEATURE_docs.md` per feature when completed.
- Use a consistent `FEATURE` prefix (kebab-case recommended), e.g.: `auth-login_spec.md`, `auth-login_plan.md`, `auth-login_docs.md`.
- spec and plan documents should be located in the `specs/` folder and the docs in the `docs/` folder.
