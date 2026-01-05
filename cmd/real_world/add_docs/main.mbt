///|
async fn main {
  let arguments_opt = @app.parse_cli_args(@sys.get_cli_args()[1:])
  match arguments_opt {
    None => {
      @stdio.stdout.write(@app.help_message())
      return
    }
    Some(arguments) => {
      let repo = @app.open_repo(arguments.path) catch {
        e => @error.fail_with("Failed to open git repository", e)
      }
      let project = @app.open_module(arguments.path) catch {
        e => @error.fail_with("Failed to read Moon module", e)
      }
      let packages = @app.list_packages(project)
      let codex = @codex.Codex::new()
      @async.with_task_group(fn(task_group) {
        let semaphore = @semaphore.Semaphore::new(arguments.parallelism)
        for pkg in packages {
          task_group.spawn_bg(allow_failure=true, fn() {
            semaphore.acquire()
            @stdio.stdout.write(
              "info [\{pkg.path}] - Acquired semaphore, starting documentation addition...\n",
            )
            defer semaphore.release()
            let worktree = @app.create_worktree(repo, pkg) catch {
              e => {
                @stdio.stderr.write("error [\{pkg.path}] - Task failed: \{e}\n")
                return
              }
            }
            if worktree.reused_branch {
              @stdio.stdout.write(
                "info [\{pkg.path}] - Branch \{worktree.branch_name} already exists, creating worktree only...\n",
              )
            } else {
              @stdio.stdout.write(
                "info [\{pkg.path}] - Creating worktree and branch \{worktree.branch_name}...\n",
              )
            }
            @stdio.stdout.write(
              "info [\{pkg.path}] - Created git worktree at \{worktree.tmp_path} \n",
            )
            try {
              let thread = codex.start_thread(
                options=@codex.ThreadOptions::new(
                  working_directory=worktree.tmp_path,
                  sandbox_mode=DangerFullAccess,
                ),
              )
              let mut response = thread.run(@app.docs_prompt(pkg.path))
              let mut completed = false
              for _ in 0..<3 {
                if response.final_response.contains("TASK COMPLETED") {
                  completed = true
                  break
                }
                response = thread.run(@app.completion_followup())
              }
              if !completed {
                @error.fail(
                  "Codex failed to add documentation after multiple attempts",
                )
              }
              match thread.id() {
                Some(session_id) =>
                  @stdio.stdout.write(
                    "info [\{pkg.path}] - [\{session_id}] - AI declared fin for package at \{pkg.path}\n",
                  )
                None =>
                  @stdio.stdout.write(
                    "info [\{pkg.path}] - AI declared fin for package at \{pkg.path}\n",
                  )
              }
              @app.verify_package(pkg)
              if !@app.remove_worktree(repo, worktree.tmp_path) {
                @error.fail(
                  "error [\{pkg.path}] - Failed to remove git worktree at \{worktree.tmp_path}\n",
                )
              }
              @stdio.stdout.write(
                "info [\{pkg.path}] - Task finished normally\n",
              )
            } catch {
              e => {
                @app.remove_worktree(repo, worktree.tmp_path, force=true)
                |> ignore
                @stdio.stderr.write(
                  "error [\{pkg.path}] - Exception while adding docs: \{e}\n",
                )
              }
            }
          })
        }
      })
    }
  }
}
