///|
async fn main {
  let env = @sys.get_env_vars()
  let args = @sys.get_cli_args()
  let config = read_config(env)
  let (file, mode, max_iterations, fix_sandbox) = parse_args(args)
  let maintenance_steps = default_maintenance_steps(config.workdir)
  let verifications = default_verifications(config.workdir)
  let all_items = read_items(file) catch {
    e => {
      @stdio.stderr.write("Error reading work items: \{e}\n")
      return
    }
  }
  if all_items.is_empty() {
    @stdio.stderr.write("No work items provided\n")
    return
  }
  let end_index = if config.task_limit < 0 {
    all_items.length()
  } else {
    let sum = config.task_offset + config.task_limit
    if sum < all_items.length() {
      sum
    } else {
      all_items.length()
    }
  }
  let items : Array[WorkItem] = []
  for i in config.task_offset..<end_index {
    items.push(all_items[i])
  }
  if items.is_empty() {
    @stdio.stderr.write(
      "No work items in range (TASK_OFFSET=\{config.task_offset}, TASK_LIMIT=\{config.task_limit}, total=\{all_items.length()})\n",
    )
    return
  }
  @stdio.stderr.write(
    "Running \{items.length()} items (TASK_OFFSET=\{config.task_offset}, mode=\{run_mode_to_string(mode)}, max_iterations=\{max_iterations})\n",
  )
  let codex = @codex.Codex::new()
  let results : Array[RunResult] = []
  for item in items {
    @stdio.stderr.write("== [\{item.index}] \{item.label} ==\n")
    let mut review_summary : String? = None
    if mode is Review || mode is Both {
      let review = run_review(codex, item, config.workdir) catch {
        e => "ERROR: \{e}"
      }
      review_summary = Some(review)
      @stdio.stderr.write("Review done\n")
    }
    if mode is Fix || mode is Both {
      let mut interface_review_summary : String? = None
      let mut last_failure_output : String? = None
      let mut ok = false
      let mut error : String? = None
      let mut iterations = 0
      while iterations < max_iterations {
        iterations = iterations + 1
        ignore(
          run_fix_iteration(
            codex,
            item,
            config.workdir,
            fix_sandbox,
            previous_failure_output=last_failure_output,
          ) catch {
            _ => ""
          },
        )
        let (maintenance_ok, maintenance_output) = run_maintenance_steps(
          config.workdir,
          maintenance_steps,
        ) catch {
          _ => (false, "")
        }
        if !maintenance_ok {
          last_failure_output = Some(maintenance_output)
          @stdio.stderr.write(
            "Maintenance failed (iteration \{iterations}); retrying\n",
          )
          continue
        }
        let interface_diff = git_interface_diff(config.workdir) catch {
          _ => None
        }
        match interface_diff {
          Some(diff) => {
            let summary = review_interface_diff(
              codex,
              item,
              config.workdir,
              diff,
            ) catch {
              e => "ERROR: \{e}"
            }
            interface_review_summary = Some(summary)
          }
          None => ()
        }
        let (verified, verification_output) = run_verifications(
          config.workdir,
          verifications,
        ) catch {
          _ => (false, "")
        }
        if verified {
          ok = true
          break
        } else {
          last_failure_output = Some(verification_output)
          @stdio.stderr.write(
            "Verifications failed (iteration \{iterations}); retrying\n",
          )
        }
      }
      if !ok {
        error = Some("Verifications did not pass within max iterations")
      }
      results.push({
        label: item.label,
        ok,
        iterations,
        review_summary,
        interface_review_summary,
        last_failure_output,
        error,
      })
    } else {
      results.push({
        label: item.label,
        ok: true,
        iterations: 0,
        review_summary,
        interface_review_summary: None,
        last_failure_output: None,
        error: None,
      })
    }
  }
  ignore(
    @stdio.stdout.write(results.to_json().stringify(indent=2) + "\n") catch {
      _ => ()
    },
  )
}
