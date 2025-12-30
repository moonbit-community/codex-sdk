///|
struct FileSummary {
  path : String
  summary : String
}

///|
fn indent(level : Int) -> String {
  let pieces : Array[String] = []
  for _ in 0..<level {
    pieces.push("  ")
  }
  pieces.join("")
}

///|
fn build_tree(paths : Array[String]) -> String {
  let lines : Array[String] = []
  for path in paths {
    let parts = path.split("/").collect()
    let level = if parts.length() > 0 { parts.length() - 1 } else { 0 }
    lines.push("\{indent(level)}- \{path}")
  }
  lines.join("\n")
}

///|
fn truncate_text(text : String, max_chars : Int) -> String {
  if text.length() <= max_chars {
    return text
  }
  let prefix = try! text[:max_chars].to_string()
  "\{prefix}\n...[truncated]"
}

///|
async fn collect_files(root : String) -> Array[String] {
  let files : Array[String] = []
  async fn visit(dir_path : String, rel_prefix : String) {
    let entries = @fs.readdir(dir_path, include_hidden=false) catch {
      _ => return
    }
    for entry in entries {
      let full_path = "\{dir_path}/\{entry}"
      let rel_path = if rel_prefix.is_empty() {
        entry
      } else {
        "\{rel_prefix}/\{entry}"
      }
      let kind = @fs.kind(full_path) catch { _ => continue }
      match kind {
        Directory => visit(full_path, rel_path)
        Regular => files.push(rel_path)
        _ => ()
      }
    }
  }

  visit(root, "")
  files
}

///|
async fn read_file_text(
  root : String,
  rel_path : String,
  max_chars : Int,
) -> String? {
  let content = @fs.read_file("\{root}/\{rel_path}").text() catch {
    _ => return None
  }
  Some(truncate_text(content, max_chars))
}

///|
fn parse_env_int(env : Map[String, String], key : String) -> Int? {
  match env.get(key) {
    Some(value) =>
      try {
        Some(@strconv.parse_int(value.trim(chars=" \t\n\r")))
      } catch {
        _ => None
      }
    None => None
  }
}

///|
async fn load_done_log(
  log_path : String,
) -> (Array[String], Map[String, Bool]) {
  let lines : Array[String] = []
  let done : Map[String, Bool] = {}
  let text = @fs.read_file(log_path).text() catch {
    _ => return (lines, done)
  }
  let parts = text.split("\n").collect()
  for part in parts {
    let trimmed = part.trim(char_set=" \t\n\r").to_string()
    if trimmed.is_empty() {
      continue
    }
    lines.push(trimmed)
    done[trimmed] = true
  }
  (lines, done)
}

///|
fn slice_files(
  files : Array[String],
  offset : Int,
  limit : Int?,
) -> Array[String] {
  let selected : Array[String] = []
  let start = if offset < 0 { 0 } else { offset }
  let end = match limit {
    Some(value) =>
      if value < 0 {
        files.length()
      } else {
        start + value
      }
    None => files.length()
  }
  let mut index = 0
  for path in files {
    if index < start {
      index += 1
      continue
    }
    if index >= end {
      break
    }
    selected.push(path)
    index += 1
  }
  selected
}

///|
async fn record_done(
  log_path : String,
  log_lines : Array[String],
  done : Map[String, Bool],
  log_lock : @async.Semaphore,
  path : String,
) -> Unit {
  log_lock.acquire()
  defer log_lock.release()
  if done.get(path) is Some(_) {
    return
  }
  done[path] = true
  log_lines.push(path)
  let content = log_lines.join("\n") + "\n"
  @fs.write_file(log_path, @encoding/utf8.encode(content), create=0o600) catch {
    e => @stdio.stderr.write("Failed to write done log: \{e}\n")
  }
}

///|
async fn summarize_file(
  codex : @codex.Codex,
  workdir : String,
  path : String,
  content : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=workdir,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|Summarize this file in 2-4 bullets.
    $|File path: \{path}
    $|Content:
    $|\{content}
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn summarize_tree(
  codex : @codex.Codex,
  workdir : String,
  tree : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=workdir,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|Summarize this directory tree in 3-5 bullets.
    $|Tree:
    $|\{tree}
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn summarize_repo(
  codex : @codex.Codex,
  workdir : String,
  content : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=workdir,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|Summarize the repository content in 5-7 bullets.
    $|Content:
    $|\{content}
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn main {
  let env = @sys.get_env_vars()
  let workdir = env.get("CODEX_WORKDIR").unwrap_or(".")
  let offset = parse_env_int(env, "CODEX_OFFSET").unwrap_or(0)
  let limit = parse_env_int(env, "CODEX_LIMIT")
  let log_path =
    env.get("CODEX_DONE_LOG").unwrap_or("\{workdir}/.codex_done.log")
  let max_file_chars = 4000
  let max_repo_chars = 20000
  let files = collect_files(workdir)
  let (log_lines, done) = load_done_log(log_path) catch {
    _ => ([], {})
  }
  let pending_files : Array[String] = []
  for path in files {
    if done.get(path) is None {
      pending_files.push(path)
    }
  }
  let target_files = slice_files(pending_files, offset, limit)
  let codex = @codex.Codex::new()
  let summaries : Array[FileSummary] = []
  let full_content_parts : Array[String] = []
  let parallelism = 4
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(parallelism)
    let log_lock = @async.Semaphore::new(1)
    for path in target_files {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let content = read_file_text(workdir, path, max_file_chars) catch {
          _ => None
        }
        if content is Some(text) {
          let summary = summarize_file(codex, workdir, path, text) catch {
            e => "ERROR: \{e}"
          }
          summaries.push(FileSummary::{ path, summary })
          full_content_parts.push("FILE: \{path}\n\{text}\n")
          record_done(log_path, log_lines, done, log_lock, path) catch {
            _ => ()
          }
        }
      })
    }
  })
  @stdio.stdout.write("== File Summaries ==\n")
  for item in summaries {
    @stdio.stdout.write("\nFILE: \{item.path}\n\{item.summary}\n")
  }
  let tree = build_tree(files)
  let tree_summary = summarize_tree(codex, workdir, tree) catch {
    e => "ERROR: \{e}"
  }
  @stdio.stdout.write("\n== Tree Summary ==\n\{tree_summary}\n")
  let repo_content = truncate_text(
    full_content_parts.join("\n"),
    max_repo_chars,
  )
  let repo_summary = summarize_repo(codex, workdir, repo_content) catch {
    e => "ERROR: \{e}"
  }
  @stdio.stdout.write("\n== Repository Summary ==\n\{repo_summary}\n")
}
