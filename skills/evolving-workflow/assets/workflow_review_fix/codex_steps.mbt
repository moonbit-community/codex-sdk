///|
async fn run_review(
  codex : @codex.Codex,
  item : WorkItem,
  workdir : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::ReadOnly,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|You are running inside a plan-as-code workflow.
    $|
    $|Task label: \{item.label}
    $|
    $|Review request:
    $|\{item.review}
    $|
    $|Constraints:
    $|- Read-only sandbox; do not propose running commands that modify files.
    $|- Return a concise, actionable review summary (bullets are fine).
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn run_fix_iteration(
  codex : @codex.Codex,
  item : WorkItem,
  workdir : String,
  fix_sandbox : @codex.SandboxMode,
  previous_failure_output? : String? = None,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=fix_sandbox,
      skip_git_repo_check=true,
    ),
  )
  let failure_context = match previous_failure_output {
    Some(text) => {
      let ctx =
        $|\n\nPrevious failure output:\n\{text}
      ctx
    }
    None => ""
  }
  let fix = item.fix.unwrap_or(
    "Implement a minimal fix for the issue described in the review request.",
  )
  let prompt =
    $|You are running inside a plan-as-code workflow.
    $|
    $|Task label: \{item.label}
    $|
    $|Fix request:
    $|\{fix}
    $|
    $|Hard verification:
    $|- The workflow will run verifications defined in code (edit verification.mbt).
    $|- If a verification fails, you will be resumed with the failure output.
    $|
    $|Constraints:
    $|- Prefer minimal diffs and keep behavior stable unless requested.
    $|- If you change behavior, update snapshots as needed.
    $|\{failure_context}
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn review_interface_diff(
  codex : @codex.Codex,
  item : WorkItem,
  workdir : String,
  diff : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::ReadOnly,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|Review the following MoonBit public interface diff and summarize what changed.
    $|
    $|Task label: \{item.label}
    $|
    $|Diff (git diff of *.mbti / pkg.generated.mbti):
    $|\{diff}
    $|
    $|Output:
    $|- 2-6 bullets summarizing changes
    $|- Call out likely breaking changes (if any)
    $|- Say whether changes seem expected for the task label
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}
