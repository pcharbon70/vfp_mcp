# Repository Instructions

## Project isolation

This repository is an independent Visual FoxPro MCP project. It is not part of
LecoWin2 or SBT. Development and automated testing must not operate on either
original application in place. The finished MCP server is intended to support
those projects when a user deliberately configures one as its project root.

### Development boundary

- While building or testing this repository, agents and automated tests must not
  modify, format, compile, build, execute, or run tools against either original
  LecoWin2 or SBT source tree.
- Development reads and edits must use isolated copies inside this repository or
  an explicitly approved temporary location.
- This restriction applies to development activity in this repository; it does
  not require the product to reject LecoWin2 or SBT as a user-configured root.

### Deployed server boundary

- The finished server may serve an original LecoWin2 or SBT project only when a
  user explicitly supplies that root at launch.
- The server must start read-only. Writes require explicit write-mode
  configuration plus all required hash preconditions, backup, validation,
  journaling, and rollback protections.
- Configuring a source root authorizes access only to supported Visual FoxPro
  source pairs under that root. It does not authorize access to application
  data, databases, connections, executables, deployments, or backups.

### Authorized fixture sources

- LecoWin2 Visual FoxPro 9 source and `..\sbt\source` Visual FoxPro 6 source may
  be read and copied only to create isolated fixtures for this repository.
- Treat both original source trees as strictly read-only during fixture intake.
  Never modify, rename, delete, format, compile, build, execute, or test files in
  either original tree as part of repository development.
- Never open, query, copy, lock, modify, or otherwise access the actual data
  tables, databases, connections, executables, deployments, or backups used by
  LecoWin2 or SBT.
- Never run a copied form until all database, table, connection, and external
  path references have been identified and removed or redirected to synthetic
  data owned by this repository.
- Copy only the minimum form and class-library source pairs required for a test.
  Do not bulk-copy either application or use either full source tree as a live
  test corpus.
- Store fixture copies inside this repository or an explicitly approved
  temporary location. All edits and automated tests must operate only on those
  isolated copies.
- Before committing a fixture, sanitize proprietary business logic, credentials,
  personal or customer information, environment-specific paths, and identifying
  application content. Prefer purpose-built synthetic fixtures whenever they
  cover the required format behavior.
- If safe isolation or sanitization cannot be established without touching
  shared data or modifying an original tree, stop and ask the user rather than
  proceeding.
