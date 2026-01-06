///|
/// Build the Codex prompt for the main repository task.
pub fn task_prompt(repo : RepositoryRecord, pr_comments : String?) -> String {
  let background =
    #|## MoonBit Project Guidelines
    #|
    #|This is a MoonBit project. Follow these guidelines:
    #|
    #|### Project Structure
    #|- Packages are organized per directory with moon.pkg.json files
    #|- Test files end in _test.mbt (blackbox) or _wbtest.mbt (whitebox)
    #|- Each package has a generated .mbti interface file
    #|
    #|### Coding Conventions
    #|- Use block style separated by ///| (block order is irrelevant)
    #|- Keep deprecated code in deprecated.mbt files
    #|
    #|### Tooling Requirements
    #|- Use `moon doc` to query interfaces
    #|- Use `moon fmt` to format code
    #|- Use `moon info` to update .mbti interface files
    #|- Use `moon test` to run tests (use `moon test --update` for snapshots)
    #|- Use `moon check` for linting
    #|- Use `inspect` in tests for snapshot testing, `assert_eq` only in loops
    #|- Run `moon coverage analyze` to check test coverage
    #|
    #|### Important Rules
    #|- Do NOT create backup files or any irrelevant files in the repository
    #|- Ensure all changes pass `moon check` and `moon test`
    #|- Make minimal, focused changes relevant only to the task
    #|- Update snapshots with `moon test --update` if behavior changes
    #|- Check .mbti diffs after `moon info` to verify interface changes
    #|
    #|After completing the task, commit them. 
    #|Then run `moon info && moon fmt && moon check && moon test --update` and commit automatic changes to finalize.
    #|
  match pr_comments {
    Some(comments) =>
      (
        $|Task: \{repo.task}
        $|
        $|PR Feedback/Comments:
        $|\{comments}
        $|
        $|Please address the task and any feedback from the PR comments.
        $|If there's nothing new since the last commit and no CI has failed, do nothing.
        $|
        $|\{background}
      )
    None =>
      (
        $|Task: \{repo.task}
        $|
        $|This is a new PR. Please implement the task.
        $|
        $|\{background}
      )
  }
}

///|
/// Read the git diff for commit message generation.
pub async fn read_git_diff(clone_path : String) -> String {
  let (status, output) = @process.collect_output_merged(
    "git",
    ["diff", "--no-color"],
    cwd=clone_path,
  )
  if status != 0 {
    @error.fail("git diff failed for commit message")
  }
  output.text()
}

///|
/// Build prompt for commit message generation.
pub fn commit_message_prompt(repo : RepositoryRecord, diff : String) -> String {
  let prompt =
    $|Based on the following task and code changes, generate a concise commit message.
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
  prompt
}

///|
/// Parse commit message from Codex JSON response.
pub fn parse_commit_message(response : String) -> String? raise {
  let parsed = @json.parse(response) catch { e => @error.reraise(e) }
  match parsed {
    Object({ "message": String(message), .. }) => Some(message)
    _ => None
  }
}

///|
/// Build prompt for summarizing a task title.
pub fn task_title_prompt(task : String) -> String {
  let prompt =
    $|Summarize the following task into a short, descriptive title.
    $|
    $|Task:
    $|\{task}
    $|
    $|Generate a JSON response with this structure:
    $|{
    $|  "title": "A concise title (max 72 characters)"
    $|}
    $|
    $|Keep it professional and specific.
  prompt
}

///|
/// Parse task title from Codex JSON response.
pub fn parse_task_title(response : String) -> String? raise {
  let parsed = @json.parse(response) catch { e => @error.reraise(e) }
  match parsed {
    Object({ "title": String(title), .. }) => Some(title)
    _ => None
  }
}

///|
/// Read diff summary for PR metadata generation.
pub async fn read_diff_summary(
  clone_path : String,
  default_branch : String,
  branch_name : String,
) -> String? {
  let (status, stdout, _stderr) = @process.collect_output(
    "git",
    ["diff", "--stat", "\{default_branch}..\{branch_name}"],
    cwd=clone_path,
  ) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  Some(stdout.text())
}

///|
/// Build prompt for PR metadata generation.
pub fn pr_metadata_prompt(
  repo : RepositoryRecord,
  diff_summary : String,
) -> String {
  let prompt =
    $|Based on the following task and code changes, generate a professional pull request title and body.
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
  prompt
}

///|
/// Parse PR metadata from Codex JSON response.
pub fn parse_pr_metadata(response : String) -> (String, String)? raise {
  let parsed = @json.parse(response) catch { e => @error.reraise(e) }
  match parsed {
    Object({ "title": String(title), "body": String(body), .. }) =>
      Some((title, body))
    _ => None
  }
}

///|
pub fn fallback_pr_title() -> String {
  "Automated code improvements"
}

///|
pub fn fallback_pr_body(task : String) -> String {
  "This PR was automatically created.\n\nTask: \{task}"
}
