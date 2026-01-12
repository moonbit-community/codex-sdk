///|
/// Main entry point: orchestrates the PR review workflow.

///|
async fn main {
  let config = match Config::parse(@sys.get_env_vars(), @sys.get_cli_args()) {
    Some(c) => c
    None => return // --help was printed
  }

  // Validate required config
  if config.repo.is_empty() {
    @stdio.stderr.write("Error: GITHUB_REPO is required (format: owner/repo)\n")
    return
  }
  @stdio.stderr.write("PR Review Bot\n")
  @stdio.stderr.write("  repo: \{config.repo}\n")
  @stdio.stderr.write("  workdir: \{config.workdir}\n")
  @stdio.stderr.write("  parallelism: \{config.parallelism}\n")
  @stdio.stderr.write("  dry_run: \{config.dry_run}\n")
  @stdio.stderr.write("  db_path: \{config.db_path}\n")

  // Ensure sqlite3 is available
  @sqlite.ensure() catch {
    e => {
      @stdio.stderr.write("Error: sqlite3 CLI not found: \{e}\n")
      return
    }
  }

  // Initialize database
  let db = @sqlite.Database::new(config.db_path)
  init_db(db) catch {
    e => {
      @stdio.stderr.write("Error initializing database: \{e}\n")
      return
    }
  }

  // Show current stats
  let (pending, reviewing, reviewed, failed) = get_stats(db) catch {
    _ => (0, 0, 0, 0)
  }
  @stdio.stderr.write(
    "  db stats: \{pending} pending, \{reviewing} reviewing, \{reviewed} reviewed, \{failed} failed\n",
  )

  // Fetch and sync PRs from GitHub
  @stdio.stderr.write("\nFetching open PRs from GitHub...\n")
  let all_tasks = fetch_and_sync_prs(config, db) catch {
    e => {
      @stdio.stderr.write("Error fetching PRs: \{e}\n")
      return
    }
  }
  @stdio.stderr.write("Found \{all_tasks.length()} open PRs\n")

  // Get tasks that need processing
  let tasks = get_tasks_to_process(db, all_tasks, config.max_retry) catch {
    e => {
      @stdio.stderr.write("Error getting pending tasks: \{e}\n")
      return
    }
  }
  @stdio.stderr.write("\{tasks.length()} PRs need review\n")
  if tasks.is_empty() {
    @stdio.stderr.write("No PRs to review\n")
    return
  }

  // Dry run: just list what would be reviewed
  if config.dry_run {
    @stdio.stderr.write("\n=== Dry Run - Would Review ===\n")
    for task in tasks {
      @stdio.stderr.write(
        "  PR #\{task.pr_number}: \{task.title} (by @\{task.author})\n",
      )
    }
    @stdio.stderr.write("\nRun without DRY_RUN=1 to post reviews\n")
  }

  // Create shared codex instance
  let codex = @codex.Codex::new()

  // Process reviews in parallel
  @stdio.stderr.write("\nStarting reviews...\n")
  let results = run_parallel(tasks, config.parallelism, async fn(task) {
    @stdio.stderr.write("  Reviewing PR #\{task.pr_number}: \{task.title}\n")
    process_task(codex, config, db, task)
  })

  // Report results
  @stdio.stderr.write("\n=== Results ===\n")
  let mut success_count = 0
  let mut skipped_count = 0
  let mut failure_count = 0
  for i, result in results {
    let task = tasks[i]
    match result {
      Success(comment_id) => {
        if config.dry_run {
          @stdio.stderr.write("[DRY] PR #\{task.pr_number}\n")
        } else {
          @stdio.stderr.write(
            "[OK] PR #\{task.pr_number} -> comment #\{comment_id}\n",
          )
        }
        success_count += 1
      }
      Skipped => {
        @stdio.stderr.write("[SKIP] PR #\{task.pr_number} (already reviewed)\n")
        skipped_count += 1
      }
      Failed(msg) => {
        @stdio.stderr.write("[FAIL] PR #\{task.pr_number}: \{msg}\n")
        failure_count += 1
      }
    }
  }
  @stdio.stderr.write(
    "\nSummary: \{success_count} reviewed, \{skipped_count} skipped, \{failure_count} failed\n",
  )

  // Show updated stats
  let (pending2, reviewing2, reviewed2, failed2) = get_stats(db) catch {
    _ => (0, 0, 0, 0)
  }
  @stdio.stderr.write(
    "Database: \{pending2} pending, \{reviewing2} reviewing, \{reviewed2} reviewed, \{failed2} failed\n",
  )
}
