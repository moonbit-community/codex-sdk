# Add Documentation

Generate documentation for MoonBit packages using parallel Codex agents.

## Overview

This example demonstrates **parallel fan-out execution** with the Codex SDK. Each package in a MoonBit project is processed by an independent agent running in its own git worktree.

## Workflow Pattern

```
┌─────────────┐
│  Package 1  │──▶ Agent 1 (worktree) ──▶ PR
├─────────────┤
│  Package 2  │──▶ Agent 2 (worktree) ──▶ PR
├─────────────┤
│  Package 3  │──▶ Agent 3 (worktree) ──▶ PR
└─────────────┘
     ...              (parallel)
```

Each agent:
1. Creates an isolated git worktree with a dedicated branch
2. Generates documentation for its assigned package
3. Runs `moon check` and `moon test` to validate
4. Commits and creates a pull request

## Usage

```bash
moon run cmd/real_world/add_docs -- [OPTIONS] <path>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<path>` | Path to a MoonBit project (must be a git repository) |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --parallelism <num>` | Number of parallel agents | 4 |
| `-h, --help` | Print help message | |

### Examples

```bash
# Process with default parallelism (4)
moon run cmd/real_world/add_docs -- /path/to/moonbit-core

# Process with 2 parallel agents
moon run cmd/real_world/add_docs -- -p 2 /path/to/moonbit-core
```

## How It Works

### Task Lifecycle

The `TaskHandle` struct manages each package's documentation task:

| Method | Purpose |
|--------|---------|
| `task_start(idx)` | Initialize task, log start |
| `setup()` | Create git worktree |
| `prompt()` | Return prompt (initial or retry) |
| `validate(response)` | Check for "TASK COMPLETED" |
| `finish(session_id)` | Verify with `moon check/test`, cleanup |
| `error(e)` | Log error, cleanup worktree |

### Retry Logic

Prompts are fetched inside the retry domain:
- First attempt: Full task description with MoonBit background
- Retry attempts: "Continue working" prompt

```moonbit
@async.retry(fn() {
  let prompt = handle.prompt()  // Gets appropriate prompt for attempt
  let response = thread.run(prompt)
  handle.validate(response.final_response)
  handle.finish(thread.id())
}, max_retry=3)
```

### Parallel Execution

Uses `@shared.for_all_tasks` for bounded concurrency:

```moonbit
let results = @shared.for_all_tasks(
  config.packages,
  async fn(idx, _) { ... },
  parallelism=config.parallelism,
)
```

## Project Structure

```
add_docs/
├── main.mbt           # Entry point, orchestration
├── app/
│   ├── job.mbt        # TaskHandle lifecycle
│   ├── task.mbt       # CLI parsing, git worktree helpers
│   ├── docs_agent.mbt # Prompt templates
│   ├── git.mbt        # Git operations
│   ├── package.mbt    # MoonBit package discovery
│   └── doc.mbt        # MoonBit language background
```

## Dependencies

- `@codex` - Codex SDK for AI agents
- `@async` - Task groups and retry
- `@fs` - File system operations
- `@process` - Git command execution
- `@args` - CLI argument parsing

## Key Concepts for SDK Users

1. **Isolated execution**: Each agent runs in its own worktree to avoid conflicts
2. **Bounded parallelism**: Semaphore limits concurrent API calls
3. **Retry with context**: Prompt changes based on attempt number
4. **Validation before finish**: Always verify agent output programmatically
