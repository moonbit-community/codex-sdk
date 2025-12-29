# Full Running Examples (Copy/Paste)

These examples are self-contained. For each one:
- Create a new MoonBit module or use an existing one.
- Paste the files exactly as shown.
- Run `moon run .`.

All examples assume the Codex CLI is installed and configured, and `MODEL`
is set if you want a specific model.

## Example 1: Single prompt (minimal)

Files to create:

`moon.mod.json`
```json
{
  "name": "codex_single",
  "version": "0.1.0",
  "preferred-target": "native"
}
```

`moon.pkg.json`
```json
{
  "is-main": true,
  "import": [
    "peter-jerry-ye/codex",
    "moonbitlang/async",
    "moonbitlang/async/stdio",
    "moonbitlang/x/sys"
  ]
}
```

`main.mbt`
```moonbit
async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )
  let turn = thread.run("Write a 2-sentence summary of MoonBit.") catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("\{turn.final_response}\n")
}
```

## Example 2: Parallel batch with bounded concurrency

Files to create:

`moon.mod.json`
```json
{
  "name": "codex_batch",
  "version": "0.1.0",
  "preferred-target": "native"
}
```

`moon.pkg.json`
```json
{
  "is-main": true,
  "import": [
    "peter-jerry-ye/codex",
    "moonbitlang/async",
    "moonbitlang/async/semaphore",
    "moonbitlang/async/stdio",
    "moonbitlang/x/sys"
  ]
}
```

`main.mbt`
```moonbit
struct Task {
  label : String
  prompt : String
}

async fn run_task(codex : @codex.Codex, task : Task) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )
  let turn = thread.run(task.prompt) catch {
    e => return "error: \{e}"
  }
  return "# \{task.label}\n\{turn.final_response}\n"
}

async fn main {
  let tasks : Array[Task] = [
    { label: "Alpha", prompt: "Give 3 ideas for a CLI tool." },
    { label: "Beta", prompt: "Summarize async/await in 2 sentences." },
    { label: "Gamma", prompt: "Write a haiku about compilers." },
    { label: "Delta", prompt: "List 4 MoonBit features." }
  ]
  let codex = @codex.Codex::new()
  let results : Array[String] = []
  let parallelism = 2
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(parallelism)
    for task in tasks {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let output = run_task(codex, task) catch {
          e => "error: \{e}"
        }
        results.push(output)
      })
    }
  })
  for item in results {
    @stdio.stdout.write("\{item}\n")
  }
}
```

## Example 3: Streaming events with progress

Files to create:

`moon.mod.json`
```json
{
  "name": "codex_stream",
  "version": "0.1.0",
  "preferred-target": "native"
}
```

`moon.pkg.json`
```json
{
  "is-main": true,
  "import": [
    "peter-jerry-ye/codex",
    "moonbitlang/async",
    "moonbitlang/async/stdio"
  ]
}
```

`main.mbt`
```moonbit
async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(),
  )
  let streamed = thread.run_streamed("Give a short plan for refactoring a CLI.")
  while streamed.events.next() is Some(event) {
    match event {
      ItemCompleted(item) => @stdio.stdout.write("completed: \{item}\n")
      TurnCompleted(_) => @stdio.stdout.write("turn completed\n")
      _ => ()
    }
  }
}
```
