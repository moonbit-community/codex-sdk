///|
/// Common utility functions for the parallel repository fixer

///|
/// Extract repository name from URL
pub fn extract_repo_name(url : String) -> String {
  let without_git = if url.has_suffix(".git") {
    let chars = url.to_array()
    let len = chars.length()
    String::from_array(chars[:len - 4])
  } else {
    url
  }
  // Split by '/' and take the last part
  match without_git.split("/").to_array().last() {
    Some(name) => name.to_string()
    None => url
  }
}

///|
/// Get current timestamp as string for unique branch names
pub fn get_timestamp() -> String {
  @async.now().to_string()
}

///|
/// Get current timestamp in ISO 8601 format for database
pub fn now() -> String {
  // Use Unix timestamp for now (simplified)
  // TODO: Use proper ISO 8601 formatting when datetime library is available
  @async.now().to_string()
}

///|
/// Expand home directory (~) in path
pub async fn expand_home_dir(path : String) -> String {
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
pub fn escape_sql(s : String) -> String {
  s.replace(old="'", new="''")
}

///|
/// Extract PR number from GitHub PR URL
/// Example: https://github.com/owner/repo/pull/123 -> Some(123)
pub fn extract_pr_number(pr_url : String) -> Int? {
  @gh.extract_pr_number(pr_url)
}

///|
/// Check if GitHub CLI (gh) is available
/// Returns true if gh is installed, false otherwise
pub async fn ensure_gh_available() -> Unit {
  @gh.ensure_available() catch {
    e => @error.reraise(e)
  }
}

///|
/// Fetch PR state information from GitHub using gh CLI
/// Returns None if gh is not available or PR doesn't exist
pub async fn fetch_pr_state(
  clone_path : String,
  pr_number : Int,
) -> PrStateInfo? {
  match @gh.get_pr_state(clone_path, pr_number) {
    Some(pr_info) =>
      Some(
        PrStateInfo::{
          state: pr_info.state,
          mergeable: pr_info.mergeable,
          review_decision: pr_info.review_decision,
        },
      )
    None => None
  }
}

///|
/// Fetch PR review comments from GitHub using gh CLI
/// Returns the comments as a formatted string, or None if unable to fetch
pub async fn fetch_pr_comments(clone_path : String, pr_number : Int) -> String {
  @gh.get_pr_comments(clone_path, pr_number) catch {
    e => @error.reraise(e)
  }
}
