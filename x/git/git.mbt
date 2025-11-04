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
/// Clone a remote repository
///
/// # Arguments
/// * `url` - Remote repository URL
/// * `destination` - Local path to clone into
///
/// # Returns
/// GitRepo instance for the cloned repository
pub async fn GitRepo::clone(url : String, destination : String) -> GitRepo? {
  let status = @process.run("git", ["clone", url, destination])
  if status == 0 {
    Some(GitRepo::{ path: destination })
  } else {
    None
  }
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
/// Create a new branch
///
/// # Arguments
/// * `branch_name` - Name of the branch to create
/// * `from_branch` - Optional branch to create from (defaults to current)
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::create_branch(
  self : GitRepo,
  branch_name : String,
  from_branch? : String,
) -> Bool {
  let args = if from_branch is Some(from) {
    ["checkout", "-b", branch_name, from]
  } else {
    ["checkout", "-b", branch_name]
  }
  @process.run("git", args, cwd=self.path) == 0
}

///|
/// Checkout a branch
///
/// # Arguments
/// * `branch_name` - Name of the branch to checkout
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::checkout(self : GitRepo, branch_name : String) -> Bool {
  @process.run("git", ["checkout", branch_name], cwd=self.path) == 0
}

///|
/// Commit changes with a message
///
/// # Arguments
/// * `message` - Commit message
/// * `add_all` - Whether to add all changes before committing (default true)
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::commit(
  self : GitRepo,
  message : String,
  add_all? : Bool = true,
) -> Bool {
  if add_all {
    let add_status = @process.run("git", ["add", "-A"], cwd=self.path)
    if add_status != 0 {
      return false
    }
  }
  @process.run("git", ["commit", "-m", message], cwd=self.path) == 0
}

///|
/// Push changes to remote
///
/// # Arguments
/// * `remote` - Remote name (default "origin")
/// * `branch` - Branch to push (optional, uses current branch if not specified)
/// * `set_upstream` - Whether to set upstream tracking (default false)
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::push(
  self : GitRepo,
  remote? : String = "origin",
  branch? : String,
  set_upstream? : Bool = false,
) -> Bool {
  let args = ["push"]
  if set_upstream {
    args.push("-u")
  }
  args.push(remote)
  if branch is Some(b) {
    args.push(b)
  }
  @process.run("git", args, cwd=self.path) == 0
}

///|
/// Get diff of uncommitted changes
///
/// # Returns
/// String containing the diff output
pub async fn GitRepo::diff(self : GitRepo) -> String {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["diff"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    return ""
  }
  pipe.read_all().text()
}

///|
/// Get diff of staged changes
///
/// # Returns
/// String containing the diff output
pub async fn GitRepo::diff_staged(self : GitRepo) -> String {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["diff", "--staged"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    return ""
  }
  pipe.read_all().text()
}

///|
/// Get current branch name
///
/// # Returns
/// Current branch name or None if detached HEAD
pub async fn GitRepo::current_branch(self : GitRepo) -> String? {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["branch", "--show-current"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    return None
  }
  let output = pipe.read_all().text().trim_space().to_string()
  if output.is_empty() {
    None
  } else {
    Some(output)
  }
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

///|
/// Remove a directory recursively
///
/// # Arguments
/// * `path` - Path to the directory to remove
///
/// # Returns
/// True if successful, false otherwise
pub async fn remove_directory(path : String) -> Bool {
  @process.run("rm", ["-rf", path]) == 0
}
