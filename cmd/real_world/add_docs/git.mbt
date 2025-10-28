///|
struct Repo {
  path : String
}

///|
async fn Repo::at(path : String) -> Self? {
  // Verify that the path is a git repository
  let status = @process.run(
    "git",
    ["rev-parse", "--is-inside-work-tree"],
    cwd=path,
  )
  guard status is 0 else { return None }
  Some(Repo::{ path, })
}

///|
async fn Repo::existing_branches(repo : Self) -> Array[String] {
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["branch", "--list", "--no-color"],
    stdout=process_read,
    cwd=repo.path,
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
async fn Repo::create_work_tree(
  repo : Self,
  branch : String,
  path : String,
) -> Bool {
  @process.run("git", ["worktree", "add", path, branch], cwd=repo.path) == 0
}

///|
async fn Repo::create_work_tree_and_branch(
  repo : Self,
  branch : String,
  path : String,
) -> Bool {
  @process.run("git", ["worktree", "add", "-b", branch, path], cwd=repo.path) ==
  0
}

///|
async fn Repo::remove_work_tree(
  repo : Self,
  path : String,
  force? : Bool,
) -> Bool {
  let args = ["worktree", "remove", path]
  if force is Some(true) {
    args.push("--force")
  }
  @process.run("git", args, cwd=repo.path) == 0
}
