///|
async fn main {
  let config = @app.initalize() catch {
    @app.AppErrors::NeedHelp(message) => {
      @stdio.stdout.write(message)
      return
    }
    e => raise e
  }
  let codex = @codex.Codex::new()
  let results = for_all_tasks(
    config.tasks,
    async fn(idx, _) {
      try {
        config.task_start(idx)
        let input = config.task_input(idx)
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=config.project_root,
            sandbox_mode=DangerFullAccess,
          ),
        )
        let response = thread.run(input.prompt)
        config.task_return(idx, response.final_response)
      } catch {
        e => config.task_error(idx, e)
      }
    },
    retry_attempts=3,
    parallelism=config.concurrency,
  )
  config.summarize(results)
}

///|
async fn[A, B] for_all_tasks(
  task : Array[A],
  fn_handle : async (Int, A) -> B,
  parallelism? : Int = 4,
  retry_strategy? : @async.RetryMethod = @async.RetryMethod::Immediate,
  retry_attempts? : Int = 1,
  fatal_error? : (Error) -> Bool,
) -> Array[B] {
  let output = Array::make(task.length(), None)
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(parallelism)
    for i, item in task {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let result = @async.retry(
          retry_strategy,
          () => fn_handle(i, item),
          max_retry=retry_attempts,
          fatal_error?,
        )
        output[i] = Some(result)
      })
    }
  })
  output.map(result => result.unwrap())
}
