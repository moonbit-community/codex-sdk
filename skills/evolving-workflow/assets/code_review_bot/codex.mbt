///|
/// Codex interaction: prompts and running Codex for code review.

///|
/// Run Codex to review code in the target directory.
/// Returns the review content as a string.
async fn run_codex_review(
  codex : @codex.Codex,
  target_path : String,
) -> String raise Error {
  let prompt = review_prompt()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=target_path,
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
  )
  let turn = thread.run(prompt) catch { e => raise e }
  turn.final_response
}

///|
/// The prompt used for code review.
/// Customize this to change what Codex analyzes.
fn review_prompt() -> String {
  let prompt =
    #|Review the code in this directory. Analyze:
    #|
    #|1. **Code Quality**: Readability, naming, structure
    #|2. **Potential Bugs**: Logic errors, edge cases, error handling
    #|3. **Performance**: Inefficiencies, unnecessary allocations
    #|4. **Security**: Input validation, unsafe operations
    #|5. **Best Practices**: Idiomatic patterns, documentation
    #|
    #|Provide specific, actionable feedback with file:line references.
    #|Format as markdown with sections for each category.
    #|Only mention issues you actually find - don't pad the review.
  prompt
}
