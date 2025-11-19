///|
/// Worker for processing repositories with state management

///|
/// Process a repository based on its current state
/// This is the main state-driven processing function
/// Continues processing through states until reaches a terminal or async state
async fn process_repository_stateful(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit {
  let repo_name = repo.name
  @stdio.stdout.write(
    "info [\{repo_name}] - Processing from state: \{repo.state}\n",
  )
  let mut last_state = None
  let mut repo = repo

  // Process based on current state
  while !(last_state is Some(state) && state == repo.state) {
    last_state = Some(repo.state)
    match repo.state {
      Pending => do_clone(config, repo) catch { e => @error.reraise(e) }
      Cloning => do_clone(config, repo) catch { e => @error.reraise(e) }
      Branching => do_branch(config, repo) catch { e => @error.reraise(e) }
      Fixing => do_fix(config, repo) catch { e => @error.reraise(e) }
      PrOpen => do_handle_pr(config, repo) catch { e => @error.reraise(e) }
      Complete =>
        @stdio.stdout.write("info [\{repo_name}] - Already complete\n")
      ...
    }
    repo = config.state_mgr.get_repository(repo.id) catch {
      e => @error.reraise(e)
    }
  }
  @stdio.stdout.write(
    "info [\{repo_name}] - Finished processing at state: \{repo.state}\n",
  )
}

///|
/// Perform cloning (reentrant - checks if already cloned)
async fn do_clone(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  let clone_path = "\{config.work_dir}/\{repo.name}"

  // Check if already cloned
  if @fs.exists(clone_path) {
    @stdio.stdout.write(
      "info [\{repo.name}] - Already cloned, discovering...\n",
    )
    let git_repo = @git.GitRepo::discover(clone_path) catch {
      e =>
        @error.fail_with(
          "Failed to discover Git at \{clone_path} but directory exists",
          e,
        )
    }

    // Save local path and default branch
    let default_branch = git_repo.default_branch.unwrap_or("main")
    let updates = [
      ("local_path", clone_path),
      ("default_branch", default_branch),
    ]
    config.state_mgr.update_repository(repo.id, updates) catch {
      e => @error.reraise(e)
    }
    // Always advance to Branching when clone is verified
    config.state_mgr.transition(
      repo.id,
      Branching,
      details="Repository discovered",
    ) catch {
      e => @error.reraise(e)
    }
    @stdio.stdout.write("info [\{repo.name}] - Clone verified\n")
    return
  }

  // Clone repository
  @stdio.stdout.write("info [\{repo.name}] - Cloning to \{clone_path}\n")
  let git_repo = @git.GitRepo::clone(repo.url, clone_path) catch {
    e => @error.reraise(e)
  }
  let default_branch = git_repo.default_branch.unwrap_or("main")
  let updates = [("local_path", clone_path), ("default_branch", default_branch)]
  config.state_mgr.update_repository(repo.id, updates) catch {
    e => @error.reraise(e)
  }
  config.state_mgr.transition(repo.id, Branching, details="Clone successful") catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Clone successful\n")
}

///|
/// Perform branching (reentrant - checks if branch exists)
async fn do_branch(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }
  guard repo.default_branch is Some(default_branch) else {
    @error.fail("No default branch set")
  }

  // Discover repository
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository at \{clone_path}", e)
  }

  // Check current branch
  let current = git_repo.current_branch()
  match current {
    Some(branch) if branch.has_prefix(config.branch_prefix) => {
      @stdio.stdout.write(
        "info [\{repo.name}] - Already on fix branch: \{branch}\n",
      )
      let updates = [("current_branch", branch)]
      config.state_mgr.update_repository(repo.id, updates) catch {
        e => @error.reraise(e)
      }
      // Always advance to Fixing when branch is verified
      config.state_mgr.transition(repo.id, Fixing, details="Branch exists") catch {
        e => @error.reraise(e)
      }
      return
    }
    _ => ()
  }

  // Create new branch
  let timestamp = get_timestamp()
  let branch_name = "\{config.branch_prefix}-\{timestamp}"
  @stdio.stdout.write("info [\{repo.name}] - Creating branch: \{branch_name}\n")

  // Checkout default branch first
  if !git_repo.checkout(default_branch) {
    @error.fail("Failed to checkout default branch")
  }
  if !git_repo.pull(branch=default_branch) {
    @error.fail("Failed to pull default branch")
  }

  // Create new branch
  if !git_repo.create_branch(branch_name) {
    @error.fail("Failed to create branch")
  }
  let updates = [("current_branch", branch_name)]
  config.state_mgr.update_repository(repo.id, updates) catch {
    e => @error.reraise(e)
  }
  config.state_mgr.transition(repo.id, Fixing, details="Branch created") catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Branch created successfully\n")
}

///|
/// Perform AI fix
/// AI can decide to go directly to Complete if there's nothing to fix
async fn do_fix(config : WorkerConfig, repo : RepositoryRecord) -> Unit {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }
  guard repo.task_description is Some(task) else {
    @error.fail("No task description set")
  }
  @stdio.stdout.write("info [\{repo.name}] - Running AI fix: \{task}\n")

  // Create codex thread with working directory
  let thread = config.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      skip_git_repo_check=true,
      sandbox_mode=WorkspaceWrite,
    ),
  )

  // Add instruction for AI to decide if work is needed
  let enhanced_task =
    #|Task: \{task}
    #|
    #|Important: Before making any changes, analyze if this task is actually needed.
    #|If you determine that:
    #|1. The issue described doesn't exist in this codebase, OR
    #|2. The requested changes have already been completed, OR
    #|3. The task is not applicable to this repository
    #|
    #|Then respond with "NO_CHANGES_NEEDED" and explain why.
    #|Otherwise, proceed with the task normally.
    #|

  // Run thread to execute the fix
  let result = thread.run(enhanced_task) catch { e => @error.reraise(e) }

  // Save thread ID if available
  if thread.id() is Some(thread_id) {
    let updates = [("thread_id", thread_id)]
    config.state_mgr.update_repository(repo.id, updates) catch {
      e => @error.reraise(e)
    }
  }

  // Check if AI determined no changes are needed
  // This is a simple heuristic - in practice, we'd need more sophisticated detection
  let response_lower = result.final_response.to_lower()
  if response_lower.contains("no_changes_needed") ||
    response_lower.contains("no changes needed") ||
    response_lower.contains("not applicable") {
    @stdio.stdout.write(
      "info [\{repo.name}] - AI determined no changes needed, marking complete\n",
    )
    config.state_mgr.transition(
      repo.id,
      Complete,
      details="AI determined no changes needed",
    ) catch {
      e => @error.reraise(e)
    }
    return
  }

  // AI made changes - now handle commit, push, and PR creation internally
  @stdio.stdout.write(
    "info [\{repo.name}] - AI fix completed, processing commit/push/PR\n",
  )

  // Discover repository
  let git_repo = @git.GitRepo::discover(clone_path) catch {
    e => @error.fail_with("Failed to discover repository", e)
  }

  // Check if there are changes
  if !git_repo.has_changes() {
    @stdio.stdout.write(
      "warning [\{repo.name}] - No changes to commit after AI fix\n",
    )
    config.state_mgr.transition(repo.id, Complete, details="No changes") catch {
      e => @error.reraise(e)
    }
    return
  }

  // Commit changes
  guard repo.current_branch is Some(branch) else {
    @error.fail("No current branch set")
  }
  let commit_msg = "AI fix: \{task}"
  @stdio.stdout.write("info [\{repo.name}] - Committing changes\n")
  if !git_repo.commit(commit_msg) {
    @error.fail("Failed to commit changes")
  }

  // Push changes
  @stdio.stdout.write("info [\{repo.name}] - Pushing branch: \{branch}\n")
  if !git_repo.push(branch~, set_upstream=true) {
    @error.fail("Failed to push branch")
  }

  // Get default branch for PR
  guard repo.default_branch is Some(base_branch) else {
    @error.fail("No default branch set")
  }

  // Create PR using gh CLI
  @stdio.stdout.write("info [\{repo.name}] - Creating pull request\n")
  let pr_title = "AI fix: \{task}"
  let pr_body = "This PR was automatically generated to address:\n\n\{task}"
  let (pipe, process_read) = @process.read_from_process()
  let (err_pipe, process_err) = @process.read_from_process()
  let status = @process.run(
    "gh",
    [
      "pr", "create", "--title", pr_title, "--body", pr_body, "--base", base_branch,
      "--head", branch,
    ],
    stdout=process_read,
    stderr=process_err,
    cwd=clone_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    // PR creation failed - check if it's because PR already exists or no changes
    let error_output = err_pipe.read_all().text().to_string()

    // Check if PR already exists for this branch
    if error_output.contains("already exists") {
      @stdio.stdout.write(
        "info [\{repo.name}] - PR already exists, fetching existing PR\n",
      )

      // Try to find existing PR for this branch
      let (list_pipe, list_read) = @process.read_from_process()
      let list_status = @process.run(
        "gh",
        ["pr", "list", "--head", branch, "--json", "number,url", "--limit", "1"],
        stdout=list_read,
        cwd=clone_path,
      ) catch {
        e => @error.reraise(e)
      }
      if list_status == 0 {
        let list_output = list_pipe
          .read_all()
          .text()
          .trim(char_set=" \t\n\r")
          .to_string()
        let json = @json.parse(list_output) catch {
          _ => {
            @stdio.stdout.write(
              "warning [\{repo.name}] - Could not parse PR list, marking complete\n",
            )
            config.state_mgr.transition(
              repo.id,
              Complete,
              details="PR exists but could not fetch details",
            ) catch {
              e => @error.reraise(e)
            }
            return
          }
        }

        // Parse the array and get first PR
        match json {
          Array(prs) if prs.length() > 0 =>
            match prs[0] {
              Object(pr_obj) => {
                let pr_number_opt = match pr_obj.get("number") {
                  Some(Number(n, ..)) => Some(n.to_int())
                  _ => None
                }
                let pr_url_opt = match pr_obj.get("url") {
                  Some(String(u)) => Some(u)
                  _ => None
                }
                match (pr_number_opt, pr_url_opt) {
                  (Some(num), Some(url)) => {
                    @stdio.stdout.write(
                      "info [\{repo.name}] - Found existing PR #\{num}: \{url}\n",
                    )
                    let updates = [
                      ("pr_url", url),
                      ("pr_state", "open"),
                      ("pr_number", num.to_string()),
                    ]
                    config.state_mgr.update_repository(repo.id, updates) catch {
                      e => @error.reraise(e)
                    }
                    config.state_mgr.transition(
                      repo.id,
                      PrOpen,
                      details="Using existing PR, AI will monitor",
                    ) catch {
                      e => @error.reraise(e)
                    }
                    return
                  }
                  _ =>
                    @error.fail(
                      "Could not extract PR number/URL from existing PR",
                    )
                }
              }
              _ => @error.fail("Invalid PR data format")
            }
          _ => @error.fail("No existing PR found")
        }
      } else {
        @error.fail("Failed to list PRs")
      }
    } else if error_output.contains("no commits") ||
      error_output.contains("No commits") {
      @stdio.stdout.write(
        "info [\{repo.name}] - No changes to create PR, task complete\n",
      )
      config.state_mgr.transition(
        repo.id,
        Complete,
        details="No changes for PR",
      ) catch {
        e => @error.reraise(e)
      }
      return
    } else {
      @error.fail("gh pr create failed: \{error_output}")
    }
  }

  // PR created successfully - extract URL
  let pr_url = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  @stdio.stdout.write("info [\{repo.name}] - PR created: \{pr_url}\n")

  // Extract PR number from URL and save
  let pr_number_opt = @gh.extract_pr_number(pr_url)
  let updates = match pr_number_opt {
    Some(num) => {
      @stdio.stdout.write("info [\{repo.name}] - Extracted PR number: \{num}\n")
      [("pr_url", pr_url), ("pr_state", "open"), ("pr_number", num.to_string())]
    }
    None => {
      @stdio.stdout.write(
        "warning [\{repo.name}] - PR URL saved but no PR number extracted\n",
      )
      [("pr_url", pr_url), ("pr_state", "open")]
    }
  }
  config.state_mgr.update_repository(repo.id, updates) catch {
    e => @error.reraise(e)
  }

  // Transition to PrOpen for AI monitoring
  config.state_mgr.transition(
    repo.id,
    PrOpen,
    details="PR created, AI will monitor",
  ) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write(
    "info [\{repo.name}] - Transitioned to PR_OPEN for AI monitoring\n",
  )
}

///|
/// Perform commit (reentrant - checks if changes exist)

///|
/// Monitor PR and let AI decide next action based on current PR state
/// This function is called when repository is in PR_OPEN state
async fn do_handle_pr(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }

  // Check if gh is available
  @gh.ensure_available() catch {
    e => @error.reraise(e)
  }

  // We're in PrOpen state - fetch current PR state and let AI decide
  @stdio.stdout.write(
    "info [\{repo.name}] - AI monitoring: Fetching PR state from GitHub\n",
  )

  // Get PR number - try from database first, then extract from URL
  let pr_number_opt = match repo.pr_number {
    Some(num) => Some(num)
    None =>
      // Try to extract from pr_url if available
      match repo.pr_url {
        Some(url) => {
          let extracted = @gh.extract_pr_number(url)
          match extracted {
            Some(num) => {
              @stdio.stdout.write(
                "info [\{repo.name}] - Extracted PR number \{num} from URL\n",
              )
              // Save the extracted PR number
              config.state_mgr.update_field(
                repo.id,
                "pr_number",
                num.to_string(),
              ) catch {
                _ => ()
              }
              Some(num)
            }
            None => None
          }
        }
        None => None
      }
  }
  guard pr_number_opt is Some(pr_number) else {
    @stdio.stdout.write(
      "warning [\{repo.name}] - No PR number and could not extract from URL, marking complete\n",
    )
    config.state_mgr.transition(
      repo.id,
      Complete,
      details="No PR number available",
    ) catch {
      e => @error.reraise(e)
    }
    return
  }

  // Fetch PR state from GitHub
  let pr_info = fetch_pr_state(clone_path, pr_number) catch {
    e => @error.reraise(e)
  }
  let review_str = if pr_info.review_decision.is_empty() {
    "none"
  } else {
    pr_info.review_decision
  }
  @stdio.stdout.write(
    "info [\{repo.name}] - AI decision point: PR state=\{pr_info.state}, mergeable=\{pr_info.mergeable}, review=\{review_str}\n",
  )

  // AI Decision Point: AI analyzes PR state and decides next action
  // The AI has full autonomy to decide whether to:
  // 1. Mark as complete (merged, closed, or AI determines no further action needed)
  // 2. Go back to fixing (changes requested, conflicts, or AI sees issues)
  // 3. Stay in PR_OPEN to continue monitoring (waiting for review, CI, etc.)

  // Use Codex AI to analyze PR state and work on issues if needed
  @stdio.stdout.write(
    "info [\{repo.name}] - Asking AI to analyze PR and address any issues\n",
  )
  guard repo.task_description is Some(original_task) else {
    @error.fail("No task description set")
  }
  guard repo.pr_url is Some(url) else { @error.fail("No PR URL set") }

  // Prepare PR state information for AI
  let review_decision = if pr_info.review_decision.is_empty() {
    "No review decision yet"
  } else {
    pr_info.review_decision
  }

  // Fetch PR comments to give AI full context
  let comments_text = fetch_pr_comments(clone_path, pr_number)

  // Let AI analyze and fix issues directly (if any)
  let analysis_task =
    $|Original task: \{original_task}
    $|
    $|PULL REQUEST STATUS UPDATE:
    $|- PR URL: \{url}
    $|- State: \{pr_info.state}
    $|- Mergeable: \{pr_info.mergeable}
    $|- Review Decision: \{review_decision}
    $|- Comments: \{comments_text}
    $|
    $|INSTRUCTIONS:
    $|
    $|Analyze the PR status above. If there are any issues (merge conflicts, review comments requesting changes, CI failures, etc.), please address them.
    $|If the PR is waiting for review/approval or already merged/closed, you don't need to do anything - just respond "NO_ACTION_NEEDED" with explanation.
    $|
    $|Review the Git diff carefully. Remove any code that does not directly address the PR issues, such as backup files, debug statements, or unrelated changes.
    $|Make sure the code adheres to best practices and the project's coding standards.
    $|

  // Create a thread to let AI analyze and work
  let thread = config.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      skip_git_repo_check=true,
      sandbox_mode=WorkspaceWrite,
    ),
  )
  let result = thread.run(analysis_task) catch { e => @error.reraise(e) }
  let response_lower = result.final_response.to_lower()

  // Check if AI determined PR is done or no action needed
  if pr_info.state is ("MERGED" | "CLOSED") ||
    response_lower.contains("no_action_needed") ||
    response_lower.contains("no action needed") {
    @stdio.stdout.write(
      "info [\{repo.name}] - AI analysis: \{result.final_response}\n",
    )
    if pr_info.state == "MERGED" {
      config.state_mgr.transition(repo.id, Complete, details="PR merged") catch {
        e => @error.reraise(e)
      }
    } else if pr_info.state == "CLOSED" {
      config.state_mgr.transition(repo.id, Complete, details="PR closed") catch {
        e => @error.reraise(e)
      }
    } else {
      // AI determined no action needed, stay in PR_OPEN for next check
      @stdio.stdout.write(
        "info [\{repo.name}] - No action needed, will check again on next run\n",
      )
    }
  } else {
    // AI made changes - check if there are actual file modifications
    let git_repo = @git.GitRepo::discover(clone_path) catch {
      e => @error.fail_with("Failed to discover repository", e)
    }
    if !git_repo.has_changes() {
      @stdio.stdout.write(
        "info [\{repo.name}] - AI analyzed but made no changes, will check again on next run\n",
      )
    } else {
      // AI made changes, commit and push
      @stdio.stdout.write(
        "info [\{repo.name}] - AI made changes to address PR issues\n",
      )
      guard repo.current_branch is Some(branch) else {
        @error.fail("No current branch set")
      }

      // Commit the changes
      let commit_msg = "AI: Address PR feedback - \{original_task}"
      if !git_repo.commit(commit_msg) {
        @error.fail("Failed to commit AI changes")
      }

      // Push the changes
      if !git_repo.push(branch~, set_upstream=true) {
        @error.fail("Failed to push AI changes")
      }
      @stdio.stdout.write(
        "info [\{repo.name}] - AI changes committed and pushed, staying in PR_OPEN for re-check\n",
      )
      // Stay in PR_OPEN state to re-check PR on next run
    }
  }
}
