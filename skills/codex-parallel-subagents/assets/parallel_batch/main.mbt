///|
struct Task {
  index : Int
  label : String
  prompt : String
}

///|
struct TaskResult {
  index : Int
  label : String
  output : String
  error : String?
}

///|
/// Parse command line arguments for offset and limit
fn parse_args(args : Array[String]) -> (Int, Int) {
  let mut offset = 0
  let mut limit = -1 // -1 means no limit
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--offset" && i + 1 < args.length() {
      offset = @strconv.parse_int(args[i + 1]) catch { _ => 0 }
      i = i + 2
    } else if arg == "--limit" && i + 1 < args.length() {
      limit = @strconv.parse_int(args[i + 1]) catch { _ => -1 }
      i = i + 2
    } else {
      i = i + 1
    }
  }
  (offset, limit)
}

///|
/// Log progress to stderr
async fn log_progress(
  completed : Int,
  total : Int,
  label : String,
  success : Bool,
) -> Unit {
  let status = if success { "OK" } else { "FAIL" }
  @stdio.stderr.write("[\{completed}/\{total}] \{status}: \{label}\n")
}

///|
async fn run_task(
  codex : @codex.Codex,
  task : Task,
  workdir : String,
) -> TaskResult {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
    ),
  )
  let turn = thread.run(task.prompt) catch {
    e =>
      return {
        index: task.index,
        label: task.label,
        output: "",
        error: Some("\{e}"),
      }
  }
  {
    index: task.index,
    label: task.label,
    output: turn.final_response,
    error: None,
  }
}

///|
async fn main {
  let env = @sys.get_env_vars()
  let args = @sys.get_cli_args()
  let (offset, limit) = parse_args(args)
  let workdir = env.get("CODEX_WORKDIR").unwrap_or(".")
  let parallelism_str = env.get("PARALLELISM").unwrap_or("2")
  let parallelism = @strconv.parse_int(parallelism_str) catch { _ => 2 }

  // Define all tasks
  let all_tasks : Array[Task] = [
    { index: 0, label: "Alpha", prompt: "Give 3 ideas for a CLI tool." },
    { index: 1, label: "Beta", prompt: "Summarize async/await in 2 sentences." },
    { index: 2, label: "Gamma", prompt: "Write a haiku about compilers." },
    { index: 3, label: "Delta", prompt: "List 4 MoonBit features." },
  ]

  // Apply offset and limit for reentrant runs
  let end_index = if limit < 0 {
    all_tasks.length()
  } else {
    let sum = offset + limit
    if sum < all_tasks.length() {
      sum
    } else {
      all_tasks.length()
    }
  }
  let tasks : Array[Task] = []
  for i in offset..<end_index {
    tasks.push(all_tasks[i])
  }
  if tasks.is_empty() {
    @stdio.stderr.write(
      "No tasks to process (offset=\{offset}, limit=\{limit}, total=\{all_tasks.length()})\n",
    )
    return
  }
  @stdio.stderr.write(
    "Processing \{tasks.length()} tasks (offset=\{offset}, parallelism=\{parallelism})\n",
  )
  let codex = @codex.Codex::new()
  let results : Array[TaskResult] = []
  let completed = @ref.new(0)
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(parallelism)
    for task in tasks {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let result = run_task(codex, task, workdir) catch {
          e =>
            {
              index: task.index,
              label: task.label,
              output: "",
              error: Some("\{e}"),
            }
        }
        results.push(result)
        completed.update(fn(n) { n + 1 })
        let success = result.error is None
        log_progress(completed.val, tasks.length(), task.label, success)
      })
    }
  })

  // Sort results by original index
  results.sort_by_key(fn(r) { r.index })

  // Output results to stdout
  @stdio.stdout.write("== Results ==\n")
  for result in results {
    match result.error {
      Some(e) => @stdio.stdout.write("# \{result.label} [ERROR]\n\{e}\n\n")
      None => @stdio.stdout.write("# \{result.label}\n\{result.output}\n\n")
    }
  }

  // Summary
  let failed = results.filter(fn(r) { r.error is Some(_) }).length()
  let succeeded = results.length() - failed
  @stdio.stderr.write("Completed: \{succeeded} succeeded, \{failed} failed\n")
}
