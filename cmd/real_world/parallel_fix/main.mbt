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
    ["add", .. remaining] => cmd_add(remaining, data_dir)
    ["run", .. remaining] => cmd_run(remaining, work_dir, data_dir)
    ["status", .. remaining] => cmd_status(remaining, data_dir)
    ["sync-prs", .. remaining] => cmd_sync_prs(remaining, work_dir, data_dir)
    ["help", .. remaining] => cmd_help(remaining)
    _ =>
      @error.fail(
        "Unknown subcommand or missing subcommand.\n\nUse --help to see available subcommands.",
      )
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
  })

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }
  let db_path = "\{data_dir}/parallel-fix.db"
  @stdio.stdout.write(
    (
      #|Initializing parallel fix workspace...
      $|  Work directory (clones): \{work_dir}
      $|  Data directory (database): \{data_dir}
      $|  Database: \{db_path}
      #|
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
async fn cmd_add(args : ArrayView[String], data_dir : String) -> Unit {
  let help_message =
    #|Usage: add <repos-file> [OPTIONS]
    #|
    #|Add repositories to the queue
    #|
    #|Options:
    #|  --task <desc>       Task description (required)
    #|  --help, -h          Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>   Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>   Data directory for database (default: ~/.parallel-fix)
    #|

  // Parse arguments
  let parsed_args = @args.parse(args, flags=["help"], options=["task"], aliases={
    "h": "help",
  })

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

  // Get task description
  guard parsed_args.options.get("task") is Some(task_description) else {
    @error.fail(
      "Missing required option: --task <description>\n\{help_message}",
    )
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
    if add_repository(db, repo_url, task_description) is Some(_) {
      added = added + 1
      @stdio.stdout.write(
        "  ✓ Added: \{repo_url} with task: \{task_description}\n",
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
      #|
      $|✓ Done! Added \{added} repository-task pairs, skipped \{skipped}
      #|
      #|Next: moon run real_world/parallel_fix -- run --parallelism 8
      #|
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
  })

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
        @stdio.stdout.write("    Task: \{repo.task}\n")
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
        @stdio.stdout.write("    Task: \{repo.task}\n")
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
  })

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
/// Handle the 'help' subcommand
/// Shows help for subcommands
async fn cmd_help(_args : ArrayView[String]) -> Unit {
  let help_message =
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
  @stdio.stdout.write(help_message)
}

///|
/// Handle the 'run' subcommand
/// Start/resume processing repositories from the database
async fn cmd_run(
  args : ArrayView[String],
  work_dir : String,
  data_dir : String,
) -> Unit {
  let help_message =
    #|Usage: run [OPTIONS]
    #|
    #|Start or resume processing repositories from the database queue
    #|
    #|Options:
    #|  --parallelism <n>      Number of parallel workers (default: 4)
    #|  --branch-prefix <p>    Branch name prefix (default: "ai-fix")
    #|  --help, -h             Show this help
    #|
    #|Global options are set before the subcommand:
    #|  --work-dir <path>      Working directory for clones (default: /tmp/parallel-fix)
    #|  --data-dir <path>      Data directory for database (default: ~/.parallel-fix)
    #|
    #|Note: Each run is a fresh start. There is no persistent failure state.
    #|

  // Parse arguments
  let parsed_args = @args.parse(
    args,
    flags=["help"],
    options=["parallelism", "branch-prefix"],
    aliases={ "h": "help" },
  )

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }

  // Main logic - expand ~ in data_dir
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
  let db_path = "\{data_dir}/parallel-fix.db"

  // Check if database exists
  let db = @sqlite.Database::new(db_path)
  db.ensure() catch {
    e =>
      @error.fail_with(
        "Database not found. Please run 'init' first:\n  moon run real_world/parallel_fix -- init",
        e,
      )
  }
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\nSTARTING PARALLEL REPOSITORY PROCESSING\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n\n")
  @stdio.stdout.write("Configuration:\n")
  @stdio.stdout.write("  Work directory: \{work_dir}\n")
  @stdio.stdout.write("  Parallelism: \{parallelism}\n")
  @stdio.stdout.write("  Branch prefix: \{branch_prefix}\n")
  @stdio.stdout.write("\n")

  // Create codex instance
  let codex = @codex.Codex::new()

  // Create worker config
  let config = WorkerConfig::{ work_dir, branch_prefix, codex, db }

  // Get total count and incomplete count
  let total = total_count(db)
  if total == 0 {
    @stdio.stdout.write(
      "No repositories in database. Add some with:\n  moon run real_world/parallel_fix -- add <repos-file> --task \"description\"\n",
    )
    return
  }
  @stdio.stdout.write("Total repositories: \{total}\n")

  // Get all incomplete repositories
  let incomplete_repos = get_incomplete_repos(db)
  if incomplete_repos.is_empty() {
    @stdio.stdout.write("\nNo incomplete repositories to process. All done!\n")
    return
  }
  @stdio.stdout.write(
    "\nProcessing \{incomplete_repos.length()} incomplete repositories...\n\n",
  )

  // Process all repositories in parallel with bounded concurrency
  let mut processed = 0
  let mut successful = 0
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(parallelism)
    for repo in incomplete_repos {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        processed = processed + 1
        process_repository(config, repo) catch {
          e =>
            @stdio.stderr.write(
              "error [\{repo.url}] - Unexpected error: \{e}\n",
            )
        }
        successful = successful + 1
      })
    }
  })

  // Print final summary
  @stdio.stdout.write("\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\nFINAL SUMMARY\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n")
  @stdio.stdout.write("  Processed: \{processed}\n")
  @stdio.stdout.write("  Successful: \{successful}\n")
  @stdio.stdout.write("\n")
  @stdio.stdout.write(
    "Run 'moon run real_world/parallel_fix -- status --verbose' for detailed status\n",
  )
}
