///|
/// Task identification: Find directories to review.

///|
/// A review target.
struct Task {
  /// Index in the batch
  index : Int
  /// Directory path relative to workdir
  path : String
  /// Display name for reporting
  name : String
}

///|
/// Identify targets to review, applying offset/limit.
async fn identify_tasks(config : Config) -> Array[Task] raise Error {
  let targets = find_review_targets(config.workdir)
  let start = @cmp.minimum(config.offset, targets.length())
  let end = if config.limit < 0 {
    targets.length()
  } else {
    @cmp.minimum(start + config.limit, targets.length())
  }
  targets[start:end].mapi(fn(i, path) {
    let name = if path.is_empty() { "root" } else { path }
    { index: start + i, path, name }
  })
}

///|
/// Find directories to review.
/// Default: find all directories with source files (*.mbt).
/// Customize this function for your review targets.
async fn find_review_targets(workdir : String) -> Array[String] raise Error {
  let targets : Array[String] = []
  find_targets_recursive(workdir, "", targets)
  targets
}

///|
async fn find_targets_recursive(
  base : String,
  relative : String,
  out : Array[String],
) -> Unit raise Error {
  let dir = if relative.is_empty() { base } else { base + "/" + relative }
  let entries = @fs.readdir(dir, include_hidden=false)

  // Check if this directory has source files
  let has_sources = entries.iter().any(fn(name) { name.has_suffix(".mbt") })
  if has_sources {
    out.push(relative)
  }
  for name in entries {
    // Skip build artifacts and hidden directories
    if name == "_build" ||
      name == "target" ||
      name == ".mooncakes" ||
      name == ".git" {
      continue
    }
    let rel_path = if relative.is_empty() {
      name
    } else {
      relative + "/" + name
    }
    let full_path = base + "/" + rel_path
    if @fs.kind(full_path) == Directory {
      find_targets_recursive(base, rel_path, out)
    }
  }
}
