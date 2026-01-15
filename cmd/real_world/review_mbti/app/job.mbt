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
pub struct Job {
  project_root : String
  output_dir : String
  concurrency : Int
  verbose : Bool
  tasks : Array[ReviewTask]
}

///|
pub async fn initalize() -> Job {
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
pub async fn Job::task_start(config : Job, idx : Int) -> Unit {
  let task = config.tasks[idx]
  let total = config.tasks.length()
  @stdio.stdout.write(
    "info [\{idx + 1}/\{total}] - Reviewing \{task.relative_path}\n",
  )
}

///|
pub async fn Job::task_input(config : Job, idx : Int) -> ReviewInput {
  let task = config.tasks[idx]
  if config.verbose {
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
pub async fn Job::task_return(
  config : Job,
  idx : Int,
  final_response : String,
) -> ReviewResult {
  let task = config.tasks[idx]
  let result = ReviewResult::{
    file: task.relative_path,
    pkg_name: task.pkg_name,
    review: final_response,
    success: true,
    error: "",
  }
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
  let status = if result.success { "✓" } else { "✗" }
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
  @stdio.stdout.write("\{status} \{result.file}\{saved_msg}\n")
  result
}

///|
pub fn Job::task_error(config : Job, idx : Int, error : Error) -> ReviewResult {
  let task = config.tasks[idx]
  error_result(task.relative_path, error.to_string())
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
