///|
/// Reviewer encapsulates Codex usage
struct Reviewer {
  codex : @codex.Codex
}

///|
fn Reviewer::new() -> Reviewer {
  Reviewer::{ codex: @codex.Codex::new() }
}

///|
/// Review a single mbti file using Codex
async fn review_mbti_file(
  file_path : String,
  project_root : String,
  reviewer : Reviewer,
  verbose : Bool,
) -> ReviewResult {
  let relative_path = if file_path.has_prefix(project_root) {
    try! file_path[project_root.length() + 1:].to_string()
  } else {
    file_path
  }
  if verbose {
    @stdio.stdout.write("Reviewing: \{relative_path}\n")
  }
  let content = @fs.read_file(file_path).text() catch { e => @error.reraise(e) }
  let package_name = extract_package_name(content)
  let thread = reviewer.codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=project_root,
      sandbox_mode=DangerFullAccess,
    ),
  )
  let prompt =
    $|Review this MoonBit package interface file (\{relative_path}):
    $|
    $|```moonbit
    $|\{content}
    $|```
    $|
    $|Please provide:
    $|1. A brief assessment of the API design
    $|2. Any potential issues or inconsistencies
    $|3. Suggestions for improvement (if any)
    $|
    $|Keep the review concise and focused on the public API surface.
  let result = thread.run(prompt) catch { e => @error.reraise(e) }
  let review_text = result.final_response
  ReviewResult::{
    file: relative_path,
    pkg_name: package_name,
    review: review_text,
    success: true,
    error: "",
  }
}
