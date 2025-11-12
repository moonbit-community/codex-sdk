///|
/// Repository information
struct RepoInfo {
  /// Repository URL
  url : String
  /// Local clone path
  local_path : String
  /// Repository name (extracted from URL)
  name : String
  /// Default branch name
  default_branch : String
}

///|
/// Extract repository name from URL
fn extract_repo_name(url : String) -> String {
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
/// Clone repository to local path
async fn clone_repository(
  url : String,
  local_path : String,
  force_fresh : Bool,
) -> RepoInfo {
  let repo_name = extract_repo_name(url)
  let clone_path = "\{local_path}/\{repo_name}"

  // Clean up if force_fresh is enabled
  if force_fresh && @fs.exists(clone_path) {
    @stdio.stdout.write("info [\{repo_name}] - Removing existing clone...\n")
    let status = @process.run("rm", ["-rf", clone_path])
    if status != 0 {
      @error.fail("Failed to remove existing clone at \{clone_path}")
    }
  }

  // Clone if doesn't exist
  if !@fs.exists(clone_path) {
    @stdio.stdout.write("info [\{repo_name}] - Cloning repository...\n")
    let status = @process.run("git", ["clone", url, clone_path]) catch {
      e => @error.reraise(e)
    }
    if status != 0 {
      @error.fail("Failed to clone repository from \{url}")
    }
  } else {
    @stdio.stdout.write(
      "info [\{repo_name}] - Using existing clone at \{clone_path}\n",
    )
    // Fetch latest changes
    let status = @process.run("git", ["fetch", "origin"], cwd=clone_path) catch {
      e => @error.reraise(e)
    }
    if status != 0 {
      @error.fail("Failed to fetch from \{url}")
    }
  }

  // Get default branch
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
    stdout=process_read,
    cwd=clone_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail("Failed to get default branch for \{url}")
  }
  let default_branch_full = pipe
    .read_all()
    .text()
    .trim(chars=" \t\n\r")
    .to_string()
  // Extract branch name from "origin/main" -> "main"
  let default_branch = if default_branch_full.has_prefix("origin/") {
    try! default_branch_full[7:].to_string()
  } else {
    default_branch_full
  }
  RepoInfo::{ url, local_path: clone_path, name: repo_name, default_branch }
}

///|
/// Get existing AI fix branch or create a new one (idempotent)
/// Returns the branch name that should be used for this task
async fn get_or_create_branch(
  repo : RepoInfo,
  branch_prefix : String,
) -> String {
  // Get current branch
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["rev-parse", "--abbrev-ref", "HEAD"],
    stdout=process_read,
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  let current_branch = if status == 0 {
    pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  } else {
    repo.default_branch
  }

  // Check if we're already on an AI fix branch
  if current_branch.has_prefix(branch_prefix) {
    @stdio.stdout.write(
      "info [\{repo.name}] - Already on AI fix branch: \{current_branch}\n",
    )
    return current_branch
  }

  // Look for existing AI fix branches
  let (pipe2, process_read2) = @process.read_from_process()
  let list_status = @process.run(
    "git",
    ["branch", "--list", "\{branch_prefix}-*"],
    stdout=process_read2,
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  if list_status == 0 {
    let output = pipe2.read_all().text().trim(char_set=" \t\n\r").to_string()
    if !output.is_empty() {
      // Found existing branch, use the first one
      let lines = output.split("\n").collect()
      if lines.length() > 0 {
        let branch = lines[0].to_string().trim(char_set=" *\t\n\r").to_string()
        @stdio.stdout.write(
          "info [\{repo.name}] - Found existing AI fix branch: \{branch}, checking out...\n",
        )
        let checkout_status = @process.run(
          "git",
          ["checkout", branch],
          cwd=repo.local_path,
        ) catch {
          e => @error.reraise(e)
        }
        if checkout_status == 0 {
          return branch
        }
      }
    }
  }

  // No existing branch found, create a new one
  let timestamp = get_timestamp()
  let new_branch = "\{branch_prefix}-\{timestamp}"
  @stdio.stdout.write(
    "info [\{repo.name}] - Creating new AI fix branch: \{new_branch}...\n",
  )

  // Ensure we're on default branch first
  let _checkout = @process.run(
    "git",
    ["checkout", repo.default_branch],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }

  // Pull latest changes
  let _pull = @process.run(
    "git",
    ["pull", "origin", repo.default_branch],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }

  // Create new branch
  let create_status = @process.run(
    "git",
    ["checkout", "-b", new_branch],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  if create_status != 0 {
    @error.fail("Failed to create branch \{new_branch}")
  }
  new_branch
}

///|
/// Check if there are uncommitted changes
async fn has_changes(repo : RepoInfo) -> Bool {
  let status = @process.run("git", ["diff", "--quiet"], cwd=repo.local_path) catch {
    e => @error.reraise(e)
  }
  // git diff --quiet returns 0 if no changes, 1 if changes exist
  status != 0
}

///|
/// Check if there are staged changes ready to commit
async fn has_staged_changes(repo : RepoInfo) -> Bool {
  let status = @process.run(
    "git",
    ["diff", "--cached", "--quiet"],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  // git diff --cached --quiet returns 0 if no staged changes, 1 if staged changes exist
  status != 0
}

///|
/// Commit all changes
async fn commit_changes(repo : RepoInfo, message : String) -> Bool {
  // Add all changes
  let add_status = @process.run("git", ["add", "-A"], cwd=repo.local_path) catch {
    e => @error.reraise(e)
  }
  if add_status != 0 {
    @error.fail("Failed to stage changes")
  }

  // Check if there are staged changes to commit
  if !has_staged_changes(repo) {
    @stdio.stdout.write("info [\{repo.name}] - No changes to commit\n")
    return false
  }

  // Commit
  let commit_status = @process.run(
    "git",
    ["commit", "-m", message],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  if commit_status != 0 {
    @error.fail("Failed to commit changes")
  }
  @stdio.stdout.write("info [\{repo.name}] - Changes committed successfully\n")
  true
}

///|
/// Push branch to remote
async fn push_branch(repo : RepoInfo, branch_name : String) -> Unit {
  @stdio.stdout.write(
    "info [\{repo.name}] - Pushing branch \{branch_name} to origin...\n",
  )
  let status = @process.run(
    "git",
    ["push", "-u", "origin", branch_name],
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail("Failed to push branch \{branch_name}")
  }
  @stdio.stdout.write("info [\{repo.name}] - Branch pushed successfully\n")
}

///|
/// Create pull request using GitHub CLI
async fn create_pull_request(
  repo : RepoInfo,
  branch_name : String,
  title : String,
  body : String,
) -> String? {
  @stdio.stdout.write(
    "info [\{repo.name}] - Creating pull request for \{repo.url}...\n",
  )

  // Check if gh CLI is available
  let which_status = @process.run("which", ["gh"]) catch {
    e => @error.reraise(e)
  }
  if which_status != 0 {
    @stdio.stdout.write(
      "warning [\{repo.name}] - GitHub CLI (gh) not found, skipping PR creation\n",
    )
    return None
  }

  // Create PR using gh CLI
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "gh",
    [
      "pr",
      "create",
      "--title",
      title,
      "--body",
      body,
      "--base",
      repo.default_branch,
      "--head",
      branch_name,
    ],
    stdout=process_read,
    cwd=repo.local_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @stdio.stdout.write(
      "warning [\{repo.name}] - Failed to create pull request\n",
    )
    return None
  }
  let pr_url = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  @stdio.stdout.write("info [\{repo.name}] - Pull request created: \{pr_url}\n")
  Some(pr_url)
}
