///|
/// Process files with concurrency control
async fn process_concurrently(
  files : Array[String],
  project_root : String,
  reviewer : Reviewer,
  output_dir : String,
  concurrency : Int,
  verbose : Bool,
) -> Array[ReviewResult] {
  let results : Array[ReviewResult] = []
  let mut completed = 0
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(concurrency)
    for i, file in files {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        @stdio.stdout.write(
          "info [\{i + 1}/\{files.length()}] - Acquired semaphore, starting review of \{file}...\n",
        )
        defer semaphore.release()
        let result = review_mbti_file(file, project_root, reviewer, verbose) catch {
          e => {
            @stdio.stderr.write("Error reviewing \{file}:\n\{e}\n")
            ReviewResult::{
              file,
              pkg_name: "unknown",
              review: "",
              success: false,
              error: e.to_string(),
            }
          }
        }
        results.push(result)
        let output_path = if result.success {
          save_review_to_file(result, output_dir) catch {
            e => {
              @stdio.stderr.write(
                "Failed to save review for \{result.file}:\n\{e}\n",
              )
              None
            }
          }
        } else {
          None
        }
        completed = completed + 1
        let status = if result.success { "✓" } else { "✗" }
        let saved_msg = match output_path {
          Some(path) => {
            let rel_path = if path.has_prefix(project_root) {
              try! path[project_root.length() + 1:].to_string()
            } else {
              path
            }
            " → \{rel_path}"
          }
          None => ""
        }
        @stdio.stdout.write(
          "\{status} [\{completed}/\{files.length()}] \{result.file}\{saved_msg}\n",
        )
      })
    }
  })
  results
}

