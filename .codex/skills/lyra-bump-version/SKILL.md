---
name: lyra-bump-version
description: >
  Bump lyra's version in Sources/VersionHandler/Resources/version.txt following
  semver, commit, and optionally push. Use this skill when working in the lyra
  repo and the user says "bump version", "version上げて", "リリース準備",
  "patch bump", "minor bump", or "major bump".
---

# Lyra Bump Version

Increment lyra's version following Semantic Versioning, commit, and report.

## Scope

This skill is repo-specific. The single source of truth is
`Sources/VersionHandler/Resources/version.txt`.

## Input

Optional: `major`, `minor`, or `patch`. If omitted, auto-detect from recent
changes.

## Procedure

### 1. Read current version

Read `Sources/VersionHandler/Resources/version.txt` and parse
`MAJOR.MINOR.PATCH`.

### 2. Determine bump level

If the user specified `major`, `minor`, or `patch`, use that.

Otherwise, analyze commits since the last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Decision criteria:

- `major`: breaking changes to public API, config format, or CLI interface
- `minor`: new features, new commands, or new config options
- `patch`: fixes, refactors, docs, chore, or performance changes

Rules:

- If any commit is breaking -> `major`
- Else if any commit adds a feature -> `minor`
- Else -> `patch`
- Prefer conventional commit prefixes as the primary signal

### 3. Bump

Apply the increment:

- `major`: `X.Y.Z` -> `X+1.0.0`
- `minor`: `X.Y.Z` -> `X.Y+1.0`
- `patch`: `X.Y.Z` -> `X.Y.Z+1`

Write the new version to `Sources/VersionHandler/Resources/version.txt`.

### 4. Commit

```bash
git add Sources/VersionHandler/Resources/version.txt
git commit -m "chore: bump version to X.Y.Z"
```

### 5. Report

Print `Bumped X.Y.Z -> A.B.C (level)`.

If auto-detected, briefly explain why.
