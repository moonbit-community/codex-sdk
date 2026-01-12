---
name: evolving-workflow
description: Write auditable, trackable, and repeatable workflows as MoonBit code using the MoonBit Codex SDK. Turn plans into runnable programs that can be reviewed, committed, and improved over time.
---

# Evolving Workflow (Plan-as-Code)

Encode "plans" as runnable MoonBit programs using the Codex SDK. Replace plan text with plan code that humans can audit, version in git, and iterate on.

## When to Use

- You need a repeatable workflow (same inputs → same steps)
- You want explicit capability choices per phase (read-only review vs write-enabled fixes)
- You need state persistence across runs (SQLite tracking)
- You want to start small and expand (offset/limit batching)

## Templates

| Template | Description |
|----------|-------------|
| [code_review_bot](assets/code_review_bot) | Review code in a repo, generate markdown reports, optionally setup worktrees for AI |
| [pr_review_bot](assets/pr_review_bot) | Review GitHub PRs, post comments, track state in SQLite to avoid duplicates |

## Creating Your Own

1. Copy a template
2. Modify `tasks.mbt` to identify your target items
3. Modify `process.mbt` to change the AI prompt and verification
4. Adjust `config.mbt` for new settings

See each template's README for details.
