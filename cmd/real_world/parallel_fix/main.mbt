///|
async fn main {
  let args = @sys.get_cli_args()[1:]

  // Parse global arguments using stop_early to detect subcommands
  let parsed = @args.parse(
    args,
    flags=["help"],
    options=["work-dir", "data-dir"],
    aliases={ "h": "help" },
    stop_early=true,
  )

  // Extract global options with defaults
  let work_dir = parsed.options.get("work-dir").unwrap_or("/tmp/parallel-fix")
  let data_dir = parsed.options.get("data-dir").unwrap_or("~/.parallel-fix")

  // Show help if requested
  if parsed.flags.get("help") is Some(true) {
    cmd_help([])
    return
  }

  // Check if first positional argument is a subcommand
  match parsed.positional {
    ["init", .. remaining] => cmd_init(remaining, work_dir, data_dir)
    ["add", .. remaining] => cmd_add(remaining, work_dir, data_dir)
    ["run", .. remaining] => cmd_run(remaining, work_dir, data_dir)
    ["status", .. remaining] => cmd_status(remaining, work_dir, data_dir)
    ["help", .. remaining] => cmd_help(remaining)
    _ => {
      @error.fail(
        "Unknown subcommand or missing subcommand.\n\nUse --help to see available subcommands.",
      )
    }
  }
}

///|
/// Read repository URLs from file
pub async fn read_repos_file(path : String) -> Array[String] {
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
pub async fn ensure_work_dir(path : String) -> Unit {
  if @fs.exists(path) {
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
    if !@fs.exists(current) {
      @fs.mkdir(current, permission=0o755) catch {
        e => @error.fail_with("Failed to create directory \{current}", e)
      }
    }
  }
}

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

