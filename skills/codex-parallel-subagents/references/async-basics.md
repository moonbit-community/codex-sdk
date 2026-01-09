# Async Basics for MoonBit

Common async patterns used with the Codex SDK: spawning processes, task groups, semaphores, and filesystem operations.

## Spawning processes

Use `@process.collect_output` to run shell commands:

```moonbit
async fn run_command(cmd : String, args : Array[String]) -> String {
  let (exit_code, stdout, stderr) = @process.collect_output(cmd, args)
  if exit_code != 0 {
    @error.fail("Command failed: \{stderr.text()}")
  }
  stdout.text()
}
```

With working directory:
```moonbit
let (exit_code, stdout, stderr) = @process.collect_output(
  "moon",
  ["check"],
  cwd="/path/to/project",
)
```

## Task groups

Use `@async.with_task_group` to spawn concurrent tasks:

```moonbit
async fn run_parallel(items : Array[String]) {
  @async.with_task_group(fn(task_group) {
    for item in items {
      task_group.spawn_bg(allow_failure=true, fn() {
        // Process each item concurrently
        process(item)
      })
    }
  })
}
```

Key points:
- `spawn_bg` runs tasks in the background
- `allow_failure=true` continues even if a task fails
- Task group waits for all tasks to complete

## Semaphores for bounded concurrency

Limit parallel execution with `@async.Semaphore`:

```moonbit
async fn run_with_limit(items : Array[String], max_concurrent : Int) {
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(max_concurrent)
    for item in items {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        process(item)
      })
    }
  })
}
```

Always use `defer semaphore.release()` to ensure release even on errors.

## Filesystem operations

### Reading files

```moonbit
async fn read_file(path : String) -> String {
  @fs.read_file(path).text() catch { e => @error.reraise(e) }
}
```

### Listing directories

```moonbit
async fn list_dir(path : String) -> Array[String] {
  @fs.readdir(path, include_hidden=false) catch { _ => [] }
}
```

### Checking file type

```moonbit
async fn is_directory(path : String) -> Bool {
  @fs.kind(path) catch { _ => return false } is Directory
}
```

### Checking existence

```moonbit
async fn exists(path : String) -> Bool {
  @fs.exists(path)
}
```

## Error handling patterns

### With catch and return

```moonbit
async fn safe_read(path : String) -> String? {
  let content = @fs.read_file(path).text() catch { _ => return None }
  Some(content)
}
```

### With catch and default

```moonbit
async fn read_or_default(path : String) -> String {
  @fs.read_file(path).text() catch { _ => "" }
}
```

### Collecting errors per task

```moonbit
struct TaskResult {
  item : String
  result : String
  error : String?
}

async fn run_collecting_errors(items : Array[String]) -> Array[TaskResult] {
  let results : Array[TaskResult] = []
  @async.with_task_group(fn(task_group) {
    for item in items {
      task_group.spawn_bg(allow_failure=true, fn() {
        let result = process(item) catch {
          e => {
            results.push({ item, result: "", error: Some("\{e}") })
            return
          }
        }
        results.push({ item, result, error: None })
      })
    }
  })
  results
}
```

## Required imports

```json
{
  "import": [
    "moonbitlang/async",
    "moonbitlang/async/process",
    "moonbitlang/async/fs",
    "moonbitlang/async/stdio"
  ]
}
```

Note: `@async.Semaphore` is available directly from the `moonbitlang/async` package.
