///|
async fn main {
  let env = @sys.get_env_vars()
  let config = read_config(env)
  let files = discover_doc_files(config.workdir) catch { _ => [] }
  if files.is_empty() {
    @stdio.stderr.write(
      "No documentation files found under CODEX_WORKDIR=\{config.workdir}\n",
    )
    return
  }
  let end_index = if config.task_limit < 0 {
    files.length()
  } else {
    @cmp.minimum(config.task_offset + config.task_limit, files.length())
  }
  let targets : Array[DocTarget] = files[config.task_offset:end_index].mapi(fn(
    i,
    path,
  ) {
    { index: config.task_offset + i, path }
  })
  if targets.is_empty() {
    @stdio.stderr.write(
      "No targets in range (TASK_OFFSET=\{config.task_offset}, TASK_LIMIT=\{config.task_limit}, total=\{files.length()})\n",
    )
    return
  }
  @stdio.stderr.write(
    "Updating \{targets.length()} docs (TASK_OFFSET=\{config.task_offset}, PARALLELISM=\{config.parallelism})\n",
  )
  let codex = @codex.Codex::new()
  let updated : Array[DocUpdateResult] = []
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(config.parallelism)
    for target in targets {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let error : String? = try
          update_doc_file(codex, config.workdir, target.path)
        catch {
          e => Some("\{e}")
        } noraise {
          _ => None
        }
        match error {
          Some(msg) =>
            updated.push({
              index: target.index,
              path: target.path,
              ok: false,
              error: Some(msg),
            })
          None =>
            updated.push({
              index: target.index,
              path: target.path,
              ok: true,
              error: None,
            })
        }
      })
    }
  })
  updated.sort_by_key(r => r.index)
  let maintenance_steps = default_maintenance_steps(config.workdir)
  let (maintenance_ok, maintenance_output) = run_maintenance_steps(
    config.workdir,
    maintenance_steps,
  ) catch {
    _ => (false, "")
  }
  let interface_diff = git_interface_diff(config.workdir) catch { _ => None }
  let interface_review_summary = match interface_diff {
    Some(diff) =>
      Some(
        review_interface_diff_with_codex(codex, config.workdir, diff) catch {
          e => "ERROR: \{e}"
        },
      )
    None => None
  }
  let verifications = default_verifications(config.workdir)
  let (verified, verification_output) = run_verifications(
    config.workdir,
    verifications,
  ) catch {
    _ => (false, "")
  }
  let report : WorkflowReport = {
    targets: targets.length(),
    updated,
    maintenance_ok,
    maintenance_output,
    interface_review_summary,
    verified,
    verification_output,
  }
  @stdio.stdout.write(report.to_json().stringify(indent=2) + "\n")
}
