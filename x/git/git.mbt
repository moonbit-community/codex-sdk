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
/// Represents a Git repository
pub struct GitRepo {
  /// Path to the repository root
  path : String
}

///|
/// Represents an isolated workspace (git worktree)
pub struct IsolatedWorkspace {
  /// Path to the workspace
  path : String
  /// Branch name
  branch : String
  /// Repository reference for cleanup
  repo : GitRepo
}

///|
/// Discover a Git repository at the given path
///
/// # Arguments
/// * `path` - Path to check for git repository
///
/// # Returns
/// Some(GitRepo) if found, None otherwise
pub async fn GitRepo::discover(path : String) -> GitRepo? {
  let status = @process.run(
    "git",
    ["rev-parse", "--is-inside-work-tree"],
    cwd=path,
  )
  if status == 0 {
    Some(GitRepo::{ path, })
  } else {
    None
  }
}

///|
/// Get list of existing branches in the repository
pub async fn GitRepo::existing_branches(self : GitRepo) -> Array[String] {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["branch", "--list", "--no-color"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    fail("Failed to list git branches")
  }
  let output = pipe.read_all().text()
  let lines = output.split("\n")
  let result = []
  for line in lines {
    if !line.is_empty() {
      // Remove leading "* " or "  "
      let cleaned = if line.length() > 2 {
        line[2:].to_string()
      } else {
        line.to_string()
      }
      result.push(cleaned)
    }
  }
  result
}

///|
/// Check if working tree is clean (no uncommitted changes)
pub async fn GitRepo::is_clean(self : GitRepo) -> Bool {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["status", "--porcelain"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    return false
  }
  let output = pipe.read_all().text()
  output.trim_space().is_empty()
}

///|
/// Create an isolated workspace using git worktree
///
/// # Arguments
/// * `package` - The package to create workspace for
/// * `branch` - Branch name to use
/// * `create_branch` - Whether to create a new branch (true) or use existing (false)
///
/// # Returns
/// IsolatedWorkspace with automatic cleanup
pub async fn GitRepo::create_workspace(
  self : GitRepo,
  path : String,
  branch : String,
  create_branch? : Bool = false,
) -> IsolatedWorkspace? {
  let args = if create_branch {
    ["worktree", "add", "-b", branch, path]
  } else {
    ["worktree", "add", path, branch]
  }
  let status = @process.run("git", args, cwd=self.path)
  if status != 0 {
    return None
  }
  Some(IsolatedWorkspace::{ path, branch, repo: self })
}

///|
/// RAII pattern: Execute work in an isolated workspace with automatic cleanup
///
/// # Arguments
/// * `repo` - The git repository
/// * `path` - Path for the workspace
/// * `branch` - Branch name
/// * `create_branch` - Whether to create new branch
/// * `work` - Async function to execute in the workspace
///
/// # Returns
/// Result of the work function
pub async fn[T] with_workspace(
  repo : GitRepo,
  path : String,
  branch : String,
  create_branch? : Bool = false,
  work : async (IsolatedWorkspace) -> T,
) -> T {
  match repo.create_workspace(path, branch, create_branch~) {
    Some(workspace) => {
      let result = work(workspace) catch {
        e => {
          workspace.cleanup()
          raise e
        }
      }
      workspace.cleanup()
      result
    }
    None => fail("Failed to create workspace")
  }
}

///|
/// Clean up the isolated workspace (remove git worktree)
pub async fn IsolatedWorkspace::cleanup(self : IsolatedWorkspace) -> Unit {
  // Try to remove worktree, force if necessary
  let args = ["worktree", "remove", self.path]
  if @process.run("git", args, cwd=self.repo.path) != 0 {
    let force_args = ["worktree", "remove", self.path, "--force"]
    @process.run("git", force_args, cwd=self.repo.path) |> ignore
  }
}
