///|
/// Common utility functions for the parallel repository fixer

///|
/// Extract repository name from URL
fn extract_repo_name(url : String) -> String {
  let path = url.strip_suffix(".git").unwrap_or(url)
  // Split by '/' and take the last part
  match path.split("/").to_array().last() {
    Some(name) => name.to_string()
    None => url
  }
}

///|
/// Get current timestamp as string for unique branch names
fn get_timestamp() -> String {
  @async.now().to_string()
}

///|
/// Get current timestamp in ISO 8601 format for database
fn now() -> String {
  // Use Unix timestamp for now (simplified)
  // TODO: Use proper ISO 8601 formatting when datetime library is available
  @async.now().to_string()
}

///|
/// Escape single quotes for SQL
fn escape_sql(s : String) -> String {
  s.replace(old="'", new="''")
}

///|
/// Fetch PR state information from GitHub using gh CLI
/// Returns None if gh is not available or PR doesn't exist
async fn fetch_pr_state(clone_path : String, pr_number : Int) -> PrStateInfo {
  let pr_info = @gh.get_pr_state(clone_path, pr_number) catch {
    e => @error.reraise(e)
  }
  PrStateInfo::{
    state: pr_info.state,
    mergeable: pr_info.mergeable,
    review_decision: pr_info.review_decision,
  }
}

///|
/// Fetch PR review comments from GitHub using gh CLI
/// Returns the comments as a formatted string, or None if unable to fetch
async fn fetch_pr_comments(clone_path : String, pr_number : Int) -> String {
  @gh.get_pr_comments(clone_path, pr_number) catch {
    e => @error.reraise(e)
  }
}

///|
/// Read repository URLs from file
async fn read_repos_file(path : String) -> Array[String] {
  let content = @fs.read_file(path).text() catch { e => @error.reraise(e) }
  let repos = []
  for line in content.split("\n") {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    // Skip empty lines and comments
    if !trimmed.is_empty() && !trimmed.has_prefix("#") {
      repos.push(trimmed)
    }
  }
  repos
}

///|
/// Ensure work directory exists
async fn ensure_work_dir(path : String) -> Unit {
  if (@fs.exists(path) catch { e => @error.reraise(e) }) {
    return
  }
  let parts = path.split("/").filter(fn(p) { !p.is_empty() }).collect()
  let is_absolute = path.has_prefix("/")
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
    if !(@fs.exists(current) catch { e => @error.reraise(e) }) {
      @fs.mkdir(current, permission=0o755) catch {
        e => @error.fail_with("Failed to create directory \{current}", e)
      }
    }
  }
}

///|
/// Ensure repository is cloned and checked out to the specified branch
/// This is a simple utility that prepares a repository for AI fixing:
/// 1. Clone repository if it doesn't exist (or discover if it does)
/// 2. Ensure we're on the exact branch specified
/// 3. Create branch from default branch if it doesn't exist
///
/// # Arguments
/// * `path` - Local path where repository should be
/// * `repository` - Repository record with URL
/// * `branch_name` - Exact branch name to checkout (not a prefix)
///
/// # Returns
/// Unit on success, raises Error on failure
async fn ensure_repository(
  path : String,
  repository : RepositoryRecord,
) -> Unit raise Error {
  guard repository.current_branch is Some(branch_name) else {
    @error.fail("Repository record does not have a current_branch set")
  }
  // Step 1: Clone or discover repository
  let exists = @fs.exists(path) catch { e => @error.reraise(e) }
  let git_repo = if exists {
    // Repository already exists, try to discover it
    let repo = @git.GitRepo::discover(path) catch {
      e =>
        @error.fail_with(
          "Directory exists at \{path} but is not a git repository",
          e,
        )
    }
    repo
  } else {
    // Clone repository
    @git.GitRepo::clone(repository.url, path) catch {
      e => @error.reraise(e)
    }
  }

  // Step 2: Get default branch (fallback to "main" if not available)
  let default_branch = git_repo.default_branch.unwrap_or("main")

  // Step 3: Check if we're already on the target branch
  let current = git_repo.current_branch()
  if current is Some(branch) && branch == branch_name {
    // Already on the correct branch
    return
  }

  // Step 4: Try to checkout the branch (might already exist)
  if git_repo.checkout(branch_name) {
    // Branch exists and we successfully checked it out
    return
  }

  // Step 5: Branch doesn't exist - create it from default branch
  // First ensure we're on default branch and it's up to date
  if !git_repo.checkout(default_branch) {
    @error.fail("Failed to checkout default branch: \{default_branch}")
  }
  if !git_repo.pull(branch=default_branch) {
    @error.fail("Failed to pull default branch: \{default_branch}")
  }

  // Create new branch from default branch
  if !git_repo.create_branch(branch_name, from_branch=default_branch) {
    @error.fail("Failed to create branch: \{branch_name}")
  }
}
