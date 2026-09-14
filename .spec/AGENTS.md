# `.spec` Agent Guide

Use this folder to maintain authored Spec Led Development subjects and generated state.

<!-- covers: spec.workspace.agents_present spec.workspace.agent_prime_context spec.workspace.planning_agent_guidance -->

## First Read

1. Read `.spec/README.md`.
2. Read `.spec/decisions/README.md` and any ADRs that affect the subject you are changing.
3. Read the current `.spec/specs/*.spec.md` files before editing.
4. If the task implements a milestone, read `.spec/planning/README.md`, the
   milestone stream `README.md`, and the active phase document.

## Working Rules

- Keep one subject per file.
- Put normative statements in `spec-requirements`.
- Add `spec-scenarios` only when `given` / `when` / `then` improves clarity.
- Add `spec-meta.decisions` only when a subject depends on a durable cross-cutting ADR.
- Keep ADRs in `.spec/decisions/*.md` for cross-cutting policy only.
- Treat `specs/` as current truth and `planning/` as intended work; a planning
  checkbox is never behavioral verification.
- Keep milestone directories and phase files zero-padded and stable after they
  are published.
- Every phase, section, task, and subtask must begin with a description.
- End every phase with a numbered integration-test section. Only completion
  evidence and connections may follow that section.
- Link tasks to applicable requirement IDs for traceability, but add verification
  to subject specs only when reproducible evidence exists.
- Start new plans with `Status: Planned` and unchecked completion items.
- Prefer targeted command verifications for behavioral proof.
- Use file-backed verifications only when the target can carry stable `covers:` markers for every covered id.
- Keep verification targets repository-root-relative.
- Use Git history and pull requests as the change log; keep `.spec` current-state only.
- At session start, run `mix spec.prime --base HEAD`.
- After code, docs, or tests change, run `mix spec.next`.
- For bug fixes, prefer `mix spec.next --bugfix`.
- If next says `needs subject updates`, update the named subject before you finish.
- If next says `ready for check`, move to `mix spec.check --base ...`.
- Use `mix spec.validate --debug` when you need low-level verifier output.
- Run `mix spec.status` when you need coverage or weak-spot summaries.
