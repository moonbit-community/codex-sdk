struct Task {
  label : String
  prompt : String
}

async fn run_task(codex : @codex.Codex, task : Task) -> String {
  let thread = codex.start_thread()
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
