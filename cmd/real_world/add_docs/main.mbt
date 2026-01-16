///|
async fn main {
  let config = @app.initialize() catch {
    @app.AppErrors::NeedHelp(message) => {
      @stdio.stdout.write(message)
      return
    }
    e => raise e
  }
  if config.packages.is_empty() {
    @stdio.stdout.write("No packages found. Exiting.\n")
    return
  }
  @stdio.stdout.write("Using parallelism: \{config.parallelism}\n\n")
  let codex = @codex.Codex::new()
  let results = @shared.for_all_tasks(
    config.packages,
    async fn(idx, _) {
      let handle = config.task_start(idx)
      try {
        let env = handle.setup()
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=env.worktree_path,
            sandbox_mode=DangerFullAccess,
          ),
        )
        // Retry domain: get prompt -> run -> validate -> finish
        @async.retry(
          @async.RetryMethod::Immediate,
          fn() {
            let prompt = handle.prompt()
            let response = thread.run(prompt)
            handle.validate(response.final_response)
            handle.finish(thread.id())
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
