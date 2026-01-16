///|
/// Recursively find all pkg.generated.mbti files
async fn find_mbti_files(dir : String, results : Array[String]) -> Unit {
  let entries = @fs.readdir(dir, include_hidden=false) catch { _ => return }
  let basename = dir.split("/").iter().last().unwrap_or("")
  if basename.has_prefix(".") ||
    basename == "node_modules" ||
    basename == "target" {
    return
  }
  if entries.contains("pkg.generated.mbti") {
    results.push("\{dir}/pkg.generated.mbti")
  }
  for entry in entries {
    let full_path = "\{dir}/\{entry}"
    let kind = @fs.kind(full_path)
    if kind is Directory {
      find_mbti_files(full_path, results)
    }
  }
}

///|
/// Helper to create directory path recursively
async fn mkdir_recursive(path : String) -> Unit {
  if @fs.exists(path) {
    return
  }
  let is_absolute = path.has_prefix("/")
  let parts = path.split("/").filter(fn(p) { !p.is_empty() }).collect()
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
    if !@fs.exists(current) {
      @fs.mkdir(current, permission=0o755) catch {
        e => @error.fail_with("Failed to create directory \{current}", e)
      }
    }
  }
}
