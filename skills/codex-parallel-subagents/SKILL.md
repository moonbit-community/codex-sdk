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
| Async patterns | [references/async-basics.md](references/async-basics.md) |
| New repo from scratch | [references/greenfield-setup.md](references/greenfield-setup.md) |
| Troubleshooting | [references/troubleshooting.md](references/troubleshooting.md) |
| Runnable examples | `assets/` directory (run with `moon run .`) |

## Quick start: one subagent

Create a Codex client, start a thread, run a prompt, and read the final response.

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

Create one thread per task and guard execution with a semaphore.

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

## Batch jobs with per-task state

Create a task record that includes inputs, output paths, and optional session IDs. Store `thread.id()` after a run to audit or resume later.

```moonbit
struct Job {
  prompt : String
  output_path : String
  session_id : String?
}
```

## Streaming events when you need progress

Use `Thread::run_streamed` to consume events as the agent works and update progress in real time.

```moonbit
async fn run_streamed(prompt : String, workdir : String) {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(working_directory=workdir),
  )
  let streamed = thread.run_streamed(prompt)
  while streamed.events.next() is Some(event) {
    match event {
      ItemCompleted(item) => @stdio.stdout.write("completed: \{item}\n")
      TurnCompleted(_) => @stdio.stdout.write("turn completed\n")
      _ => ()
    }
  }
}
```

## Structured outputs for batch post-processing

Ask Codex for JSON and parse `turn.final_response` into a known shape. Prefer `TurnOptions::new(output_schema=...)` when strict output is required.

## Key rules

1. **One thread per task** - never share threads across concurrent tasks
2. **Use semaphores** - guard parallel runs with `@semaphore.Semaphore` to avoid rate limits
3. **Set working directory** - use `ThreadOptions::new(working_directory=...)` for task isolation
4. **Allow failures** - use `allow_failure=true` and capture errors per task
