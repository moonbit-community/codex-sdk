///|
/// Simplified worker: for each incomplete repo, check PR, create draft if needed, run AI, sync changes

///|
/// Process a single repository - simplified logic
async fn process_repository(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit {
  let repo_name = extract_repo_name(repo.url)
  @stdio.stdout.write("info [\{repo_name}] Processing...\n")
  let clone_path = "\{config.work_dir}/\{repo_name}"
  ensure_repo_cloned(clone_path, repo.url) catch {
    e => {
      @stdio.stderr.write("error [\{repo_name}] Failed to clone: \{e}\n")
      return
    }
  }

  // 1. Check if PR exists
  match repo.pr_number {
    Some(pr_num) => {
      // PR exists, check its status and get comments
      @stdio.stdout.write(
        "info [\{repo_name}] PR #\{pr_num} exists, checking status...\n",
      )

      // Get PR comments to pass to AI
      let comments = get_pr_comments(clone_path, pr_num)

      // Ask AI to work on the task considering PR feedback
      run_ai_task(config, repo, clone_path, Some(comments)) catch {
        e => {
          @stdio.stderr.write("error [\{repo_name}] AI task failed: \{e}\n")
          return
        }
      }
    }
    None => {
      // No PR yet, create a draft PR first
      @stdio.stdout.write(
        "info [\{repo_name}] No PR exists, creating draft PR...\n",
      )
      let pr_num = create_draft_pr(clone_path, repo, config.branch_prefix) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to create draft PR: \{e}\n",
          )
          return
        }
      }

      // Save PR number
      update_pr_number(config.db, repo.id, pr_num) catch {
        e =>
          @stdio.stderr.write(
            "warning [\{repo_name}] Failed to save PR number: \{e}\n",
          )
      }
      @stdio.stdout.write("info [\{repo_name}] Draft PR #\{pr_num} created\n")

      // Now run AI task
      run_ai_task(config, repo, clone_path, None) catch {
        e => {
          @stdio.stderr.write("error [\{repo_name}] AI task failed: \{e}\n")
          return
        }
      }
    }
  }
}

///|
/// Ensure repository is cloned and ready
async fn ensure_repo_cloned(clone_path : String, url : String) -> Unit {
  if @fs.exists(clone_path) {
    return
  }
  @stdio.stdout.write("info Cloning \{url} to \{clone_path}...\n")
  let _ = @git.GitRepo::clone(url, clone_path) catch {
    e => @error.fail_with("Failed to clone repository", e)
  }

}

///|
/// Create a draft PR for the repository
async fn create_draft_pr(
  clone_path : String,
  repo : RepositoryRecord,
  branch_prefix : String,
) -> Int {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Get default branch
  let default_branch = git_repo.default_branch.unwrap_or("main")

  // Checkout and pull default branch
  if !git_repo.checkout(default_branch) {
    @error.fail("Failed to checkout default branch")
  }
  if !git_repo.pull(branch=default_branch) {
    @error.fail("Failed to pull default branch")
  }

  // Create feature branch
  let branch_name = "\{branch_prefix}-\{@async.now()}"
  git_repo.create_branch(branch_name, from_branch=default_branch) catch {
    e => @error.reraise(e)
  }

  // Push branch
  git_repo.push(branch=branch_name, set_upstream=true) catch {
    e => @error.reraise(e)
  }

  // Create draft PR using gh CLI
  let pr_title = "AI task: \{repo.task}"
  let pr_body = "This PR was automatically created for:\n\n\{repo.task}\n\nWork in progress..."
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr", "create", "--draft", "--title", pr_title, "--body", pr_body, "--base",
      default_branch, "--head", branch_name,
    ],
    cwd=clone_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    let error_output = stderr.text()
    @error.fail("gh pr create failed: \{error_output}")
  }
  let pr_url = stdout.text().trim(char_set=" \t\n\r")

  // Extract PR number from URL
  match @gh.extract_pr_number(pr_url) {
    Some(num) => num
    None => @error.fail("Failed to extract PR number from URL: \{pr_url}")
  }
}

///|
/// Get PR comments for AI context
async fn get_pr_comments(clone_path : String, pr_number : Int) -> String {
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr",
      "view",
      pr_number.to_string(),
      "--json",
      "comments",
      "--jq",
      ".comments[] | \"\\(.author.login): \\(.body)\"",
    ],
    cwd=clone_path,
  ) catch {
    e =>
      @error.fail_with(
        "Failed to get PR comments for \{clone_path} #\{pr_number}",
        e,
      )
  }
  if status != 0 {
    @error.fail(
      "Failed to get PR comments for \{clone_path} #\{pr_number}\n\{stderr.text()}",
    )
  }
  let comments = stdout.text()
  if comments.is_empty() {
    "No comments yet"
  } else {
    comments
  }
}

///|
/// Run AI task on the repository
async fn run_ai_task(
  config : WorkerConfig,
  repo : RepositoryRecord,
  clone_path : String,
  pr_comments : String?,
) -> Unit {
  @stdio.stdout.write("info Running AI task: \{repo.task}\n")

  // Build task description for AI
  let task_description = match pr_comments {
    Some(comments) =>
      (
        $|Task: \{repo.task}
        $|
        $|PR Feedback/Comments:
        $|\{comments}
        $|
        $|Please address the task and any feedback from the PR comments.
        $|
      )
    None =>
      (
        $|Task: \{repo.task}
        $|
        $|This is a new PR. Please implement the task.
        $|
      )
  }

  // Create codex thread
  let thread = config.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      skip_git_repo_check=true,
      sandbox_mode=WorkspaceWrite,
    ),
  )

  // Run AI
  let _result = thread.run(task_description) catch { e => @error.reraise(e) }
  @stdio.stdout.write("info AI task completed\n")

  // After AI completes, sync changes (commit and push)
  sync_changes(clone_path, repo) catch {
    e => @stdio.stderr.write("warning Failed to sync changes: \{e}\n")
  }
}

///|
/// Sync changes to remote (commit and push)
async fn sync_changes(clone_path : String, repo : RepositoryRecord) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Check if there are changes
  if !git_repo.has_changes() {
    @stdio.stdout.write("No changes to sync\n")
    return
  }

  // Commit changes
  let commit_msg = "AI progress on: \{repo.task}"
  if !git_repo.commit(commit_msg) {
    @error.fail("Failed to commit changes")
  }

  // Push changes
  git_repo.push() catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("Changes synced to remote\n")
}
