///|
/// Utilities: parallelism, retry helpers, and common operations.

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

///|
/// Setup git worktree for isolated work.
/// Returns error message if setup fails.
async fn setup_worktree(workdir : String, worktree_path : String) -> String? {
  // Create worktrees directory if needed
  let worktrees_dir = workdir + "/.worktrees"
  if not(@fs.exists(worktrees_dir)) {
    @fs.mkdir(worktrees_dir, permission=0o755) catch {
      e => return Some("Failed to create worktrees dir: \{e}")
    }
  }

  // Create worktree from HEAD
  let (code, _, err) = @process.collect_output("git", [
    "-C", workdir, "worktree", "add", "--detach", worktree_path, "HEAD",
  ])
  if code != 0 {
    let err_msg = err.text() catch { _ => "unknown error" }
    return Some("git worktree add failed: " + err_msg)
  }
  None
}

///|
/// Cleanup worktree after use.
async fn cleanup_worktree(workdir : String, worktree_path : String) -> Unit {
  ignore(
    @process.collect_output("git", [
      "-C", workdir, "worktree", "remove", "--force", worktree_path,
    ]),
  )
}
