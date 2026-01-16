///|
/// Runs tasks in parallel with bounded concurrency and preserves input order.
pub async fn[A, B] for_all_tasks(
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
