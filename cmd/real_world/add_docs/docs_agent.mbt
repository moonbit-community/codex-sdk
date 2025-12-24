///|
/// Codex agent for generating documentation
struct DocsAgent {
  codex : @codex.Codex
}

///|
fn DocsAgent::new() -> DocsAgent {
  DocsAgent::{ codex: @codex.Codex::new() }
}

///|
/// Generate documentation for a package. Returns session id if available.
async fn DocsAgent::generate_for_package(
  self : DocsAgent,
  pkg_path : String,
  worktree_path : String,
) -> String? {
  let thread = self.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=worktree_path,
      sandbox_mode=DangerFullAccess,
    ),
  )
  let mut response = thread.run(
    (
      $|Generate documentation for the MoonBit package in the directory \{pkg_path} only.
      #|
      #|[Task Description]
      #|You will need to generate comments for all public functions, structs, enums, and modules in the package.
      #|You will also need to update the `README.mbt.md` file in the package.
      #|
      #|Remember that all the code block within the `README.mbt.md` file and the doc comments will be type checked and executed.
      #|When you have finished generating the documentation, commit the changes with a meaningful commit message, push the changes to the remote repository, and create a pull request for the changes.
      #|
      #|[Requirements]
      #|You must ensure that the generated documentation is accurate and up-to-date with the code. The `moon check` and `moon test` commands must pass. The build process on GitHub must also pass.
      #|Create clean pull request, namely ones that only contain changes related to documentation. No other changes (such as backup files) should be included.
      #|
      #|[Note]
      #|Rebase the branch onto the main branch first and fix any merge conflicts if necessary.
      #|You have the MCP for GitHub enabled and access to the shell.
      #|Review the commits between the current branch and the main branch (if there are any) to understand what documentation has been changed.
      #|Revert the commits if necessary to create a clean pull request.
      #|Review the GitHub Pull Request associated with this branch (if there is already one) to see if the build have all passed and if there are any comments from reviewers.
      #|
      #|DO NOT STOP UNTIL YOU HAVE COMPLETED THE TASK.
      #|
      #|Here are the knowledge of MoonBit:
      #|
      $|\{background}
    ),
  )
  for i in 0..<3 {
    if !response.final_response.contains("TASK COMPLETED") {
      response = thread.run(
        "If you have finished the task, please respond with 'TASK COMPLETED'. If not, please continue working on it.",
      )
      continue
    }
    return thread.id()
  } else {
    @error.fail("Codex failed to add documentation after multiple attempts")
  }
}
