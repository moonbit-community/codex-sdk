///|
/// Worker for processing repositories with state management

///|
/// Configuration for repository processing
struct WorkerConfig {
  work_dir : String
  branch_prefix : String
  codex : @codex.Codex
  state_mgr : StateManager
}

///|
/// Process a repository based on its current state
/// This is the main state-driven processing function
pub async fn process_repository_stateful(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit {
  let repo_id = repo.id
  let repo_name = repo.name
  @stdio.stdout.write(
    "info [\{repo_name}] - Processing from state: \{repo.state}\n",
  )

  // Process based on current state
  match repo.state {
    Pending | Retry =>
      start_cloning(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "cloning", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Cloning =>
      do_clone(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "cloning", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Branching =>
      do_branch(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "branching", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Fixing =>
      do_fix(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "fixing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Committing =>
      do_commit(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "committing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Pushing =>
      do_push(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "pushing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    PrCreating | PrOpen =>
      do_handle_pr(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "PR handling", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    PrChangesRequested | PrApproved | PrConflicts | PrMerged => {
      // These states are deprecated - should not appear in new design
      @stdio.stdout.write(
        "warning [\{repo_name}] - Deprecated state \{repo.state}, transitioning to PR_OPEN\n",
      )
      config.state_mgr.transition(
        repo_id,
        PrOpen,
        Some("Migrating from deprecated state"),
      ) catch {
        e => @error.reraise(e)
      }
    }
    Complete => @stdio.stdout.write("info [\{repo_name}] - Already complete\n")
  }
}

///|
/// Handle error during processing
async fn handle_error(
  config : WorkerConfig,
  repo_id : Int,
  repo_name : String,
  phase : String,
  error : String,
) -> Unit raise Error {
  @stdio.stderr.write(
    "error [\{repo_name}] - Failed during \{phase}: \{error}\n",
  )
  config.state_mgr.log(repo_id, "ERROR", "Failed during \{phase}: \{error}") catch {
    e => @error.reraise(e)
  }

  // Update error and transition to Retry
  let updates = [("last_error", error)]
  config.state_mgr.update_repository(repo_id, updates) catch {
    e => @error.reraise(e)
  }
  config.state_mgr.transition(
    repo_id,
    Retry,
    Some("Retry after \{phase} error"),
  ) catch {
    e => @error.reraise(e)
  }
}

///|
/// Start cloning phase
async fn start_cloning(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  config.state_mgr.transition(repo.id, Cloning, Some("Starting clone")) catch {
    e => @error.reraise(e)
  }
  do_clone(config, repo) catch {
    e => @error.reraise(e)
  }
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
    match @git.GitRepo::discover(clone_path) {
      Some(git_repo) => {
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
          Some("Repository discovered"),
        ) catch {
          e => @error.reraise(e)
        }
        @stdio.stdout.write("info [\{repo.name}] - Clone verified\n")
        return
      }
      None => {
        @stdio.stdout.write(
          "warning [\{repo.name}] - Failed to discover, removing and recloning\n",
        )
        ignore(@process.run("rm", ["-rf", clone_path]) catch { _ => 1 })
      }
    }
  }

  // Clone repository
  @stdio.stdout.write("info [\{repo.name}] - Cloning to \{clone_path}\n")
  match @git.GitRepo::clone(repo.url, clone_path) {
    Some(git_repo) => {
      let default_branch = git_repo.default_branch.unwrap_or("main")
      let updates = [
        ("local_path", clone_path),
        ("default_branch", default_branch),
      ]
      config.state_mgr.update_repository(repo.id, updates) catch {
        e => @error.reraise(e)
      }
      config.state_mgr.transition(repo.id, Branching, Some("Clone successful")) catch {
        e => @error.reraise(e)
      }
      @stdio.stdout.write("info [\{repo.name}] - Clone successful\n")
    }
    None => @error.fail("Failed to clone repository")
  }
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
  guard @git.GitRepo::discover(clone_path) is Some(git_repo) else {
    @error.fail("Failed to discover repository at \{clone_path}")
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
      config.state_mgr.transition(repo.id, Fixing, Some("Branch exists")) catch {
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
  config.state_mgr.transition(repo.id, Fixing, Some("Branch created")) catch {
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
      Some("AI determined no changes needed"),
    ) catch {
      e => @error.reraise(e)
    }
    return
  }

  // AI made changes, proceed to committing
  config.state_mgr.transition(repo.id, Committing, Some("AI fix completed")) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - AI fix completed\n")
}

///|
/// Perform commit (reentrant - checks if changes exist)
async fn do_commit(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }
  guard repo.task_description is Some(task) else {
    @error.fail("No task description set")
  }

  // Discover repository
  guard @git.GitRepo::discover(clone_path) is Some(git_repo) else {
    @error.fail("Failed to discover repository")
  }

  // Check if there are changes
  if !git_repo.has_changes() {
    @stdio.stdout.write("warning [\{repo.name}] - No changes to commit\n")
    config.state_mgr.transition(repo.id, Pushing, Some("No changes")) catch {
      e => @error.reraise(e)
    }
    return
  }

  // Commit changes
  let commit_msg = "AI fix: \{task}"
  @stdio.stdout.write("info [\{repo.name}] - Committing changes\n")
  if !git_repo.commit(commit_msg) {
    @error.fail("Failed to commit changes")
  }
  config.state_mgr.transition(repo.id, Pushing, Some("Changes committed")) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Changes committed successfully\n")
}

///|
/// Perform push
async fn do_push(config : WorkerConfig, repo : RepositoryRecord) -> Unit {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }
  guard repo.current_branch is Some(branch) else {
    @error.fail("No current branch set")
  }

  // Discover repository
  guard @git.GitRepo::discover(clone_path) is Some(git_repo) else {
    @error.fail("Failed to discover repository")
  }
  @stdio.stdout.write("info [\{repo.name}] - Pushing branch: \{branch}\n")
  if !git_repo.push(branch~, set_upstream=true) {
    @error.fail("Failed to push branch")
  }
  config.state_mgr.transition(repo.id, PrCreating, Some("Branch pushed")) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Branch pushed successfully\n")
}

///|
/// Handle PR creation and post-PR state management
/// This function creates a PR if in PrCreating state, or fetches PR state and decides next action if in PrOpen
async fn do_handle_pr(
  config : WorkerConfig,
  repo : RepositoryRecord,
) -> Unit raise Error {
  guard repo.local_path is Some(clone_path) else {
    @error.fail("No local path set")
  }
  guard repo.current_branch is Some(branch) else {
    @error.fail("No current branch set")
  }
  guard repo.default_branch is Some(default_branch) else {
    @error.fail("No default branch set")
  }
  guard repo.task_description is Some(task) else {
    @error.fail("No task description set")
  }

  // Check if gh is available
  let which_status = @process.run("which", ["gh"]) catch { _ => 1 }
  if which_status != 0 {
    @stdio.stdout.write(
      "warning [\{repo.name}] - GitHub CLI not found, cannot manage PR\n",
    )
    config.state_mgr.transition(repo.id, Complete, Some("No gh CLI available")) catch {
      e => @error.reraise(e)
    }
    return
  }

  // If we're in PrCreating state, create the PR first
  if repo.state == PrCreating {
    @stdio.stdout.write("info [\{repo.name}] - Creating pull request\n")

    // Create PR using gh
    let title = "AI fix: \{task}"
    let body = "This PR was automatically generated to address:\n\n\{task}"
    let (pipe, process_read) = @process.read_from_process()
    let status = @process.run(
      "gh",
      [
        "pr", "create", "--title", title, "--body", body, "--base", default_branch,
        "--head", branch,
      ],
      stdout=process_read,
      cwd=clone_path,
    ) catch {
      e => @error.reraise(e)
    }
    if status != 0 {
      @error.fail("gh pr create failed")
    }
    let pr_url = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
    @stdio.stdout.write("info [\{repo.name}] - PR created: \{pr_url}\n")

    // Extract PR number from URL (e.g., https://github.com/owner/repo/pull/123)
    // Example: https://github.com/owner/repo/pull/123 -> 123
    let pr_number_opt : Int? = {
      let parts = pr_url.split("/").to_array()
      if parts.length() > 0 {
        let last = parts[parts.length() - 1].to_string()
        let num = @strconv.parse_int(last) catch { _ => -1 }
        if num > 0 {
          Some(num)
        } else {
          None
        }
      } else {
        None
      }
    }

    // Update repository with PR info
    let updates = match pr_number_opt {
      Some(num) =>
        [
          ("pr_url", pr_url),
          ("pr_state", "open"),
          ("pr_number", num.to_string()),
        ]
      None => [("pr_url", pr_url), ("pr_state", "open")]
    }
    config.state_mgr.update_repository(repo.id, updates) catch {
      e => @error.reraise(e)
    }

    // Transition to PrOpen for next processing
    config.state_mgr.transition(repo.id, PrOpen, Some("PR created")) catch {
      e => @error.reraise(e)
    }
    @stdio.stdout.write(
      "info [\{repo.name}] - Transitioned to PR_OPEN, will fetch state on next run\n",
    )
    return
  }

  // We're in PrOpen state - fetch current PR state and let AI decide
  @stdio.stdout.write("info [\{repo.name}] - Fetching PR state from GitHub\n")

  // Get PR number
  guard repo.pr_number is Some(pr_number) else {
    @stdio.stdout.write(
      "warning [\{repo.name}] - No PR number, marking complete\n",
    )
    config.state_mgr.transition(
      repo.id,
      Complete,
      Some("No PR number available"),
    ) catch {
      e => @error.reraise(e)
    }
    return
  }

  // Fetch PR state
  match fetch_pr_state(clone_path, pr_number) {
    Some(pr_info) => {
      let review_str = if pr_info.review_decision.is_empty() {
        "none"
      } else {
        pr_info.review_decision
      }
      @stdio.stdout.write(
        "info [\{repo.name}] - PR state: \{pr_info.state}, mergeable: \{pr_info.mergeable}, review: \{review_str}\n",
      )

      // AI Decision Point: Decide what to do based on PR state
      if pr_info.state == "MERGED" {
        @stdio.stdout.write("info [\{repo.name}] - PR merged, task complete\n")
        config.state_mgr.transition(repo.id, Complete, Some("PR merged")) catch {
          e => @error.reraise(e)
        }
      } else if pr_info.review_decision == "CHANGES_REQUESTED" {
        @stdio.stdout.write(
          "info [\{repo.name}] - Changes requested, going back to fixing\n",
        )
        config.state_mgr.transition(
          repo.id,
          Fixing,
          Some("Changes requested by reviewers"),
        ) catch {
          e => @error.reraise(e)
        }
      } else if pr_info.mergeable == "CONFLICTING" {
        @stdio.stdout.write(
          "info [\{repo.name}] - PR has conflicts, going back to fixing\n",
        )
        config.state_mgr.transition(
          repo.id,
          Fixing,
          Some("Merge conflicts detected"),
        ) catch {
          e => @error.reraise(e)
        }
      } else {
        // PR is open, approved, or no issues - consider task complete
        @stdio.stdout.write(
          "info [\{repo.name}] - PR is \{pr_info.state} with no issues, task complete\n",
        )
        config.state_mgr.transition(
          repo.id,
          Complete,
          Some("PR in good state (\{pr_info.state})"),
        ) catch {
          e => @error.reraise(e)
        }
      }
    }
    None => {
      @stdio.stdout.write(
        "warning [\{repo.name}] - Could not fetch PR state, marking complete\n",
      )
      config.state_mgr.transition(
        repo.id,
        Complete,
        Some("Could not fetch PR state"),
      ) catch {
        e => @error.reraise(e)
      }
    }
  }
}
