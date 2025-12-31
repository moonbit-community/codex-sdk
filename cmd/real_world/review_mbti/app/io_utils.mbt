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
/// Extract package name from mbti file content
fn extract_package_name(content : String) -> String {
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim(char_set=" \t\n\r").to_string()
    if trimmed.has_prefix("package") {
      let parts = trimmed.split("\"").collect()
      if parts.length() >= 2 {
        return parts[1].to_string()
      }
    }
  }
  "unknown"
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

///|
/// Save review result to file
pub async fn save_review_to_file(
  result : ReviewResult,
  output_dir : String,
) -> String? {
  if !result.success {
    return None
  }
  mkdir_recursive(output_dir) catch {
    e => @error.fail_with("Failed to create output directory \{output_dir}", e)
  }
  let file_name = result.file
    .replace_all(old="/pkg.generated.mbti", new="")
    .replace_all(old="/", new="_") +
    ".review.md"
  let output_path = "\{output_dir}/\{file_name}"
  let status_icon = "✓ Success"
  let content_text =
    $|# Review: \{result.pkg_name}
    $|
    $|**File:** `\{result.file}`  
    $|**Status:** \{status_icon}
    $|
    $|---
    $|
    $|\{result.review}
    $|
  @fs.write_file(output_path, @encoding/utf8.encode(content_text), create=0o700) catch {
    e => @error.fail_with("Failed to write review file to \{output_path}", e)
  }
  Some(output_path)
}
