///|
/// Task identification: Fetch open PRs from GitHub.

///|
/// A PR to review
struct Task {
  pr_number : Int
  title : String
  author : String
}

///|
/// Fetch open PRs from GitHub and sync to database
async fn fetch_and_sync_prs(
  config : Config,
  db : @sqlite.Database,
) -> Array[Task] {
  // Fetch open PRs using gh CLI
  let (code, stdout, stderr) = @process.collect_output("gh", [
    "pr",
    "list",
    "--repo",
    config.repo,
    "--state",
    "open",
    "--json",
    "number,title,author",
    "--limit",
    "100",
  ]) catch {
    e => @error.fail_with("Failed to run gh pr list", e)
  }
  if code != 0 {
    let err_msg = stderr.text() catch { _ => "unknown error" }
    @error.fail("gh pr list failed: " + err_msg)
  }
  let output = stdout.text() catch {
    e => @error.fail_with("Failed to read gh output", e)
  }
  if output.is_blank() {
    return []
  }

  // Parse JSON output
  let json = @json.parse(output) catch {
    e => @error.fail_with("Failed to parse gh output", e)
  }
  let tasks : Array[Task] = []
  match json {
    Array(prs) =>
      for pr in prs {
        match pr {
          {
            "number": Number(n, ..),
            "title": String(title),
            "author": { "login": String(author), .. },
            ..
          } => {
            let pr_number = n.to_int()
            // Sync to database
            upsert_pr(db, pr_number, title, author) catch {
              e => @error.fail_with("Failed to sync PR #\{pr_number}", e)
            }
            tasks.push({ pr_number, title, author })
          }
          _ => ()
        }
      }
    _ => ()
  }
  tasks
}

///|
/// Get tasks that need processing (pending in database)
async fn get_tasks_to_process(
  db : @sqlite.Database,
  all_tasks : Array[Task],
  max_attempts : Int,
) -> Array[Task] {
  let pending_prs = get_pending_prs(db, max_attempts) catch {
    e => @error.fail_with("Failed to get pending PRs", e)
  }
  all_tasks.filter(fn(task) {
    pending_prs.iter().any(fn(n) { n == task.pr_number })
  })
}
