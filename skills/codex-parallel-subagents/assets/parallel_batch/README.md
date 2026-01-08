# Parallel Batch Example

Production-ready parallel batch processing with offset/limit support for reentrant runs.

## Run

```bash
moon run -C skills/codex-parallel-subagents/assets/parallel_batch skills/codex-parallel-subagents/assets/parallel_batch
```

With offset and limit for resumable runs:
```bash
moon run -C skills/codex-parallel-subagents/assets/parallel_batch skills/codex-parallel-subagents/assets/parallel_batch -- --offset 2 --limit 2
```

## Features

- **Offset/limit**: Skip tasks or limit batch size for resumable runs
- **Progress logging**: Logs `[n/total] OK/FAIL: label` to stderr
- **Error handling**: Captures per-task errors without crashing the batch
- **Ordered output**: Results sorted by original task index
- **Summary**: Reports succeeded/failed counts at end

## Environment variables

- `CODEX_WORKDIR` - Working directory for Codex (default: `.`)
- `PARALLELISM` - Max concurrent tasks (default: `2`)

## Example output

```
Processing 4 tasks (offset=0, parallelism=2)
[1/4] OK: Alpha
[2/4] OK: Beta
[3/4] OK: Gamma
[4/4] OK: Delta
== Results ==
# Alpha
...

Completed: 4 succeeded, 0 failed
```
