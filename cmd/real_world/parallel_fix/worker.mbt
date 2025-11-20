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
      // PR exists, check its status
      @stdio.stdout.write(
        "info [\{repo_name}] PR #\{pr_num} exists, checking status...\n",
      )

      // Get PR state from GitHub
      let pr_state = get_pr_state(clone_path, pr_num) catch {
        e => {
          @stdio.stderr.write(
            "warning [\{repo_name}] Failed to get PR state: \{e}\n",
          )
          "UNKNOWN"
        }
      }

      // Check if PR is merged or closed
      if pr_state == "MERGED" || pr_state == "CLOSED" {
        @stdio.stdout.write(
          "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, marking as completed\n",
        )
        mark_completed(config.db, repo.id) catch {
          e =>
            @stdio.stderr.write(
              "warning [\{repo_name}] Failed to mark as completed: \{e}\n",
            )
        }
        return
      }

      // PR is still open, get comments and continue work
      @stdio.stdout.write(
        "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, continuing work...\n",
      )

      // Get branch name from PR
      let branch_name = get_pr_branch(clone_path, pr_num) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to get PR branch: \{e}\n",
          )
          return
        }
      }

      // Checkout the PR branch
      checkout_branch(clone_path, branch_name) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to checkout branch: \{e}\n",
          )
          return
        }
      }
      let comments = get_pr_comments(clone_path, pr_num)

      // Ask AI to work on the task considering PR feedback
      run_ai_task(config, repo, clone_path, Some(comments)) catch {
        e => {
          @stdio.stderr.write("error [\{repo_name}] AI task failed: \{e}\n")
          return
        }
      }

      // Sync changes if any
      sync_changes(clone_path, repo) catch {
        e => @stdio.stderr.write("warning Failed to sync changes: \{e}\n")
      }
    }
    None => {
      // No PR yet, run AI first to see if there's work to do
      @stdio.stdout.write(
        "info [\{repo_name}] No PR exists, running AI to check if work is needed...\n",
      )

      // Setup branch for AI to work on
      let branch_name = setup_work_branch(clone_path, config.branch_prefix) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to setup work branch: \{e}\n",
          )
          return
        }
      }

      // Run AI task
      run_ai_task(config, repo, clone_path, None) catch {
        e => {
          @stdio.stderr.write("error [\{repo_name}] AI task failed: \{e}\n")
          return
        }
      }

      // Check if AI made any changes (committed or uncommitted) on the feature branch
      let has_changes = check_branch_has_changes(clone_path, branch_name) catch {
        e => {
          @stdio.stderr.write(
            "warning [\{repo_name}] Failed to check changes: \{e}\n",
          )
          false
        }
      }
      if not(has_changes) {
        // No changes needed, mark as completed
        @stdio.stdout.write(
          "info [\{repo_name}] No changes needed, marking as completed\n",
        )
        mark_completed(config.db, repo.id) catch {
          e =>
            @stdio.stderr.write(
              "warning [\{repo_name}] Failed to mark as completed: \{e}\n",
            )
        }
        return
      }

      // Commit any remaining uncommitted changes (if AI made file changes but didn't commit)
      commit_changes(clone_path, repo) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to commit changes: \{e}\n",
          )
          return
        }
      }

      // Push changes
      push_branch(clone_path, branch_name) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to push changes: \{e}\n",
          )
          return
        }
      }

      // Now create PR
      @stdio.stdout.write("info [\{repo_name}] Changes made, creating PR...\n")
      let pr_num = create_pr_from_branch(
        clone_path,
        repo,
        branch_name,
        config.codex,
      ) catch {
        e => {
          @stdio.stderr.write(
            "error [\{repo_name}] Failed to create PR: \{e}\n",
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
      @stdio.stdout.write("info [\{repo_name}] PR #\{pr_num} created\n")
    }
  }
}

///|
/// Get PR branch name from GitHub
async fn get_pr_branch(clone_path : String, pr_number : Int) -> String {
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr",
      "view",
      pr_number.to_string(),
      "--json",
      "headRefName",
      "--jq",
      ".headRefName",
    ],
    cwd=clone_path,
  ) catch {
    e =>
      @error.fail_with(
        "Failed to get PR branch for \{clone_path} #\{pr_number}",
        e,
      )
  }
  if status != 0 {
    @error.fail(
      "Failed to get PR branch for \{clone_path} #\{pr_number}\n\{stderr.text()}",
    )
  }
  stdout.text().trim(char_set=" \t\n\r").to_string()
}

///|
/// Checkout a branch
async fn checkout_branch(clone_path : String, branch_name : String) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }
  if !git_repo.checkout(branch_name) {
    @error.fail("Failed to checkout branch \{branch_name}")
  }
  // Pull latest changes
  if !git_repo.pull(branch=branch_name) {
    @error.fail("Failed to pull branch \{branch_name}")
  }
}

///|
/// Setup a work branch for AI (without creating PR yet)
async fn setup_work_branch(
  clone_path : String,
  branch_prefix : String,
) -> String {
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
  branch_name
}

///|
/// Check if the feature branch has any changes compared to base branch
/// This includes both committed changes and uncommitted changes
async fn check_branch_has_changes(
  clone_path : String,
  branch_name : String,
) -> Bool {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Get default branch
  let default_branch = git_repo.default_branch.unwrap_or("main")

  // First check if there are uncommitted changes
  if git_repo.has_changes() {
    return true
  }

  // Check if there are committed changes on the branch compared to default
  let (status, stdout, _) = @process.collect_output(
    "git",
    ["rev-list", "--count", "\{default_branch}..\{branch_name}"],
    cwd=clone_path,
  ) catch {
    e => @error.fail_with("Failed to check branch commits", e)
  }
  if status != 0 {
    return false
  }

  // Parse commit count
  let commit_count = @strconv.parse_int(stdout.text().trim(char_set=" \t\n\r")) catch {
    _ => 0
  }
  commit_count > 0
}

///|
/// Commit all changes (if there are any uncommitted changes)
async fn commit_changes(clone_path : String, repo : RepositoryRecord) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Only commit if there are uncommitted changes
  if git_repo.has_changes() {
    let commit_msg = "AI work on: \{repo.task}"
    if !git_repo.commit(commit_msg) {
      @error.fail("Failed to commit changes")
    }
  } else {
    @stdio.stdout.write(
      "info No uncommitted changes, AI may have already committed\n",
    )
  }
}

///|
/// Push branch to remote
async fn push_branch(clone_path : String, branch_name : String) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }
  git_repo.push(branch=branch_name, set_upstream=true) catch {
    e => @error.reraise(e)
  }
}

///|
/// Generate PR metadata (title and body) using AI
async fn generate_pr_metadata(
  codex : @codex.Codex,
  clone_path : String,
  repo : RepositoryRecord,
  branch_name : String,
  default_branch : String,
) -> (String, String) {
  // Get diff summary
  let (status, stdout, stderr) = @process.collect_output(
    "git",
    ["diff", "--stat", "\{default_branch}..\{branch_name}"],
    cwd=clone_path,
  ) catch {
    e => {
      @stdio.stderr.write("warning Failed to get diff summary: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
  if status != 0 {
    @stdio.stderr.write("warning git diff failed: \{stderr.text()}\n")
    return (
      "Automated code improvements",
      "This PR was automatically created.\n\nTask: \{repo.task}",
    )
  }
  let diff_summary = stdout.text()

  // Create a simple thread for PR metadata generation
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      skip_git_repo_check=true,
      sandbox_mode=ReadOnly,
      model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
    ),
  )
  let prompt =
    #|Based on the following task and code changes, generate a professional pull request title and body.
    $|
    $|Task: \{repo.task}
    $|
    $|Changes summary:
    $|\{diff_summary}
    $|
    $|Generate a JSON response with this structure:
    $|{
    $|  "title": "A concise PR title (max 72 characters)",
    $|  "body": "A detailed PR description in markdown format"
    $|}
    $|
    $|The title should be concise and descriptive.
    $|The body should include:
    $|   - Summary of what was changed
    $|   - Why these changes were made (based on the task)
    $|   - Any notable implementation details
    $|
    $|Keep the tone professional and technical.

  // Run with output schema
  let result = thread.run(prompt) catch {
    e => {
      @stdio.stderr.write("warning Failed to generate PR metadata: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }

  // Parse the structured response
  let parsed = @json.parse(result.final_response) catch {
    e => {
      @stdio.stderr.write("warning Failed to parse PR metadata JSON: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
  match parsed {
    Object({ "title": String(title), "body": String(body), .. }) =>
      (title, body)
    _ => {
      @stdio.stderr.write(
        "warning PR metadata response missing title/body fields\n",
      )
      (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
}

///|
/// Create a PR from an existing branch (already pushed)
async fn create_pr_from_branch(
  clone_path : String,
  repo : RepositoryRecord,
  branch_name : String,
  codex : @codex.Codex,
) -> Int {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Get default branch
  let default_branch = git_repo.default_branch.unwrap_or("main")

  // Generate PR metadata using AI
  @stdio.stdout.write("info Generating PR title and description...\n")
  let (pr_title, pr_body) = generate_pr_metadata(
    codex, clone_path, repo, branch_name, default_branch,
  )
  @stdio.stdout.write("info PR title: \{pr_title}\n")

  // Create PR using gh CLI
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr", "create", "--title", pr_title, "--body", pr_body, "--base", default_branch,
      "--head", branch_name,
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
/// Get PR state from GitHub
async fn get_pr_state(clone_path : String, pr_number : Int) -> String {
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    ["pr", "view", pr_number.to_string(), "--json", "state", "--jq", ".state"],
    cwd=clone_path,
  ) catch {
    e =>
      @error.fail_with(
        "Failed to get PR state for \{clone_path} #\{pr_number}",
        e,
      )
  }
  if status != 0 {
    @error.fail(
      "Failed to get PR state for \{clone_path} #\{pr_number}\n\{stderr.text()}",
    )
  }
  stdout.text().trim(char_set=" \t\n\r").to_string()
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
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )

  // Run AI
  let _result = thread.run(task_description) catch { e => @error.reraise(e) }
  @stdio.stdout.write("info AI task completed\n")
}

///|
/// Sync changes to remote for existing PR (commit and push)
async fn sync_changes(clone_path : String, repo : RepositoryRecord) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Check if there are changes
  if !git_repo.has_changes() {
    @stdio.stdout.write("info No new changes to sync\n")
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
  @stdio.stdout.write("info Changes synced to remote\n")
}
