///|
/// Subcommand handlers for the stateful parallel fix system

///|
/// Handle the 'init' subcommand
/// Initializes the database and working directory
pub async fn cmd_init(args : ArrayView[String]) -> Unit {
  let help_message =
    #|Usage: init [OPTIONS]
    #|
    #|Initialize workspace and database
    #|
    #|Options:
    #|  --work-dir <path>   Working directory (default: /tmp/parallel-fix)
    #|  --help, -h          Show this help
    #|

  // Parse arguments
  let parsed_args = @args.parse(args, flags=["help"], options=["work-dir"], aliases={
    "h": "help",
  })

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }

  // Main logic
  let work_dir = parsed_args.options
    .get("work-dir")
    .unwrap_or("/tmp/parallel-fix")
  let db_path = "\{work_dir}/parallel-fix.db"
  @stdio.stdout.write("Initializing parallel fix workspace...\n")
  @stdio.stdout.write("  Work directory: \{work_dir}\n")
  @stdio.stdout.write("  Database: \{db_path}\n")

  // Check if sqlite3 is available
  if !@sqlite.check_sqlite3() {
    @error.fail(
      "sqlite3 not found. Please install sqlite3 to use stateful mode.",
    )
  }
  @stdio.stdout.write("✓ sqlite3 found\n")

  // Create work directory
  ensure_work_dir(work_dir) catch {
    e => @error.fail_with("Failed to create work directory", e)
  }
  @stdio.stdout.write("✓ Work directory created\n")

  // Initialize database
  let state_mgr = StateManager::new(db_path)
  if !state_mgr.init() {
    @error.fail("Failed to initialize database")
  }
  @stdio.stdout.write("✓ Database initialized\n")

  // Save configuration
  if !state_mgr.db.exec(
      "INSERT OR REPLACE INTO config (key, value, updated_at) VALUES ('work_dir', '\{work_dir}', '\{now()}');",
    ) {
    @stdio.stdout.write("Warning: Failed to save configuration\n")
  }
  @stdio.stdout.write("\n✓ Workspace initialized successfully!\n")
  @stdio.stdout.write(
    "\nNext steps:\n  1. Add repositories: moon run real_world/parallel_fix -- add repos.txt --task \"Your task\"\n  2. Start processing: moon run real_world/parallel_fix -- run\n",
  )
}

///|
/// Handle the 'add' subcommand
/// Adds repositories from a file to the database
pub async fn cmd_add(args : ArrayView[String]) -> Unit {
  let help_message =
    #|Usage: add <repos-file> [OPTIONS]
    #|
    #|Add repositories to the queue
    #|
    #|Options:
    #|  --task <desc>       Task description (required)
    #|  --work-dir <path>   Working directory (default: /tmp/parallel-fix)
    #|  --help, -h          Show this help
    #|

  // Parse arguments
  let parsed_args = @args.parse(
    args,
    flags=["help"],
    options=["work-dir", "task"],
    aliases={ "h": "help" },
  )

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }

  // Main logic
  let work_dir = parsed_args.options
    .get("work-dir")
    .unwrap_or("/tmp/parallel-fix")
  let db_path = "\{work_dir}/parallel-fix.db"

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
        @stdio.stdout.write("  ✓ Added: \{repo_name}\n")
      }
      None => {
        skipped = skipped + 1
        @stdio.stdout.write("  - Skipped (already exists): \{repo_name}\n")
      }
    }
  }
  @stdio.stdout.write(
    "\n✓ Done! Added \{added} repositories, skipped \{skipped}\n",
  )
  @stdio.stdout.write(
    "Next: moon run real_world/parallel_fix -- run --parallelism 8\n",
  )
}

///|
/// Handle the 'status' subcommand
/// Shows current state of all repositories
pub async fn cmd_status(args : ArrayView[String]) -> Unit {
  let help_message =
    #|Usage: status [OPTIONS]
    #|
    #|Show current state of all repositories
    #|
    #|Options:
    #|  --work-dir <path>   Working directory (default: /tmp/parallel-fix)
    #|  --verbose, -v       Show detailed output
    #|  --help, -h          Show this help
    #|

  // Parse arguments
  let parsed_args = @args.parse(
    args,
    flags=["help", "verbose", "v"],
    options=["work-dir"],
    aliases={ "h": "help" },
  )

  // Handle help flag
  if parsed_args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message)
    return
  }

  // Main logic
  let work_dir = parsed_args.options
    .get("work-dir")
    .unwrap_or("/tmp/parallel-fix")
  let db_path = "\{work_dir}/parallel-fix.db"
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

  // Count by state
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\nREPOSITORY STATUS\n")
  @stdio.stdout.write("=".repeat(60))
  @stdio.stdout.write("\n\n")
  @stdio.stdout.write("Total repositories: \{total}\n\n")

  // Show counts for each important state
  let states_to_show = [
    (Pending, "Pending"),
    (Cloning, "Cloning"),
    (Cloned, "Cloned"),
    (Fixing, "Fixing"),
    (Committed, "Committed"),
    (PrOpen, "PR Open"),
    (PrMerged, "PR Merged"),
    (Complete, "Complete"),
    (Failed, "Failed"),
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
    @stdio.stdout.write("\nDETAILED REPOSITORY LIST\n")
    @stdio.stdout.write("=".repeat(60))
    @stdio.stdout.write("\n\n")
    let mut i = 0
    while i < states_to_show.length() {
      let (state, label) = states_to_show[i]
      let repos = state_mgr.get_repos_in_state(state)
      if repos.length() > 0 {
        @stdio.stdout.write("[\{label}]\n")
        for repo in repos {
          @stdio.stdout.write("  - \{repo.name} (\{repo.url})\n")
        }
        @stdio.stdout.write("\n")
      }
      i = i + 1
    }
  } else {
    @stdio.stdout.write("\nUse --verbose or -v for detailed repository list\n")
  }
}

///|
/// Handle the 'help' subcommand
/// Shows help for subcommands
pub async fn cmd_help(_args : ArrayView[String]) -> Unit {
  let help_message =
    #|Usage: moon run real_world/parallel_fix -- <subcommand> [OPTIONS]
    #|
    #|Subcommands:
    #|  init              Initialize workspace and database
    #|  add <repos-file>  Add repositories to the queue
    #|  status            Show current state of all repositories
    #|  run               Start/resume processing (not implemented yet)
    #|
    #|Options:
    #|  --work-dir <path>   Working directory (default: /tmp/parallel-fix)
    #|  --task <desc>       Task description (required for 'add')
    #|  --verbose, -v       Show detailed output (for 'status')
    #|  --help, -h          Show this help message
    #|
    #|Examples:
    #|  # Initialize workspace
    #|  moon run real_world/parallel_fix -- init --work-dir /tmp/fixes
    #|
    #|  # Add repositories
    #|  moon run real_world/parallel_fix -- add repos.txt --task "Fix linting"
    #|
    #|  # Check status
    #|  moon run real_world/parallel_fix -- status --verbose
    #|
    #|Note: The original 'run' command (without subcommand) still works for quick one-off fixes.
    #|
  @stdio.stdout.write(help_message)
}
