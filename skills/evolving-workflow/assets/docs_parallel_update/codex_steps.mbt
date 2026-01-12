///|
async fn update_doc_file(
  codex : @codex.Codex,
  workdir : String,
  relative_path : String,
) -> Unit raise Error {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      approval_policy=@codex.ApprovalMode::OnFailure,
      skip_git_repo_check=true,
    ),
  )
  let prompt =
    $|Update the documentation file at path: \{relative_path}
    $|
    $|Goal:
    $|- Improve clarity and correctness.
    $|- Fix broken references or misleading statements if you find them.
    $|
    $|Constraints:
    $|- Only modify this one file (do not edit other files).
    $|- Preserve code examples; if it is a *.mbt.md, keep `mbt check` blocks valid.
    $|- Avoid adding new dependencies.
  let _turn = thread.run(prompt)
  ()
}

///|
async fn review_interface_diff_with_codex(
  codex : @codex.Codex,
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
    $|Diff (git diff of *.mbti / pkg.generated.mbti):
    $|\{diff}
    $|
    $|Output:
    $|- 2-6 bullets summarizing changes
    $|- Call out likely breaking changes (if any)
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}
