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
/// Check if GitHub CLI (gh) is available
/// Returns true if gh is installed, false otherwise
pub async fn is_gh_available() -> Bool {
  let (_, discard_read) = @process.read_from_process()
  let status = @process.run("which", ["gh"], stdout=discard_read) catch {
    _ => 1
  }
  status == 0
}

///|
/// Extract PR number from GitHub PR URL
/// Example: https://github.com/owner/repo/pull/123 -> Some(123)
pub fn extract_pr_number(pr_url : String) -> Int? {
  let parts = pr_url.split("/").to_array()
  if parts.length() > 0 {
    let last = parts[parts.length() - 1].to_string().trim(char_set=" \t\n\r")
    let num = @strconv.parse_int(last) catch { _ => -1 }
    if num > 0 {
      Some(num)
    } else {
      None
    }
  } else {
    None
  }
}

///|
/// PR state information fetched from GitHub
pub struct PrStateInfo {
  state : String // OPEN, CLOSED, MERGED
  mergeable : String // MERGEABLE, CONFLICTING, UNKNOWN
  review_decision : String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or empty string
}

///|
/// Fetch PR state information from GitHub using gh CLI
/// Returns None if gh is not available or PR doesn't exist
pub async fn fetch_pr_state(
  clone_path : String,
  pr_number : Int,
) -> PrStateInfo? {
  // Check if gh is available
  let which_status = @process.run("which", ["gh"]) catch { _ => 1 }
  if which_status != 0 {
    return None
  }

  // Fetch PR details using gh api
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "gh",
    [
      "pr",
      "view",
      pr_number.to_string(),
      "--json",
      "state,mergeable,reviewDecision",
    ],
    stdout=process_read,
    cwd=clone_path,
  ) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  let output = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()

  // Parse JSON output
  let json = @json.parse(output) catch { _ => return None }
  match json {
    Object(obj) => {
      guard obj.get("state") is Some(String(state)) else { return None }
      // Parse mergeable as string (MERGEABLE, CONFLICTING, UNKNOWN)
      let mergeable = match obj.get("mergeable") {
        Some(String(s)) => s
        _ => "UNKNOWN"
      }
      // Parse review decision as string (may be empty)
      let review_decision = match obj.get("reviewDecision") {
        Some(String(s)) => s
        _ => ""
      }
      Some(PrStateInfo::{ state, mergeable, review_decision })
    }
    _ => None
  }
}
