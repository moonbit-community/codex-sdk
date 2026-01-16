///|
/// Job configuration and TaskHandle lifecycle.
/// Customize this file for your specific workflow.

///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
/// Job holds the configuration for the entire workflow.
/// Customize the fields for your specific use case.
pub struct Job {
  project_root : String
  items : Array[String] // Items to process (e.g., file paths, package names)
  parallelism : Int
  output_dir : String
  verbose : Bool
}

///|
/// Initialize the job from CLI arguments.
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => apply_env_overrides(arguments)
  }
  let items = discover_items(arguments.path)
  Job::{
    project_root: arguments.path,
    items,
    parallelism: arguments.parallelism,
    output_dir: arguments.output,
    verbose: arguments.verbose,
  }
}

// =============================================================================
// TaskHandle: manages lifecycle of a single task
// =============================================================================

///|
pub struct TaskHandle {
  item : String
  config : Job
  idx : Int
  mut attempt : Int
  content : String // Cached content (read once at start)
  mut last_error : String
}

///|
/// Start a new task. Cache any data needed for the prompt here.
pub async fn Job::task_start(config : Job, idx : Int) -> TaskHandle {
  let item = config.items[idx]
  let total = config.items.length()
  if config.verbose {
    @stdio.stdout.write("info [\{idx + 1}/\{total}] - Starting: \{item}\n")
  }
  // Cache content at setup (not on retry)
  let content = read_item_content(config.project_root, item)
  TaskHandle::{
    item,
    config,
    idx,
    attempt: 0,
    content,
    last_error: "",
  }
}

///|
/// Generate the prompt for the AI.
/// First attempt: full prompt with context.
/// Retry: shorter continuation prompt with error context.
pub fn TaskHandle::prompt(self : TaskHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    // === CUSTOMIZE: Your task prompt ===
    let prompt =
      $|Analyze the following content and provide a summary.
      $|
      $|Item: \{self.item}
      $|
      $|Content:
      $|```
      $|\{self.content}
      $|```
      $|
      $|Respond with a brief analysis.
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    "\{error_context}Please complete the analysis."
  }
}

///|
pub suberror ValidationError {
  EmptyResponse
} derive(Show)

///|
/// Validate the AI response.
/// Customize validation logic for your use case.
pub fn TaskHandle::validate(
  self : TaskHandle,
  response : String,
) -> Unit raise ValidationError {
  let trimmed = response.trim(char_set=" \t\n\r").to_string()
  if trimmed.is_empty() {
    self.last_error = "Empty response"
    raise ValidationError::EmptyResponse
  }
  // === CUSTOMIZE: Add more validation as needed ===
}

///|
pub struct TaskResult {
  item : String
  success : Bool
  error : String
}

///|
pub impl Show for TaskResult with output(self, logger) {
  if self.success {
    logger.write_string("TaskResult::Success(\{self.item})")
  } else {
    logger.write_string("TaskResult::Failed(\{self.item}, \{self.error})")
  }
}

///|
/// Finish the task successfully.
pub async fn TaskHandle::finish(self : TaskHandle) -> TaskResult {
  if self.config.verbose {
    @stdio.stdout.write("info [\{self.item}] - Completed\n")
  }
  // === CUSTOMIZE: Save results, write files, etc. ===
  TaskResult::{ item: self.item, success: true, error: "" }
}

///|
/// Handle task failure.
pub async fn TaskHandle::error(self : TaskHandle, error : Error) -> TaskResult {
  @stdio.stderr.write("error [\{self.item}] - Failed: \{error}\n")
  TaskResult::{
    item: self.item,
    success: false,
    error: error.to_string(),
  }
}

///|
/// Print summary of all results.
pub async fn Job::summarize(config : Job, results : Array[TaskResult]) -> Unit {
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { not(r.success) })
  let summary =
    $|
    $|\{"=".repeat(60)}
    $|SUMMARY
    $|\{"=".repeat(60)}
    $|Total items: \{results.length()}
    $|Successful: \{successful}
    $|Failed: \{failed.length()}
    $|Parallelism: \{config.parallelism}
    $|
  @stdio.stdout.write(summary)
  if not(failed.is_empty()) {
    @stdio.stdout.write("\nFailed items:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.item}: \{f.error}\n")
    }
  }
}

// =============================================================================
// Helpers: Customize these for your use case
// =============================================================================

///|
/// Discover items to process. Customize for your workflow.
async fn discover_items(path : String) -> Array[String] {
  // === CUSTOMIZE: Return list of items to process ===
  // Example: find all .mbt files, packages, directories, etc.
  let items : Array[String] = []
  find_items_recursive(path, "", items) catch { _ => () }
  items
}

///|
async fn find_items_recursive(
  base : String,
  relative : String,
  out : Array[String],
) -> Unit raise {
  let dir = if relative.is_empty() { base } else { "\{base}/\{relative}" }
  let entries = @fs.readdir(dir, include_hidden=false)
  // Check if this directory has .mbt files
  let has_sources = entries.iter().any(fn(name) { name.has_suffix(".mbt") })
  if has_sources {
    out.push(relative)
  }
  for name in entries {
    if name == "_build" || name == "target" || name == ".mooncakes" || name == ".git" {
      continue
    }
    let rel_path = if relative.is_empty() { name } else { "\{relative}/\{name}" }
    let full_path = "\{base}/\{rel_path}"
    if @fs.kind(full_path) == Directory {
      find_items_recursive(base, rel_path, out)
    }
  }
}

///|
/// Read content for an item. Customize for your workflow.
async fn read_item_content(project_root : String, item : String) -> String {
  // === CUSTOMIZE: Read the content needed for the prompt ===
  let path = if item.is_empty() { project_root } else { "\{project_root}/\{item}" }
  // Example: read first .mbt file in directory
  let entries = @fs.readdir(path, include_hidden=false) catch { _ => return "" }
  for entry in entries {
    if entry.has_suffix(".mbt") {
      let file_path = "\{path}/\{entry}"
      return @fs.read_file(file_path).text() catch { _ => "" }
    }
  }
  ""
}
