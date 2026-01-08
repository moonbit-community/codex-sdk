# Parallel Batch

Production-ready parallel batch processor. Reads tasks from JSON, runs them through Codex in parallel, outputs results as JSON.

## Run

From file:
```bash
moon run -C skills/codex-parallel-subagents/assets/parallel_batch skills/codex-parallel-subagents/assets/parallel_batch -- --file tasks.json
```

From stdin:
```bash
echo '[{"label":"A","prompt":"Say hello"}]' | moon run -C skills/codex-parallel-subagents/assets/parallel_batch skills/codex-parallel-subagents/assets/parallel_batch
```

With offset/limit for resumable runs:
```bash
moon run -C ... ... -- --file tasks.json --offset 10 --limit 5
```

## Input format

JSON array of tasks:
```json
[
  {"label": "task-1", "prompt": "Do something"},
  {"label": "task-2", "prompt": "Do something else"}
]
```

## Output format

JSON array of results to stdout:
```json
[
  {"label": "task-1", "output": "...", "error": null},
  {"label": "task-2", "output": "...", "error": null}
]
```

Progress logged to stderr:
```
Processing 2 tasks (offset=0, parallelism=2)
[1/2] OK: task-1
[2/2] OK: task-2
Completed: 2 succeeded, 0 failed
```

## Options

| Option | Description |
|--------|-------------|
| `--file <path>` | Read tasks from JSON file (default: stdin) |
| `--offset <n>` | Skip first n tasks (default: 0) |
| `--limit <n>` | Process at most n tasks (default: all) |

## Environment variables

| Variable | Description |
|----------|-------------|
| `CODEX_WORKDIR` | Working directory for Codex (default: `.`) |
| `PARALLELISM` | Max concurrent tasks (default: `2`) |

## Customization

To use this as a template:
1. Copy this directory
2. Modify `run_task()` to customize how each task is processed
3. Adjust `TaskInput` struct if you need additional fields
