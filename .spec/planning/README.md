# `.spec/planning`

This directory contains phased implementation plans for the architecture
milestones. Plans translate current specifications and decisions into ordered,
testable work without asserting that the work is already implemented.

<!-- covers: spec.workspace.planning_index_present spec.workspace.planning_conventions -->

## Milestone Index

| Milestone | Planning stream | Status |
|---|---|---|
| 0 — Codec and acceptance spike | [00-codec-and-acceptance-spike](00-codec-and-acceptance-spike/README.md) | In progress |
| 1 — Read-only MCP server | Not yet created | Not planned |
| 2 — Guarded property and code edits | Not yet created | Not planned |
| 3 — Structural editing | Not yet created | Not planned |

Directory numbers correspond to the milestone numbers in
[the architecture](../../docs/architecture.md#3-milestones). Creating a plan
does not change a milestone's architectural definition or completion gate.

## Planning Contract

- Use one zero-padded directory per milestone: `NN-short-name`.
- Give every stream a `README.md` that records its purpose, governing contract,
  scope, dependencies, phase index, dependency graph, status rules, and overall
  completion gate.
- Use stable, zero-padded phase filenames: `phase-NN-short-name.md`.
- Number phase content as `Section N.M`, `Task N.M.K`, and
  `Subtask N.M.K.L`.
- Begin every phase, section, task, and subtask with a description of intent and
  boundaries.
- Give every task and subtask an unchecked completion item when first planned.
- Make `Phase N Integration Tests` the phase's final numbered section.
- After integration tests, allow only `Phase N Completion Evidence` and
  `Connections` sections.
- Link implementation work to existing SpecLed requirement IDs, scenarios, and
  ADRs. Traceability is not verification.
- Do not add completion evidence until the referenced implementation and proof
  exist in the repository or in an admitted, hash-bound native evidence bundle.
- Preserve published identifiers even when work moves; document supersession
  instead of renumbering completed or active items.

## Status and Evidence

New phases and checklist items begin as `Planned` and unchecked. A phase may be
marked complete only when every task, subtask, integration test, and explicit
completion gate has reproducible evidence. Compilation, placeholders, a happy
path, or self-reparse alone do not satisfy a phase gate.

Plans are not part of the SpecLed verification graph. When implemented behavior
changes current truth, update the governing subject under `../specs/` and attach
the real command, test, source, or native evidence there.
