///|
struct Arguments {
  /// Path to file containing list of repositories (one per line)
  repos_file : String
  /// Number of parallel tasks
  parallelism : Int
  /// Task description to send to AI agent
  task_description : String
  /// Branch name prefix for fix branches
  branch_prefix : String
  /// Base directory for cloning repositories
  work_dir : String
  /// Whether to force fresh clone (delete existing)
  force_fresh : Bool
} derive(Default)

///|
async fn main {
  // First pass: check for subcommands using stop_early
  let initial_args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["help", "verbose", "v"],
    options=["work-dir", "task"],
    stop_early=true,
  )

  // Check if first positional argument is a subcommand
  if initial_args.positional.length() > 0 {
    let maybe_subcommand = initial_args.positional[0].to_string()
    match maybe_subcommand {
      "init" => {
        // Parse remaining args for init command
        let remaining = @sys.get_cli_args()[2:]
        let args = @args.parse(
          remaining,
          flags=["help"],
          options=["work-dir"],
          aliases={ "h": "help" },
        )
        if args.flags.get("help") is Some(true) {
          @stdio.stdout.write(
            "Usage: init [OPTIONS]\n\nInitialize workspace and database\n\nOptions:\n  --work-dir <path>   Working directory (default: /tmp/parallel-fix)\n  --help, -h          Show this help\n",
          )
          return
        }
        cmd_init(args)
        return
      }
      "add" => {
        // Parse remaining args for add command
        let remaining = @sys.get_cli_args()[2:]
        let args = @args.parse(
          remaining,
          flags=["help"],
          options=["work-dir", "task"],
          aliases={ "h": "help" },
        )
        if args.flags.get("help") is Some(true) {
          @stdio.stdout.write(
            "Usage: add <repos-file> [OPTIONS]\n\nAdd repositories to the queue\n\nOptions:\n  --task <desc>       Task description (required)\n  --work-dir <path>   Working directory (default: /tmp/parallel-fix)\n  --help, -h          Show this help\n",
          )
          return
        }
        cmd_add(args)
        return
      }
      "status" => {
        // Parse remaining args for status command
        let remaining = @sys.get_cli_args()[2:]
        let args = @args.parse(
          remaining,
          flags=["help", "verbose", "v"],
          options=["work-dir"],
          aliases={ "h": "help" },
        )
        if args.flags.get("help") is Some(true) {
          @stdio.stdout.write(
            "Usage: status [OPTIONS]\n\nShow current state of all repositories\n\nOptions:\n  --work-dir <path>   Working directory (default: /tmp/parallel-fix)\n  --verbose, -v       Show detailed output\n  --help, -h          Show this help\n",
          )
          return
        }
        cmd_status(args)
        return
      }
      "help" => {
        show_subcommand_help()
        return
      }
      _ => () // Not a subcommand, fall through to original behavior
    }
  }

  // Original behavior: quick one-off batch fix
  // Parse CLI arguments
  let help_message =
    #|Usage: moon run real_world/parallel_fix -- [OPTIONS] <repos-file>
    #|
    #|<repos-file>    Path to file containing repository URLs (one per line)
    #|
    #|Options:
    #|  --task <description>           Task description for AI agent (required)
    #|  --parallelism <n>              Number of parallel tasks (default: 4)
    #|  --branch-prefix <prefix>       Branch name prefix (default: "ai-fix")
    #|  --work-dir <path>              Working directory for clones (default: /tmp/parallel-fix)
    #|  --force-fresh                  Delete existing clones and start fresh
    #|  --help                         Print this help message
    #|
    #|Subcommands (for stateful mode):
    #|  init, add, status, help
    #|
    #|Example:
    #|  moon run real_world/parallel_fix -- repos.txt --task "Fix linting errors" --parallelism 8
    #|
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["help", "resume", "force-fresh"],
    options=["task", "parallelism", "branch-prefix", "work-dir"],
    aliases={ "h": "help" },
  )
  if args.flags.get("help") is Some(true) {
    @stdio.stdout.write("\{help_message}\n")
    return
  }
  guard args.positional is [repos_file] else {
    @error.fail(
      "Missing required positional argument: <repos-file>\n\{help_message}\n",
    )
  }
  guard args.options.get("task") is Some(task_description) else {
    @error.fail(
      "Missing required option: --task <description>\n\{help_message}\n",
    )
  }
  let parallelism = args.options.get("parallelism").unwrap_or("4")
  let argument = Arguments::{
    repos_file,
    parallelism: @strconv.parse_int(parallelism) catch {
      e => @error.fail_with("Invalid parallelism value", e)
    },
    task_description,
    branch_prefix: args.options.get("branch-prefix").unwrap_or("ai-fix"),
    work_dir: args.options.get("work-dir").unwrap_or("/tmp/parallel-fix"),
    force_fresh: args.flags.get("force-fresh") is Some(true),
  }

  // Read repository list
  let repos = read_repos_file(argument.repos_file) catch {
    e => @error.fail_with("Failed to read repos file", e)
  }
  if repos.is_empty() {
    @stdio.stdout.write("No repositories found in \{argument.repos_file}\n")
    return
  }
  @stdio.stdout.write(
    "Loaded \{repos.length()} repositories from \{argument.repos_file}\n",
  )

  // Prepare environment
  let codex = @codex.Codex::new()
  ensure_work_dir(argument.work_dir) catch {
    e => @error.fail_with("Failed to create work directory", e)
  }

  // Process repositories in parallel
  @stdio.stdout.write(
    "Starting parallel processing with \{argument.parallelism} concurrent tasks...\n\n",
  )
  let results : Array[TaskResult] = []
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(argument.parallelism)
    for i, repo in repos {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        @stdio.stdout.write(
          "info [\{i + 1}/\{repos.length()}] \{repo} - Acquired semaphore, starting fix...\n",
        )
        let result = process_repository(
          codex,
          repo,
          argument.task_description,
          argument.branch_prefix,
          argument.work_dir,
          argument.force_fresh,
        ) catch {
          e => {
            @stdio.stderr.write(
              "error [\{i + 1}/\{repos.length()}] \{repo} - Task failed: \{e}\n",
            )
            TaskResult::{
              repo,
              success: false,
              error: e.to_string(),
              pr_url: None,
              thread_id: None,
            }
          }
        }
        results.push(result)
        let status = if result.success { "✓" } else { "✗" }
        @stdio.stdout.write(
          "\{status} [\{i + 1}/\{repos.length()}] \{repo} - Task finished\n",
        )
      })
    }
  })

  // Print summary
  print_summary(results)
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
/// Print summary of results
async fn print_summary(results : Array[TaskResult]) -> Unit {
  let successful = results.filter(fn(r) { r.success })
  let failed = results.filter(fn(r) { !r.success })
  let sep = "=".repeat(80)
  @stdio.stdout.write(
    (
      $|
      $|\{sep}
      $|SUMMARY
      $|\{sep}
      $|Total repositories: \{results.length()}
      $|Successful: \{successful.length()}
      $|Failed: \{failed.length()}
      $|
    ),
  )
  if successful.length() > 0 {
    @stdio.stdout.write("\n✓ Successful repositories:\n")
    for r in successful {
      let pr_info = match r.pr_url {
        Some(url) => " → \{url}"
        None => ""
      }
      @stdio.stdout.write("  - \{r.repo}\{pr_info}\n")
    }
  }
  if failed.length() > 0 {
    @stdio.stdout.write("\n✗ Failed repositories:\n")
    for r in failed {
      @stdio.stdout.write("  - \{r.repo}: \{r.error}\n")
    }
  }
}
