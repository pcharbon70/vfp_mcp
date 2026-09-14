---
id: vfp_mcp.source_access_boundary
status: accepted
date: 2026-09-09
affects:
  - vfp_mcp.project_boundary
  - vfp_mcp.acceptance
---

# Constrain

## Context

Visual FoxPro source can contain application paths, bindings, proprietary code,
and references to live data. Development also has read access to two existing
applications, LecoWin2 and SBT, whose source and data must not become a live test
corpus. A deployed server nevertheless needs to serve a project selected by its
user.

## Decision

Each server process is confined to one explicit, canonical project root and one
declared VFP compatibility target. That root authorizes only supported
SCX/SCT and VCX/VCT source pairs; it never authorizes databases, tables,
connections, executables, deployments, or backups. External `CLASSLOC` values
may be reported but are not followed outside the root.

Repository development and automated testing use synthetic or isolated,
sanitized fixtures. The original LecoWin2 and SBT trees remain read-only and
must never be compiled, executed, formatted, or used in place. The product may
serve either original source tree only when a user deliberately supplies it as
the deployed server root.

## Consequences

Path canonicalization and traversal checks are mandatory at every file-system
entry point. Discovery may be less convenient for projects with external class
libraries, and one process cannot span multiple projects or compatibility
targets. Fixture preparation costs more, but test activity cannot mutate or
expose live applications or their data.
