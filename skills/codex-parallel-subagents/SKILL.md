---
name: codex-parallel-subagents
description: Run multiple Codex agent threads in parallel or batch. Use when you need concurrent execution, fan-out patterns, parallel batch processing, multiple agents, bounded concurrency, streaming events, or structured outputs with the Codex SDK.
---

# Codex Parallel Subagents

Run multiple Codex SDK threads concurrently with bounded parallelism and collect results safely.

## When to use this skill

- Running multiple agent tasks in parallel
- Fan-out work across files, packages, or repositories
- Batch processing with rate limiting
- Streaming progress from concurrent tasks
- Collecting structured outputs from multiple agents

## Quick navigation

| Need | Resource |
|------|----------|
| New to Codex SDK | [references/codex-basics.md](references/codex-basics.md) |
| Advanced options | [references/codex-advanced.md](references/codex-advanced.md) |
| Async patterns | [references/async-basics.md](references/async-basics.md) |
| New repo setup | [references/greenfield-setup.md](references/greenfield-setup.md) |
| Troubleshooting | [references/troubleshooting.md](references/troubleshooting.md) |

## Assets

Production-ready examples in `assets/`:

| Asset | Description |
|-------|-------------|
| `parallel_batch` | Reentrant batch processing with offset/limit and progress logging |
| `package_analyzer` | Discover and summarize all MoonBit packages in a project |

Run with:
```bash
moon run -C <asset_path> <asset_path>
```

## Quick start: one subagent

```moonbit
async fn run_once(prompt : String, workdir : String) -> String {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(working_directory=workdir),
  )
  let turn = thread.run(prompt) catch { e => @error.reraise(e) }
  turn.final_response
}
```

## Parallel fan-out with bounded concurrency

```moonbit
async fn run_batch(tasks : Array[String], workdir : String, parallelism : Int) {
  let codex = @codex.Codex::new()
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(parallelism)
    for task in tasks {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(working_directory=workdir),
        )
        let _ = thread.run(task) catch { e => @stdio.stderr.write("\{e}\n") }
      })
    }
  })
}
```

## Key rules

1. **One thread per task** - never share threads across concurrent tasks
2. **Use semaphores** - guard parallel runs with `@semaphore.Semaphore` to avoid rate limits
3. **Set working directory** - use `ThreadOptions::new(working_directory=...)` for task isolation
4. **Allow failures** - use `allow_failure=true` and capture errors per task
