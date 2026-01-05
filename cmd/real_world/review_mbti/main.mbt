///|
/// Main entry point
async fn main {
  let arguments_opt = @app.parse_cli_args(@sys.get_cli_args()[1:])
  match arguments_opt {
    None => {
      @stdio.stdout.write(@app.help_message())
      return
    }
    Some(arguments) => {
      let project_root = arguments.path
      let output_dir = @app.output_dir(arguments)
      let files_to_review = @app.resolve_files_to_review(arguments)
      if files_to_review.is_empty() {
        @stdio.stdout.write("No files to review. Exiting.\n")
        return
      }
      @stdio.stdout.write(
        "Using concurrency limit: \{arguments.concurrency}\n\n",
      )
      let codex = @codex.Codex::new()
      let results : Array[@app.ReviewResult] = []
      let mut completed = 0
      @async.with_task_group(fn(task_group) {
        let semaphore = @semaphore.Semaphore::new(arguments.concurrency)
        for i, file in files_to_review {
          task_group.spawn_bg(allow_failure=true, fn() {
            semaphore.acquire()
            @stdio.stdout.write(
              "info [\{i + 1}/\{files_to_review.length()}] - Acquired semaphore, starting review of \{file}...\n",
            )
            defer semaphore.release()
            let result = try {
              let input = @app.prepare_review_input(
                file,
                project_root,
                arguments.verbose,
              )
              let thread = codex.start_thread(
                options=@codex.ThreadOptions::new(
                  working_directory=project_root,
                  sandbox_mode=DangerFullAccess,
                ),
              )
              let response = thread.run(input.prompt)
              @app.review_result_from_response(input, response.final_response)
            } catch {
              e => {
                @stdio.stderr.write("Error reviewing \{file}:\n\{e}\n")
                @app.error_result(file, e.to_string())
              }
            }
            results.push(result)
            let output_path = if result.success {
              @app.save_review_to_file(result, output_dir) catch {
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
              "\{status} [\{completed}/\{files_to_review.length()}] \{result.file}\{saved_msg}\n",
            )
          })
        }
      })
      let successful = results.filter(fn(r) { r.success }).length()
      let failed = results.filter(fn(r) { !r.success })
      let rel_output_dir = @app.summary_output_dir(output_dir, project_root)
      @stdio.stdout.write(
        (
          $|
          $|\{"=".repeat(80)}
          $|SUMMARY
          $|\{"=".repeat(80)}
          $|Total files \{results.length()}
          $|Successful: \{successful}
          $|Failed: \{failed.length()}
          $|Concurrency: \{arguments.concurrency}
          $|Output Directory: \{rel_output_dir}
          $|
        ),
      )
      if failed.length() > 0 {
        @stdio.stdout.write("\n❌ Failed reviews:\n")
        for f in failed {
          @stdio.stdout.write("  - \{f.file}: \{f.error}\n")
        }
      }
      @stdio.stdout.write("\n💾 Reviews saved to: \{output_dir}\n")
    }
  }
}
