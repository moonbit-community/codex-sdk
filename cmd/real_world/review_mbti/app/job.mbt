///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
pub struct ReviewTask {
  file_path : String
  relative_path : String
  pkg_name : String
}

///|
pub enum TaskStatus {
  Running
  Validated
  ValidationFailed(String)
  Completed
} derive(Show)

///|
pub struct TaskHandle {
  task : ReviewTask
  config : Job
  idx : Int
  mut status : TaskStatus
  mut response : String
}

///|
pub struct Job {
  project_root : String
  output_dir : String
  concurrency : Int
  verbose : Bool
  tasks : Array[ReviewTask]
}

///|
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => apply_env_overrides(arguments)
  }
  let files_to_review = resolve_files_to_review(arguments)
  let tasks = []
  for file_path in files_to_review {
    let relative_path = if file_path.has_prefix(arguments.path) {
      try! file_path[arguments.path.length() + 1:].to_string()
    } else {
      file_path
    }
    let pkg_name = extract_package_name_from_file(file_path) catch {
      _ => "unknown"
    }
    tasks.push(ReviewTask::{ file_path, relative_path, pkg_name })
  }
  Job::{
    project_root: arguments.path,
    output_dir: output_dir(arguments),
    concurrency: arguments.concurrency,
    verbose: arguments.verbose,
    tasks,
  }
}

///|
/// Creates a TaskHandle for the given task index and logs the start.
/// The handle tracks status through the retry domain.
pub async fn Job::task_start(config : Job, idx : Int) -> TaskHandle {
  let task = config.tasks[idx]
  let total = config.tasks.length()
  @stdio.stdout.write(
    "info [\{idx + 1}/\{total}] - Reviewing \{task.relative_path}\n",
  )
  TaskHandle::{ task, config, idx, status: TaskStatus::Running, response: "" }
}

///|
/// Prepares the review input for this task.
pub async fn TaskHandle::input(self : TaskHandle) -> ReviewInput {
  let task = self.task
  if self.config.verbose {
    @stdio.stdout.write("Reviewing: \{task.relative_path}\n")
  }
  let content = @fs.read_file(task.file_path).text() catch {
    e => @error.reraise(e)
  }
  let prompt =
    $|Review this MoonBit package interface file (\{task.relative_path}):
    $|
    $|```moonbit
    $|\{content}
    $|```
    $|
    $|Please provide:
    $|1. A brief assessment of the API design
    $|2. Any potential issues or inconsistencies
    $|3. Suggestions for improvement (if any)
    $|
    $|Keep the review concise and focused on the public API surface.
  ReviewInput::{
    file: task.relative_path,
    relative_path: task.relative_path,
    pkg_name: task.pkg_name,
    prompt,
  }
}

///|
pub suberror ValidationError {
  EmptyResponse
} derive(Show)

///|
/// Validates the response from the model.
/// Raises ValidationError on failure so retry can catch it.
/// Updates internal status to Validated on success.
pub fn TaskHandle::validate(
  self : TaskHandle,
  response : String,
) -> Unit raise ValidationError {
  self.response = response
  // Basic validation: check if response is non-empty
  if response.trim(char_set=" \t\n\r").is_empty() {
    self.status = TaskStatus::ValidationFailed("Empty response from model")
    raise ValidationError::EmptyResponse
  }
  self.status = TaskStatus::Validated
}

///|
/// Finalizes the task based on validation status.
/// Should be called after validate(). Returns the final ReviewResult.
pub async fn TaskHandle::finish(self : TaskHandle) -> ReviewResult {
  let task = self.task
  let config = self.config
  let result = match self.status {
    TaskStatus::Validated =>
      ReviewResult::{
        file: task.relative_path,
        pkg_name: task.pkg_name,
        review: self.response,
        success: true,
        error: "",
      }
    TaskStatus::ValidationFailed(err) =>
      ReviewResult::{
        file: task.relative_path,
        pkg_name: task.pkg_name,
        review: "",
        success: false,
        error: err,
      }
    status =>
      ReviewResult::{
        file: task.relative_path,
        pkg_name: task.pkg_name,
        review: "",
        success: false,
        error: "Unexpected status: \{status}",
      }
  }
  self.status = TaskStatus::Completed
  let output_path = if result.success {
    save_review_to_file(result, config.output_dir) catch {
      e => {
        @stdio.stderr.write("Failed to save review for \{result.file}:\n\{e}\n")
        None
      }
    }
  } else {
    None
  }
  let status_icon = if result.success { "✓" } else { "✗" }
  let saved_msg = match output_path {
    Some(path) => {
      let rel_path = if path.has_prefix(config.project_root) {
        try! path[config.project_root.length() + 1:].to_string()
      } else {
        path
      }
      " → \{rel_path}"
    }
    None => ""
  }
  @stdio.stdout.write("\{status_icon} \{result.file}\{saved_msg}\n")
  result
}

///|
/// Creates an error result for a task that failed before validation.
pub fn TaskHandle::error(self : TaskHandle, error : Error) -> ReviewResult {
  error_result(self.task.relative_path, error.to_string())
}

///|
pub async fn Job::summarize(
  config : Job,
  results : Array[ReviewResult],
) -> Unit {
  if results.is_empty() {
    @stdio.stdout.write("No files to review. Exiting.\n")
    return
  }
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { !r.success })
  let rel_output_dir = summary_output_dir(
    config.output_dir,
    config.project_root,
  )
  @stdio.stdout.write(
    (
      $|
      $|\{"=".repeat(80)}
      $|SUMMARY
      $|\{"=".repeat(80)}
      $|Total files \{results.length()}
      $|Successful: \{successful}
      $|Failed: \{failed.length()}
      $|Concurrency: \{config.concurrency}
      $|Output Directory: \{rel_output_dir}
      $|
    ),
  )
  if failed.length() > 0 {
    @stdio.stdout.write("\n❌ Failed reviews:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.file}: \{f.error}\n")
    }
  }
  @stdio.stdout.write("\n💾 Reviews saved to: \{config.output_dir}\n")
}

///|
fn apply_env_overrides(arguments : Arguments) -> Arguments {
  let env = @sys.get_env_vars()
  if env.get("REVIEW_MBTI_CONCURRENCY") is Some(value) {
    arguments.concurrency = @strconv.parse_int(value) catch {
      _ => arguments.concurrency
    }
  }
  if env.get("REVIEW_MBTI_OUTPUT") is Some(value) {
    arguments.output = value
  }
  if env.get("REVIEW_MBTI_VERBOSE") is Some(value) {
    arguments.verbose = parse_env_bool(value).unwrap_or(arguments.verbose)
  }
  if env.get("REVIEW_MBTI_CHANGED") is Some(value) {
    arguments.changed = parse_env_bool(value).unwrap_or(arguments.changed)
  }
  if env.get("REVIEW_MBTI_FILES") is Some(value) && arguments.files.is_empty() {
    arguments.files = value
      .split(",")
      .map(fn(s) { s.trim(char_set=" \\t\\n\\r").to_string() })
      .collect()
  }
  arguments
}

///|
fn parse_env_bool(value : String) -> Bool? {
  let v = value.trim(char_set=" \\t\\n\\r").to_string().to_lower()
  if v == "1" || v == "true" || v == "yes" || v == "on" {
    Some(true)
  } else if v == "0" || v == "false" || v == "no" || v == "off" {
    Some(false)
  } else {
    None
  }
}

///|
async fn extract_package_name_from_file(file_path : String) -> String {
  let content = @fs.read_file(file_path).text()
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    if trimmed.has_prefix("package") {
      let parts = trimmed.split("\"").collect()
      if parts.length() >= 2 {
        return parts[1].to_string()
      }
    }
  }
  "unknown"
}
