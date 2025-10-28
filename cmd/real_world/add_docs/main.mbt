///|
struct Arguments {
  /// Path to the root directory containing packages
  mut path : String
  /// Number of parallel tasks
  mut parallelism : Int
} derive(Default)

///|
impl @clap.Value for Arguments with add_value(self, name, value, positional) {
  if name is "parallelism" {
    self.parallelism = @clap.BasicValue::parse(value) catch {
      StrConvError(err) =>
        raise @clap.ParserError::InvalidArgumentValue(
          "Invalid value for \{name}: \{err}",
        )
    }
  } else if name is "path" && positional {
    self.path = value
  } else {
    raise @clap.ParserError::InvalidArgumentName(
      "Invalid argument name \{name}",
    )
  }
}

///|
async fn main {
  // Parse CLI arguments
  let parser = @clap.Parser::new(prog="moon run real_world/add_docs --", args={
    "parallelism": @clap.Arg::named(
      nargs=@clap.AtMost(1),
      help="Number of parallel tasks",
      defaults=["4"],
    ),
    "path": @clap.Arg::positional(
      nargs=@clap.One,
      help="Path to the root directory containing packages",
    ),
  })
  let argument = Arguments::default()
  if parser.parse(argument, @sys.get_cli_args()[1:]) is Some(help_message) {
    @stdio.stdout.write("\{help_message}\n")
    return
  }

  // Prepare environments
  let codex = @codex.Codex::new()

  // Check the branches
  let repo = try {
    if Repo::at(argument.path) is Some(repo) {
      repo
    } else {
      fail("error - No git repository found at \{argument.path}\n")
    }
  } catch {
    e => {
      @stdio.stderr.write(
        "error - Failed to open git repository at \{argument.path}\n",
      )
      raise e
    }
  }
  let project = try {
    if Module::at(argument.path) is Some(project) {
      project
    } else {
      fail("error - No Moon module found at \{argument.path}\n")
    }
  } catch {
    e => {
      @stdio.stderr.write("error - Failed to read module at \{argument.path}\n")
      raise e
    }
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
        visit(codex, repo, pkg)
      })
    }
  })
}

///|
extern "C" fn random() -> UInt = "arc4random"

///|
async fn visit(codex : @codex.Codex, repo : Repo, pkg : Package) -> Unit {
  // Add documentation to the package at the given path
  // Create git worktree

  let tmp_path = "/tmp/moon_add_docs_\{random()}/"
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=tmp_path,
      sandbox_mode=DangerFullAccess,
    ),
  )
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
    for _ in 0..<2 {
      let response = thread.run(
        (
          $|Generate documentation for the MoonBit package in the directory \{pkg.path} only.
          #|
          #|[Task Description]
          #|You will need to generate comments for all public functions, structs, enums, and modules in the package.
          #|You will also need to update the `README.mbt.md` file in the package.
          #|
          #|Remember that all the code block within the `README.mbt.md` file and the doc comments will be type checked and executed.
          #|When you have finished generating the documentation, commit the changes with a meaningful commit message, push the changes to the remote repository, and create a pull request for the changes.
          #|
          #|[Requirements]
          #|You must ensure that the generated documentation is accurate and up-to-date with the code. The `moon check` and `moon test` commands must pass. The build process on GitHub must also pass.
          #|Do not modify any code outside of the package directory.
          #|
          #|[Note]
          #|You have the MCP for GitHub enabled and access to the shell.
          #|Review the commits between the current branch and the main branch (if there are any) to understand what documentation has been changed.
          #|Review the GitHub Pull Request associated with this branch (if there is already one) to see if the build have all passed and if there are any comments from reviewers.
          #|
          #|Remember to cleanup any temporary files you created during this process. Since this is a Git repository, do not fear the loss of tracked files.
          #|
          #|DO NOT STOP UNTIL YOU HAVE COMPLETED THE TASK.
          #|
          #|IF YOU HAVE FINISHED THE TASK, RESPOND WITH "TASK COMPLETED".
        ),
      )
      if response.final_response.contains("TASK COMPLETED") {
        @stdio.stdout.write(
          "info [\{pkg.path}] - [\{thread.id()}] - Successfully added docs and created PR for package at \{pkg.path}\n",
        )
        @process.run(
          "git",
          ["worktree", "remove", tmp_path, "--force"],
          cwd=pkg.mod.root,
        )
        |> ignore
        return
      } else {
        @stdio.stdout.write(
          "info [\{pkg.path}] - [\{thread.id()}] - Codex response did not indicate completion, retrying...\n",
        )
      }
    } else {
      let err_message = "error [\{pkg.path}] - [\{thread.id()}] - Codex failed to add documentation after multiple attempts\n"
      @stdio.stderr.write(err_message)
      fail(err_message)
    }
  } catch {
    e => {
      @process.run(
        "git",
        ["worktree", "remove", tmp_path, "--force"],
        cwd=pkg.mod.root,
      )
      |> ignore
      let err_message = "error [\{pkg.path}] - [\{thread.id()}] - Exception while adding docs: \{e}\n"
      @stdio.stderr.write(err_message)
      fail(err_message)
    }
  }
}
