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
///
/// This is a documentation/template example showing the SDK's capabilities.
/// To run this workflow, adapt it to your specific needs and execute in an
/// async context.
pub async fn fix_warnings_workflow(
  repo_url : String,
  clone_path : String,
  branch_name : String,
) -> Unit {
  println("=== MoonBit Project Warning Fixer ===\n")

  // Step 1: Clone the repository
  println("Step 1: Cloning repository...")
  let repo = match @git.GitRepo::clone(repo_url, clone_path) {
    Some(r) => {
      println("✓ Repository cloned to \{clone_path}")
      r
    }
    None => {
      println("✗ Failed to clone repository")
      return
    }
  }

  // Step 2: Create and checkout new branch
  println("\nStep 2: Creating branch '\{branch_name}'...")
  if !repo.create_branch(branch_name) {
    println("✗ Failed to create branch")
    @git.remove_directory(clone_path) |> ignore
    return
  }
  println("✓ Branch created and checked out")

  // Step 3: Discover the MoonBit project
  println("\nStep 3: Discovering MoonBit project...")
  let project = match @moon.MoonProject::discover(clone_path) {
    Some(p) => {
      println("✓ Found project: \{p.name}")
      p
    }
    None => {
      println("✗ No MoonBit project found")
      @git.remove_directory(clone_path) |> ignore
      return
    }
  }

  // Step 4: Run initial moon check to identify warnings
  println("\nStep 4: Running moon check to find warnings...")
  let initial_check = project.check()
  let diagnostics = @moon.parse_diagnostics(initial_check.stderr)
  let warnings = @moon.get_warnings(diagnostics)
  let errors = @moon.get_errors(diagnostics)
  println("Found \{errors.length()} errors and \{warnings.length()} warnings")
  if warnings.is_empty() && errors.is_empty() {
    println("✓ No issues found! Nothing to fix.")
    @git.remove_directory(clone_path) |> ignore
    return
  }

  // Display warnings
  if !warnings.is_empty() {
    println("\nWarnings to fix:")
    for warning in warnings {
      println("  - \{warning.file}:\{warning.line}: \{warning.message}")
    }
  }

  // Step 5: Use AI to fix warnings iteratively
  println("\nStep 5: Using AI to fix warnings...")
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=clone_path,
    ),
  )

  // Build a comprehensive prompt
  let mut prompt = build_fix_prompt(warnings, errors)
  println("Sending task to AI agent...")
  let mut iterations = 0
  let max_iterations = 5
  while iterations < max_iterations {
    iterations = iterations + 1
    println("\n--- Iteration \{iterations} ---")

    // Run AI agent
    let turn = thread.run(prompt)
    println("AI response: \{turn.final_response}")

    // Step 6: Verify with moon check
    println("\nRunning moon check...")
    let check_result = project.check()
    let new_diagnostics = @moon.parse_diagnostics(check_result.stderr)
    let new_warnings = @moon.get_warnings(new_diagnostics)
    let new_errors = @moon.get_errors(new_diagnostics)
    println(
      "Remaining: \{new_errors.length()} errors, \{new_warnings.length()} warnings",
    )
    if new_errors.is_empty() && new_warnings.is_empty() {
      println("✓ All issues fixed!")
      break
    }
    if new_warnings.length() >= warnings.length() &&
      new_errors.length() >= errors.length() {
      println("⚠ No progress made, stopping iterations")
      break
    }

    // Update for next iteration
    prompt = "There are still \{new_errors.length()} errors and \{new_warnings.length()} warnings. Please continue fixing them."
  }

  // Step 7: Run moon test
  println("\nStep 7: Running moon test...")
  let test_result = project.test_()
  if test_result.passed {
    println("✓ All tests passed")
  } else {
    println("⚠ Some tests failed:")
    println(test_result.stderr)
  }

  // Step 8: Run moon info and moon fmt
  println("\nStep 8: Running moon info and moon fmt...")
  project.update_info() |> ignore
  project.format() |> ignore
  println("✓ Updated interface files and formatted code")

  // Step 9: Review changes
  println("\nStep 9: Reviewing changes...")
  let diff = repo.diff()
  if diff.is_empty() {
    println("No changes to commit")
  } else {
    println("Changes:\n\{diff}")

    // Step 10: Commit changes
    println("\nStep 10: Committing changes...")
    if repo.commit("fix: resolve compilation warnings", add_all=true) {
      println("✓ Changes committed")

      // Step 11: Push to remote
      println("\nStep 11: Pushing to remote...")
      if repo.push(set_upstream=true, branch=branch_name) {
        println("✓ Changes pushed to origin/\{branch_name}")
        println(
          "\nNext steps:\n  - Create a pull request using GitHub MCP\n  - Review and merge the PR",
        )
      } else {
        println("✗ Failed to push changes")
      }
    } else {
      println("✗ Failed to commit changes")
    }
  }

  // Step 12: Clean up
  println("\nStep 12: Cleaning up...")
  if @git.remove_directory(clone_path) {
    println("✓ Removed cloned repository")
  } else {
    println("⚠ Failed to remove \{clone_path}, please clean up manually")
  }
  println("\n=== Workflow Complete ===")
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
