///|
async fn main {
  let config = @app.initialize() catch {
    @app.AppErrors::NeedHelp(message) => {
      @stdio.stdout.write(message)
      return
    }
    e => raise e
  }
  let codex = @codex.Codex::new()
  let results = @shared.for_all_tasks(
    config.tasks,
    async fn(idx, _) {
      let handle = config.task_start(idx)
      try {
        let input = handle.input()
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=config.project_root,
            sandbox_mode=DangerFullAccess,
          ),
        )
        // Retry domain: thread.run -> validate -> finish
        // Thread is shared so it can re-pickup the job on validation failure
        @async.retry(
          @async.RetryMethod::Immediate,
          fn() {
            let response = thread.run(input.prompt)
            handle.validate(response.final_response)
            handle.finish()
          },
          max_retry=3,
        )
      } catch {
        e => handle.error(e)
      }
    },
    parallelism=config.concurrency,
  )
  config.summarize(results)
}
