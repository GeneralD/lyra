# Codex Project Files

- `AGENTS.md` is the project-wide instruction file that Codex reads for this
  repository.
- `.codex/skills/` stores repo-local skill source files derived from
  `.claude/skills/`.
- Repo-local skills are versioned here for review, but they are not
  auto-discovered from the repository itself. To enable auto-discovery, copy or
  symlink the skill folder into `${CODEX_HOME:-~/.codex}/skills/`.
- `.claude/` remains the long-form design source. Keep `AGENTS.md` in sync when
  build/test commands, architecture boundaries, or workflow rules change.
