---
name: bump-version
description: >
  Bump the project version in version.txt following semver, commit, and optionally push.
  Use this skill when the user says "bump version", "version上げて", "リリース準備",
  "patch bump", "minor bump", "major bump", or before/after creating a PR that includes
  meaningful changes. Also trigger when the user says "バージョン" in a development context.
---

# Bump Version

Increment the project version following Semantic Versioning, commit, and report.

## Input

Optional: `major`, `minor`, or `patch`. If omitted, auto-detect from recent changes.

## Version File

The single source of truth is `Sources/VersionHandler/Resources/version.txt` — a plain text file containing only a semver string (e.g., `2.2.1`). If the project uses a different path, search for `version.txt` or a file containing a semver pattern.

## Procedure

### 1. Read current version

Read `version.txt` and parse `MAJOR.MINOR.PATCH`.

### 2. Determine bump level

If the user specified `major`, `minor`, or `patch`, use that.

Otherwise, auto-detect by analyzing commits since the last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

**Decision criteria:**

| Level | Condition | Examples |
|-------|-----------|---------|
| **major** | Breaking changes to public API, config format, or CLI interface | Renamed commands, removed config keys, changed default behavior |
| **minor** | New features, new commands, new config options | `feat:` commits, new modules, new CLI subcommands |
| **patch** | Bug fixes, refactoring, docs, chore, performance | `fix:`, `refactor:`, `docs:`, `chore:`, `perf:` commits |

Rules:
- If ANY commit is breaking → major
- Else if ANY commit adds a feature → minor
- Else → patch
- Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`) as primary signals
- If no conventional prefixes, read commit messages to judge intent

### 3. Bump

Apply the increment:
- `major`: `X.Y.Z` → `X+1.0.0`
- `minor`: `X.Y.Z` → `X.Y+1.0`
- `patch`: `X.Y.Z` → `X.Y.Z+1`

Write the new version to `version.txt`.

### 4. Commit

```bash
git add <version-file>
git commit -m "chore: bump version to X.Y.Z"
```

### 5. Report

Print: `Bumped X.Y.Z → A.B.C (level)`

If auto-detected, briefly explain why (e.g., "minor: feat commits found").
