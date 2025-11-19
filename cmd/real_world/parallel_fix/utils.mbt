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
