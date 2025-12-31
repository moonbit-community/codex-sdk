///|
async fn main {
  let command_opt = @app.parse_cli_args(@sys.get_cli_args()[1:])
  match command_opt {
    None => {
      @stdio.stdout.write(@app.help_message())
      return
    }
    Some(command) => {
      if command.subcommand == "run" {
        let run_context_opt = @app.prepare_run(
          command.args,
          command.work_dir,
          command.data_dir,
        )
        match run_context_opt {
          None => {
            @stdio.stdout.write(@app.run_help_message())
            return
          }
          Some(run_context) => {
            @stdio.stdout.write("=".repeat(60))
            @stdio.stdout.write("\nSTARTING PARALLEL REPOSITORY PROCESSING\n")
            @stdio.stdout.write("=".repeat(60))
            @stdio.stdout.write("\n\n")
            @stdio.stdout.write("Configuration:\n")
            @stdio.stdout.write("  Work directory: \{run_context.work_dir}\n")
            @stdio.stdout.write("  Parallelism: \{run_context.parallelism}\n")
            @stdio.stdout.write("  Branch prefix: \{run_context.branch_prefix}\n")
            @stdio.stdout.write("\n")

            if run_context.total == 0 {
              @stdio.stdout.write(
                "No repositories in database. Add some with:\n  moon run real_world/parallel_fix -- add <repos-file> --task \"description\"\n",
              )
              return
            }
            @stdio.stdout.write("Total repositories: \{run_context.total}\n")

            if run_context.incomplete_repos.is_empty() {
              @stdio.stdout.write(
                "\nNo incomplete repositories to process. All done!\n",
              )
              return
            }
            @stdio.stdout.write(
              "\nProcessing \{run_context.incomplete_repos.length()} incomplete repositories...\n\n",
            )

            let codex = @codex.Codex::new(
              options=@codex.CodexOptions::new(
                codex_path_override="./alternative_codex.sh",
              ),
            )
            let run_task = async fn(
              clone_path : String,
              prompt : String,
            ) {
              run_task_with_codex(codex, clone_path, prompt)
            }
            let generate_commit_message = async fn(
              repo : @app.RepositoryRecord,
              diff : String,
            ) {
              generate_commit_message_with_codex(codex, repo, diff)
            }
            let generate_pr_metadata = async fn(
              repo : @app.RepositoryRecord,
              diff_summary : String,
            ) {
              generate_pr_metadata_with_codex(codex, repo, diff_summary)
            }
            let config = @app.WorkerConfig::{
              work_dir: run_context.work_dir,
              branch_prefix: run_context.branch_prefix,
              db: run_context.db,
            }
            let mut processed = 0
            let mut successful = 0
            @async.with_task_group(fn(task_group) {
              let semaphore = @semaphore.Semaphore::new(
                run_context.parallelism,
              )
              for repo in run_context.incomplete_repos {
                task_group.spawn_bg(allow_failure=true, fn() {
                  semaphore.acquire()
                  defer semaphore.release()
                  processed = processed + 1
                  @app.process_repository(
                    config,
                    repo,
                    run_task,
                    generate_commit_message,
                    generate_pr_metadata,
                  ) catch {
                    e =>
                      @stdio.stderr.write(
                        "error [\{repo.url}] - Unexpected error: \{e}\n",
                      )
                  }
                  successful = successful + 1
                })
              }
            })

            @stdio.stdout.write("\n")
            @stdio.stdout.write("=".repeat(60))
            @stdio.stdout.write("\nFINAL SUMMARY\n")
            @stdio.stdout.write("=".repeat(60))
            @stdio.stdout.write("\n")
            @stdio.stdout.write("  Processed: \{processed}\n")
            @stdio.stdout.write("  Successful: \{successful}\n")
            @stdio.stdout.write("\n")
            @stdio.stdout.write(
              "Run 'moon run real_world/parallel_fix -- status --verbose' for detailed status\n",
            )
          }
        }
      } else {
        @app.run_non_run(command)
      }
    }
  }
}

///|
async fn run_task_with_codex(
  codex : @codex.Codex,
  clone_path : String,
  prompt : String,
) -> String? {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )
  let _ = thread.run(prompt)
  @stdio.stdout.write("info AI task completed\n")
  thread.id()
}

///|
async fn generate_commit_message_with_codex(
  codex : @codex.Codex,
  repo : @app.RepositoryRecord,
  diff : String,
) -> String {
  try {
    let thread = codex.start_thread(
      options=@codex.ThreadOptions::new(
        working_directory=".",
        model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
      ),
    )
    let prompt = @app.commit_message_prompt(repo, diff)
    let result = thread.run(prompt)
    let message_opt = @app.parse_commit_message(
      result.final_response,
    ) catch {
      _ => None
    }
    match message_opt {
      Some(message) => message
      None => @error.fail("Commit message response missing message field")
    }
  } catch {
    e => {
      @stdio.stderr.write("warning Failed to generate commit message: \{e}\n")
      "AI work on: \{repo.task}"
    }
  }
}

///|
async fn generate_pr_metadata_with_codex(
  codex : @codex.Codex,
  repo : @app.RepositoryRecord,
  diff_summary : String,
) -> (String, String) {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=".",
      model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
    ),
  )
  let prompt = @app.pr_metadata_prompt(repo, diff_summary)
  let result = thread.run(prompt) catch {
    e => {
      @stdio.stderr.write(
        "warning Failed to generate PR metadata: \{e}\n",
      )
      return (
        @app.fallback_pr_title(),
        @app.fallback_pr_body(repo.task),
      )
    }
  }
  let parsed = @app.parse_pr_metadata(result.final_response) catch {
    e => {
      @stdio.stderr.write(
        "warning Failed to parse PR metadata JSON: \{e}\n",
      )
      return (
        @app.fallback_pr_title(),
        @app.fallback_pr_body(repo.task),
      )
    }
  }
  match parsed {
    Some((title, body)) => (title, body)
    None => {
      @stdio.stderr.write(
        "warning PR metadata response missing title/body fields\n",
      )
      (
        @app.fallback_pr_title(),
        @app.fallback_pr_body(repo.task),
      )
    }
  }
}
