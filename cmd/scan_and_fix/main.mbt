// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// CLI arguments structure
struct Arguments {
  /// Directory path to scan for MoonBit projects
  mut target_dir : String
  /// Maximum number of fix iterations per project
  mut max_iterations : Int
  /// Dry run mode - don't actually execute
  mut dry_run : Bool
  /// Show help message
  mut help : Bool
} derive(Default)

///|
fn parse_args(args : @args.Args) -> Arguments raise {
  let arguments = Arguments::default()

  // Set defaults
  arguments.target_dir = "."
  arguments.max_iterations = 5
  arguments.dry_run = false
  arguments.help = false

  // Parse flags
  if args.flags.get("dry-run") is Some(true) {
    arguments.dry_run = true
  }
  if args.flags.get("help") is Some(true) {
    arguments.help = true
  }

  // Parse options
  if args.options.get("target-dir") is Some(value) {
    arguments.target_dir = value
  }
  if args.options.get("max-iterations") is Some(value) {
    arguments.max_iterations = @strconv.parse_int(value) catch {
      e => @error.fail_with("Invalid max-iterations value: \{value}", e)
    }
  }

  // Parse positional arguments
  if !args.positional.is_empty() {
    arguments.target_dir = args.positional[0]
  }
  arguments
}

///|
/// Scan a directory and return list of MoonBit projects found (depth 1 only)
async fn scan_moonbit_projects(target_dir : String) -> Array[String] {
  let projects = Array::new()

  // Read directory contents
  let entries = @fs.readdir(target_dir, include_hidden=false) catch {
    _ => {
      @stdio.stdout.write("⚠ Failed to read directory: \{target_dir}\n")
      |> ignore
      return projects
    }
  }

  // Check each entry sequentially
  let mut i = 0
  while i < entries.length() {
    let entry = entries[i]
    let project_path = "\{target_dir}/\{entry}"

    // Check if it's a directory and contains moon.mod.json
    let kind = @fs.kind(project_path)
    if kind is Directory && @fs.exists("\{project_path}/moon.mod.json") {
      projects.push(project_path)
    }
    i = i + 1
  }
  projects
}

///|
/// Fix warnings in a single MoonBit project
async fn fix_project_warnings(
  project_path : String,
  max_iterations : Int,
  dry_run : Bool,
) -> Bool {
  @stdio.stdout.write("\n=== Processing: \{project_path} ===\n")

  // Discover the MoonBit project
  let project = match @moon.MoonProject::discover(project_path) {
    Some(p) => {
      @stdio.stdout.write("✓ Found project: \{p.name}\n")
      p
    }
    None => {
      @stdio.stdout.write("✗ Invalid MoonBit project structure\n")
      return false
    }
  }

  // Check if it's a git repository
  let repo = match @git.GitRepo::discover(project_path) {
    Some(r) => {
      @stdio.stdout.write("✓ Git repository found\n")
      Some(r)
    }
    None => {
      @stdio.stdout.write(
        "⚠ No git repository found, will not commit changes\n",
      )
      None
    }
  }

  // Run initial moon check to identify warnings
  @stdio.stdout.write("Running moon check to find warnings...\n")
  let initial_check = project.check()
  let diagnostics = @moon.parse_diagnostics(initial_check.stderr)
  let warnings = @moon.get_warnings(diagnostics)
  let errors = @moon.get_errors(diagnostics)
  @stdio.stdout.write(
    "Found \{errors.length()} errors and \{warnings.length()} warnings\n",
  )
  if warnings.is_empty() && errors.is_empty() {
    @stdio.stdout.write("✓ No issues found! Nothing to fix.\n")
    return true
  }

  // Display warnings and errors
  if !errors.is_empty() {
    @stdio.stdout.write("\nErrors to fix:\n")
    for error in errors {
      @stdio.stdout.write("  - \{error.file}:\{error.line}: \{error.message}\n")
    }
  }
  if !warnings.is_empty() {
    @stdio.stdout.write("\nWarnings to fix:\n")
    for warning in warnings {
      @stdio.stdout.write(
        "  - \{warning.file}:\{warning.line}: \{warning.message}\n",
      )
    }
  }
  if dry_run {
    @stdio.stdout.write(
      "🔍 DRY RUN: Would fix \{errors.length()} errors and \{warnings.length()} warnings\n",
    )
    return true
  }

  // Use AI to fix warnings iteratively
  @stdio.stdout.write("\nUsing AI to fix issues...\n")
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=project_path,
    ),
  )

  // Build initial prompt
  let mut prompt = build_fix_prompt(warnings, errors)
  let mut iterations = 0
  let mut previous_issue_count = warnings.length() + errors.length()
  while iterations < max_iterations {
    iterations = iterations + 1
    @stdio.stdout.write("\n--- Iteration \{iterations}/\{max_iterations} ---\n")

    // Run AI agent
    let _ = thread.run(prompt) catch {
      e => @error.fail_with("AI agent failed to run", e)
    }
    @stdio.stdout.write("AI completed task\n")

    // Verify with moon check
    @stdio.stdout.write("Running moon check...\n")
    let check_result = project.check()
    let new_diagnostics = @moon.parse_diagnostics(check_result.stderr)
    let new_warnings = @moon.get_warnings(new_diagnostics)
    let new_errors = @moon.get_errors(new_diagnostics)
    let current_issue_count = new_warnings.length() + new_errors.length()
    @stdio.stdout.write(
      "Remaining: \{new_errors.length()} errors, \{new_warnings.length()} warnings\n",
    )

    // Check if all issues are fixed
    if new_errors.is_empty() && new_warnings.is_empty() {
      @stdio.stdout.write("✓ All issues fixed!\n")

      // Run moon test to ensure no regressions
      @stdio.stdout.write("Running moon test...\n")
      let test_result = project.test_()
      if test_result.passed {
        @stdio.stdout.write("✓ All tests passed\n")
      } else {
        @stdio.stdout.write("⚠ Some tests failed, but warnings are fixed\n")
      }

      // Run moon info and moon fmt
      @stdio.stdout.write("Running moon info and moon fmt...\n")
      project.update_info() |> ignore
      project.format() |> ignore
      @stdio.stdout.write("✓ Updated interface files and formatted code\n")

      // Commit changes if git repository exists
      match repo {
        Some(r) => {
          let diff = r.diff()
          if !diff.is_empty() {
            @stdio.stdout.write("Committing changes...\n")
            if r.commit(
                "fix: resolve compilation warnings and errors",
                add_all=true,
              ) {
              @stdio.stdout.write("✓ Changes committed\n")
            } else {
              @stdio.stdout.write("✗ Failed to commit changes\n")
            }
          } else {
            @stdio.stdout.write("No changes to commit\n")
          }
        }
        None => @stdio.stdout.write("Skipping commit (no git repository)\n")
      }
      return true
    }

    // Check if we made progress
    if current_issue_count >= previous_issue_count {
      @stdio.stdout.write("⚠ No progress made in this iteration\n")
      if iterations >= 2 {
        @stdio.stdout.write("Stopping iterations due to lack of progress\n")
        break
      }
    }

    // Update for next iteration
    previous_issue_count = current_issue_count
    prompt = "There are still \{new_errors.length()} errors and \{new_warnings.length()} warnings. Please continue fixing them systematically."
  }
  @stdio.stdout.write(
    "⚠ Max iterations reached, some issues may remain unfixed\n",
  )
  return false
}

///|
/// Build a comprehensive prompt for fixing warnings and errors
fn build_fix_prompt(
  warnings : Array[@moon.Diagnostic],
  errors : Array[@moon.Diagnostic],
) -> String {
  let prompt = StringBuilder::new()
  prompt.write_string(
    "I need you to fix compilation issues in this MoonBit project.\n\n",
  )
  if !errors.is_empty() {
    prompt.write_string("ERRORS (\{errors.length()}):\n")
    for error in errors {
      prompt.write_string("- \{error.file}:\{error.line}: \{error.message}\n")
    }
    prompt.write_string("\n")
  }
  if !warnings.is_empty() {
    prompt.write_string("WARNINGS (\{warnings.length()}):\n")
    for warning in warnings {
      prompt.write_string(
        "- \{warning.file}:\{warning.line}: \{warning.message}\n",
      )
    }
    prompt.write_string("\n")
  }
  prompt.write_string(
    "Please fix these issues one by one. Follow these guidelines:\n",
  )
  prompt.write_string("1. Fix the root cause, not just suppress warnings\n")
  prompt.write_string("2. Follow MoonBit idioms and best practices\n")
  prompt.write_string("3. Maintain code clarity and documentation\n")
  prompt.write_string(
    "4. After making changes, run `moon check` to verify fixes\n",
  )
  prompt.write_string("5. Run `moon test` to ensure no regressions\n")
  prompt.write_string("6. Focus on fixing one issue at a time\n")
  prompt.to_string()
}

///|
/// Scan and fix workflow
async fn scan_and_fix_workflow(
  target_dir : String,
  max_iterations : Int,
  dry_run : Bool,
) -> Unit {
  @stdio.stdout.write("=== MoonBit Project Scanner and Fixer ===\n\n")
  @stdio.stdout.write("Scanning directory: \{target_dir}\n")

  // Scan for MoonBit projects
  let projects = scan_moonbit_projects(target_dir)
  if projects.is_empty() {
    @stdio.stdout.write(
      "No MoonBit projects found in the specified directory.\n",
    )
    return
  }
  @stdio.stdout.write("Found \{projects.length()} MoonBit project(s):\n")
  let mut i = 0
  while i < projects.length() {
    @stdio.stdout.write("  - \{projects[i]}\n")
    i = i + 1
  }
  if dry_run {
    @stdio.stdout.write("\n🔍 DRY RUN MODE - No changes will be made\n")
    @stdio.stdout.write(
      "Would process each project to fix warnings and errors\n",
    )
    return
  }

  // Process each project
  let mut successful_fixes = 0
  let mut i = 0
  while i < projects.length() {
    let success = fix_project_warnings(projects[i], max_iterations, dry_run)
    if success {
      successful_fixes = successful_fixes + 1
    }
    i = i + 1
  }
  @stdio.stdout.write("\n=== Summary ===\n")
  @stdio.stdout.write("Projects processed: \{projects.length()}\n")
  @stdio.stdout.write("Successfully fixed: \{successful_fixes}\n")
  @stdio.stdout.write(
    "Failed to fix: \{projects.length() - successful_fixes}\n",
  )
  if successful_fixes == projects.length() {
    @stdio.stdout.write("✓ All projects fixed successfully!\n")
  } else {
    @stdio.stdout.write("⚠ Some projects require manual attention\n")
  }
}

///|
/// Main entry point with CLI argument parsing
async fn main {
  let help_message =
    $|Usage: moon run scan_and_fix -- [DIRECTORY] [OPTIONS]
    $|Scan a directory for MoonBit projects and automatically fix warnings.
    $|
    $|Arguments:
    $|  DIRECTORY                 Directory to scan (default: current directory)
    $|
    $|Options:
    $|  --target-dir <path>       Directory to scan for MoonBit projects
    $|  --max-iterations <num>    Maximum number of fix iterations per project (default: 5)
    $|  --dry-run                 Show what would be done without executing
    $|  -h, --help                Show this help message
    $|

  // Parse CLI arguments
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["dry-run", "help"],
    options=["target-dir", "max-iterations"],
    aliases={ "h": "help" },
  )
  let arguments = parse_args(args)
  if arguments.help {
    @stdio.stdout.write("\{help_message}\n")
    return
  }

  // Display configuration
  @stdio.stdout.write("Configuration:\n")
  @stdio.stdout.write("  Target directory: \{arguments.target_dir}\n")
  @stdio.stdout.write("  Max iterations: \{arguments.max_iterations}\n")
  @stdio.stdout.write("  Dry run: \{arguments.dry_run}\n\n")

  // Execute the workflow
  scan_and_fix_workflow(
    arguments.target_dir,
    arguments.max_iterations,
    arguments.dry_run,
  )
}
