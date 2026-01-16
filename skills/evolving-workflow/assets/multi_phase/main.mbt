///|
/// Main entry point: multi-phase workflow.
/// Pattern: Fan-out → Sequential → Fan-out
async fn main {
  let config = @app.initialize() catch {
    @app.AppErrors::NeedHelp(message) => {
      @stdio.stdout.write(message)
      return
    }
    e => raise e
  }
  if config.items.is_empty() {
    @stdio.stdout.write("No items to process. Exiting.\n")
    return
  }
  let codex = @codex.Codex::new()

  // =========================================================================
  // Phase 1: Fan out - Summarize each item
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 1: Summarizing items ===\n")
  let summaries = @app.for_all_tasks(
    config.items,
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
    parallelism=config.parallelism,
  )
  @stdio.stdout.write("Summarized \{summaries.length()} items\n")

  // =========================================================================
  // Phase 2: Sequential - Single planner groups items
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 2: Planning groups ===\n")
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
    @stdio.stdout.write("No groups to process. Exiting.\n")
    return
  }

  // =========================================================================
  // Phase 3: Fan out - Process each group
  // =========================================================================
  @stdio.stdout.write("\n=== Phase 3: Processing groups ===\n")
  let results = @app.for_all_tasks(
    groups,
    async fn(idx, group) {
      let handle = config.process_start(idx, group)
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
            let result = handle.validate(response.final_response)
            handle.finish(result)
          },
          max_retry=2,
        )
      } catch {
        e => handle.error(e)
      }
    },
    parallelism=config.parallelism,
  )
  config.summarize_results(results)
}
