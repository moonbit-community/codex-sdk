///|
struct Arguments {
  /// Path to the root directory containing packages
  path : String
  /// Number of parallel tasks
  parallelism : Int
} derive(Default)

///|
async fn main {
  // Parse CLI arguments
  let help_message =
    #|Usage: moon run real_world/add_docs -- [OPTIONS] <path>
    #|
    #|<path>    Path to the root directory containing packages
    #|
    #|Options:
    #|  --parallelism <parallelism>    Number of parallel tasks (default: 4)
    #|  --help                         Print this help message
    #|
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["help"],
    options=["parallelism", "path"],
    aliases={ "h": "help" },
  )
  if args.flags.get("help") is Some(true) {
    @stdio.stdout.write("\{help_message}\n")
    return
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

  // Prepare environments
  let agent = DocsAgent::new()

  // Check the branches
  let repo = try {
    if Repo::at(argument.path) is Some(repo) {
      repo
    } else {
      fail("No git repository found at \{argument.path}\n")
    }
  } catch {
    e => fail_with("Failed to open git repository", e)
  }
  let project = try {
    if Module::at(argument.path) is Some(project) {
      project
    } else {
      fail("No Moon module found at \{argument.path}\n")
    }
  } catch {
    e => fail_with("Failed to read Moon module", e)
  }

  // Start visiting packages
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(argument.parallelism)
    for pkg in project.packages() {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        @stdio.stdout.write(
          "info [\{pkg.path}] - Acquired semaphore, starting documentation addition...\n",
        )
        defer semaphore.release()
        try visit(agent, repo, pkg) catch {
          e => @stdio.stderr.write("error [\{pkg.path}] - Task failed: \{e}\n")
        } noraise {
          _ =>
            @stdio.stdout.write("info [\{pkg.path}] - Task finished normally\n")
        }
      })
    }
  })
}

///|
extern "C" fn random() -> UInt = "arc4random"

///|
async fn visit(agent : DocsAgent, repo : Repo, pkg : Package) -> Unit {
  // Add documentation to the package at the given path
  // Create git worktree
  let tmp_path = "/tmp/moon_add_docs_\{random()}/"
  let branch_name = "code-review-" + pkg.path.replace_all(old="/", new="-")
  let args = if repo.existing_branches().contains(branch_name) {
    @stdio.stdout.write(
      "info [\{pkg.path}] - Branch \{branch_name} already exists, creating worktree only...\n",
    )
    ["worktree", "add", tmp_path, branch_name]
  } else {
    @stdio.stdout.write(
      "info [\{pkg.path}] - Creating worktree and branch \{branch_name}...\n",
    )
    ["worktree", "add", tmp_path, "-b", branch_name]
  }
  if @process.run("git", args, cwd=pkg.mod.root) != 0 {
    let error_message = "error [\{pkg.path}] - Failed to create git worktree at \{tmp_path}\n"
    @stdio.stderr.write(error_message)
    fail(error_message)
  }

  // Add docs using codex
  try {
    @stdio.stdout.write(
      "info [\{pkg.path}] - Created git worktree at \{tmp_path} \n",
    )
    let session_id_opt = agent.generate_for_package(pkg.path, tmp_path) catch {
      e => @error.reraise(e)
    }
    match session_id_opt {
      Some(session_id) =>
        @stdio.stdout.write(
          "info [\{pkg.path}] - [\{session_id}] - AI declared fin for package at \{pkg.path}\n",
        )
      None =>
        @stdio.stdout.write(
          "info [\{pkg.path}] - AI declared fin for package at \{pkg.path}\n",
        )
    }
    // verify and cleanup
    if pkg.mod.check().status != 0 || pkg.mod.test_().status != 0 {
      let err_message = "error [\{pkg.path}] - moon check or test failed after adding docs\n"
      @stdio.stderr.write(err_message)
      fail(err_message)
    }
    if pkg.mod.format().status != 0 || pkg.mod.update_info().status != 0 {
      fail(
        "error [\{pkg.path}] - moon format or update_info modified files after adding docs\n",
      )
    }
    if !repo.remove_work_tree(tmp_path) {
      let err_message = "error [\{pkg.path}] - Failed to remove git worktree at \{tmp_path}\n"
      @stdio.stderr.write(err_message)
      fail(err_message)
    }
    return
  } catch {
    e => {
      repo.remove_work_tree(tmp_path, force=true) |> ignore
      let err_message = "error [\{pkg.path}] - Exception while adding docs: \{e}\n"
      @stdio.stderr.write(err_message)
      fail_with(err_message, e)
    }
  }
}
