///|
pub struct ParsedCommand {
  subcommand : String
  args : ArrayView[String]
  work_dir : String
  data_dir : String
}

///|
pub fn parse_cli_args(cli_args : ArrayView[String]) -> ParsedCommand? raise {
  // Parse global arguments using stop_early to detect subcommands
  let parsed = @args.parse(
    cli_args,
    flags=["help"],
    options=["work-dir", "data-dir"],
    aliases={ "h": "help" },
    stop_early=true,
  ) catch {
    e => @error.reraise(e)
  }

  // Extract global options with defaults
  let work_dir = parsed.options.get("work-dir").unwrap_or("/tmp/parallel-fix")
  let home = @sys.get_env_vars().get("HOME").unwrap_or("")
  let data_dir = parsed.options
    .get("data-dir")
    .unwrap_or("\{home}/.parallel-fix")

  // Show help if requested
  if parsed.flags.get("help") is Some(true) {
    return None
  }

  // Check if first positional argument is a subcommand
  match parsed.positional {
    ["init", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "init",
        args: remaining,
        work_dir,
        data_dir,
      })
    ["add", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "add",
        args: remaining,
        work_dir,
        data_dir,
      })
    ["run", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "run",
        args: remaining,
        work_dir,
        data_dir,
      })
    ["status", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "status",
        args: remaining,
        work_dir,
        data_dir,
      })
    ["sync-prs", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "sync-prs",
        args: remaining,
        work_dir,
        data_dir,
      })
    ["help", .. remaining] =>
      Some(ParsedCommand::{
        subcommand: "help",
        args: remaining,
        work_dir,
        data_dir,
      })
    [] =>
      @error.fail(
        (
          #|No subcommand provided.
          #|Use --help to see available subcommands.",
        ),
      )
    [subcommand, ..] =>
      @error.fail(
        (
          $|Unknown subcommand \{subcommand}.
          $|Use --help to see available subcommands.",
        ),
      )
  }
}

///|
pub async fn run_non_run(command : ParsedCommand, codex : @codex.Codex) -> Unit {
  match command.subcommand {
    "init" => cmd_init(command.args, command.work_dir, command.data_dir)
    "add" => cmd_add(command.args, command.data_dir, codex)
    "status" => cmd_status(command.args, command.data_dir)
    "sync-prs" => cmd_sync_prs(command.args, command.work_dir, command.data_dir)
    "help" => cmd_help(command.args)
    "run" => @error.fail("Run command should be handled by main")
    _ => @error.fail("Unknown subcommand: \{command.subcommand}")
  }
}

///|
pub struct RunContext {
  work_dir : String
  data_dir : String
  parallelism : Int
  branch_prefix : String
  dry_run : Bool
  db : @sqlite.Database
  total : Int
  incomplete_repos : Array[RepositoryRecord]
}

///|
pub fn run_help_message() -> String {
  let message =
    #|Usage: run [OPTIONS]
    #|
    #|Start or resume processing repositories from the database queue
    #|
    #|Options:
    #|  --parallelism <n>      Number of parallel workers (default: 4)
    #|  --branch-prefix <p>    Branch name prefix (default: "ai-fix")
    #|  --offset <n>          Skip first n repositories (default: 0)
    #|  --limit <n>           Process at most n repositories (default: all)
    #|  --dry-run              Preview what would be processed without executing
    #|  --help, -h             Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>      Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>      Data directory for database (default: ~/.parallel-fix)
    #|
    #|Note: Each run is a fresh start. There is no persistent failure state.
    #|
  message
}

///|
pub async fn prepare_run(
  args : ArrayView[String],
  work_dir : String,
  data_dir : String,
) -> RunContext? {
  let parsed_args = @args.parse(
    args,
    flags=["help", "dry-run"],
    options=["parallelism", "branch-prefix", "offset", "limit"],
    aliases={ "h": "help" },
  ) catch {
    e => @error.reraise(e)
  }
  if parsed_args.flags.get("help") is Some(true) {
    return None
  }
  let dry_run = parsed_args.flags.get("dry-run") is Some(true)
  let parallelism_str = parsed_args.options.get("parallelism").unwrap_or("4")
  let parallelism = @strconv.parse_int(parallelism_str) catch {
    e => @error.fail_with("Invalid parallelism value", e)
  }
  if parallelism <= 0 {
    @error.fail("Parallelism must be a positive integer")
  }
  let branch_prefix = parsed_args.options
    .get("branch-prefix")
    .unwrap_or("ai-fix")
  let offset_str = parsed_args.options.get("offset").unwrap_or("0")
  let offset = @strconv.parse_int(offset_str) catch {
    e => @error.fail_with("Invalid offset value", e)
  }
  if offset < 0 {
    @error.fail("Offset must be a non-negative integer")
  }
  let limit_str = parsed_args.options.get("limit").unwrap_or("-1")
  let limit = @strconv.parse_int(limit_str) catch {
    e => @error.fail_with("Invalid limit value", e)
  }
  let db_path = "\{data_dir}/parallel-fix.db"
  let db = @sqlite.Database::new(db_path)
  db.ensure() catch {
    e =>
      @error.fail_with(
        "Database not found. Please run 'init' first:\n  moon run real_world/parallel_fix -- init",
        e,
      )
  }
  ensure_db_schema(db) catch {
    e => @error.fail_with("Failed to ensure database schema", e)
  }
  let total = total_count(db)
  let all_incomplete_repos = get_incomplete_repos(db)
  let incomplete_repos = if limit == -1 {
    all_incomplete_repos[offset:]
  } else {
    let end_idx = if offset + limit > all_incomplete_repos.length() {
      all_incomplete_repos.length()
    } else {
      offset + limit
    }
    all_incomplete_repos[offset:end_idx]
  }
  Some(RunContext::{
    work_dir,
    data_dir,
    parallelism,
    branch_prefix,
    dry_run,
    db,
    total,
    incomplete_repos: incomplete_repos.to_array(),
  })
}

///|
/// Read a task prompt from a file.
async fn read_prompt_file(path : String) -> String {
  let content = @fs.read_file(path).text() catch { e => @error.reraise(e) }
  let prompt = content.trim(char_set=" \t\n\r").to_string()
  if prompt.is_empty() {
    @error.fail("Task file is empty")
  }
  prompt
}

///|
/// Generate a concise task title using Codex.
async fn generate_task_title_with_codex(
  codex : @codex.Codex,
  prompt : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=".",
      model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
    ),
  )
  let title_prompt = task_title_prompt(prompt)
  let result = thread.run(title_prompt)
  let title_opt = parse_task_title(result.final_response) catch { _ => None }
  match title_opt {
    Some(title) => title
    None => @error.fail("Task title response missing title field")
  }
}

///|
/// Handle the 'init' subcommand
/// Initializes the database and working directory
async fn cmd_init(
  args : ArrayView[String],
  work_dir : String,
  data_dir : String,
) -> Unit {
  let help_message =
    #|Usage: init [OPTIONS]
    #|
    #|Initialize workspace and database
    #|
    #|Options:
    #|  --help, -h          Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|

  // Parse arguments
  let parsed_args = @args.parse(args, flags=["help"], options=[], aliases={
    "h": "help",
  }) catch {
    e => @error.reraise(e)
  }

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }
  let db_path = "\{data_dir}/parallel-fix.db"
  @stdio.stdout.write(
    (
      $|Initializing parallel fix workspace...
      $|  Work directory (clones): \{work_dir}
      $|  Data directory (database): \{data_dir}
      $|  Database: \{db_path}
      $|
    ),
  )
  // Check if sqlite3 is available
  @sqlite.ensure() catch {
    e => @error.fail_with("Failed to find sqlite3", e)
  }
  // Create data directory
  ensure_work_dir(data_dir) catch {
    e => @error.fail_with("Failed to create data directory", e)
  }
  // Create work directory
  ensure_work_dir(work_dir) catch {
    e => @error.fail_with("Failed to create work directory", e)
  }

  // Initialize database
  let db = @sqlite.Database::new(db_path)
  db.exec(schema_sql) catch {
    e => @error.fail_with("Failed to initialize database", e)
  }
  @stdio.stdout.write("✓ Database initialized\n")
  @stdio.stdout.write(
    (
      #|✓ Workspace initialized successfully!
      #|
      #|Next steps:
      #|1. Add repositories: moon run real_world/parallel_fix -- add repos.txt --task "Your task"
      #|2. Start processing: moon run real_world/parallel_fix -- run
    ),
  )
}

///|
/// Handle the 'add' subcommand
/// Adds repositories from a file to the database
async fn cmd_add(
  args : ArrayView[String],
  data_dir : String,
  codex : @codex.Codex,
) -> Unit {
  let help_message =
    #|Usage: add <repos-file> [OPTIONS]
    #|
    #|Add repositories to the queue
    #|
    #|Options:
    #|  --task <desc>       Task description (required unless --task-file)
    #|  --task-file <path>  Task prompt file (required unless --task)
    #|  --help, -h          Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|

  // Parse arguments
  let parsed_args = @args.parse(
    args,
    flags=["help"],
    options=["task", "task-file"],
    aliases={ "h": "help" },
  ) catch {
    e => @error.reraise(e)
  }

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }
  let db_path = "\{data_dir}/parallel-fix.db"

  // Check if sqlite3 is available
  @sqlite.ensure() catch {
    e => @error.fail_with("Failed to find sqlite3", e)
  }
  // Create data directory
  ensure_work_dir(data_dir) catch {
    e => @error.fail_with("Failed to create data directory", e)
  }

  // Get repos file
  guard parsed_args.positional is [repos_file] else {
    @error.fail("Missing required argument: <repos-file>\n\{help_message}")
  }

  // Get task description or task file
  let task_opt = parsed_args.options.get("task")
  let task_file_opt = parsed_args.options.get("task-file")
  if task_opt is Some(_) && task_file_opt is Some(_) {
    @error.fail("Use only one of --task or --task-file\n\{help_message}")
  }
  guard task_opt is Some(_) || task_file_opt is Some(_) else {
    @error.fail(
      "Missing required option: --task <description> or --task-file <path>\n\{help_message}",
    )
  }
  let (task_description, task_title) = match task_file_opt {
    Some(task_file) => {
      let prompt = read_prompt_file(task_file) catch {
        e => @error.fail_with("Failed to read task file", e)
      }
      let title = generate_task_title_with_codex(codex, prompt) catch {
        e => {
          @stdio.stderr.write("warning Failed to summarize task title: \{e}\n")
          "Task"
        }
      }
      (prompt, Some(title))
    }
    None => {
      let task_value = task_opt.unwrap_or("")
      (task_value, Some(task_value))
    }
  }

  // Check if database exists
  let db = @sqlite.Database::new(db_path)
  db.ensure() catch {
    e =>
      @error.fail_with(
        "Database not found. Please run 'init' first:\n  moon run real_world/parallel_fix -- init",
        e,
      )
  }

  // Ensure schema is initialized
  ensure_db_schema(db) catch {
    e => @error.fail_with("Failed to ensure database schema", e)
  }

  // Read repositories
  @stdio.stdout.write("Reading repositories from \{repos_file}...\n")
  let repos = read_repos_file(repos_file) catch {
    e => @error.fail_with("Failed to read repos file", e)
  }
  if repos.is_empty() {
    @stdio.stdout.write("No repositories found in file.\n")
    return
  }
  @stdio.stdout.write("Found \{repos.length()} repositories\n")

  // Add repositories to database
  @stdio.stdout.write("Adding repositories to database...\n")
  let mut added = 0
  let mut skipped = 0
  for repo_url in repos {
    if add_repository(db, repo_url, task_description, task_title) is Some(_) {
      added = added + 1
      @stdio.stdout.write(
        "  ✓ Added: \{repo_url} with task: \{task_title.unwrap_or(task_description)}\n",
      )
    } else {
      skipped = skipped + 1
      @stdio.stdout.write(
        "  - Skipped (this repo+task pair already exists): \{repo_url}\n",
      )
    }
  }
  @stdio.stdout.write(
    (
      $|
      $|✓ Done! Added \{added} repository-task pairs, skipped \{skipped}
      $|
      $|Next: moon run real_world/parallel_fix -- run --parallelism 8
      $|
    ),
  )
}

///|
/// Handle the 'status' subcommand
/// Shows current state of all repositories
async fn cmd_status(args : ArrayView[String], data_dir : String) -> Unit {
  let help_message =
    #|Usage: status [OPTIONS]
    #|
    #|Show current state of all repositories
    #|
    #|Options:
    #|  --verbose, -v       Show detailed output
    #|  --help, -h          Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|

  // Parse arguments
  let parsed_args = @args.parse(args, flags=["help", "verbose"], aliases={
    "h": "help",
    "v": "verbose",
  }) catch {
    e => @error.reraise(e)
  }

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) ||
    parsed_args.positional.length() > 0 {
    @stdio.stdout.write(help_message)
    return
  }
  let db_path = "\{data_dir}/parallel-fix.db"
  let verbose = parsed_args.flags.get("verbose") is Some(true)
  // Check if database exists
  let db = @sqlite.Database::new(db_path)
  db.ensure() catch {
    e => @error.fail_with("Database not found. Please run 'init' first.", e)
  }

  // Ensure schema is initialized
  ensure_db_schema(db) catch {
    e => @error.fail_with("Failed to ensure database schema", e)
  }

  // Get total count and completed count
  let total = total_count(db)
  if total == 0 {
    @stdio.stdout.write(
      "No repositories found. Add some with: add <repos-file> --task \"description\"\n",
    )
    return
  }
  let completed_count = count_completed(db)
  let incomplete_count = total - completed_count
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\nREPOSITORY STATUS\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n\n")
  @stdio.stdout.write("Total repository-task pairs: \{total}\n")
  @stdio.stdout.write("  Completed: \{completed_count}\n")
  @stdio.stdout.write("  Incomplete: \{incomplete_count}\n\n")

  // Show detailed list if verbose
  if verbose {
    let all_repos = get_all_repos(db)
    @stdio.stdout.write("DETAILED LIST:\n")
    @stdio.stdout.write("-".repeat(60))
    @stdio.stdout.write("\n")

    // Group by completion status
    @stdio.stdout.write("\n[Incomplete - \{incomplete_count}]\n")
    let mut shown_incomplete = false
    for repo in all_repos {
      if not(repo.completed) {
        shown_incomplete = true
        @stdio.stdout.write("  - \{repo.url}\n")
        @stdio.stdout.write("    Task: \{task_display_title(repo)}\n")
        match repo.pr_number {
          Some(pr_num) => @stdio.stdout.write("    PR: #\{pr_num}\n")
          None => @stdio.stdout.write("    PR: Not created yet\n")
        }
      }
    }
    if not(shown_incomplete) {
      @stdio.stdout.write("  (none)\n")
    }
    @stdio.stdout.write("\n[Completed - \{completed_count}]\n")
    let mut shown_completed = false
    for repo in all_repos {
      if repo.completed {
        shown_completed = true
        @stdio.stdout.write("  - \{repo.url}\n")
        @stdio.stdout.write("    Task: \{task_display_title(repo)}\n")
        match repo.pr_number {
          Some(pr_num) => @stdio.stdout.write("    PR: #\{pr_num}\n")
          None => @stdio.stdout.write("    PR: N/A\n")
        }
      }
    }
    if not(shown_completed) {
      @stdio.stdout.write("  (none)\n")
    }
  } else {
    @stdio.stdout.write("\nUse --verbose or -v for detailed repository list\n")
  }
}

///|
/// Fetch PR cache data (head sha and comment count).
async fn get_pr_cache_snapshot(
  clone_path : String,
  pr_number : Int,
) -> (String, Int)? {
  let (status, stdout, _stderr) = @process.collect_output(
    "gh",
    [
      "pr",
      "view",
      pr_number.to_string(),
      "--json",
      "headRefOid,comments",
      "--jq",
      ".headRefOid + \"|\" + (.comments | length | tostring)",
    ],
    cwd=clone_path,
  ) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  let output = stdout.trim_output()
  guard output.split("|").collect() is [head_sha, count_str] else {
    return None
  }
  let count = @strconv.parse_int(count_str) catch { _ => return None }
  Some((head_sha.to_string(), count))
}

///|
/// Handle the 'sync-prs' subcommand
/// Sync PR status from GitHub for repositories with PR URLs
async fn cmd_sync_prs(
  args : ArrayView[String],
  work_dir : String,
  data_dir : String,
) -> Unit {
  let help_message =
    #|Usage: sync-prs [OPTIONS]
    #|
    #|Sync PR status from GitHub for all repositories with PR URLs
    #|This is useful to restore correct status after errors or interruptions
    #|
    #|Options:
    #|  --help, -h          Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|

  // Parse arguments
  let parsed_args = @args.parse(args, flags=["help"], options=[], aliases={
    "h": "help",
  }) catch {
    e => @error.reraise(e)
  }

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }
  let db_path = "\{data_dir}/parallel-fix.db"

  // Check if database exists
  let db = @sqlite.Database::new(db_path)
  db.ensure() catch {
    e => @error.fail_with("Database not found. Please run 'init' first.", e)
  }

  // Ensure schema is initialized
  ensure_db_schema(db) catch {
    e => @error.fail_with("Failed to ensure database schema", e)
  }

  // Check if gh is available
  @gh.ensure_available() catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("Syncing PR status from GitHub...\n\n")

  // Get all repositories that have a PR
  let all_repos = get_all_repos(db)
  let mut checked = 0
  let mut reopened = 0
  let mut still_completed = 0
  for repo in all_repos {
    match repo.pr_number {
      Some(pr_num) => {
        checked = checked + 1
        let repo_name = extract_repo_name(repo.url)

        // Clone or update repository to check PR status
        let clone_path = "\{work_dir}/\{repo_name}"
        ensure_repo_cloned(clone_path, repo.url) catch {
          e => {
            @stdio.stderr.write(
              "warning [\{repo_name}] Failed to clone: \{e}\n",
            )
            continue
          }
        }

        // Get PR state
        let pr_state = get_pr_state(clone_path, pr_num) catch {
          e => {
            @stdio.stderr.write(
              "warning [\{repo_name}] Failed to get PR state: \{e}\n",
            )
            continue
          }
        }
        // Update PR cache if possible
        match get_pr_cache_snapshot(clone_path, pr_num) {
          Some((head_sha, comment_count)) =>
            update_pr_cache(db, repo.id, head_sha, comment_count) catch {
              e =>
                @stdio.stderr.write(
                  "warning [\{repo_name}] Failed to update PR cache: \{e}\n",
                )
            }
          None =>
            @stdio.stderr.write(
              "warning [\{repo_name}] Failed to read PR cache metadata\n",
            )
        }

        // If completed but PR is still OPEN, reopen it
        if repo.completed && pr_state == "OPEN" {
          @stdio.stdout.write(
            "info [\{repo_name}] PR #\{pr_num} is still OPEN, reopening task\n",
          )
          mark_incomplete(db, repo.id) catch {
            e => {
              @stdio.stderr.write(
                "warning [\{repo_name}] Failed to mark as incomplete: \{e}\n",
              )
              continue
            }
          }
          reopened = reopened + 1
        } else if repo.completed &&
          (pr_state == "MERGED" || pr_state == "CLOSED") {
          @stdio.stdout.write(
            "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, task correctly completed\n",
          )
          still_completed = still_completed + 1
        } else if not(repo.completed) &&
          (pr_state == "MERGED" || pr_state == "CLOSED") {
          @stdio.stdout.write(
            "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, marking as completed\n",
          )
          mark_completed(db, repo.id) catch {
            e => {
              @stdio.stderr.write(
                "warning [\{repo_name}] Failed to mark as completed: \{e}\n",
              )
              continue
            }
          }
        } else {
          @stdio.stdout.write(
            "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, status unchanged\n",
          )
        }
      }
      None => () // Skip repositories without PR
    }
  }
  @stdio.stdout.write("\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n")
  @stdio.stdout.write("Sync complete!\n")
  @stdio.stdout.write("  Total repositories checked: \{checked}\n")
  @stdio.stdout.write("  Tasks reopened (OPEN PRs): \{reopened}\n")
  @stdio.stdout.write(
    "  Tasks still completed (MERGED/CLOSED): \{still_completed}\n",
  )
}

///|
pub fn help_message() -> String {
  let message =
    #|Usage: moon run real_world/parallel_fix -- [GLOBAL_OPTIONS] <subcommand> [OPTIONS]
    #|
    #|Subcommands:
    #|  init              Initialize workspace and database
    #|  add <repos-file>  Add repositories to the queue
    #|  run               Start/resume processing repositories
    #|  status            Show current state of all repositories
    #|  sync-prs          Sync PR status from GitHub
    #|  help              Show this help message
    #|
    #|Global Options (set before subcommand):
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|  --help, -h          Show help for a subcommand
    #|
    #|Note: work-dir is where repositories are cloned (can be temporary).
    #|      data-dir is where the database is stored (should be persistent).
    #|
    #|Examples:
    #|  # Initialize workspace
    #|  moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/my-fixes init
    #|
    #|  # Add repositories
    #|  moon run real_world/parallel_fix -- --data-dir ~/my-fixes add repos.txt --task "Fix linting"
    #|
    #|  # Start processing
    #|  moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/my-fixes run --parallelism 8
    #|
    #|  # Sync PR status from GitHub
    #|  moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/my-fixes sync-prs
    #|
    #|  # Check status
    #|  moon run real_world/parallel_fix -- --data-dir ~/my-fixes status --verbose
    #|
    #|Use '<subcommand> --help' for more information about a specific subcommand.
    #|
  message
}

///|
/// Handle the 'help' subcommand
/// Shows help for subcommands
async fn cmd_help(_args : ArrayView[String]) -> Unit {
  @stdio.stdout.write(help_message())
}
