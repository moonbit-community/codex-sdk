///|
/// Common utility functions for the parallel repository fixer

///|
/// Extract repository name from URL
fn extract_repo_name(url : String) -> String {
  let path = url.strip_suffix(".git").unwrap_or(url)
  // Split by '/' and take the last part
  guard path.split("/").collect() is [.., org, name] else { return url }
  "\{org}/\{name}"
}

///|
/// Escape single quotes for SQL
fn escape_sql(s : String) -> String {
  s.replace(old="'", new="''")
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
async fn execute(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String],
  inherit_env? : Bool,
  stdin? : &@process.ProcessInput,
  cwd? : String,
) -> &@io.Data {
  let (status, stdout, stderr) = @process.collect_output(
    cmd,
    args,
    extra_env?,
    inherit_env?,
    stdin?,
    cwd?,
  ) catch {
    e => @error.reraise(e)
  }
  let stderr = stderr.text() catch { e => @error.reraise(e) }
  if status != 0 {
    @error.fail(
      "Command \{cmd} failed with exit code \{status}. Stderr: \{stderr}",
    )
  }
  stdout
}

///|
/// Check if we have write access to a repository
async fn check_write_access(repo_url : String) -> Bool {
  // Extract owner/repo from URL
  let repo_path = repo_url.strip_suffix(".git").unwrap_or(repo_url)
  guard repo_path.split("/").collect() is [.., owner, repo] else {
    return false
  }
  
  // Use gh to check if we can push to this repo
  let (status, stdout, _) = @process.collect_output(
    "gh",
    ["repo", "view", "\{owner}/\{repo}", "--json", "viewerPermission", "--jq", ".viewerPermission"],
  ) catch {
    _ => return false
  }
  
  if status != 0 {
    return false
  }
  
  // Check the actual permission level
  let permission = stdout.text().trim(char_set=" \t\n\r").to_string()
  
  // We need at least WRITE permission to push
  // Valid write permissions: ADMIN, MAINTAIN, WRITE
  permission == "ADMIN" || permission == "MAINTAIN" || permission == "WRITE"
}

///|
/// Get the fork URL for the current user
async fn get_fork_url(original_url : String) -> String? {
  // Extract owner/repo from original URL
  let repo_path = original_url.strip_suffix(".git").unwrap_or(original_url)
  guard repo_path.split("/").collect() is [.., _owner, repo] else {
    return None
  }
  
  // Get current user
  let (status, stdout, _) = @process.collect_output(
    "gh",
    ["api", "user", "--jq", ".login"],
  ) catch {
    _ => return None
  }
  
  if status != 0 {
    return None
  }
  
  let current_user = stdout.text().trim(char_set=" \t\n\r").to_string()
  
  // Check if fork exists
  let (fork_status, fork_stdout, _) = @process.collect_output(
    "gh",
    ["repo", "list", current_user, "--fork", "--json", "nameWithOwner", "--jq", ".[] | select(.nameWithOwner | contains(\"\{repo}\")) | .nameWithOwner"],
  ) catch {
    _ => return None
  }
  
  if fork_status != 0 {
    return None
  }
  
  let fork_name = fork_stdout.text().trim(char_set=" \t\n\r").to_string()
  if fork_name.is_empty() {
    return None
  }
  
  // Return fork URL in HTTPS format
  Some("https://github.com/\{fork_name}.git")
}

///|
/// Create a fork of the repository
async fn create_fork(original_url : String) -> String {
  // Extract owner/repo from original URL
  let repo_path = original_url.strip_suffix(".git").unwrap_or(original_url)
  guard repo_path.split("/").collect() is [.., owner, repo] else {
    @error.fail("Invalid repository URL: \{original_url}")
  }
  
  @stdio.stdout.write("info Creating fork of \{owner}/\{repo}...\n")
  
  // Create fork using gh
  let (status, _stdout, stderr) = @process.collect_output(
    "gh",
    ["repo", "fork", "\{owner}/\{repo}", "--clone=false"],
  ) catch {
    e => @error.fail_with("Failed to create fork", e)
  }
  
  if status != 0 {
    @error.fail("Failed to create fork: \{stderr.text()}")
  }
  
  @stdio.stdout.write("info Fork created successfully\n")
  
  // Get the fork URL
  match get_fork_url(original_url) {
    Some(fork_url) => {
      @stdio.stdout.write("info Fork URL: \{fork_url}\n")
      fork_url
    }
    None => @error.fail("Failed to get fork URL after creation")
  }
}

///|
/// Get the target repository URL (fork if no write access, original otherwise)
async fn get_target_repo_url(original_url : String) -> String {
  // First check if we have write access to the original repo
  if check_write_access(original_url) {
    @stdio.stdout.write("info Write access confirmed for \{original_url}\n")
    return original_url
  }
  
  @stdio.stdout.write("info No write access to \{original_url}, checking for fork...\n")
  
  // Check if fork exists
  match get_fork_url(original_url) {
    Some(fork_url) => {
      @stdio.stdout.write("info Using existing fork: \{fork_url}\n")
      fork_url
    }
    None => {
      // Fork doesn't exist, create one
      create_fork(original_url)
    }
  }
}
