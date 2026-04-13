# Module Addition Checklist

When adding a new module (Handler, UseCase, Repository, DataSource, etc.):

1. **Package.swift** — add `.target` and `.testTarget`
2. **DependencyInjection** — add module to dependencies list + registration file
3. **Documentation updates**:
   - `AGENTS.md` — update Codex-facing summary, commands, and guardrails when the
     change affects project instructions
   - `CLAUDE.md` — update:
     - Mermaid module dependency graph — add node and edges
     - Layer Summary table — update the relevant row
     - Key Design Decisions — add entry if the module has notable design choices
     - Build & Test section — add any new CLI commands or Makefile targets
4. **README.md** — add new CLI commands to the Usage section
5. **Domain protocol** — add `TestDependencyKey` + `DependencyValues` extension
6. **StandardOutput** — add `write(_ result:)` overload if the module has a CLI result type

## Documentation Updates

- **AGENTS.md must be updated** when build/test commands, workflow rules, or
  architecture boundaries change. Keep Codex-facing instructions aligned with
  the current repository shape.
- **CLAUDE.md must be updated** when adding/removing modules, changing
  architecture, or modifying dependency graphs. Specifically check:
  - Mermaid module dependency graph
  - Layer Summary table
  - Key Design Decisions section
  - Build & Test commands
- **README.md must be updated** when adding/changing/removing CLI commands
  or configuration options. Specifically check:
  - Usage section
  - Configuration section

For Handler modules specifically:
- Entity result type (e.g., `BenchmarkReport.swift`)
- Domain protocol (e.g., `BenchmarkHandler.swift`)
- Implementation module (e.g., `BenchmarkHandler/BenchmarkHandlerImpl.swift`)
- CLI command (e.g., `CLI/Commands/BenchmarkCommand.swift`)
- Register in `RootCommand.subcommands`

## Data Type Placement

- **Pure data types (structs/enums with no logic) → Entity module**. This includes
  result types, metrics structs, config types, etc. Domain re-exports Entity via
  `@_exported import Entity`, so all layers can access them.
- **Never define data types in Domain** — Domain contains only protocols and
  DependencyKey definitions. If you need a new type for a protocol signature,
  put it in Entity first.
