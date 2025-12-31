///|
pub async fn prepare_review_input(
  file_path : String,
  project_root : String,
  verbose : Bool,
) -> ReviewInput raise {
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
  ReviewInput::{ file: relative_path, relative_path, pkg_name: package_name, prompt }
}

///|
pub fn review_result_from_response(
  input : ReviewInput,
  review_text : String,
) -> ReviewResult {
  ReviewResult::{
    file: input.relative_path,
    pkg_name: input.pkg_name,
    review: review_text,
    success: true,
    error: "",
  }
}
