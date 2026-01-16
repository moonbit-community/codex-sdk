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
    #|Usage: moon run real_world/add_docs -- [OPTIONS] <path>
    #|
    #|<path>    Path to the root directory containing packages
    #|
    #|Options:
    #|  --parallelism <parallelism>    Number of parallel tasks (default: 4)
    #|  --help                         Print this help message
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
    aliases={ "h": "help" },
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
async fn open_repo(path : String) -> Repo {
  if Repo::at(path) is Some(repo) {
    repo
  } else {
    fail("No git repository found at \{path}\n")
  }
}

///|
async fn open_module(path : String) -> Module {
  if Module::at(path) is Some(project) {
    project
  } else {
    fail("No Moon module found at \{path}\n")
  }
}

///|
async fn list_packages(project : Module) -> Array[Package] {
  project.packages()
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
pub fn worktree_path() -> String {
  "/tmp/moon_add_docs_\{random()}/"
}

///|
pub fn branch_name(pkg : Package) -> String {
  "code-review-" + pkg.path.replace_all(old="/", new="-")
}

///|
async fn create_worktree(repo : Repo, pkg : Package) -> WorktreeInfo {
  let tmp_path = worktree_path()
  let branch = branch_name(pkg)
  let branches = repo.existing_branches()
  let reused_branch = branches.contains(branch)
  let ok = if reused_branch {
    repo.create_work_tree(branch, tmp_path)
  } else {
    repo.create_work_tree_and_branch(branch, tmp_path)
  }
  if !ok {
    fail("error [\{pkg.path}] - Failed to create git worktree at \{tmp_path}\n")
  }
  WorktreeInfo::{ tmp_path, branch_name: branch, reused_branch }
}

///|
async fn verify_package(pkg : Package) -> Unit {
  if pkg.mod.check().status != 0 || pkg.mod.test_().status != 0 {
    fail("error [\{pkg.path}] - moon check or test failed after adding docs\n")
  }
  if pkg.mod.format().status != 0 || pkg.mod.update_info().status != 0 {
    fail(
      "error [\{pkg.path}] - moon format or update_info modified files after adding docs\n",
    )
  }
}

///|
async fn remove_worktree(
  repo : Repo,
  tmp_path : String,
  force? : Bool,
) -> Bool {
  repo.remove_work_tree(tmp_path, force?)
}
