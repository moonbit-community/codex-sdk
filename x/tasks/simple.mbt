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
/// Simplified high-level task orchestration
/// 
/// This package provides simplified APIs for common MoonBit project automation tasks.
/// For more complex workflows, use the lower-level codex, moon, and git packages directly.

///|
/// Run a simple task on a MoonBit project
///
/// # Arguments
/// * `project_path` - Path to the MoonBit project
/// * `task_prompt` - The prompt to send to the AI
/// * `model` - Optional model name (e.g. "anthropic/claude-sonnet-4")
///
/// # Returns
/// The turn result from the AI
pub async fn run_simple_task(
  project_path : String,
  task_prompt : String,
  model? : String,
) -> @codex.Turn {
  let codex_options = @codex.CodexOptions::new()
  let codex = @codex.Codex::new(options=codex_options)
  let thread_options = @codex.ThreadOptions::new(
    model?,
    working_directory=project_path,
  )
  let thread = codex.start_thread(options=thread_options)
  thread.run(task_prompt)
}

///|
/// Example: Process each package in a project
///
/// This is a simplified helper that you can use as a template.
/// For production use, you may want to add:
/// - Parallel execution
/// - Git worktree isolation
/// - Validation and retries
/// - Progress reporting
pub async fn for_each_package(
  project_path : String,
  work : async (@moon.Package) -> Unit,
) -> Unit {
  let project = match @moon.MoonProject::discover(project_path) {
    Some(p) => p
    None => fail("No MoonBit project found at \{project_path}")
  }
  let packages = project.packages()
  for pkg in packages {
    work(pkg)
  }
}
