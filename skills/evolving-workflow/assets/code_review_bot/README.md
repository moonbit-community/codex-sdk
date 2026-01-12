# Code Review Bot

Automated code review workflow that analyzes directories and generates markdown reports.

## What It Does

1. Finds directories with source files (`.mbt` by default)
2. Runs Codex in read-only mode to review each directory
3. Generates a markdown report for each target
4. Creates an index file linking all reports

## Usage

```bash
# Review all directories in a repo
CODEX_WORKDIR=/path/to/repo moon run .

# Dry run - see what would be reviewed
DRY_RUN=1 CODEX_WORKDIR=/path/to/repo moon run .

# Review with AI isolation (git worktrees)
USE_WORKTREE=1 CODEX_WORKDIR=/path/to/repo moon run .

# Test with a small batch
TASK_LIMIT=2 CODEX_WORKDIR=/path/to/repo moon run .

# Custom output directory
OUTPUT_DIR=./my-reviews CODEX_WORKDIR=/path/to/repo moon run .
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CODEX_WORKDIR` | Target repository path | `.` |
| `PARALLELISM` | Max concurrent reviews | `4` |
| `TASK_OFFSET` | Skip first N targets | `0` |
| `TASK_LIMIT` | Process at most N targets (-1 = all) | `-1` |
| `MAX_RETRY` | Retry attempts per review | `2` |
| `DRY_RUN` | List targets without reviewing | `false` |
| `USE_WORKTREE` | Use git worktree for AI isolation | `false` |
| `OUTPUT_DIR` | Directory for review reports | `./reviews` |

## Output

Reports are written to `OUTPUT_DIR`:

```
reviews/
├── INDEX.md           # Links to all reports
├── src_core.md        # Review of src/core
├── src_utils.md       # Review of src/utils
└── root.md            # Review of root directory
```

## Customization

### Change Review Targets

Edit `tasks.mbt` to change how targets are identified:

```moonbit
// Example: only review directories with test files
let has_tests = entries.iter().any(fn(name) { name.ends_with("_test.mbt") })
```

### Change Review Prompt

Edit `process.mbt` `run_review` function to change what Codex analyzes.

### Change Output Format

Edit `write_report` and `write_index` in `process.mbt` and `main.mbt`.

## File Structure

| File | Purpose |
|------|---------|
| `config.mbt` | Environment configuration |
| `tasks.mbt` | Target identification |
| `parallel.mbt` | Bounded concurrency helper |
| `process.mbt` | Review execution and report writing |
| `main.mbt` | Orchestration |
