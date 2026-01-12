///|
/// Utilities: parallelism helper.

///|
/// Run tasks in parallel with bounded concurrency.
/// Returns results in the same order as input items.
async fn[T, R] run_parallel(
  items : Array[T],
  concurrency : Int,
  f : async (T) -> R,
) -> Array[R] {
  let results : Array[R?] = Array::make(items.length(), None)
  @async.with_task_group(fn(tg) {
    let sem = @async.Semaphore::new(concurrency)
    for i, item in items {
      tg.spawn_bg(allow_failure=true, fn() {
        sem.acquire()
        defer sem.release()
        results[i] = Some(f(item))
      })
    }
  })
  results.map(fn(r) { r.unwrap() })
}
