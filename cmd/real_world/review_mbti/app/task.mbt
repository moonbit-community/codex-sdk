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
  let files_to_review : Array[String] = if argument.files.length() > 0 {
    @stdio.stdout.write(
      "Reviewing \{argument.files.length()} specified file(s)\n",
    )
    argument.files.map(fn(f) { "\{project_root}/\{f}" })
  } else if argument.changed {
    let changed = get_changed_mbti_files(project_root) catch {
      e => {
        @stdio.stderr.write("Failed to get changed files:\n\{e}\n")
        []
      }
    }
    @stdio.stdout.write("Found \{changed.length()} changed mbti file(s)\n")
    changed
  } else {
    let all_files = []
    find_mbti_files(project_root, all_files)
    @stdio.stdout.write("Found \{all_files.length()} mbti file(s) to review\n")
    all_files
  }
  files_to_review
}

///|
fn summary_output_dir(output_dir : String, project_root : String) -> String {
  if output_dir.has_prefix(project_root) {
    try! output_dir[project_root.length() + 1:].to_string()
  } else {
    output_dir
  }
}
