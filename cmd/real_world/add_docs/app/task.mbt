///|
priv struct Arguments {
  /// Path to the root directory containing packages
  path : String
  /// Number of parallel tasks
  parallelism : Int
}

///|
fn help_message() -> String {
  let message =
    #|Usage: moon run cmd/real_world/add_docs -- [OPTIONS] <path>
    #|
    #|Generate documentation for MoonBit packages using parallel Codex agents.
    #|Each package is processed in an isolated git worktree with its own branch.
    #|
    #|Arguments:
    #|  <path>                         Path to a MoonBit project (must be a git repo)
    #|
    #|Options:
    #|  -p, --parallelism <num>        Number of parallel agents (default: 4)
    #|  -h, --help                     Print this help message
    #|
    #|Environment:
    #|  CODEX_API_KEY                  API key for Codex (required)
    #|
    #|Example:
    #|  moon run cmd/real_world/add_docs -- --parallelism 2 /path/to/moonbit-project
    #|
  message
}

///|
fn parse_cli_args(cli_args : ArrayView[String]) -> Arguments? raise {
  let help_message = help_message()
  let args = @args.parse(
    cli_args,
    flags=["help"],
    options=["parallelism", "path"],
    aliases={ "h": "help", "p": "parallelism" },
  )
  if args.flags.get("help") is Some(true) {
    return None
  }
  guard args.positional is [path] else {
    @error.fail(
      "Missing required positional argument: <path>\n\{help_message}\n",
    )
  }
  let parallelism = args.options.get("parallelism").unwrap_or("4")
  let argument = {
    path,
    parallelism: @strconv.parse_int(parallelism) catch {
      e => @error.fail_with("Invalid parallelism value", e)
    },
  }
  Some(argument)
}

///|
async fn ensure_repo(path : String) -> Unit {
  if not(repo_exists(path)) {
    fail("No git repository found at \{path}\n")
  }
}

///|
pub struct WorktreeInfo {
  tmp_path : String
  branch_name : String
  reused_branch : Bool
} derive(Show)

///|
extern "C" fn random() -> UInt = "arc4random"

///|
fn worktree_path() -> String {
  "/tmp/moon_add_docs_\{random()}/"
}

///|
fn branch_name(pkg_path : String) -> String {
  "code-review-" + pkg_path.replace_all(old="/", new="-")
}

///|
async fn create_worktree(repo_path : String, pkg_path : String) -> WorktreeInfo {
  let tmp_path = worktree_path()
  let branch = branch_name(pkg_path)
  let branches = git_list_branches(repo_path)
  let reused_branch = branches.contains(branch)
  let ok = if reused_branch {
    git_create_worktree(repo_path, branch, tmp_path)
  } else {
    git_create_worktree_and_branch(repo_path, branch, tmp_path)
  }
  if !ok {
    fail("error [\{pkg_path}] - Failed to create git worktree at \{tmp_path}\n")
  }
  WorktreeInfo::{ tmp_path, branch_name: branch, reused_branch }
}

///|
async fn verify_package(project_root : String, pkg_path : String) -> Unit {
  let check_status = @process.run("moon", ["check", "-C", project_root])
  let test_status = @process.run("moon", ["test", "-C", project_root])
  if check_status != 0 || test_status != 0 {
    fail("error [\{pkg_path}] - moon check or test failed after adding docs\n")
  }
  let fmt_status = @process.run("moon", ["fmt", "-C", project_root])
  let info_status = @process.run("moon", ["update-info", "-C", project_root])
  if fmt_status != 0 || info_status != 0 {
    fail(
      "error [\{pkg_path}] - moon format or update_info modified files after adding docs\n",
    )
  }
}

///|
async fn remove_worktree(
  repo_path : String,
  tmp_path : String,
  force? : Bool,
) -> Bool {
  git_remove_worktree(repo_path, tmp_path, force?)
}
