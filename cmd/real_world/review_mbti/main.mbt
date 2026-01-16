///|
async fn main {
  let config = @app.initialize() catch {
    @app.AppErrors::NeedHelp(message) => {
      @stdio.stdout.write(message)
      return
    }
    e => raise e
  }
  if config.files.is_empty() {
    @stdio.stdout.write("No files to review. Exiting.\n")
    return
  }
  let codex = @codex.Codex::new()

  // =========================================================================
  // Phase 1: Fan out - Summarize each package
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 1: Summarizing packages ===\n")
  let summaries = @shared.for_all_tasks(
    config.files,
    async fn(idx, _) {
      let handle = config.summarize_start(idx)
      try {
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=config.project_root,
            sandbox_mode=DangerFullAccess,
          ),
        )
        @async.retry(
          @async.RetryMethod::Immediate,
          fn() {
            let prompt = handle.prompt()
            let response = thread.run(prompt)
            let summary = handle.validate(response.final_response)
            handle.finish(summary)
          },
          max_retry=2,
        )
      } catch {
        e => handle.error(e)
      }
    },
    parallelism=config.concurrency,
  )
  @stdio.stdout.write("Summarized \{summaries.length()} packages\n")

  // =========================================================================
  // Phase 2: Sequential - Single planner groups packages
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 2: Planning review groups ===\n")
  let plan_handle = config.plan_start(summaries)
  let groups = try {
    let thread = codex.start_thread(
      options=@codex.ThreadOptions::new(
        working_directory=config.project_root,
        sandbox_mode=DangerFullAccess,
      ),
    )
    @async.retry(
      @async.RetryMethod::Immediate,
      fn() {
        let prompt = plan_handle.prompt()
        let response = thread.run(prompt)
        let groups = plan_handle.validate(response.final_response)
        plan_handle.finish(groups)
      },
      max_retry=3,
    )
  } catch {
    e => plan_handle.error(e)
  }
  if groups.is_empty() {
    @stdio.stdout.write("No groups to review. Exiting.\n")
    return
  }

  // =========================================================================
  // Phase 3: Fan out - Review each group
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 3: Reviewing groups ===\n")
  let reviews = @shared.for_all_tasks(
    groups,
    async fn(idx, group) {
      let handle = config.review_start(idx, group)
      try {
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=config.project_root,
            sandbox_mode=DangerFullAccess,
          ),
        )
        @async.retry(
          @async.RetryMethod::Immediate,
          fn() {
            let prompt = handle.prompt()
            let response = thread.run(prompt)
            let review = handle.validate(response.final_response)
            handle.finish(review)
          },
          max_retry=2,
        )
      } catch {
        e => handle.error(e)
      }
    },
    parallelism=config.concurrency,
  )
  config.summarize_results(reviews)
}
