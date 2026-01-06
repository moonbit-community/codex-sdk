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
/// Get display title for a task (prefer summarized title).
fn task_display_title(repo : RepositoryRecord) -> String {
  repo.task_title.unwrap_or(repo.task)
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
/// Ensure database schema is initialized
async fn ensure_db_schema(db : @sqlite.Database) -> Unit {
  db.exec(schema_sql) catch {
    e => @error.fail_with("Failed to ensure database schema", e)
  }
  ensure_repo_columns(db) catch {
    e => @error.fail_with("Failed to ensure repository columns", e)
  }
}

///|
/// Ensure optional columns exist for the repositories table
async fn ensure_repo_columns(db : @sqlite.Database) -> Unit {
  let rows = db.query("PRAGMA table_info(repositories);") catch {
    e => @error.reraise(e)
  }
  let columns = @hashset.HashSet::new()
  for row in rows {
    match row {
      Object({ "name": String(name), .. }) => {
        columns.add(name)
      }
      _ => continue
    }
  }
  if !columns.contains("last_pr_head_sha") {
    db.exec("ALTER TABLE repositories ADD COLUMN last_pr_head_sha TEXT;") catch {
      e => @error.reraise(e)
    }
  }
  if !columns.contains("last_pr_comment_count") {
    db.exec(
      "ALTER TABLE repositories ADD COLUMN last_pr_comment_count INTEGER;",
    ) catch {
      e => @error.reraise(e)
    }
  }
  if !columns.contains("task_title") {
    db.exec("ALTER TABLE repositories ADD COLUMN task_title TEXT;") catch {
      e => @error.reraise(e)
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
/// Choose a fork name, adding a numeric suffix on collisions.
fn fork_candidate_name(repo : String, attempt : Int) -> String {
  if attempt == 0 {
    repo
  } else {
    "\{repo}-\{attempt + 1}"
  }
}

///|
/// Get repository nameWithOwner and parent nameWithOwner (empty if no parent)
async fn get_repo_name_and_parent(owner_repo : String) -> (String, String)? {
  let (status, stdout, _) = @process.collect_output("gh", [
    "repo",
    "view",
    owner_repo,
    "--json",
    "nameWithOwner,parent",
    "--jq",
    ".nameWithOwner + \"|\" + (.parent.nameWithOwner // \"\")",
  ]) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  let output = stdout.trim_output()
  guard output.split("|").collect() is [name, parent] else { return None }
  Some((name.to_string(), parent.to_string()))
}

///|
/// Check if a repository exists on GitHub.
async fn ensure_repo_exists(owner_repo : String) -> Unit {
  let (status, _stdout, stderr) = @process.collect_output("gh", [
    "repo",
    "view",
    owner_repo,
    "--json",
    "nameWithOwner",
  ]) catch {
    e => @error.fail_with("Failed to check repository existence", e)
  }
  if status != 0 {
    @error.fail("Repository not found: \{owner_repo}. \{stderr.text()}")
  }
}

///|
/// Create a fork with a specific name and verify the parent repository.
async fn try_create_fork_url(
  original_repo : String,
  current_user : String,
  fork_name : String,
) -> String? {
  @stdio.stdout.write("info Creating fork \{current_user}/\{fork_name}...\n")
  let (status, _stdout, stderr) = @process.collect_output("gh", [
    "repo",
    "fork",
    original_repo,
    "--clone=false",
    "--fork-name",
    fork_name,
  ]) catch {
    e => {
      @stdio.stderr.write("warning Failed to create fork: \{e}\n")
      return None
    }
  }
  if status != 0 {
    let error_text = stderr.text()
    if error_text.contains("HTTP 404") {
      @error.fail("Repository not found: \{original_repo}")
    }
    @stdio.stderr.write("warning Failed to create fork: \{error_text}\n")
    return None
  }
  let fork_url = @async.retry(
    @async.RetryMethod::FixedDelay(2000),
    max_retry=10,
    async fn() {
      match get_repo_name_and_parent("\{current_user}/\{fork_name}") {
        Some((name, parent)) if parent == original_repo =>
          "https://github.com/\{name}.git"
        Some(_) => @error.fail("Fork parent mismatch")
        None => @error.fail("Fork not yet available in API")
      }
    },
  ) catch {
    e => {
      @stdio.stderr.write("warning Failed to verify fork: \{e}\n")
      return None
    }
  }
  @stdio.stdout.write("info Fork URL: \{fork_url}\n")
  Some(fork_url)
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
  let (owner, repo) = match extract_owner_repo(original_url) {
    Some((o, r)) => (o, r)
    None => @error.fail("Invalid repository URL: \{original_url}")
  }
  let current_user_opt = get_current_user() catch { _ => None }
  let current_user = match current_user_opt {
    Some(u) => u
    None => @error.fail("Unable to determine current GitHub user")
  }
  let original_repo = "\{owner}/\{repo}"
  ensure_repo_exists(original_repo) catch {
    e => @error.reraise(e)
  }
  let mut attempt = 0
  while attempt < 20 {
    let fork_name = fork_candidate_name(repo, attempt)
    let candidate_owner_repo = "\{current_user}/\{fork_name}"
    match get_repo_name_and_parent(candidate_owner_repo) {
      Some((name, parent)) =>
        if parent == original_repo {
          let fork_url = "https://github.com/\{name}.git"
          @stdio.stdout.write("info Using existing fork: \{fork_url}\n")
          return fork_url
        } else {
          @stdio.stdout.write(
            "info Fork name \{candidate_owner_repo} is not a fork of \{original_repo}, trying next...\n",
          )
        }
      None =>
        match try_create_fork_url(original_repo, current_user, fork_name) {
          Some(fork_url) => return fork_url
          None =>
            @stdio.stdout.write(
              "info Failed to create fork \{candidate_owner_repo}, trying next...\n",
            )
        }
    }
    attempt = attempt + 1
  }
  @error.fail("Unable to find or create a valid fork for \{original_repo}")
}
