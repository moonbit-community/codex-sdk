///|
/// Task processing: the lifecycle of processing a single task.
///
/// Each task goes through:
/// 1. **Preprocess**: Setup (e.g., create worktree for isolation)
/// 2. **Codex**: Run AI analysis with retry
/// 3. **Postprocess**: Write results, cleanup

///|
/// Result of reviewing a target.
enum ReviewResult {
  /// Review completed, report written
  Success(String) // report path
  /// Review failed
  Failed(String) // error message
}

///|
/// Process a single review target.
/// This is the main task lifecycle: preprocess → codex → postprocess
async fn process_task(
  codex : @codex.Codex,
  config : Config,
  task : Task,
) -> ReviewResult {
  //
  // 1. PREPROCESS: Setup the environment
  //
  let target_path = if task.path.is_empty() {
    config.workdir
  } else {
    config.workdir + "/" + task.path
  }
  let (review_path, worktree_to_cleanup) : (String, String?) = if config.use_worktree {
    let worktree_path = config.workdir +
      "/.worktrees/review-" +
      task.index.to_string()
    match setup_worktree(config.workdir, worktree_path) {
      Some(e) => return Failed("Worktree setup failed: " + e)
      None => {
        let actual_path = if task.path.is_empty() {
          worktree_path
        } else {
          worktree_path + "/" + task.path
        }
        (actual_path, Some(worktree_path))
      }
    }
  } else {
    (target_path, None)
  }

  //
  // 2. CODEX: Run AI review with retry
  //
  let review_content : String = @async.retry(
    Immediate,
    max_retry=config.max_retry,
    async fn() { run_codex_review(codex, review_path) },
  ) catch {
    e => {
      cleanup_if_needed(config.workdir, worktree_to_cleanup)
      return Failed("Review failed: \{e}")
    }
  }

  //
  // 3. POSTPROCESS: Write results and cleanup
  //
  let report_path = write_review_report(config, task, review_content) catch {
    e => {
      cleanup_if_needed(config.workdir, worktree_to_cleanup)
      return Failed("Failed to write report: \{e}")
    }
  }
  cleanup_if_needed(config.workdir, worktree_to_cleanup)
  Success(report_path)
}

///|
/// Write review report to output directory.
async fn write_review_report(
  config : Config,
  task : Task,
  content : String,
) -> String raise Error {
  // Ensure output directory exists
  if not(@fs.exists(config.output_dir)) {
    @fs.mkdir(config.output_dir, permission=0o755)
  }

  // Generate report filename
  let safe_name = task.name.replace_all(old="/", new="_")
  let report_path = config.output_dir + "/" + safe_name + ".md"

  // Write report with header
  let header = "# Code Review: \{task.name}\n\n"
  @fs.write_file(report_path, header + content)
  report_path
}

///|
/// Cleanup worktree if one was created.
async fn cleanup_if_needed(workdir : String, worktree : String?) -> Unit {
  match worktree {
    Some(path) => cleanup_worktree(workdir, path)
    None => ()
  }
}
