///|
/// Subcommand handlers for the stateful parallel fix system

///|
/// Handle the 'init' subcommand
/// Initializes the database and working directory
pub async fn cmd_init(
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
  @stdio.stdout.write("Initializing parallel fix workspace...\n")
  @stdio.stdout.write("  Work directory (clones): \{work_dir}\n")
  @stdio.stdout.write("  Data directory (database): \{data_dir}\n")
  @stdio.stdout.write("  Database: \{db_path}\n")

  // Check if sqlite3 is available
  if !@sqlite.check_sqlite3() {
    @error.fail(
      "sqlite3 not found. Please install sqlite3 to use stateful mode.",
    )
  }
  @stdio.stdout.write("✓ sqlite3 found\n")

  // Create data directory
  ensure_work_dir(data_dir) catch {
    e => @error.fail_with("Failed to create data directory", e)
  }
  @stdio.stdout.write("✓ Data directory created\n")

  // Create work directory
  ensure_work_dir(work_dir) catch {
    e => @error.fail_with("Failed to create work directory", e)
  }
  @stdio.stdout.write("✓ Work directory created\n")

  // Initialize database
  let state_mgr = StateManager::new(db_path)
  state_mgr.init() catch {
    e => @error.fail_with("Failed to initialize database", e)
  }
  @stdio.stdout.write("✓ Database initialized\n")
  try {
    // Save configuration
    state_mgr.db.exec(
      "INSERT OR REPLACE INTO config (key, value, updated_at) VALUES ('work_dir', '\{work_dir}', '\{now()}');",
    )
    state_mgr.db.exec(
      "INSERT OR REPLACE INTO config (key, value, updated_at) VALUES ('data_dir', '\{data_dir}', '\{now()}');",
    )
  } catch {
    e => @error.fail_with("Failed to save configuration", e)
  }
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
pub async fn cmd_add(args : ArrayView[String], data_dir : String) -> Unit {
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

  // Get repos file
  guard parsed_args.positional.length() > 0 else {
    @error.fail("Missing required argument: <repos-file>\n\{help_message}")
  }
  let repos_file = parsed_args.positional[0].to_string()

  // Get task description
  guard parsed_args.options.get("task") is Some(task_description) else {
    @error.fail(
      "Missing required option: --task <description>\n\{help_message}",
    )
  }

  // Check if database exists
  let state_mgr = StateManager::new(db_path)
  if !state_mgr.db.exists() {
    @error.fail(
      "Database not found. Please run 'init' first:\n  moon run real_world/parallel_fix -- init",
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
    let repo_name = extract_repo_name(repo_url)
    match state_mgr.add_repository(repo_url, repo_name, task_description) {
      Some(_id) => {
        added = added + 1
        @stdio.stdout.write(
          "  ✓ Added: \{repo_name} with task: \{task_description}\n",
        )
      }
      None => {
        skipped = skipped + 1
        @stdio.stdout.write(
          "  - Skipped (this repo+task pair already exists): \{repo_name}\n",
        )
      }
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
pub async fn cmd_status(args : ArrayView[String], data_dir : String) -> Unit {
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
  let parsed_args = @args.parse(
    args,
    flags=["help", "verbose", "v"],
    options=[],
    aliases={ "h": "help" },
  )

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }

  // Main logic - expand ~ in data_dir
  let expanded_data_dir = if data_dir.has_prefix("~") {
    let (pipe, process_read) = @process.read_from_process()
    let _status = @process.run("sh", ["-c", "echo $HOME"], stdout=process_read) catch {
      _ => 1
    }
    let home = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
    let home_final = if home.is_empty() { "/tmp" } else { home }
    "\{home_final}\{data_dir[1:].to_string()}"
  } else {
    data_dir
  }
  let db_path = "\{expanded_data_dir}/parallel-fix.db"
  let verbose = parsed_args.flags.get("verbose") is Some(true) ||
    parsed_args.flags.get("v") is Some(true)

  // Check if database exists
  let state_mgr = StateManager::new(db_path)
  if !state_mgr.db.exists() {
    @error.fail("Database not found. Please run 'init' first.")
  }

  // Get total count
  let total = state_mgr.total_count()
  if total == 0 {
    @stdio.stdout.write(
      "No repositories found. Add some with: add <repos-file> --task \"description\"\n",
    )
    return
  }

  // Get all unique tasks
  let all_tasks = state_mgr.get_all_tasks()

  // Count by state
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\nREPOSITORY STATUS\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n\n")
  @stdio.stdout.write("Total repository-task pairs: \{total}\n")
  @stdio.stdout.write("Unique tasks: \{all_tasks.length()}\n\n")

  // Show breakdown by task
  @stdio.stdout.write("BREAKDOWN BY TASK:\n")
  for task in all_tasks {
    let task_total = state_mgr.count_by_task_and_state(task, Pending) +
      state_mgr.count_by_task_and_state(task, Cloning) +
      state_mgr.count_by_task_and_state(task, Branching) +
      state_mgr.count_by_task_and_state(task, Fixing) +
      state_mgr.count_by_task_and_state(task, Committing) +
      state_mgr.count_by_task_and_state(task, Pushing) +
      state_mgr.count_by_task_and_state(task, PrCreating) +
      state_mgr.count_by_task_and_state(task, PrOpen) +
      state_mgr.count_by_task_and_state(task, Complete) +
      state_mgr.count_by_task_and_state(task, Retry)
    @stdio.stdout.write("  \"\{task}\" - \{task_total} repos\n")
  }
  @stdio.stdout.write("\n")

  // Show counts for each important state (overall)
  @stdio.stdout.write("OVERALL STATE COUNTS:\n")
  let states_to_show = [
    (Pending, "Pending"),
    (Cloning, "Cloning"),
    (Branching, "Branching"),
    (Fixing, "Fixing"),
    (Committing, "Committing"),
    (Pushing, "Pushing"),
    (PrCreating, "PR Creating"),
    (PrOpen, "PR Open"),
    (Complete, "Complete"),
    (Retry, "Retry"),
  ]
  let mut i = 0
  while i < states_to_show.length() {
    let (state, label) = states_to_show[i]
    let count = state_mgr.count_by_state(state)
    if count > 0 {
      @stdio.stdout.write("  \{label}: \{count}\n")
    }
    i = i + 1
  }

  // Show detailed list if verbose
  if verbose {
    @stdio.stdout.write("\n")
    @stdio.stdout.write("=".repeat(60))
    @stdio.stdout.write("\nDETAILED LIST (Grouped by Task)\n")
    @stdio.stdout.write("=".repeat(60))
    @stdio.stdout.write("\n\n")

    // Group by task
    for task in all_tasks {
      @stdio.stdout.write("TASK: \"\{task}\"\n")
      @stdio.stdout.write("-".repeat(60))
      @stdio.stdout.write("\n")
      let mut i = 0
      while i < states_to_show.length() {
        let (state, label) = states_to_show[i]
        let repos = state_mgr.get_repos_in_state(state)
        let task_repos = repos.filter(fn(r) {
          match r.task_description {
            Some(t) => t == task
            None => false
          }
        })
        if task_repos.length() > 0 {
          @stdio.stdout.write("  [\{label}]\n")
          for repo in task_repos {
            @stdio.stdout.write("    - \{repo.name}\n")
            @stdio.stdout.write("      URL: \{repo.url}\n")
            if repo.attempt_count > 0 {
              @stdio.stdout.write("      Attempts: \{repo.attempt_count}\n")
            }
            match repo.last_error {
              Some(err) => @stdio.stdout.write("      Last error: \{err}\n")
              None => ()
            }
          }
        }
        i = i + 1
      }
      @stdio.stdout.write("\n")
    }
  } else {
    @stdio.stdout.write(
      "\nUse --verbose or -v for detailed repository list grouped by task\n",
    )
  }
}

///|
/// Handle the 'help' subcommand
/// Shows help for subcommands
pub async fn cmd_help(_args : ArrayView[String]) -> Unit {
  let help_message =
    #|Usage: moon run real_world/parallel_fix -- [GLOBAL_OPTIONS] <subcommand> [OPTIONS]
    #|
    #|Subcommands:
    #|  init              Initialize workspace and database
    #|  add <repos-file>  Add repositories to the queue
    #|  run               Start/resume processing repositories
    #|  status            Show current state of all repositories
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
    #|  # Retry failed repositories
    #|  moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/my-fixes run --include-failed
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
pub async fn cmd_run(
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
    #|  --include-failed       Include failed repositories for retry (deprecated - kept for compatibility)
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
  let expanded_data_dir = if data_dir.has_prefix("~") {
    let (pipe, process_read) = @process.read_from_process()
    let _status = @process.run("sh", ["-c", "echo $HOME"], stdout=process_read) catch {
      _ => 1
    }
    let home = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
    let home_final = if home.is_empty() { "/tmp" } else { home }
    "\{home_final}\{data_dir[1:].to_string()}"
  } else {
    data_dir
  }
  let parallelism_str = parsed_args.options.get("parallelism").unwrap_or("4")
  let parallelism = @strconv.parse_int(parallelism_str) catch {
    e => @error.fail_with("Invalid parallelism value", e)
  }
  let branch_prefix = parsed_args.options
    .get("branch-prefix")
    .unwrap_or("ai-fix")
  let db_path = "\{expanded_data_dir}/parallel-fix.db"

  // Check if database exists
  let state_mgr = StateManager::new(db_path)
  if !state_mgr.db.exists() {
    @error.fail(
      "Database not found. Please run 'init' first:\n  moon run real_world/parallel_fix -- init",
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
  let config = WorkerConfig::{
    work_dir,
    branch_prefix,
    codex,
    state_mgr,
  }

  // Get total count and processable count
  let total = state_mgr.total_count()
  if total == 0 {
    @stdio.stdout.write(
      "No repositories in database. Add some with:\n  moon run real_world/parallel_fix -- add <repos-file> --task \"description\"\n",
    )
    return
  }
  @stdio.stdout.write("Total repositories: \{total}\n")

  // Process repositories in parallel using worker pool
  let mut processed = 0
  let mut successful = 0
  let mut continue_processing = true
  while continue_processing {
    // Get batch of processable repositories
    let repos = state_mgr.get_processable_repos(parallelism * 2, false)
    if repos.is_empty() {
      @stdio.stdout.write("\nNo more repositories to process.\n")
      continue_processing = false
      continue
    }
    @stdio.stdout.write(
      "\nProcessing batch of \{repos.length()} repositories...\n\n",
    )

    // Process batch in parallel
    @async.with_task_group(fn(task_group) {
      let semaphore = @semaphore.Semaphore::new(parallelism)
      for repo in repos {
        task_group.spawn_bg(allow_failure=true, fn() {
          semaphore.acquire()
          defer semaphore.release()
          processed = processed + 1
          process_repository_stateful(config, repo) catch {
            e => {
              @stdio.stderr.write(
                "error [\{repo.name}] - Unexpected error: \{e}\n",
              )
            }
          }
          successful = successful + 1
        })
      }
    })
  }

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
