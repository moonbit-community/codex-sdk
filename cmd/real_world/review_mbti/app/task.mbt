///|
fn output_dir(argument : Arguments) -> String {
  let project_root = argument.path
  if argument.output.has_prefix("/") {
    argument.output
  } else {
    "\{project_root}/\{argument.output}"
  }
}

///|
async fn resolve_files_to_review(argument : Arguments) -> Array[String] {
  let project_root = argument.path
  let all_files : Array[String] = []
  find_mbti_files(project_root, all_files)
  @stdio.stdout.write("Found \{all_files.length()} mbti file(s) to review\n")
  all_files
}

///|
fn summary_output_dir(output_dir : String, project_root : String) -> String {
  if output_dir.has_prefix(project_root) {
    try! output_dir[project_root.length() + 1:].to_string()
  } else {
    output_dir
  }
}
