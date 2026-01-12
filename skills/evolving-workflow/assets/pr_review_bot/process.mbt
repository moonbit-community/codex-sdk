///|
/// Task processing: Review PR and post comment.
///
/// Each task goes through:
/// 1. **Preprocess**: Check DB status, fetch PR diff
/// 2. **Codex**: Run AI review with retry
/// 3. **Postprocess**: Post comment to GitHub, update DB

///|
/// Result of reviewing a PR
enum ReviewResult {
  /// Review posted successfully
  Success(Int) // comment ID
  /// Already reviewed (skipped)
  Skipped
  /// Review failed
  Failed(String)
}

///|
/// Process a single PR review
async fn process_task(
  codex : @codex.Codex,
  config : Config,
  db : @sqlite.Database,
  task : Task,
) -> ReviewResult {
  // === 1. PREPROCESS ===
  // Check if already reviewed
  let already_reviewed = is_pr_reviewed(db, task.pr_number) catch { _ => false }
  if already_reviewed {
    return Skipped
  }

  // Mark as reviewing
  update_pr_status(db, task.pr_number, Reviewing, None, None) catch {
    _ => ()
  }

  // Fetch PR diff
  let diff = fetch_pr_diff(config, task.pr_number) catch {
    e => {
      let msg = "Failed to fetch diff: \{e}"
      update_pr_status(db, task.pr_number, PrStatus::Failed, None, Some(msg)) catch {
        _ => ()
      }
      return ReviewResult::Failed(msg)
    }
  }

  // === 2. CODEX ===
  // Run AI review with retry
  let review_content : String = @async.retry(
    Immediate,
    max_retry=config.max_retry,
    async fn() { run_codex_review(codex, config.workdir, task, diff) },
  ) catch {
    e => {
      let msg = "Review failed: \{e}"
      update_pr_status(db, task.pr_number, PrStatus::Failed, None, Some(msg)) catch {
        _ => ()
      }
      return ReviewResult::Failed(msg)
    }
  }

  // === 3. POSTPROCESS ===
  // Post comment to GitHub (unless dry run)
  if config.dry_run {
    @stdio.stderr.write(
      "  [DRY RUN] Would post review for PR #\{task.pr_number}\n",
    )
    @stdio.stderr.write("  Review content:\n\{review_content}\n")
    update_pr_status(db, task.pr_number, Reviewed, None, None) catch {
      _ => ()
    }
    return Success(0)
  }
  let comment_id = post_review_comment(config, task.pr_number, review_content) catch {
    e => {
      let msg = "Failed to post comment: \{e}"
      update_pr_status(db, task.pr_number, PrStatus::Failed, None, Some(msg)) catch {
        _ => ()
      }
      return ReviewResult::Failed(msg)
    }
  }

  // Update DB with success
  update_pr_status(db, task.pr_number, Reviewed, Some(comment_id), None) catch {
    _ => ()
  }
  Success(comment_id)
}

///|
/// Fetch PR diff from GitHub
async fn fetch_pr_diff(config : Config, pr_number : Int) -> String {
  let (code, stdout, stderr) = @process.collect_output("gh", [
    "pr",
    "diff",
    pr_number.to_string(),
    "--repo",
    config.repo,
  ]) catch {
    e => @error.fail_with("Failed to run gh pr diff", e)
  }
  if code != 0 {
    let err_msg = stderr.text() catch { _ => "unknown error" }
    @error.fail("gh pr diff failed: " + err_msg)
  }
  stdout.text() catch {
    e => @error.fail_with("Failed to read diff", e)
  }
}

///|
/// Post review comment to GitHub PR
async fn post_review_comment(
  config : Config,
  pr_number : Int,
  content : String,
) -> Int {
  // Write content to temp file to avoid shell escaping issues
  let temp_file = "/tmp/pr_review_\{pr_number}.md"
  @fs.write_file(temp_file, content) catch {
    e => @error.fail_with("Failed to write temp file", e)
  }
  let (code, stdout, stderr) = @process.collect_output("gh", [
    "pr",
    "comment",
    pr_number.to_string(),
    "--repo",
    config.repo,
    "--body-file",
    temp_file,
  ]) catch {
    e => @error.fail_with("Failed to run gh pr comment", e)
  }

  // Clean up temp file
  ignore(@fs.remove(temp_file))
  if code != 0 {
    let err_msg = stderr.text() catch { _ => "unknown error" }
    @error.fail("gh pr comment failed: " + err_msg)
  }

  // Parse comment URL to get ID (format: https://github.com/owner/repo/pull/123#issuecomment-456)
  let output = stdout.text() catch { _ => "" }
  let parts = output.split("#issuecomment-").collect()
  if parts.length() >= 2 {
    @strconv.parse_int(parts[1].trim(chars=" \n\t")) catch {
      _ => 0
    }
  } else {
    0
  }
}
