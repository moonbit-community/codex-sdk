///|
fn normalize_find_path(path : String) -> String {
  let p = path.trim().to_string()
  match p {
    [.. "./", .. rest] => rest.to_string()
    _ => p
  }
}

///|
async fn discover_doc_files(workdir : String) -> Array[String] {
  let args : Array[String] = [
    workdir, "-type", "f", "(", "-name", "*.mbt.md", "-o", "-name", "README.mbt.md",
    "-o", "-name", "README.md", "-o", "-name", "DESIGN.md", "-o", "-path", "*/docs/*.md",
    ")", "-not", "-path", "*/.git/*", "-not", "-path", "*/.mooncakes/*", "-not",
    "-path", "*/_build/*", "-not", "-path", "*/target/*", "-not", "-path", "*/node_modules/*",
  ]
  let (exit_code, stdout, _stderr) = @process.collect_output("find", args) catch {
    _ => return []
  }
  if exit_code != 0 {
    return []
  }
  let files : Array[String] = []
  for line in (stdout.text() catch { _ => "" }).split("\n") {
    let trimmed = line.trim()
    if !trimmed.is_empty() {
      files.push(normalize_find_path(trimmed.to_string()))
    }
  }
  files.sort_by(fn(a, b) { a.compare(b) })
  files
}
