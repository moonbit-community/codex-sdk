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
  let results = for_all_tasks(
    config.packages,
    async fn(idx, _) {
      let handle = config.task_start(idx)
      try {
        let input = handle.input()
        let thread = codex.start_thread(
          options=@codex.ThreadOptions::new(
            working_directory=input.worktree.tmp_path,
            sandbox_mode=DangerFullAccess,
          ),
        )
        // Retry domain: run prompt -> check completion -> finish
        @async.retry(
          @async.RetryMethod::Immediate,
          fn() {
            let response = thread.run(input.prompt)
            handle.validate(response.final_response) catch {
              @app.ValidationError::TaskNotCompleted => {
                // Ask for completion confirmation
                let followup = thread.run(@app.completion_followup())
                handle.validate(followup.final_response)
              }
            }
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

///|
/// Runs tasks in parallel with bounded concurrency.
async fn[A, B] for_all_tasks(
  tasks : Array[A],
  fn_handle : async (Int, A) -> B,
  parallelism? : Int = 4,
) -> Array[B] {
  let output : Array[B?] = Array::make(tasks.length(), None)
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(parallelism)
    for i, item in tasks {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let result = fn_handle(i, item)
        output[i] = Some(result)
      })
    }
  })
  output.map(fn(result) { result.unwrap() })
}
