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
  /// Repository URL to clone
  mut repo_url : String
  /// Local path where to clone (optional, will use /tmp if not specified)
  mut clone_path : String
  /// Branch name to create for fixes
  mut branch_name : String
  /// Maximum number of fix iterations
  mut max_iterations : Int
  /// Dry run mode - don't actually execute
  mut dry_run : Bool
} derive(Default)

///|
impl @clap.Value for Arguments with set_flag(self : Arguments, name, value) {
  if name == "dry-run" {
    self.dry_run = value
  } else {
    raise @clap.ParserError::InvalidArgumentName("Invalid flag name \{name}")
  }
}

///|
impl @clap.Value for Arguments with add_value(
  self : Arguments,
  name,
  value,
  _positional,
) {
  if name == "repo-url" {
    self.repo_url = value
  } else if name == "clone-path" {
    self.clone_path = value
  } else if name == "branch-name" {
    self.branch_name = value
  } else if name == "max-iterations" {
    self.max_iterations = @clap.BasicValue::parse(value) catch {
      StrConvError(err) =>
        raise @clap.ParserError::InvalidArgumentValue(
          "Invalid value for \{name}: \{err}",
        )
    }
  } else {
    raise @clap.ParserError::InvalidArgumentName(
      "Invalid argument name \{name}",
    )
  }
}

///|
/// Example: Automated workflow to fix compilation warnings in a MoonBit project
///
/// This example demonstrates the complete workflow for the scenario described in
/// the project documentation:
/// 1. Clone the repository
/// 2. Checkout a new branch  
/// 3. Run moon check to find warnings
/// 4. Use AI to fix warnings iteratively
/// 5. Verify with moon check and test after each fix
/// 6. Run moon info and moon fmt
/// 7. Review changes with git diff
/// 8. Commit and push changes
/// 9. Create pull request (via GitHub MCP)
/// 10. Clean up (remove cloned repo)
pub async fn fix_warnings_workflow(
  repo_url : String,
  clone_path : String,
  branch_name : String,
  max_iterations : Int,
) -> Unit {
  @stdio.stdout.write("=== MoonBit Project Warning Fixer ===\n\n")

  // Step 1: Clone the repository
  @stdio.stdout.write("Step 1: Cloning repository...\n")
  let repo = match @git.GitRepo::clone(repo_url, clone_path) {
    Some(r) => {
      @stdio.stdout.write("✓ Repository cloned to \{clone_path}\n")
      r
    }
    None => {
      @stdio.stdout.write("✗ Failed to clone repository\n")
      return
    }
  }

  // Step 2: Create and checkout new branch
  @stdio.stdout.write("\nStep 2: Creating branch '\{branch_name}'...\n")
  if !repo.create_branch(branch_name) {
    @stdio.stdout.write("✗ Failed to create branch\n")
    @git.remove_directory(clone_path) |> ignore
    return
  }
  @stdio.stdout.write("✓ Branch created and checked out\n")

  // Step 3: Discover the MoonBit project
  @stdio.stdout.write("\nStep 3: Discovering MoonBit project...\n")
  let project = match @moon.MoonProject::discover(clone_path) {
    Some(p) => {
      @stdio.stdout.write("✓ Found project: \{p.name}\n")
      p
    }
    None => {
      @stdio.stdout.write("✗ No MoonBit project found\n")
      @git.remove_directory(clone_path) |> ignore
      return
    }
  }

  // Step 4: Run initial moon check to identify warnings
  @stdio.stdout.write("\nStep 4: Running moon check to find warnings...\n")
  let initial_check = project.check()
  let diagnostics = @moon.parse_diagnostics(initial_check.stderr)
  let warnings = @moon.get_warnings(diagnostics)
  let errors = @moon.get_errors(diagnostics)
  @stdio.stdout.write(
    "Found \{errors.length()} errors and \{warnings.length()} warnings\n",
  )
  if warnings.is_empty() && errors.is_empty() {
    @stdio.stdout.write("✓ No issues found! Nothing to fix.\n")
    @git.remove_directory(clone_path) |> ignore
    return
  }

  // Display warnings
  if !warnings.is_empty() {
    @stdio.stdout.write("\nWarnings to fix:\n")
    for warning in warnings {
      @stdio.stdout.write(
        "  - \{warning.file}:\{warning.line}: \{warning.message}\n",
      )
    }
  }

  // Step 5: Use AI to fix warnings iteratively
  @stdio.stdout.write("\nStep 5: Using AI to fix warnings...\n")
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=clone_path,
    ),
  )

  // Build a comprehensive prompt
  let mut prompt = build_fix_prompt(warnings, errors)
  @stdio.stdout.write("Sending task to AI agent...\n")
  let mut iterations = 0
  while iterations < max_iterations {
    iterations = iterations + 1
    @stdio.stdout.write("\n--- Iteration \{iterations}/\{max_iterations} ---\n")

    // Run AI agent
    let turn = thread.run(prompt)
    @stdio.stdout.write("AI response: \{turn.final_response}\n")

    // Step 6: Verify with moon check
    @stdio.stdout.write("\nRunning moon check...\n")
    let check_result = project.check()
    let new_diagnostics = @moon.parse_diagnostics(check_result.stderr)
    let new_warnings = @moon.get_warnings(new_diagnostics)
    let new_errors = @moon.get_errors(new_diagnostics)
    @stdio.stdout.write(
      "Remaining: \{new_errors.length()} errors, \{new_warnings.length()} warnings\n",
    )
    if new_errors.is_empty() && new_warnings.is_empty() {
      @stdio.stdout.write("✓ All issues fixed!\n")
      break
    }
    if new_warnings.length() >= warnings.length() &&
      new_errors.length() >= errors.length() {
      @stdio.stdout.write("⚠ No progress made, stopping iterations\n")
      break
    }

    // Update for next iteration
    prompt = "There are still \{new_errors.length()} errors and \{new_warnings.length()} warnings. Please continue fixing them."
  }

  // Step 7: Run moon test
  @stdio.stdout.write("\nStep 7: Running moon test...\n")
  let test_result = project.test_()
  if test_result.passed {
    @stdio.stdout.write("✓ All tests passed\n")
  } else {
    @stdio.stdout.write("⚠ Some tests failed:\n")
    @stdio.stdout.write(test_result.stderr)
  }

  // Step 8: Run moon info and moon fmt
  @stdio.stdout.write("\nStep 8: Running moon info and moon fmt...\n")
  project.update_info() |> ignore
  project.format() |> ignore
  @stdio.stdout.write("✓ Updated interface files and formatted code\n")

  // Step 9: Review changes
  @stdio.stdout.write("\nStep 9: Reviewing changes...\n")
  let diff = repo.diff()
  if diff.is_empty() {
    @stdio.stdout.write("No changes to commit\n")
  } else {
    @stdio.stdout.write("Changes:\n\{diff}\n")

    // Step 10: Commit changes
    @stdio.stdout.write("\nStep 10: Committing changes...\n")
    if repo.commit("fix: resolve compilation warnings", add_all=true) {
      @stdio.stdout.write("✓ Changes committed\n")

      // Step 11: Push to remote
      @stdio.stdout.write("\nStep 11: Pushing to remote...\n")
      if repo.push(set_upstream=true, branch=branch_name) {
        @stdio.stdout.write("✓ Changes pushed to origin/\{branch_name}\n")
        @stdio.stdout.write(
          "\nNext steps:\n  - Create a pull request using GitHub MCP\n  - Review and merge the PR\n",
        )
      } else {
        @stdio.stdout.write("✗ Failed to push changes\n")
      }
    } else {
      @stdio.stdout.write("✗ Failed to commit changes\n")
    }
  }

  // Step 12: Clean up
  @stdio.stdout.write("\nStep 12: Cleaning up...\n")
  if @git.remove_directory(clone_path) {
    @stdio.stdout.write("✓ Removed cloned repository\n")
  } else {
    @stdio.stdout.write(
      "⚠ Failed to remove \{clone_path}, please clean up manually\n",
    )
  }
  @stdio.stdout.write("\n=== Workflow Complete ===\n")
}

///|
/// Build a comprehensive prompt for fixing warnings
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
    "Please fix these issues one by one. After making changes, run `moon check` to verify. Make sure to:\n",
  )
  prompt.write_string("1. Fix the root cause, not just suppress warnings\n")
  prompt.write_string("2. Follow MoonBit idioms and best practices\n")
  prompt.write_string("3. Maintain code clarity and documentation\n")
  prompt.write_string("4. Run `moon test` to ensure no regressions\n")
  prompt.to_string()
}

///|
/// Main entry point with CLI argument parsing
async fn main {
  @stdio.stdout.write("=== MoonBit Warning Fixer ===\n\n")

  // Parse CLI arguments
  let parser = @clap.Parser::new(prog="moon run example_fix_warnings --", args={
    "repo-url": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Repository URL to clone (e.g., https://github.com/owner/repo.git)",
      defaults=["https://github.com/moonbit-community/codex-sdk.git"],
    ),
    "clone-path": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Local directory where to clone the repository",
      defaults=["/tmp/moonbit-fix-warnings"],
    ),
    "branch-name": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Name of the branch to create for fixes",
      defaults=["fix/warnings-auto"],
    ),
    "max-iterations": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Maximum number of fix iterations",
      defaults=["5"],
    ),
    "dry-run": @clap.Arg::flag(help="Show what would be done without executing"),
  })
  let args = Arguments::{
    repo_url: "https://github.com/moonbit-community/codex-sdk.git",
    clone_path: "/tmp/moonbit-fix-warnings",
    branch_name: "fix/warnings-auto",
    max_iterations: 5,
    dry_run: false,
  }
  if parser.parse(args, @sys.get_cli_args()[1:]) is Some(help_message) {
    @stdio.stdout.write("\{help_message}\n")
    return
  }

  // Display configuration
  @stdio.stdout.write("Configuration:\n")
  @stdio.stdout.write("  Repository URL: \{args.repo_url}\n")
  @stdio.stdout.write("  Clone path: \{args.clone_path}\n")
  @stdio.stdout.write("  Branch name: \{args.branch_name}\n")
  @stdio.stdout.write("  Max iterations: \{args.max_iterations}\n")
  @stdio.stdout.write("  Dry run: \{args.dry_run}\n\n")
  if args.dry_run {
    @stdio.stdout.write("🔍 DRY RUN MODE - No changes will be made\n\n")
    @stdio.stdout.write("Workflow steps that would be executed:\n")
    @stdio.stdout.write("1. Clone repository from \{args.repo_url}\n")
    @stdio.stdout.write("2. Create and checkout branch '\{args.branch_name}'\n")
    @stdio.stdout.write("3. Run moon check to identify warnings\n")
    @stdio.stdout.write(
      "4. Use AI to fix warnings (up to \{args.max_iterations} iterations)\n",
    )
    @stdio.stdout.write("5. Run moon test to verify changes\n")
    @stdio.stdout.write("6. Run moon info and moon fmt\n")
    @stdio.stdout.write("7. Review and commit changes\n")
    @stdio.stdout.write("8. Push to remote\n")
    @stdio.stdout.write("9. Clean up temporary directory\n\n")
    @stdio.stdout.write(
      "To execute the workflow, run without --dry-run flag.\n",
    )
    return
  }

  // Execute the workflow
  @stdio.stdout.write("🚀 Starting workflow...\n\n")
  fix_warnings_workflow(
    args.repo_url,
    args.clone_path,
    args.branch_name,
    args.max_iterations,
  )
}
