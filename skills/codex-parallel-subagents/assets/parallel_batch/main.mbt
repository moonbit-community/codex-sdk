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
struct TaskInput {
  label : String
  prompt : String
} derive(FromJson)

///|
/// Parse command line arguments
fn parse_args(args : Array[String]) -> (Int, Int, String?) {
  let mut offset = 0
  let mut limit = -1
  let mut file : String? = None
  loop args[:] {
    ["--offset", val, .. rest] => {
      offset = @strconv.parse_int(val) catch { _ => 0 }
      continue rest
    }
    ["--limit", val, .. rest] => {
      limit = @strconv.parse_int(val) catch { _ => -1 }
      continue rest
    }
    ["--file", val, .. rest] => {
      file = Some(val)
      continue rest
    }
    [_, .. rest] => continue rest
    [] => break
  }
  (offset, limit, file)
}

///|
/// Read tasks from JSON file or stdin
async fn read_tasks(file : String?) -> Array[Task] raise Error {
  let content = match file {
    Some(path) => @fs.read_file(path).text() catch { e => raise e }
    None => @stdio.stdin.read_all().text()
  }
  let json = @json.parse(content) catch { e => raise e }
  guard json is Array(items) else {
    raise @builtin.Failure("Expected JSON array of tasks")
  }
  let tasks : Array[Task] = []
  for i, item in items {
    let input : TaskInput = @json.from_json(item) catch { e => raise e }
    tasks.push({ index: i, label: input.label, prompt: input.prompt })
  }
  tasks
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
/// Escape string for JSON output
fn escape_json(s : String) -> String {
  let result = StringBuilder::new()
  for c in s {
    match c {
      '\\' => result.write_string("\\\\")
      '"' => result.write_string("\\\"")
      '\n' => result.write_string("\\n")
      '\r' => result.write_string("\\r")
      '\t' => result.write_string("\\t")
      _ => result.write_char(c)
    }
  }
  result.to_string()
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
  let (offset, limit, file) = parse_args(args)
  let workdir = env.get("CODEX_WORKDIR").unwrap_or(".")
  let parallelism_str = env.get("PARALLELISM").unwrap_or("2")
  let parallelism = @strconv.parse_int(parallelism_str) catch { _ => 2 }

  // Read tasks from file or stdin
  let all_tasks = read_tasks(file) catch {
    e => {
      @stdio.stderr.write("Error reading tasks: \{e}\n")
      return
    }
  }
  if all_tasks.is_empty() {
    @stdio.stderr.write("No tasks provided\n")
    return
  }

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
      "No tasks in range (offset=\{offset}, limit=\{limit}, total=\{all_tasks.length()})\n",
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
    let semaphore = @async.Semaphore::new(parallelism)
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

  // Output results to stdout as JSON
  @stdio.stdout.write("[\n")
  for i, result in results {
    let error_json = match result.error {
      Some(e) => "\"" + escape_json(e) + "\""
      None => "null"
    }
    let output_escaped = escape_json(result.output)
    let json = "  {\"label\": \"\{result.label}\", \"output\": \"\{output_escaped}\", \"error\": \{error_json}}"
    if i < results.length() - 1 {
      @stdio.stdout.write(json + ",\n")
    } else {
      @stdio.stdout.write(json + "\n")
    }
  }
  @stdio.stdout.write("]\n")

  // Summary to stderr
  let failed = results.filter(fn(r) { r.error is Some(_) }).length()
  let succeeded = results.length() - failed
  @stdio.stderr.write("Completed: \{succeeded} succeeded, \{failed} failed\n")
}
