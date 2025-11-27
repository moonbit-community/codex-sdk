///|
/// Common utility functions for the parallel repository fixer

///|
/// Extract repository name from URL (owner/repo format)
fn extract_repo_name(url : String) -> String {
  let path = url.strip_suffix(".git").unwrap_or(url)
  guard path.split("/").collect() is [.., org, name] else { return url }
  "\{org}/\{name}"
}

///|
/// Extract owner and repo name from URL
fn extract_owner_repo(url : String) -> (String, String)? {
  let path = url.strip_suffix(".git").unwrap_or(url)
  match path.split("/").collect() {
    [.., owner, repo] => Some((owner.to_string(), repo.to_string()))
    _ => None
  }
}

///|
/// Trim whitespace from output data
fn &@io.Data::trim_output(data : Self) -> String raise {
  data.text().trim(char_set=" \t\n\r").to_string()
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
/// Check if permission level allows write access
fn has_write_permission(permission : String) -> Bool {
  match permission {
    "ADMIN" | "MAINTAIN" | "WRITE" => true
    _ => false
  }
}

///|
/// Check if we have write access to a repository
async fn check_write_access(repo_url : String) -> Bool {
  let (owner, repo) = match extract_owner_repo(repo_url) {
    Some(pair) => pair
    None => return false
  }
  let (status, stdout, _) = @process.collect_output("gh", [
    "repo",
    "view",
    "\{owner}/\{repo}",
    "--json",
    "viewerPermission",
    "--jq",
    ".viewerPermission",
  ]) catch {
    _ => return false
  }
  if status != 0 {
    return false
  }
  has_write_permission(stdout.trim_output())
}

///|
/// Get current GitHub user login
async fn get_current_user() -> String? {
  let (status, stdout, _) = @process.collect_output("gh", [
    "api", "user", "--jq", ".login",
  ]) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  Some(stdout.trim_output())
}

///|
/// Get the fork URL for the current user
async fn get_fork_url(original_url : String) -> String? {
  let (_owner, repo) = match extract_owner_repo(original_url) {
    Some(pair) => pair
    None => return None
  }
  let current_user_opt = get_current_user() catch { _ => None }
  let current_user = match current_user_opt {
    Some(u) => u
    None => return None
  }
  let (fork_status, fork_stdout, _) = @process.collect_output("gh", [
    "repo",
    "list",
    current_user,
    "--fork",
    "--json",
    "nameWithOwner",
    "--jq",
    ".[] | select(.nameWithOwner | contains(\"\{repo}\")) | .nameWithOwner",
  ]) catch {
    _ => return None
  }
  if fork_status != 0 {
    return None
  }
  let fork_name = fork_stdout.trim_output()
  if fork_name.is_empty() {
    return None
  }
  Some("https://github.com/\{fork_name}.git")
}

///|
/// Create a fork of the repository
async fn create_fork(original_url : String) -> String {
  let (owner, repo) = match extract_owner_repo(original_url) {
    Some((o, r)) => (o, r)
    None => @error.fail("Invalid repository URL: \{original_url}")
  }
  @stdio.stdout.write("info Creating fork of \{owner}/\{repo}...\n")
  let (status, _stdout, stderr) = @process.collect_output("gh", [
    "repo",
    "fork",
    "\{owner}/\{repo}",
    "--clone=false",
  ]) catch {
    e => @error.fail_with("Failed to create fork", e)
  }
  if status != 0 {
    @error.fail("Failed to create fork: \{stderr.text()}")
  }
  @stdio.stdout.write("info Fork created successfully\n")
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
  @stdio.stdout.write(
    "info No write access to \{original_url}, checking for fork...\n",
  )

  // Check if fork exists
  match get_fork_url(original_url) {
    Some(fork_url) => {
      @stdio.stdout.write("info Using existing fork: \{fork_url}\n")
      fork_url
    }
    None =>
      // Fork doesn't exist, create one
      create_fork(original_url)
  }
}
