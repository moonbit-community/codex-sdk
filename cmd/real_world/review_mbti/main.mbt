///|
/// CLI arguments structure
struct Arguments {
  /// Review all mbti files (default)
  mut all : Bool
  /// Only review changed files in git
  mut changed : Bool
  /// Specific files to review (comma-separated)
  mut files : Array[String]
  /// Number of concurrent reviews
  mut concurrency : Int
  /// Show detailed progress
  mut verbose : Bool
  /// Path to the project root
  mut path : String
  /// Output directory for review files
  mut output : String
} derive(Default)

///|
impl @clap.Value for Arguments with set_flag(self, name, value) {
  if name == "all" {
    self.all = value
  } else if name == "changed" {
    self.changed = value
  } else if name == "verbose" {
    self.verbose = value
  } else {
    raise @clap.ParserError::InvalidArgumentName("Invalid flag name \{name}")
  }
}

///|
impl @clap.Value for Arguments with add_value(self, name, value, positional) {
  if name == "concurrency" {
    self.concurrency = @clap.BasicValue::parse(value) catch {
      StrConvError(err) =>
        raise @clap.ParserError::InvalidArgumentValue(
          "Invalid value for \{name}: \{err}",
        )
    }
  } else if name == "files" {
    self.files = value
      .split(",")
      .map(fn(s) { s.trim(char_set=" \t\n\r").to_string() })
      .collect()
  } else if name == "output" {
    self.output = value
  } else if name == "path" && positional {
    self.path = value
  } else {
    raise @clap.ParserError::InvalidArgumentName(
      "Invalid argument name \{name}",
    )
  }
}

///|
/// Result of reviewing a single mbti file
struct ReviewResult {
  /// Relative path to the file
  file : String
  /// Package name
  pkg_name : String
  /// Review content
  review : String
  /// Whether review was successful
  success : Bool
  /// Error message if failed
  error : String
} derive(Show)

///|
/// Recursively find all pkg.generated.mbti files
async fn find_mbti_files(dir : String, results : Array[String]) -> Unit {
  let entries = @fs.readdir(dir, include_hidden=false) catch {
    _ => return // Skip directories we can't access
  }

  // Skip certain directories
  let basename = dir.split("/").iter().last().unwrap_or("")
  if basename.has_prefix(".") ||
    basename == "node_modules" ||
    basename == "target" {
    return
  }

  // Check if this directory has pkg.generated.mbti
  if entries.contains("pkg.generated.mbti") {
    results.push("\{dir}/pkg.generated.mbti")
  }

  // Recurse into subdirectories
  for entry in entries {
    let full_path = "\{dir}/\{entry}"
    let kind = @fs.kind(full_path)
    if kind is Directory {
      find_mbti_files(full_path, results)
    }
  }
}

///|
/// Get changed mbti files from git
async fn get_changed_mbti_files(project_root : String) -> Array[String] {
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["diff", "--name-only", "HEAD"],
    stdout=process_read,
    cwd=project_root,
  ) catch {
    e => reraise(e)
  }
  if status != 0 {
    fail("Git diff failed with status \{status}")
  }
  let output = pipe.read_all().text()
  let changed = []
  for line in output.split("\n") {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    if trimmed.has_suffix("pkg.generated.mbti") {
      changed.push("\{project_root}/\{trimmed}")
    }
  }
  if changed.is_empty() {
    @stdio.stdout.write("No changed pkg.generated.mbti files found\n")
  }
  changed
}

///|
/// Review a single mbti file using Codex
async fn review_mbti_file(
  file_path : String,
  project_root : String,
  codex : @codex.Codex,
  verbose : Bool,
) -> ReviewResult {
  let relative_path = if file_path.has_prefix(project_root) {
    try! file_path[project_root.length() + 1:].to_string()
  } else {
    file_path
  }
  if verbose {
    @stdio.stdout.write("Reviewing: \{relative_path}\n")
  }
  let content = @fs.read_file(file_path).text() catch { e => reraise(e) }

  // Extract package name using regex-like matching
  let package_name = extract_package_name(content)
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=project_root,
      sandbox_mode=DangerFullAccess,
    ),
  )
  let prompt =
    $|Review this MoonBit package interface file (\{relative_path}):
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
  let result = thread.run(prompt) catch { e => reraise(e) }
  let review_text = result.final_response
  ReviewResult::{
    file: relative_path,
    pkg_name: package_name,
    review: review_text,
    success: true,
    error: "",
  }
}

///|
/// Extract package name from mbti file content
fn extract_package_name(content : String) -> String {
  // Look for pattern: package "name"
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    if trimmed.has_prefix("package") {
      // Extract the quoted string
      let parts = trimmed.split("\"").collect()
      if parts.length() >= 2 {
        return parts[1].to_string()
      }
    }
  }
  "unknown"
}

///|

///|
/// Helper to create directory path recursively
async fn mkdir_recursive(path : String) -> Unit {
  if @fs.exists(path) {
    return
  }

  // Handle absolute vs relative paths
  let is_absolute = path.has_prefix("/")
  let parts = path.split("/").filter(fn(p) { !p.is_empty() }).collect()
  let mut current = StringView::default()
  for i in 0..<parts.length() {
    let part = parts[i]
    current = if i == 0 && is_absolute {
      "/\{part}"
    } else if current.is_empty() {
      part
    } else {
      "\{current}/\{part}"
    }
    if !@fs.exists(current) {
      @fs.mkdir(current, permission=0o755) catch {
        e => fail_with("Failed to create directory \{current}", e)
      }
    }
  }
}

///|
/// Save review result to file
async fn save_review_to_file(
  result : ReviewResult,
  output_dir : String,
) -> String? {
  // Only save successful reviews
  if !result.success {
    return None
  }

  // Create output directory if it doesn't exist
  mkdir_recursive(output_dir) catch {
    e => fail_with("Failed to create output directory \{output_dir}", e)
  }

  // Generate filename from package path (result.file is relative path like "bench/pkg.generated.mbti")
  // e.g., "bench/pkg.generated.mbti" -> "bench.review.md"
  let file_name = result.file
    .replace_all(old="/pkg.generated.mbti", new="")
    .replace_all(old="/", new="_") +
    ".review.md"
  let output_path = "\{output_dir}/\{file_name}"

  // Format the review content
  let status_icon = "✓ Success"
  let content_text =
    $|# Review: \{result.pkg_name}
    $|
    $|**File:** `\{result.file}`  
    $|**Status:** \{status_icon}
    $|
    $|---
    $|
    $|\{result.review}
    $|
  @fs.write_file(output_path, @encoding/utf8.encode(content_text), create=0o700) catch {
    e => fail_with("Failed to write review file to \{output_path}", e)
  }
  Some(output_path)
}

///|
/// Process files with concurrency control
async fn process_concurrently(
  files : Array[String],
  project_root : String,
  codex : @codex.Codex,
  output_dir : String,
  concurrency : Int,
  verbose : Bool,
) -> Array[ReviewResult] {
  let results : Array[ReviewResult] = []
  let mut completed = 0
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(concurrency)
    for i, file in files {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        @stdio.stdout.write(
          "info [\{i + 1}/\{files.length()}] - Acquired semaphore, starting review of \{file}...\n",
        )
        defer semaphore.release()
        let result = review_mbti_file(file, project_root, codex, verbose) catch {
          e => {
            @stdio.stderr.write("Error reviewing \{file}:\n\{e}\n")
            ReviewResult::{
              file,
              pkg_name: "unknown",
              review: "",
              success: false,
              error: e.to_string(),
            }
          }
        }
        results.push(result)

        // Save review to file (only if successful)
        let output_path = if result.success {
          save_review_to_file(result, output_dir) catch {
            e => {
              @stdio.stderr.write(
                "Failed to save review for \{result.file}:\n\{e}\n",
              )
              None
            }
          }
        } else {
          None
        }
        completed = completed + 1

        // Show progress with status indicator
        let status = if result.success { "✓" } else { "✗" }
        let saved_msg = match output_path {
          Some(path) => {
            let rel_path = if path.has_prefix(project_root) {
              try! path[project_root.length() + 1:].to_string()
            } else {
              path
            }
            " → \{rel_path}"
          }
          None => ""
        }
        @stdio.stdout.write(
          "\{status} [\{completed}/\{files.length()}] \{result.file}\{saved_msg}\n",
        )
      })
    }
  })
  results
}

///|
/// Main entry point
async fn main {
  @stdio.stdout.write("🔍 Starting mbti file review...\n\n")

  // Parse CLI arguments
  let parser = @clap.Parser::new(prog="moon run real_world/review_mbti --", args={
    "all": @clap.Arg::flag(help="Review all mbti files (default)"),
    "changed": @clap.Arg::flag(help="Only review changed files in git"),
    "files": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Specific files to review (comma-separated)",
    ),
    "concurrency": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Number of concurrent reviews",
      defaults=["5"],
    ),
    "verbose": @clap.Arg::flag(help="Show detailed progress"),
    "output": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Output directory for review files",
      defaults=["mbti-reviews"],
    ),
    "path": @clap.Arg::positional(
      nargs=@clap.One,
      help="Path to the project root",
    ),
  })
  let argument = Arguments::{
    all: true,
    changed: false,
    files: [],
    concurrency: 5,
    verbose: false,
    path: ".",
    output: "mbti-reviews",
  }
  if parser.parse(argument, @sys.get_cli_args()[1:]) is Some(help_message) {
    @stdio.stdout.write("\{help_message}\n")
    return
  }
  let project_root = argument.path

  // Make output directory absolute if it's relative
  let output_dir = if argument.output.has_prefix("/") {
    argument.output
  } else {
    "\{project_root}/\{argument.output}"
  }

  // Determine which files to review
  let files_to_review : Array[String] = if argument.files.length() > 0 {
    @stdio.stdout.write(
      "Reviewing \{argument.files.length()} specified file(s)\n",
    )
    argument.files.map(fn(f) { "\{project_root}/\{f}" })
  } else if argument.changed {
    let changed = get_changed_mbti_files(project_root) catch {
      e => {
        @stdio.stderr.write("Failed to get changed files:\n\{e}\n")
        []
      }
    }
    @stdio.stdout.write("Found \{changed.length()} changed mbti file(s)\n")
    changed
  } else {
    let all_files = []
    find_mbti_files(project_root, all_files)
    @stdio.stdout.write("Found \{all_files.length()} mbti file(s) to review\n")
    all_files
  }
  if files_to_review.is_empty() {
    @stdio.stdout.write("No files to review. Exiting.\n")
    return
  }
  @stdio.stdout.write("Using concurrency limit: \{argument.concurrency}\n\n")

  // Initialize Codex
  let codex = @codex.Codex::new()

  // Process files with concurrency control
  let results = process_concurrently(
    files_to_review,
    project_root,
    codex,
    output_dir,
    argument.concurrency,
    argument.verbose,
  )

  // Display results summary
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { !r.success })
  let rel_output_dir = if output_dir.has_prefix(project_root) {
    try! output_dir[project_root.length() + 1:].to_string()
  } else {
    output_dir
  }
  @stdio.stdout.write(
    (
      $|
      $|\{"=".repeat(80)}
      $|SUMMARY
      $|\{"=".repeat(80)}
      $|Total files \{results.length()}
      $|Successful: \{successful}
      $|Failed: \{failed.length()}
      $|Concurrency: \{argument.concurrency}
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
  @stdio.stdout.write("\n💾 Reviews saved to: \{output_dir}\n")
}
