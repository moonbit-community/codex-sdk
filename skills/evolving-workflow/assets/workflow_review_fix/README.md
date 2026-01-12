# workflow_review_fix

Minimal “plan-as-code” template: review → (optional) fix → maintenance → interface review → verifications.

## What it does

- Reads a JSON array of work items from `--file` or stdin
- Supports reentrant runs with `--offset` and `--limit`
- Runs a **review** phase in `ReadOnly` sandbox mode (default)
- Runs a **fix** phase in `WorkspaceWrite` sandbox mode (default)
- Runs required maintenance steps (edit `maintenance.mbt`): `moon fmt`, `moon info`
- Reviews generated interface diffs (edit `interface_review.mbt`)
- Runs verifications (edit `verification.mbt`): defaults to `moon test`, `moon check`
- Writes a JSON result array to stdout (useful for CI/snapshots)

## Run

```bash
export CODEX_WORKDIR=.
export TASK_OFFSET=0
export TASK_LIMIT=3
moon run -C assets/workflow_review_fix assets/workflow_review_fix -- --file items.json --mode both
```

## Configuration

Environment variables are read in `config.mbt`:

- `CODEX_WORKDIR` (default `"."`)
- `TASK_OFFSET` (default `0`)
- `TASK_LIMIT` (default `-1`)

## Input format

`items.json`:

```json
[
  {
    "label": "tighten error message",
    "review": "Review error handling around X and propose minimal fix.",
    "fix": "Implement the minimal fix and keep behavior stable."
  }
]
```

## Notes

- If verifications fail, the template retries the fix phase up to `--max-iterations`.
- Adjust maintenance in `maintenance.mbt`, interface review in `interface_review.mbt`, and verifications in `verification.mbt`.
- Adjust sandboxing and prompts in `codex_steps.mbt`.
- If you want to pin the newest Codex SDK, run `moon add peter-jerry-ye/codex` in this directory after copying.
