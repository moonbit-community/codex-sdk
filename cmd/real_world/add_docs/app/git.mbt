///|
async fn repo_exists(path : String) -> Bool {
  @process.run("git", ["rev-parse", "--is-inside-work-tree"], cwd=path) == 0
}

///|
async fn git_list_branches(repo_path : String) -> Array[String] {
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["branch", "--list", "--no-color"],
    stdout=process_read,
    cwd=repo_path,
  ) catch {
    e => raise e
  }
  guard status is 0 else {
    fail("Failed to list git branches with status \{status} \n")
  }
  let branches = pipe
    .read_all()
    .text()
    .split("\n")
    .filter(line => !line.is_empty())
    .map(fn(line) { try! line[2:] })
  branches.map(StringView::to_string).collect()
}

///|
async fn git_create_worktree(
  repo_path : String,
  branch : String,
  path : String,
) -> Bool {
  @process.run("git", ["worktree", "add", path, branch], cwd=repo_path) == 0
}

///|
async fn git_create_worktree_and_branch(
  repo_path : String,
  branch : String,
  path : String,
) -> Bool {
  @process.run("git", ["worktree", "add", "-b", branch, path], cwd=repo_path) ==
  0
}

///|
async fn git_remove_worktree(
  repo_path : String,
  path : String,
  force? : Bool,
) -> Bool {
  let args = ["worktree", "remove", path]
  if force is Some(true) {
    args.push("--force")
  }
  @process.run("git", args, cwd=repo_path) == 0
}
