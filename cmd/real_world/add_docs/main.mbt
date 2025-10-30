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
        try visit(codex, repo, pkg) catch {
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
    let mut response = thread.run(
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
        #|Create clean pull request, namely ones that only contain changes related to documentation. No other changes (such as backup files) should be included.
        #|
        #|[Note]
        #|Rebase the branch onto the main branch first and fix any merge conflicts if necessary.
        #|You have the MCP for GitHub enabled and access to the shell.
        #|Review the commits between the current branch and the main branch (if there are any) to understand what documentation has been changed.
        #|Revert the commits if necessary to create a clean pull request.
        #|Review the GitHub Pull Request associated with this branch (if there is already one) to see if the build have all passed and if there are any comments from reviewers.
        #|
        #|DO NOT STOP UNTIL YOU HAVE COMPLETED THE TASK.
        #|
        #|Here are the knowledge of MoonBit:
        #|
        $|\{background}
      ),
    )
    for i in 0..<3 {
      @stdio.stdout.write(
        "info [\{pkg.path}] - [\{thread.id()}] - Finished attempt \{i}\n",
      )
      if !response.final_response.contains("TASK COMPLETED") {
        @stdio.stdout.write(
          "info [\{pkg.path}] - [\{thread.id()}] - Codex response did not indicate completion, retrying...\n",
        )
        response = thread.run(
          "If you have finished the task, please respond with 'TASK COMPLETED'. If not, please continue working on it.",
        )
        continue
      }
      @stdio.stdout.write(
        "info [\{pkg.path}] - [\{thread.id()}] - AI declared fin for package at \{pkg.path}\n",
      )
      // verify and cleanup
      if pkg.mod.check().status != 0 || pkg.mod.test_().status != 0 {
        let err_message = "error [\{pkg.path}] - [\{thread.id()}] - moon check or test failed after adding docs\n"
        @stdio.stderr.write(err_message)
        response = thread.run(
          "The build checks have failed after adding documentation. Please fix the issues so that `moon check` and `moon test` both pass.",
        )
        continue
      }
      if pkg.mod.format().status != 0 || pkg.mod.update_info().status != 0 {
        fail(
          "error [\{pkg.path}] - [\{thread.id()}] - moon format or update_info modified files after adding docs\n",
        )
      }
      if !repo.remove_work_tree(tmp_path) {
        let err_message = "error [\{pkg.path}] - [\{thread.id()}] - Failed to remove git worktree at \{tmp_path}\n"
        @stdio.stderr.write(err_message)
        response = thread.run(
          "Looks like there are changes remaining in the worktree that prevent its removal. Please either reject them or commit them properly.",
        )
        continue
      }
      return
    } else {
      let err_message = "error [\{pkg.path}] - [\{thread.id()}] - Codex failed to add documentation after multiple attempts\n"
      @stdio.stderr.write(err_message)
      fail(err_message)
    }
  } catch {
    e => {
      repo.remove_work_tree(tmp_path, force=true) |> ignore
      let err_message = "error [\{pkg.path}] - [\{thread.id()}] - Exception while adding docs: \{e}\n"
      @stdio.stderr.write(err_message)
      fail_with(err_message, e)
    }
  }
}
