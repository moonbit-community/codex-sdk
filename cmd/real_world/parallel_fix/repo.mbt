///|
/// Repository information
struct RepoInfo {
  /// Underlying GitRepo instance
  git : @git.GitRepo
  /// Repository URL
  url : String
  /// Repository name (extracted from URL)
  name : String
}

///|
/// Get the local path of the repository
fn RepoInfo::local_path(self : RepoInfo) -> String {
  self.git.path
}

///|
/// Get the default branch of the repository
fn RepoInfo::default_branch(self : RepoInfo) -> String {
  match self.git.default_branch {
    Some(branch) => branch
    None => "main" // fallback
  }
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
  let repo_name = @git.extract_repo_name(url)
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
  let git_repo = if !@fs.exists(clone_path) {
    @stdio.stdout.write("info [\{repo_name}] - Cloning repository...\n")
    match @git.GitRepo::clone(url, clone_path) {
      Some(repo) => repo
      None => @error.fail("Failed to clone repository from \{url}")
    }
  } else {
    @stdio.stdout.write(
      "info [\{repo_name}] - Using existing clone at \{clone_path}\n",
    )
    // Discover existing repo
    let repo = match @git.GitRepo::discover(clone_path) {
      Some(r) => r
      None => @error.fail("Failed to discover git repository at \{clone_path}")
    }
    // Fetch latest changes
    if !repo.fetch() {
      @error.fail("Failed to fetch from \{url}")
    }
    repo
  }
  RepoInfo::{ git: git_repo, url, name: repo_name }
}

///|
/// Get existing AI fix branch or create a new one (idempotent)
/// Returns the branch name that should be used for this task
async fn get_or_create_branch(
  repo : RepoInfo,
  branch_prefix : String,
) -> String {
  // Get current branch using GitRepo
  let current_branch = match repo.git.current_branch() {
    Some(branch) => branch
    None => repo.default_branch()
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
    cwd=repo.local_path(),
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
        if repo.git.checkout(branch) {
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
  let _checkout = repo.git.checkout(repo.default_branch()) catch {
    e => @error.reraise(e)
  }

  // Pull latest changes
  let _pull = repo.git.pull(branch=repo.default_branch()) catch {
    e => @error.reraise(e)
  }

  // Create new branch
  if !repo.git.create_branch(new_branch) {
    @error.fail("Failed to create branch \{new_branch}")
  }
  new_branch
}

///|
/// Check if there are uncommitted changes
async fn has_changes(repo : RepoInfo) -> Bool {
  repo.git.has_changes()
}

///|
/// Check if there are staged changes ready to commit
async fn has_staged_changes(repo : RepoInfo) -> Bool {
  repo.git.has_staged_changes()
}

///|
/// Commit all changes
async fn commit_changes(repo : RepoInfo, message : String) -> Bool {
  // Use GitRepo's commit method which handles adding changes
  if repo.git.commit(message) {
    @stdio.stdout.write(
      "info [\{repo.name}] - Changes committed successfully\n",
    )
    true
    // Check if there were no changes to commit
  } else if !has_staged_changes(repo) {
    @stdio.stdout.write("info [\{repo.name}] - No changes to commit\n")
    false
  } else {
    @error.fail("Failed to commit changes")
  }
}

///|
/// Push branch to remote
async fn push_branch(repo : RepoInfo, branch_name : String) -> Unit {
  @stdio.stdout.write(
    "info [\{repo.name}] - Pushing branch \{branch_name} to origin...\n",
  )
  if !repo.git.push(branch=branch_name, set_upstream=true) {
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
      repo.default_branch(),
      "--head",
      branch_name,
    ],
    stdout=process_read,
    cwd=repo.local_path(),
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
