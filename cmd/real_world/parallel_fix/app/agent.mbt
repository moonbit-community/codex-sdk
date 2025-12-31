///|
/// Codex agent encapsulating all Codex usage
struct Agent {
  codex : @codex.Codex
}

///|
fn Agent::new() -> Agent {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(
      codex_path_override="./alternative_codex.sh",
    ),
  )
  Agent::{ codex, }
}

///|
fn Agent::new_with_codex(codex : @codex.Codex) -> Agent {
  Agent::{ codex, }
}

///|
/// Run an AI task and return session id if available
async fn Agent::run_task(
  self : Agent,
  clone_path : String,
  model_env_key : String,
  prompt : String,
) -> String? {
  let thread = self.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      model?=@sys.get_env_vars().get(model_env_key),
    ),
  )
  let _ = thread.run(prompt) catch { e => @error.reraise(e) }
  match thread.id() {
    Some(id) => Some(id)
    None => None
  }
}

///|
/// Generate commit message using AI
async fn Agent::generate_commit_message(
  self : Agent,
  clone_path : String,
  repo : RepositoryRecord,
) -> String {
  try {
    let (status, output) = @process.collect_output_merged(
      "git",
      ["diff", "--no-color"],
      cwd=clone_path,
    )
    if status != 0 {
      @error.fail("git diff failed for commit message")
    }
    let diff = output.text()
    if diff.is_empty() {
      @error.fail("No changes to generate commit message for")
    }
    let thread = self.codex.start_thread(
      options=@codex.ThreadOptions::new(
        working_directory=clone_path,
        model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
      ),
    )
    let prompt =
      #|Based on the following task and code changes, generate a concise commit message.
      $|
      $|Task: \{repo.task}
      $|
      $|Changes:
      $|\{diff}
      $|
      $|Generate a JSON response with this structure:
      $|{
      $|  "message": "A concise commit message (max 72 characters)"
      $|}
      $|
      $|The message should follow conventional commit guidelines.
      $|Keep it professional and technical.
    let result = thread.run(prompt) catch { e => @error.reraise(e) }
    let parsed = @json.parse(result.final_response) catch {
      e => @error.reraise(e)
    }
    match parsed {
      Object({ "message": String(message), .. }) => message
      _ => @error.fail("Commit message response missing message field")
    }
  } catch {
    e => {
      @stdio.stderr.write("warning Failed to generate commit message: \{e}\n")
      "AI work on: \{repo.task}"
    }
  }
}

///|
/// Generate PR metadata (title and body) using AI
async fn Agent::generate_pr_metadata(
  self : Agent,
  clone_path : String,
  repo : RepositoryRecord,
  branch_name : String,
  default_branch : String,
) -> (String, String) {
  let (status, stdout, stderr) = @process.collect_output(
    "git",
    ["diff", "--stat", "\{default_branch}..\{branch_name}"],
    cwd=clone_path,
  ) catch {
    e => {
      @stdio.stderr.write("warning Failed to get diff summary: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
  if status != 0 {
    @stdio.stderr.write("warning git diff failed: \{stderr.text()}\n")
    return (
      "Automated code improvements",
      "This PR was automatically created.\n\nTask: \{repo.task}",
    )
  }
  let diff_summary = stdout.text()
  let thread = self.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=clone_path,
      model?=@sys.get_env_vars().get("LOWCOST_MODEL"),
    ),
  )
  let prompt =
    #|Based on the following task and code changes, generate a professional pull request title and body.
    $|
    $|Task: \{repo.task}
    $|
    $|Changes summary:
    $|\{diff_summary}
    $|
    $|Generate a JSON response with this structure:
    $|{
    $|  "title": "A concise PR title (max 72 characters)",
    $|  "body": "A detailed PR description in markdown format"
    $|}
    $|
    $|The title should be concise and descriptive.
    $|The body should include:
    $|   - Summary of what was changed
    $|   - Why these changes were made (based on the task)
    $|   - Any notable implementation details
    $|
    $|Keep the tone professional and technical.
  let result = thread.run(prompt) catch {
    e => {
      @stdio.stderr.write("warning Failed to generate PR metadata: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
  let parsed = @json.parse(result.final_response) catch {
    e => {
      @stdio.stderr.write("warning Failed to parse PR metadata JSON: \{e}\n")
      return (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
  match parsed {
    Object({ "title": String(title), "body": String(body), .. }) =>
      (title, body)
    _ => {
      @stdio.stderr.write(
        "warning PR metadata response missing title/body fields\n",
      )
      (
        "Automated code improvements",
        "This PR was automatically created.\n\nTask: \{repo.task}",
      )
    }
  }
}
