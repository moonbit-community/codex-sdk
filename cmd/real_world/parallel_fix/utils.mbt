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
/// Expand home directory (~) in path
async fn expand_home_dir(path : String) -> String {
  if !path.has_prefix("~") {
    return path
  }
  let (pipe, process_read) = @process.read_from_process()
  let _status = @process.run("sh", ["-c", "echo $HOME"], stdout=process_read) catch {
    _ => return path
  }
  let home = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  let home_final = if home.is_empty() { "/tmp" } else { home }
  "\{home_final}\{path[1:].to_string()}"
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
