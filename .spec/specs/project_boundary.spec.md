# Project and Source Access Boundary

The authorization boundary shared by repository development, fixture intake,
and a deployed server instance.

## Intent

Keep development isolated from existing applications while allowing a user to
deliberately configure one supported VFP project root for a deployed process.

```spec-meta
id: vfp_mcp.project_boundary
kind: policy
status: active
summary: Explicit-root confinement and isolation rules for VFP source access.
surface:
  - AGENTS.md
  - docs/architecture.md
  - docs/research/fixture-intake-investigation.md
  - docs/testing/fixture-authoring-checklist.md
  - docs/contracts/milestone-0.md
  - lib/vfp_mcp/development/isolation_policy.ex
  - test/vfp_mcp/development/isolation_policy_test.exs
  - test/test_helper.exs
  - scripts/intake-fixtures.ps1
decisions:
  - vfp_mcp.source_access_boundary
  - vfp_mcp.versioned_capability_rollout
```

## Requirements

```spec-requirements
- id: vfp_mcp.boundary.development_isolation
  statement: Repository development and automated tests shall not modify, format, compile, build, execute, or run tools against the original LecoWin2 or SBT source trees.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.fixture_intake
  statement: Fixture intake may read and minimally copy authorized VFP source pairs only into an isolated repository or approved temporary location, and committed fixtures shall be synthetic or sanitized of proprietary and identifying content.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.explicit_root
  statement: A deployed process shall access a VFP project only after the user explicitly supplies one project root at launch.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.canonical_confinement
  statement: Every discovered or requested path shall be canonicalized and rejected when it escapes the configured root through traversal, absolute paths, links, or case-insensitive aliasing.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.source_pairs_only
  statement: Root authorization shall extend only to supported SCX/SCT and VCX/VCT source pairs and shall exclude databases, tables, connections, executables, deployments, and backups.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.read_only_start
  statement: Every deployed server shall start in read-only mode unless write mode is explicitly configured and all mutation safeguards are available.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.one_version_per_process
  statement: One process shall serve one configured root and one declared VFP compatibility target of either 6 or 9.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.external_classloc
  statement: A CLASSLOC that resolves outside the configured root shall be reported as an external reference and shall not be followed.
  priority: must
  stability: stable

- id: vfp_mcp.boundary.no_vfp_execution
  statement: The server shall never execute or compile VFP source or automate the Visual FoxPro IDE.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.boundary.reject_escape
  given:
    - a server has one canonical configured project root
  when:
    - a request resolves outside that root by any path representation
  then:
    - the request fails before the target is opened
  covers:
    - vfp_mcp.boundary.canonical_confinement

- id: vfp_mcp.boundary.explicit_deployment_authorization
  given:
    - an original LecoWin2 or SBT source tree exists on the machine
  when:
    - the user deliberately supplies that tree as the deployed server root
  then:
    - only supported source pairs under that root are readable and the process still starts read-only
  covers:
    - vfp_mcp.boundary.explicit_root
    - vfp_mcp.boundary.source_pairs_only
    - vfp_mcp.boundary.read_only_start

- id: vfp_mcp.boundary.safe_fixture_intake
  given:
    - a minimum source pair is selected from an authorized original tree
  when:
    - it is copied for format investigation
  then:
    - inspection occurs only on the isolated copy and the raw copy is neither committed nor executed
  covers:
    - vfp_mcp.boundary.development_isolation
    - vfp_mcp.boundary.fixture_intake
    - vfp_mcp.boundary.no_vfp_execution
```

## Verification

```spec-verification
- kind: guide_file
  target: AGENTS.md
  covers:
    - vfp_mcp.boundary.development_isolation
    - vfp_mcp.boundary.fixture_intake
    - vfp_mcp.boundary.explicit_root
    - vfp_mcp.boundary.source_pairs_only
    - vfp_mcp.boundary.read_only_start
    - vfp_mcp.boundary.no_vfp_execution
    - vfp_mcp.boundary.explicit_deployment_authorization
    - vfp_mcp.boundary.safe_fixture_intake

- kind: guide_file
  target: docs/architecture.md
  covers:
    - vfp_mcp.boundary.canonical_confinement
    - vfp_mcp.boundary.one_version_per_process
    - vfp_mcp.boundary.external_classloc
    - vfp_mcp.boundary.reject_escape

- kind: guide_file
  target: docs/research/fixture-intake-investigation.md
  covers:
    - vfp_mcp.boundary.safe_fixture_intake

- kind: guide_file
  target: docs/testing/fixture-authoring-checklist.md
  covers:
    - vfp_mcp.boundary.fixture_intake

- kind: source_file
  target: lib/vfp_mcp/development/isolation_policy.ex
  covers:
    - vfp_mcp.boundary.development_isolation
    - vfp_mcp.boundary.no_vfp_execution

- kind: test_file
  target: test/vfp_mcp/development/isolation_policy_test.exs
  covers:
    - vfp_mcp.boundary.development_isolation
    - vfp_mcp.boundary.no_vfp_execution
```
