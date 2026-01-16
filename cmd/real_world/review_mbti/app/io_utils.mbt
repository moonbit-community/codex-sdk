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
/// Get changed mbti files from git
async fn get_changed_mbti_files(project_root : String) -> Array[String] {
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["diff", "--name-only", "HEAD"],
    stdout=process_read,
    cwd=project_root,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail("Git diff failed with status \{status}")
  }
  let output = pipe.read_all().text()
  let changed = []
  for line in output.split("\n") {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    if trimmed.has_suffix("pkg.generated.mbti") {
      changed.push("\{project_root}/\{trimmed}")
    }
  }
  if changed.is_empty() {
    @stdio.stdout.write("No changed pkg.generated.mbti files found\n")
  }
  changed
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
