///|
async fn git_is_repo(workdir : String) -> Bool {
  let (exit_code, stdout, _stderr) = @process.collect_output("git", [
    "-C", workdir, "rev-parse", "--is-inside-work-tree",
  ]) catch {
    _ => return false
  }
  if exit_code != 0 {
    return false
  }
  (stdout.text() catch { _ => "" }).trim() == "true"
}

///|
fn is_interface_file(path : String) -> Bool {
  path.has_suffix("pkg.generated.mbti") || path.has_suffix(".mbti")
}

///|
async fn git_interface_diff(workdir : String) -> String? {
  if !git_is_repo(workdir) {
    return None
  }
  let (exit_code, stdout, _stderr) = @process.collect_output("git", [
    "-C", workdir, "diff", "--name-only",
  ]) catch {
    _ => return None
  }
  if exit_code != 0 {
    return None
  }
  let files : Array[String] = []
  for line in (stdout.text() catch { _ => "" }).split("\n") {
    let trimmed = line.trim()
    if !trimmed.is_empty() {
      let path = trimmed.to_string()
      if is_interface_file(path) {
        files.push(path)
      }
    }
  }
  if files.is_empty() {
    return None
  }
  let args : Array[String] = ["-C", workdir, "diff", "--"]
  for f in files {
    args.push(f)
  }
  let (diff_exit, diff_out, _diff_err) = @process.collect_output("git", args) catch {
    _ => return None
  }
  if diff_exit != 0 {
    return None
  }
  let diff = diff_out.text() catch { _ => "" }
  if diff.trim().is_empty() {
    None
  } else {
    Some(diff)
  }
}
