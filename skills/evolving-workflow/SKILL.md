---
name: evolving-workflow
description: Write auditable, trackable, and repeatable workflows as MoonBit code using the MoonBit Codex SDK. Use when Agent should turn a planning process into a runnable program (plan-as-code), enforce user-defined verifications, and choose explicit sandbox/approval settings per phase.
---

# Evolving Workflow (Plan-as-Code)

Use MoonBit + the MoonBit Codex SDK to encode “plans” as runnable workflow programs that can be reviewed, committed, rerun, and improved over time.

## Why this skill exists

- Replace "plan text" with "plan code" that humans can audit and version in git.
- Make workflows repeatable (same inputs → same steps) and evolvable (iterate on the workflow itself).
- Use explicit capability choices per phase (e.g. review is read-only; fixing is write-enabled).
- Start small on a subset of inputs, then expand to full runs.

## Quick navigation

| Need | Resource |
|------|----------|
| Find and explore the SDK API | [references/sdk-discovery.md](references/sdk-discovery.md) |
| Copy-paste templates | [assets/workflow_review_fix](assets/workflow_review_fix) |

## Templates (copy + run)

| Template | What it demonstrates | Run |
|----------|----------------------|-----|
| [workflow_review_fix](assets/workflow_review_fix) | Review/fix phases, explicit sandbox/approval settings, maintenance (`moon fmt/info`), interface review, and verifications (`moon test/check`) | `moon run -C assets/workflow_review_fix assets/workflow_review_fix` |
| [docs_parallel_update](assets/docs_parallel_update) | Parallel doc updates with bounded concurrency, then maintenance + verifications, with optional interface diff review | `moon run -C assets/docs_parallel_update assets/docs_parallel_update` |

## Usage pattern (recommended)

1. Copy an `assets/` template into your repo (commit it early).
2. Encode the workflow as MoonBit code: inputs, phases, verifications, outputs.
3. Keep the early feedback loop tight: run with `--offset` and `--limit`.
4. Expand to full runs once the workflow is stable.
5. Iterate by code review: tune prompts, checks, and capability boundaries.

## Best practices to keep

- Use `TASK_OFFSET` / `TASK_LIMIT` for reentrant runs and safe rollout.
- Separate phases by capability (review ≠ fix).
- Fail closed: if a verification fails, stop or retry explicitly.
- Emit machine-readable results (JSON) for CI and audit trails.
