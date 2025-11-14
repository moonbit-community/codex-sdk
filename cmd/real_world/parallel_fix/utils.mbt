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
