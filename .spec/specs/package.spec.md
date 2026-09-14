# VFP MCP Package

Package-level purpose, implementation boundaries, and delivery sequence for the
independent Visual FoxPro MCP server.

```spec-meta
id: vfp_mcp.package
kind: package
status: active
summary: Elixir/OTP MCP server for safe comprehension and milestone-gated editing of VFP 6 and VFP 9 source pairs.
surface:
  - README.md
  - mix.exs
  - mix.lock
  - lib/vfp_mcp.ex
  - lib/vfp_mcp/application.ex
  - lib/vfp_mcp/milestone_0/contract.ex
  - docs/contracts/milestone-0.md
  - test/vfp_mcp/milestone_0/contract_test.exs
decisions:
  - vfp_mcp.custom_vfp_codec
  - vfp_mcp.stdio_protocol_boundary
  - vfp_mcp.versioned_capability_rollout
```

## Requirements

```spec-requirements
- id: vfp_mcp.package.independent_application
  statement: The repository shall remain an independent Elixir/OTP application named vfp_mcp and shall not be treated as part of LecoWin2 or SBT.
  priority: must
  stability: stable

- id: vfp_mcp.package.supported_sources
  statement: The package shall understand VFP 6 and VFP 9 SCX/SCT form pairs and VCX/VCT class-library pairs while preserving their source fidelity.
  priority: must
  stability: stable

- id: vfp_mcp.package.elixir_otp_runtime
  statement: The application shall target Elixir 1.20 and run under an OTP supervision tree.
  priority: must
  stability: stable

- id: vfp_mcp.package.dependency_boundaries
  statement: The package shall pin ex_mcp at 1.0.0-rc.8 behind the protocol boundary, declare Jason directly for evidence JSON, keep spec_led_ex as a development and test dependency with runtime disabled, and keep StreamData test-only.
  priority: must
  stability: stable

- id: vfp_mcp.package.milestone_delivery
  statement: Delivery shall proceed from codec and acceptance fixtures to read-only MCP tools, then guarded property and named-method edits, and finally separately accepted structural edits.
  priority: must
  stability: stable

- id: vfp_mcp.package.excluded_operations
  statement: The package shall not execute or compile VFP code, automate the VFP IDE, access application data, or initially edit MNX, FRX, LBX, or other non-form source formats.
  priority: must
  stability: stable

- id: vfp_mcp.package.phase_quality_gates
  statement: Implemented milestone phases shall expose fixed-seed quality gates that check formatting, warning-free compilation, automated tests, and strict SpecLed validation without requiring an external VFP source root.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: vfp_mcp.package.development_bootstrap
  given:
    - the Elixir and Erlang toolchain is installed
  when:
    - dependencies are fetched and the test task starts the application
  then:
    - the vfp_mcp OTP application compiles with its pinned protocol and specification dependencies
  covers:
    - vfp_mcp.package.elixir_otp_runtime
    - vfp_mcp.package.dependency_boundaries

- id: vfp_mcp.package.capability_sequence
  given:
    - a capability belongs to a later delivery milestone
  when:
    - its earlier acceptance gates are incomplete
  then:
    - that capability is not exposed as supported behavior
  covers:
    - vfp_mcp.package.milestone_delivery
    - vfp_mcp.package.excluded_operations

- id: vfp_mcp.package.run_phase_gate
  given:
    - dependencies for an implemented milestone phase are available
  when:
    - its named Mix quality gate is run from the repository root
  then:
    - the gate uses a fixed seed and verifies formatting, warning-free compilation, tests, and the SpecLed workspace without external application input
  covers:
    - vfp_mcp.package.phase_quality_gates
```

## Verification

```spec-verification
- kind: readme_file
  target: README.md
  covers:
    - vfp_mcp.package.independent_application
    - vfp_mcp.package.supported_sources
    - vfp_mcp.package.milestone_delivery
    - vfp_mcp.package.excluded_operations
    - vfp_mcp.package.capability_sequence

- kind: source_file
  target: mix.exs
  covers:
    - vfp_mcp.package.elixir_otp_runtime
    - vfp_mcp.package.dependency_boundaries
    - vfp_mcp.package.phase_quality_gates
    - vfp_mcp.package.run_phase_gate

- kind: guide_file
  target: docs/contracts/milestone-0.md
  covers:
    - vfp_mcp.package.milestone_delivery
    - vfp_mcp.package.excluded_operations
    - vfp_mcp.package.capability_sequence

- kind: source_file
  target: lib/vfp_mcp/milestone_0/contract.ex
  covers:
    - vfp_mcp.package.milestone_delivery
    - vfp_mcp.package.excluded_operations
    - vfp_mcp.package.capability_sequence

- kind: test_file
  target: test/vfp_mcp/milestone_0/contract_test.exs
  covers:
    - vfp_mcp.package.milestone_delivery
    - vfp_mcp.package.excluded_operations
    - vfp_mcp.package.capability_sequence

- kind: command
  target: 'cd "$OLDPWD" && mix test'
  execute: true
  covers:
    - vfp_mcp.package.development_bootstrap
```
