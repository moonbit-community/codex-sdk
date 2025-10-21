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
    @pipe.stdout.write("\{help_message}\n")
    return
  }

  // Prepare environments
  let codex = @codex.Codex::new()
  let branches : @set.Set[StringView] = @set.Set::new()

  // Check the branches
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "git",
    ["branch", "--list", "--no-color"],
    stdout=process_read,
    cwd=argument.path,
  ) catch {
    e => {
      @pipe.stderr.write("error - Failed to list git branches\n")
      raise e
    }
  }
  guard status is 0 else {
    @pipe.stderr.write(
      "error - Failed to list git branches with status \{status}\n",
    )
    fail("Failed to list git branches with status \{status} \n")
  }
  pipe
  .read_all()
  .text()
  .split("\n")
  .filter(line => !line.is_empty())
  .map(fn(line) { try! line[2:] })
  .each(name => branches.add(name))

  // Start visiting packages
  @async.with_task_group(fn(task_group) {
    let visitor = Visitor::{
      taskgroup: task_group,
      semaphore: @semaphore.Semaphore::new(argument.parallelism),
      codex,
      branches,
    }
    visitor.visit("", argument.path)
  })
}

///|
extern "C" fn random() -> UInt = "arc4random"

///|
struct Visitor {
  taskgroup : @async.TaskGroup[Unit]
  semaphore : @semaphore.Semaphore
  codex : @codex.Codex
  branches : @set.Set[StringView]
}

///|
fn Visitor::add_doc(visitor : Self, root : String, path : String) -> Unit raise {
  // Add documentation to the package at the given path
  visitor.taskgroup.spawn_bg(allow_failure=true, fn() {
    visitor.semaphore.acquire()
    @pipe.stdout.write("info [\{path}] - Starting to add docs\n")
    defer visitor.semaphore.release()
    // Create git worktree

    let tmp_path = "/tmp/moon_add_docs_\{random()}/"
    let thread = visitor.codex.start_thread(
      options=@codex.ThreadOptions::new(
        working_directory=tmp_path,
        sandbox_mode=DangerFullAccess,
      ),
    )
    let branch_name = "code-review-" + path.replace_all(old="/", new="-")
    let args = if visitor.branches.contains(branch_name) {
      @pipe.stdout.write(
        "info [\{path}] - Branch \{branch_name} already exists, creating worktree only...\n",
      )
      ["worktree", "add", tmp_path, branch_name]
    } else {
      @pipe.stdout.write(
        "info [\{path}] - Creating worktree and branch \{branch_name}...\n",
      )
      ["worktree", "add", tmp_path, "-b", branch_name]
    }
    if @process.run("git", args, cwd=root) != 0 {
      let error_message = "error [\{path}] - Failed to create git worktree at \{tmp_path}\n"
      @pipe.stderr.write(error_message)
      fail(error_message)
    }

    // Add docs using codex
    try {
      @pipe.stdout.write(
        "info [\{path}] - Created git worktree at \{tmp_path} \n",
      )
      for _ in 0..<2 {
        let response = thread.run(
          (
            $|Generate documentation for the MoonBit package in the directory \{path} only.
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
          @pipe.stdout.write(
            "info [\{path}] - [\{thread.id()}] - Successfully added docs and created PR for package at \{path}\n",
          )
          @process.run(
            "git",
            ["worktree", "remove", tmp_path, "--force"],
            cwd=root,
          )
          |> ignore
          return
        } else {
          @pipe.stdout.write(
            "info [\{path}] - [\{thread.id()}] - Codex response did not indicate completion, retrying...\n",
          )
        }
      } else {
        let err_message = "error [\{path}] - [\{thread.id()}] - Codex failed to add documentation after multiple attempts\n"
        @pipe.stderr.write(err_message)
        fail(err_message)
      }
    } catch {
      e => {
        @process.run(
          "git",
          ["worktree", "remove", tmp_path, "--force"],
          cwd=root,
        )
        |> ignore
        let err_message = "error [\{path}] - [\{thread.id()}] - Exception while adding docs: \{e}\n"
        @pipe.stderr.write(err_message)
        fail(err_message)
      }
    }
  })
}

///|
async fn Visitor::visit(visitor : Self, path : String, root : String) -> Unit {
  let entries = @fs.readdir("\{root}\{path}", include_hidden=false)
  if !path.is_empty() && entries.contains("moon.mod.json") {
    // Found a submodule, skip
    return
  }
  if entries.contains("moon.pkg.json") {
    // Found a package, add docs
    visitor.add_doc(root, path)
  }
  for entry in entries {
    let subpath = "\{path}/\{entry}"
    let kind = @fs.kind("\{root}\{subpath}")
    if kind is Directory {
      visitor.visit(subpath, root)
    }
  }
}
