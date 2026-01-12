///|
/// Main entry point: orchestrates the code review workflow.

///|
async fn main {
  // Parse configuration from env and args
  let config = match Config::parse(@sys.get_env_vars(), @sys.get_cli_args()) {
    Some(c) => c
    None => return // --help was requested
  }
  @stdio.stderr.write("Code Review Bot\n")
  @stdio.stderr.write("  workdir: \{config.workdir}\n")
  @stdio.stderr.write("  parallelism: \{config.parallelism}\n")
  @stdio.stderr.write("  output_dir: \{config.output_dir}\n")
  @stdio.stderr.write("  dry_run: \{config.dry_run}\n")
  @stdio.stderr.write("  use_worktree: \{config.use_worktree}\n")

  // Identify targets
  let tasks = identify_tasks(config) catch {
    e => {
      @stdio.stderr.write("Error identifying targets: \{e}\n")
      return
    }
  }
  @stdio.stderr.write("Found \{tasks.length()} targets to review\n")
  if tasks.is_empty() {
    @stdio.stderr.write("No targets to review\n")
    return
  }

  // Dry run: just list targets
  if config.dry_run {
    @stdio.stderr.write("\n=== Dry Run - Would Review ===\n")
    for task in tasks {
      @stdio.stderr.write("  [\{task.index}] \{task.name}\n")
    }
    @stdio.stderr.write("\nRun without --dry-run to perform reviews\n")
    return
  }

  // Ensure output directory exists
  if not(@fs.exists(config.output_dir)) {
    @fs.mkdir(config.output_dir, permission=0o755) catch {
      e => {
        @stdio.stderr.write("Failed to create output directory: \{e}\n")
        return
      }
    }
  }

  // Create shared codex instance
  let codex = @codex.Codex::new()

  // Process reviews in parallel
  @stdio.stderr.write("\nStarting reviews...\n")
  let results = run_parallel(tasks, config.parallelism, async fn(task) {
    @stdio.stderr.write("  Reviewing: \{task.name}\n")
    process_task(codex, config, task)
  })

  // Report results
  @stdio.stderr.write("\n=== Results ===\n")
  let mut success_count = 0
  let mut failure_count = 0
  for i, result in results {
    let task = tasks[i]
    match result {
      Success(report_path) => {
        @stdio.stderr.write("[OK] \{task.name} -> \{report_path}\n")
        success_count += 1
      }
      Failed(msg) => {
        @stdio.stderr.write("[FAIL] \{task.name}: \{msg}\n")
        failure_count += 1
      }
    }
  }
  @stdio.stderr.write(
    "\nSummary: \{success_count} succeeded, \{failure_count} failed\n",
  )

  // Write index file
  write_index(config, tasks, results) catch {
    e => @stdio.stderr.write("Warning: Failed to write index: \{e}\n")
  }
}

///|
/// Write an index file linking all review reports.
async fn write_index(
  config : Config,
  tasks : Array[Task],
  results : Array[ReviewResult],
) -> Unit raise Error {
  let mut content = "# Code Review Index\n\n"
  content += "| Target | Status | Report |\n"
  content += "|--------|--------|--------|\n"
  for i, task in tasks {
    let (status, link) = match results[i] {
      Success(path) => {
        let parts = path.split("/").collect()
        let filename = parts[parts.length() - 1]
        ("OK", "[\{filename}](\{filename})")
      }
      Failed(msg) => ("FAILED: " + msg, "-")
    }
    content += "| \{task.name} | \{status} | \{link} |\n"
  }
  @fs.write_file(config.output_dir + "/INDEX.md", content.to_bytes())
}
