///|
/// Worker for processing repositories with state management

///|
/// Configuration for repository processing
struct WorkerConfig {
  work_dir : String
  branch_prefix : String
  max_retries : Int
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

  // Check retry limit
  if repo.attempt_count >= config.max_retries {
    @stdio.stderr.write(
      "error [\{repo_name}] - Max retries exceeded (\{repo.attempt_count})\n",
    )
    config.state_mgr.transition(repo_id, Failed, Some("Max retries exceeded")) catch {
      e => @error.reraise(e)
    }
    @error.fail("Max retries exceeded for \{repo_name}")
  }

  // Increment attempt count at start
  config.state_mgr.increment_attempts(repo_id) catch {
    e => @error.reraise(e)
  }

  // Process based on current state
  // Note: Failed state should have been reset to Retry before processing
  match repo.state {
    Pending | Retry | Failed =>
      start_cloning(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "cloning", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Cloning | Cloned =>
      do_clone(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "cloning", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Branching | Branched =>
      do_branch(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "branching", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Fixing | Fixed =>
      do_fix(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "fixing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Committing | Committed =>
      do_commit(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "committing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    Pushing | Pushed =>
      do_push(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "pushing", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    PrCreating | PrOpen =>
      do_create_pr(config, repo) catch {
        e =>
          handle_error(config, repo_id, repo_name, "PR creation", e.to_string()) catch {
            err => @error.reraise(err)
          }
      }
    PrChangesRequested | PrApproved | PrConflicts =>
      @stdio.stdout.write(
        "info [\{repo_name}] - PR is in state \{repo.state}, no action needed\n",
      )
    PrMerged => {
      @stdio.stdout.write("info [\{repo_name}] - PR merged, marking complete\n")
      config.state_mgr.transition(repo_id, Complete, Some("PR merged")) catch {
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
        // If already in Cloned state, move to Branching to advance the workflow
        let next_state = if repo.state == Cloned { Branching } else { Cloned }
        config.state_mgr.transition(
          repo.id,
          next_state,
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
      config.state_mgr.transition(repo.id, Branched, Some("Branch exists")) catch {
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
  config.state_mgr.transition(repo.id, Branched, Some("Branch created")) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Branch created successfully\n")
}

///|
/// Perform AI fix
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

  // Run thread to execute the fix
  let _result = thread.run(task) catch { e => @error.reraise(e) }

  // Save thread ID if available
  if thread.id() is Some(thread_id) {
    let updates = [("thread_id", thread_id)]
    config.state_mgr.update_repository(repo.id, updates) catch {
      e => @error.reraise(e)
    }
  }
  config.state_mgr.transition(repo.id, Fixed, Some("AI fix completed")) catch {
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
    config.state_mgr.transition(repo.id, Committed, Some("No changes")) catch {
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
  config.state_mgr.transition(repo.id, Committed, Some("Changes committed")) catch {
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
  config.state_mgr.transition(repo.id, Pushed, Some("Branch pushed")) catch {
    e => @error.reraise(e)
  }
  @stdio.stdout.write("info [\{repo.name}] - Branch pushed successfully\n")
}

///|
/// Perform PR creation
async fn do_create_pr(config : WorkerConfig, repo : RepositoryRecord) -> Unit {
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
      "warning [\{repo.name}] - GitHub CLI not found, marking as pushed\n",
    )
    config.state_mgr.transition(repo.id, PrOpen, Some("No gh CLI")) catch {
      e => @error.reraise(e)
    }
    return
  }
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
  let updates = [("pr_url", pr_url), ("pr_state", "open")]
  config.state_mgr.update_repository(repo.id, updates) catch {
    e => @error.reraise(e)
  }
  config.state_mgr.transition(repo.id, PrOpen, Some("PR created")) catch {
    e => @error.reraise(e)
  }
}
