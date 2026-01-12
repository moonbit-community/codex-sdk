# docs_parallel_update

Parallel “plan-as-code” template: update documentation files concurrently with bounded parallelism, then run required maintenance + verifications.

## What it does

- Discovers documentation targets under `CODEX_WORKDIR` (edit `discover.mbt`)
- Supports reentrant runs with `TASK_OFFSET` and `TASK_LIMIT`
- Updates docs in parallel using Codex threads (edit `codex_steps.mbt`)
- Runs required maintenance (edit `maintenance.mbt`): `moon fmt`, `moon info`
- Reviews interface diffs after `moon info` when in a git repo (edit `interface_review.mbt`)
- Runs verifications (edit `verification.mbt`): default `moon check`, `moon test`

## Run

```bash
export CODEX_WORKDIR=.
export PARALLELISM=3
export TASK_OFFSET=0
export TASK_LIMIT=5
moon run -C assets/docs_parallel_update assets/docs_parallel_update
```

## Configuration

Environment variables are read in `config.mbt`:

- `CODEX_WORKDIR` (default `"."`)
- `PARALLELISM` (default `3`)
- `TASK_OFFSET` (default `0`)
- `TASK_LIMIT` (default `-1`)

## Notes

- Keep each doc-update task file-scoped to avoid conflicts during parallel edits.
- If you want to pin the newest Codex SDK after copying, run `moon add peter-jerry-ye/codex` in this directory.
