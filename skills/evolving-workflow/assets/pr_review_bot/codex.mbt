///|
/// Codex interaction: prompts and running Codex for PR review.

///|
/// Run Codex to review a PR.
/// Returns the review content as a string.
async fn run_codex_review(
  codex : @codex.Codex,
  review_path : String,
  task : Task,
  diff : String,
) -> String raise Error {
  let prompt = build_review_prompt(task, diff)
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=review_path,
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
  )
  let turn = thread.run(prompt) catch { e => raise e }
  turn.final_response
}

///|
/// Build the prompt for PR review.
/// Customize this to change what Codex analyzes.
fn build_review_prompt(task : Task, diff : String) -> String {
  let parts = [
    "Review this pull request. The PR is titled: \"",
    task.title,
    "\" by @",
    task.author,
    ".\n\nHere is the diff:\n```diff\n",
    diff,
    "\n```\n\n",
    "Provide a constructive code review focusing on:\n",
    "1. **Correctness**: Logic errors, edge cases, potential bugs\n",
    "2. **Code Quality**: Readability, naming, structure\n",
    "3. **Best Practices**: Idiomatic patterns, error handling\n",
    "4. **Suggestions**: Specific improvements with examples\n\n",
    "Be concise and actionable. Reference specific lines from the diff.\n",
    "Format as markdown suitable for a GitHub PR comment.",
  ]
  parts.iter().fold(init="", fn(acc, part) { acc + part })
}
