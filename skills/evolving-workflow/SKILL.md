---
name: evolving-workflow
description: Templates for building parallel AI agent workflows in MoonBit. Includes patterns for simple fan-out processing and multi-phase orchestration with automatic retry and validation.
---

# Evolving Workflow

Templates for building parallel AI agent workflows using the Codex SDK.

## Templates

| Template | Pattern | Description |
|----------|---------|-------------|
| [parallel_tasks](assets/parallel_tasks) | Fan-out | Process items in parallel with bounded concurrency |
| [multi_phase](assets/multi_phase) | Fan-out → Sequential → Fan-out | Three-phase workflow with intermediate planning |

## Project Structure

```
your_workflow/
├── main.mbt           # Orchestration (usually unchanged)
├── moon.pkg.json
└── app/
    ├── job.mbt        # TaskHandle lifecycle (customize this)
    ├── args.mbt       # CLI parsing
    └── moon.pkg.json
```

## main.mbt: Orchestration

The main file orchestrates: initialize → spawn parallel agents → summarize results.

```moonbit
async fn main {
  let config = @app.initialize() catch { ... }
  let codex = @codex.Codex::new()

  let results = @shared.for_all_tasks(
    config.items,
    async fn(idx, _) {
      let handle = config.task_start(idx)
      try {
        let thread = codex.start_thread(...)
        @async.retry(@async.RetryMethod::Immediate, fn() {
          let prompt = handle.prompt()
          let response = thread.run(prompt)
          handle.validate(response.final_response)
          handle.finish()
        }, max_retry=3)
      } catch { e => handle.error(e) }
    },
    parallelism=config.parallelism,
  )
  config.summarize(results)
}
```

For multi-phase, the pattern chains three phases: summarize (fan-out) → plan (sequential) → process (fan-out).

## Customization

Edit `app/job.mbt` to customize:

| Function | What to change |
|----------|----------------|
| `discover_items()` | How to find targets to process |
| `read_item_content()` | What data to load for prompts |
| `prompt()` | Your task instructions |
| `validate()` | Success criteria (raise to retry) |
| `finish()` | How to save results |
