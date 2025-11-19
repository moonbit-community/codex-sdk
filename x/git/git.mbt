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
/// Extract repository name from URL
///
/// # Arguments
/// * `url` - Repository URL (e.g., https://github.com/user/repo.git)
///
/// # Returns
/// Repository name without .git suffix
pub fn extract_repo_name(url : String) -> String {
  // Handle URLs like:
  // - https://github.com/user/repo.git
  // - https://github.com/user/repo
  // - git@github.com:user/repo.git
  let parts = url.split("/").collect()
  let last = if parts.length() > 0 {
    parts[parts.length() - 1].to_string()
  } else {
    url
  }
  // Remove .git suffix if present
  if last.has_suffix(".git") {
    try! last[0:last.length() - 4].to_string()
  } else {
    last
  }
}

///|
/// Represents a Git repository
pub struct GitRepo {
  /// Path to the repository root
  path : String
  /// Optional repository URL
  url : String?
  /// Optional repository name (extracted from URL)
  name : String?
  /// Optional default branch name
  default_branch : String?
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
/// * `get_default_branch` - Whether to fetch and set default branch (default true)
///
/// # Returns
/// GitRepo instance for the cloned repository
pub async fn GitRepo::clone(url : String, destination : String) -> GitRepo {
  let (status, output) = @process.collect_output_merged("git", [
    "clone", url, destination,
  ]) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: Failed to clone repository \{url}")
        $|Output: \{output.text()}
        $|
      ),
    )
  }
  let repo_name = extract_repo_name(url)
  let mut default_branch = None
  try {
    let (status, output) = @process.collect_output_merged(
      "git",
      ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
      cwd=destination,
    )
    if status == 0 {
      default_branch = Some(
        {
          let full = output.text().trim_space().to_string()
          full.strip_prefix("origin/").unwrap_or(full)
        }.to_string(),
      )
    }
  } catch {
    _ => ()
  }
  GitRepo::{
    path: destination,
    url: Some(url),
    name: Some(repo_name),
    default_branch,
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
pub async fn GitRepo::discover(path : String) -> GitRepo {
  let (status, output) = @process.collect_output_merged(
    "git",
    ["rev-parse", "--is-inside-work-tree"],
    cwd=path,
  ) catch {
    e => @error.fail_with("Failed to discover git repository at " + path, e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: Failed to discover git repository at \{path}"),
        $|Output: \{output.text()}
      ),
    )
  }
  // Try to get default branch
  let mut default_branch = None
  try {
    let (status, output) = @process.collect_output_merged(
      "git",
      ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
      cwd=path,
    )
    if status == 0 {
      default_branch = Some(
        {
          let full = output.text().trim_space().to_string()
          full.strip_prefix("origin/").unwrap_or(full)
        }.to_string(),
      )
    }
  } catch {
    _ => ()
  }
  GitRepo::{ path, url: None, name: None, default_branch }
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
) -> Unit {
  let args = if from_branch is Some(from) {
    ["checkout", "-b", branch_name, from]
  } else {
    ["checkout", "-b", branch_name]
  }
  let (status, _, stderr) = @process.collect_output("git", args, cwd=self.path) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail("Failed to create branch \{branch_name}: \{stderr.text()}")
  }
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
) -> Unit {
  let args = ["push"]
  if set_upstream {
    args.push("-u")
  }
  args.push(remote)
  if branch is Some(b) {
    args.push(b)
  }
  let (status, _, stderr) = @process.collect_output("git", args, cwd=self.path) catch {
    e => @error.fail_with("Failed to push to remote \{remote}", e)
  }
  if status != 0 {
    @error.fail("Failed to push to remote \{remote}: \{stderr.text()}")
  }
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
/// Get default branch from remote
///
/// # Arguments
/// * `remote` - Remote name (default "origin")
///
/// # Returns
/// Default branch name or None if unable to determine
pub async fn GitRepo::get_default_branch(
  self : GitRepo,
  remote? : String = "origin",
) -> String? {
  let (pipe, process_write) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["symbolic-ref", "refs/remotes/\{remote}/HEAD", "--short"],
    stdout=process_write,
    cwd=self.path,
  )
  if status != 0 {
    return None
  }
  let default_branch_full = pipe.read_all().text().trim_space().to_string()
  // Extract branch name from "origin/main" -> "main"
  let prefix = "\{remote}/"
  if default_branch_full.has_prefix(prefix) {
    Some(try! default_branch_full[prefix.length():].to_string())
  } else {
    Some(default_branch_full)
  }
}

///|
/// Fetch from remote
///
/// # Arguments
/// * `remote` - Remote name (default "origin")
/// * `branch` - Optional specific branch to fetch
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::fetch(
  self : GitRepo,
  remote? : String = "origin",
  branch? : String,
) -> Bool {
  let args = ["fetch", remote]
  if branch is Some(b) {
    args.push(b)
  }
  @process.run("git", args, cwd=self.path) == 0
}

///|
/// Pull from remote
///
/// # Arguments
/// * `remote` - Remote name (default "origin")
/// * `branch` - Optional specific branch to pull
///
/// # Returns
/// True if successful, false otherwise
pub async fn GitRepo::pull(
  self : GitRepo,
  remote? : String = "origin",
  branch? : String,
) -> Bool {
  let args = ["pull", remote]
  if branch is Some(b) {
    args.push(b)
  }
  @process.run("git", args, cwd=self.path) == 0
}

///|
/// Check if there are staged changes ready to commit
///
/// # Returns
/// True if there are staged changes, false otherwise
pub async fn GitRepo::has_staged_changes(self : GitRepo) -> Bool {
  let status = @process.run(
    "git",
    ["diff", "--cached", "--quiet"],
    cwd=self.path,
  )
  // git diff --cached --quiet returns 0 if no staged changes, 1 if staged changes exist
  status != 0
}

///|
/// Check if there are any uncommitted changes (staged or unstaged)
///
/// # Returns
/// True if there are uncommitted changes, false otherwise
pub async fn GitRepo::has_changes(self : GitRepo) -> Bool {
  let status = @process.run("git", ["diff", "--quiet"], cwd=self.path)
  // git diff --quiet returns 0 if no changes, 1 if changes exist
  status != 0
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
