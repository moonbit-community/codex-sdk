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

  // Determine target repository URL if not already set
  let mut target_url = repo.target_url
  if target_url == repo.url {
    // First time processing, determine if we need a fork
    target_url = get_target_repo_url(repo.url) catch {
      e => {
        @stdio.stderr.write(
          "error [\{repo_name}] Failed to determine target repository: \{e}\n",
        )
        @error.reraise(e)
      }
    }

    // Update database with target URL if different from original
    if target_url != repo.url {
      update_target_url(config.db, repo.id, target_url) catch {
        e =>
          @stdio.stderr.write(
            "warning [\{repo_name}] Failed to update target URL in database: \{e}\n",
          )
      }
    }
  } else {
    @stdio.stdout.write(
      "info [\{repo_name}] Using previously determined target: \{target_url}\n",
    )
  }

  // Clone from target repository
  ensure_repo_cloned(clone_path, target_url) catch {
    e => @error.reraise(e)
  }

  // Check if PR exists and handle accordingly
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
          e => @error.fail_with("Failed to mark repository as completed", e)
        }
        return
      }

      // PR is still open, get comments and continue work
      @stdio.stdout.write(
        "info [\{repo_name}] PR #\{pr_num} is \{pr_state}, continuing work...\n",
      )

      // Get branch name from PR and checkout
      let branch_name = get_pr_branch(clone_path, pr_num) catch {
        e => @error.fail_with("Failed to get PR branch", e)
      }
      checkout_branch(clone_path, branch_name) catch {
        e => @error.fail_with("Failed to checkout PR branch", e)
      }

      // Get PR comments and run AI task
      let comments = get_pr_comments(clone_path, pr_num)
      run_ai_task(config, repo, clone_path, Some(comments)) catch {
        e => @error.fail_with("AI task failed", e)
      }

      // Commit AI changes, run moon tools, and push
      commit_changes(config, clone_path, repo) catch {
        e => @error.fail_with("Failed to commit changes", e)
      }
      run_moon_tools_and_commit(clone_path) catch {
        e => @error.fail_with("Failed to run moon tools", e)
      }
      push_branch(clone_path, branch_name) catch {
        e => @error.fail_with("Failed to push changes", e)
      }
    }
    None => {
      // No PR yet, create one if AI makes changes
      @stdio.stdout.write(
        "info [\{repo_name}] No PR exists, running AI to check if work is needed...\n",
      )

      // Setup branch and run AI task
      let branch_name = setup_work_branch(clone_path, config.branch_prefix) catch {
        e => @error.fail_with("Failed to setup work branch", e)
      }
      run_ai_task(config, repo, clone_path, None) catch {
        e => @error.fail_with("AI task failed", e)
      }

      // Commit AI changes and run moon tools
      commit_changes(config, clone_path, repo) catch {
        e => @error.fail_with("Failed to commit changes", e)
      }
      run_moon_tools_and_commit(clone_path) catch {
        e => @error.fail_with("Failed to run moon tools", e)
      }

      // Check if there are any changes on the branch
      let has_changes = check_branch_has_changes(clone_path, branch_name) catch {
        e => @error.fail_with("Failed to check if branch has changes", e)
      }
      if not(has_changes) {
        @stdio.stdout.write(
          "info [\{repo_name}] No changes needed, marking as completed\n",
        )
        mark_completed(config.db, repo.id) catch {
          e => @error.fail_with("Failed to mark repository as completed", e)
        }
        return
      }

      // Push changes and create PR
      push_branch(clone_path, branch_name) catch {
        e => @error.fail_with("Failed to push branch", e)
      }
      @stdio.stdout.write("info [\{repo_name}] Changes made, creating PR...\n")
      let pr_num = create_pr_from_branch(
        clone_path,
        repo,
        branch_name,
        config.codex,
      ) catch {
        e => @error.fail_with("Failed to create PR", e)
      }

      // Save PR number
      update_pr_number(config.db, repo.id, pr_num) catch {
        e => @error.fail_with("Failed to save PR number", e)
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
  stdout.trim_output()
}

///|
/// Update a branch to match its remote tracking branch
/// Uses git reset --hard to sync with remote, handling rebased/merged branches
async fn update_branch_from_remote(
  clone_path : String,
  branch_name : String,
) -> Unit {
  let (status, stdout, _) = @process.collect_output(
    "git",
    ["rev-parse", "--abbrev-ref", "\{branch_name}@{u}"],
    cwd=clone_path,
  ) catch {
    e => @error.fail_with("Failed to get remote tracking branch", e)
  }
  if status != 0 {
    // No remote tracking branch, skip update
    @stdio.stdout.write(
      "info Branch \{branch_name} has no remote tracking branch\n",
    )
    return
  }
  let remote_branch = stdout.trim_output()
  @stdio.stdout.write(
    "info Updating \{branch_name} to match remote \{remote_branch}...\n",
  )

  // Reset to remote branch (handles rebased/merged branches)
  let (status_reset, _, reset_err) = @process.collect_output(
    "git",
    ["reset", "--hard", remote_branch],
    cwd=clone_path,
  ) catch {
    e => @error.fail_with("Failed to reset to remote branch", e)
  }
  if status_reset != 0 {
    @error.fail("Failed to reset branch to remote: \{reset_err.text()}")
  }
  @stdio.stdout.write("info Successfully synced \{branch_name} with remote\n")
}

///|
/// Checkout a branch and ensure it's updated from remote
/// If the remote branch is newer (rebased or merged), automatically sync to it
/// Also attempts to update the branch with the latest changes from the default branch
async fn checkout_branch(clone_path : String, branch_name : String) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // First, ensure default branch is up to date
  let default_branch = git_repo.default_branch.unwrap_or("main")
  if !git_repo.checkout(default_branch) {
    @stdio.stdout.write(
      "warning Failed to checkout default branch \{default_branch}\n",
    )
  } else {
    // Update default branch from remote
    git_repo.pull(branch=default_branch) catch {
      _ => {
        @stdio.stdout.write("info Syncing default branch with remote...\n")
        update_branch_from_remote(clone_path, default_branch) catch {
          e =>
            @stdio.stderr.write(
              "warning Failed to sync default branch with remote: \{e}\n",
            )
        }
      }
    }
  }

  // Now checkout the PR branch
  if !git_repo.checkout(branch_name) {
    @error.fail("Failed to checkout branch \{branch_name}")
  }

  // Try to pull latest changes from remote for the PR branch
  git_repo.pull(branch=branch_name) catch {
    _ => {
      // If pull fails, try explicit reset to remote
      @stdio.stdout.write("info Syncing \{branch_name} with remote branch...\n")
      let _ = update_branch_from_remote(clone_path, branch_name) catch {
        e => {
          @stdio.stderr.write(
            "warning Failed to sync branch with remote: \{e}\n",
          )
          @error.reraise(e)
        }
      }

    }
  }

  // Try to update the PR branch with the latest changes from default branch
  // This helps keep the PR branch up to date with the base branch
  @stdio.stdout.write(
    "info Attempting to merge latest \{default_branch} into \{branch_name}...\n",
  )
  let (merge_status, _, merge_err) = @process.collect_output(
    "git",
    ["merge", "--no-edit", default_branch],
    cwd=clone_path,
  ) catch {
    e => {
      @stdio.stderr.write("warning Failed to merge \{default_branch}: \{e}\n")
      return
    }
  }
  if merge_status != 0 {
    @stdio.stdout.write(
      "warning Could not merge \{default_branch} into \{branch_name}: \{merge_err.text()}\n",
    )
    @stdio.stdout.write("info Aborting merge...\n")
    // Abort the merge to leave the branch in a clean state
    ignore(@process.run("git", ["merge", "--abort"], cwd=clone_path)) catch {
      _ => ()
    }
  } else {
    @stdio.stdout.write(
      "info Successfully merged \{default_branch} into \{branch_name}\n",
    )
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

  // Checkout default branch
  if !git_repo.checkout(default_branch) {
    @error.fail("Failed to checkout default branch")
  }

  // Ensure we have latest from remote (pull or reset if rebase detected)
  git_repo.pull(branch=default_branch) catch {
    _ => {
      @stdio.stdout.write("info Syncing default branch with remote...\n")
      update_branch_from_remote(clone_path, default_branch) catch {
        e =>
          @stdio.stderr.write(
            "warning Failed to sync default branch with remote: \{e}\n",
          )
      }
    }
  }

  // Create feature branch from the latest default branch
  let branch_name = "\{branch_prefix}-\{@async.now()}"
  git_repo.create_branch(branch_name, from_branch=default_branch) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write(
    "info Created branch \{branch_name} from \{default_branch}\n",
  )
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
  let stdout = execute(
    "git",
    ["rev-list", "--count", "\{default_branch}..\{branch_name}"],
    cwd=clone_path,
  ) catch {
    e => @error.fail_with("Failed to check branch commits", e)
  }

  // Parse commit count
  let commit_count = @strconv.parse_int(stdout.trim_output()) catch {
    e => @error.fail_with("Failed to parse commit count", e)
  }
  commit_count > 0
}

///|
/// Commit all changes (if there are any uncommitted changes)
async fn commit_changes(
  config : WorkerConfig,
  clone_path : String,
  repo : RepositoryRecord,
) -> Unit {
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Only commit if there are uncommitted changes
  if git_repo.has_changes() {
    // Generate commit message using AI
    let commit_msg = generate_commit_message(config.codex, clone_path, repo)
    @stdio.stdout.write("info Commit message: \{commit_msg}\n")
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
/// Run moon fmt and moon info, then commit any changes they make
async fn run_moon_tools_and_commit(clone_path : String) -> Unit {
  @stdio.stdout.write("info Running moon fmt and moon info...\n")

  // Run moon fmt (allow failure)
  ignore(@process.collect_output("moon", ["fmt"], cwd=clone_path)) catch {
    e => @stdio.stderr.write("warning moon fmt failed: \{e}\n")
  }

  // Run moon info (allow failure)
  ignore(@process.collect_output("moon", ["info"], cwd=clone_path)) catch {
    e => @stdio.stderr.write("warning moon info failed: \{e}\n")
  }

  // Commit any changes from formatting and info updates
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }
  if git_repo.has_changes() {
    @stdio.stdout.write("info Committing formatting and interface changes...\n")
    if !git_repo.commit("chore: run moon fmt and moon info") {
      @stdio.stderr.write("warning Failed to commit moon tool changes\n")
    }
  } else {
    @stdio.stdout.write("info No changes from moon tools\n")
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
/// Generate commit message using AI
async fn generate_commit_message(
  codex : @codex.Codex,
  clone_path : String,
  repo : RepositoryRecord,
) -> String {
  try {
    // Get diff of uncommitted changes
    let (status, output) = @process.collect_output_merged(
      "git",
      ["diff", "--no-color"],
      cwd=clone_path,
    )
    if status != 0 {
      @error.fail("git diff failed for commit message")
    }
    let diff = output.text()
    if diff.is_empty() {
      @error.fail("No changes to generate commit message for")
    }

    // Create a simple thread for commit message generation
    let thread = codex.start_thread(
      options=@codex.ThreadOptions::new(
        working_directory=clone_path,
        model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
      ),
    )
    let prompt =
      #|Based on the following task and code changes, generate a concise commit message.
      $|
      $|Task: \{repo.task}
      $|
      $|Changes:
      $|\{diff}
      $|
      $|Generate a JSON response with this structure:
      $|{
      $|  "message": "A concise commit message (max 72 characters)"
      $|}
      $|
      $|The message should follow conventional commit guidelines.
      $|Keep it professional and technical.

    // Run with output schema
    let result = thread.run(prompt) catch { e => @error.reraise(e) }

    // Parse the structured response
    let parsed = @json.parse(result.final_response) catch {
      e => @error.reraise(e)
    }
    match parsed {
      Object({ "message": String(message), .. }) => message
      _ => @error.fail("Commit message response missing message field")
    }
  } catch {
    e => {
      @stdio.stderr.write("warning Failed to generate commit message: \{e}\n")
      "AI work on: \{repo.task}"
    }
  }
}

///|
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

  // Extract target repo owner/name for PR creation
  let target_repo_path = repo.target_url
    .strip_suffix(".git")
    .unwrap_or(repo.target_url)
  guard target_repo_path.split("/").collect() is [.., target_owner, target_repo] else {
    @error.fail("Invalid target repository URL: \{repo.target_url}")
  }

  // Create PR using gh CLI
  // When creating a PR on a fork, we need to specify the target repo explicitly
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr",
      "create",
      "--title",
      pr_title,
      "--body",
      pr_body,
      "--base",
      default_branch,
      "--head",
      branch_name,
      "--repo",
      "\{target_owner}/\{target_repo}",
    ],
    cwd=clone_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    let error_output = stderr.text()
    @error.fail("gh pr create failed: \{error_output}")
  }
  let pr_url = stdout.trim_output()

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
  let stdout = execute(
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
  stdout.trim_output()
}

///|
/// Get PR comments for AI context
async fn get_pr_comments(clone_path : String, pr_number : Int) -> String {
  let stdout = execute(
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
  let comments = stdout.text()
  if comments.is_blank() {
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
  let background =
    #|## MoonBit Project Guidelines
    #|
    #|This is a MoonBit project. Follow these guidelines:
    #|
    #|### Project Structure
    #|- Packages are organized per directory with moon.pkg.json files
    #|- Test files end in _test.mbt (blackbox) or _wbtest.mbt (whitebox)
    #|- Each package has a generated .mbti interface file
    #|
    #|### Coding Conventions
    #|- Use block style separated by ///| (block order is irrelevant)
    #|- Keep deprecated code in deprecated.mbt files
    #|
    #|### Tooling Requirements
    #|- Use `moon fmt` to format code
    #|- Use `moon info` to update .mbti interface files
    #|- Use `moon test` to run tests (use `moon test --update` for snapshots)
    #|- Use `moon check` for linting
    #|- Use `inspect` in tests for snapshot testing, `assert_eq` only in loops
    #|- Run `moon coverage analyze` to check test coverage
    #|
    #|### Important Rules
    #|- Do NOT create backup files or any irrelevant files in the repository
    #|- Ensure all changes pass `moon check` and `moon test`
    #|- Make minimal, focused changes relevant only to the task
    #|- Update snapshots with `moon test --update` if behavior changes
    #|- Check .mbti diffs after `moon info` to verify interface changes
    #|
    #|After completing the task, commit them. 
    #|Then run `moon info && moon fmt && moon check && moon test --update` and commit automatic changes to finalize.
    #|

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
        $|If there's nothing new, do nothing.
        $|
        $|\{background}
      )
    None =>
      (
        $|Task: \{repo.task}
        $|
        $|This is a new PR. Please implement the task.
        $|
        $|\{background}
      )
  }

  // Create codex thread
  let thread = config.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )

  // Run AI
  let _result = thread.run(task_description) catch {
    e => {
      if thread.id() is Some(session_id) {
        @stdio.stderr.write(
          "error AI task failed (session ID: \{session_id}): \{e}\n",
        )
        save_codex_session(config.db, repo.id, session_id) catch {
          e =>
            @stdio.stderr.write(
              "warning Failed to save codex session ID after error: \{e}\n",
            )
        }
      } else {
        @stdio.stderr.write("error AI task failed: \{e}\n")
      }
      @error.reraise(e)
    }
  }

  // Save the thread/session ID to the database
  if thread.id() is Some(session_id) {
    @stdio.stdout.write("info Saving codex session ID: \{session_id}\n")
    save_codex_session(config.db, repo.id, session_id) catch {
      e =>
        @stdio.stderr.write("warning Failed to save codex session ID: \{e}\n")
    }
  } else {
    @stdio.stderr.write("warning No thread ID available from codex session\n")
  }
  @stdio.stdout.write("info AI task completed\n")
}
