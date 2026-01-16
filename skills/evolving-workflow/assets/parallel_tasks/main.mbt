///|
/// Main entry point: parallel task processing workflow.
/// Pattern: Fan-out with bounded concurrency.
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
  @stdio.stdout.write("Processing \{config.items.length()} items with parallelism \{config.parallelism}\n\n")
  let codex = @codex.Codex::new()
  let results = @app.for_all_tasks(
    config.items,
    async fn(idx, _) {
      let handle = config.task_start(idx)
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
            handle.validate(response.final_response)
            handle.finish()
          },
          max_retry=3,
        )
      } catch {
        e => handle.error(e)
      }
    },
    parallelism=config.parallelism,
  )
  config.summarize(results)
}
