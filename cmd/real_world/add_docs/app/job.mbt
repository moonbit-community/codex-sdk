///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
pub struct Job {
  project_root : String
  repo : Repo
  packages : Array[Package]
  parallelism : Int
}

///|
pub enum TaskStatus {
  Running
  WorktreeCreated(WorktreeInfo)
  Completed
} derive(Show)

///|
pub struct TaskHandle {
  pkg : Package
  config : Job
  idx : Int
  mut status : TaskStatus
  mut worktree : WorktreeInfo?
}

///|
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => arguments
  }
  let repo = open_repo(arguments.path) catch {
    e => @error.fail_with("Failed to open git repository", e)
  }
  let project = open_module(arguments.path) catch {
    e => @error.fail_with("Failed to read Moon module", e)
  }
  let packages = list_packages(project)
  Job::{
    project_root: arguments.path,
    repo,
    packages,
    parallelism: arguments.parallelism,
  }
}

///|
pub async fn Job::task_start(config : Job, idx : Int) -> TaskHandle {
  let pkg = config.packages[idx]
  let total = config.packages.length()
  @stdio.stdout.write(
    "info [\{idx + 1}/\{total}] - Starting documentation for \{pkg.path}\n",
  )
  TaskHandle::{ pkg, config, idx, status: TaskStatus::Running, worktree: None }
}

///|
pub struct TaskInput {
  pkg : Package
  worktree : WorktreeInfo
  prompt : String
}

///|
pub async fn TaskHandle::input(self : TaskHandle) -> TaskInput {
  let pkg = self.pkg
  let worktree = create_worktree(self.config.repo, pkg) catch {
    e => @error.reraise(e)
  }
  self.worktree = Some(worktree)
  self.status = TaskStatus::WorktreeCreated(worktree)
  if worktree.reused_branch {
    @stdio.stdout.write(
      "info [\{pkg.path}] - Branch \{worktree.branch_name} already exists, creating worktree only...\n",
    )
  } else {
    @stdio.stdout.write(
      "info [\{pkg.path}] - Creating worktree and branch \{worktree.branch_name}...\n",
    )
  }
  @stdio.stdout.write(
    "info [\{pkg.path}] - Created git worktree at \{worktree.tmp_path}\n",
  )
  TaskInput::{ pkg, worktree, prompt: docs_prompt(pkg.path) }
}

///|
pub suberror ValidationError {
  TaskNotCompleted
} derive(Show)

///|
pub fn TaskHandle::validate(
  _self : TaskHandle,
  response : String,
) -> Unit raise ValidationError {
  if not(response.contains("TASK COMPLETED")) {
    raise ValidationError::TaskNotCompleted
  }
}

///|
pub struct TaskResult {
  pkg_path : String
  success : Bool
  error : String
}

///|
pub impl Show for TaskResult with output(self, logger) {
  if self.success {
    logger.write_string("TaskResult::Success(\{self.pkg_path})")
  } else {
    logger.write_string("TaskResult::Failed(\{self.pkg_path}, \{self.error})")
  }
}

///|
pub async fn TaskHandle::finish(
  self : TaskHandle,
  session_id : String?,
) -> TaskResult {
  let pkg = self.pkg
  match session_id {
    Some(id) =>
      @stdio.stdout.write(
        "info [\{pkg.path}] - [\{id}] - AI declared fin for package at \{pkg.path}\n",
      )
    None =>
      @stdio.stdout.write(
        "info [\{pkg.path}] - AI declared fin for package at \{pkg.path}\n",
      )
  }
  verify_package(pkg) catch {
    e => {
      self.cleanup(force=true)
      return TaskResult::{
        pkg_path: pkg.path,
        success: false,
        error: "Verification failed: \{e}",
      }
    }
  }
  self.cleanup(force=false)
  self.status = TaskStatus::Completed
  @stdio.stdout.write("info [\{pkg.path}] - Task finished normally\n")
  TaskResult::{ pkg_path: pkg.path, success: true, error: "" }
}

///|
pub async fn TaskHandle::error(self : TaskHandle, error : Error) -> TaskResult {
  @stdio.stderr.write("error [\{self.pkg.path}] - Exception: \{error}\n")
  self.cleanup(force=true)
  TaskResult::{ pkg_path: self.pkg.path, success: false, error: error.to_string() }
}

///|
async fn TaskHandle::cleanup(self : TaskHandle, force? : Bool) -> Unit {
  match self.worktree {
    Some(worktree) =>
      if not(remove_worktree(self.config.repo, worktree.tmp_path, force?)) {
        @stdio.stderr.write(
          "warning [\{self.pkg.path}] - Failed to remove git worktree at \{worktree.tmp_path}\n",
        )
      }
    None => ()
  }
}

///|
pub async fn Job::summarize(config : Job, results : Array[TaskResult]) -> Unit {
  if results.is_empty() {
    @stdio.stdout.write("No packages to process. Exiting.\n")
    return
  }
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { not(r.success) })
  @stdio.stdout.write(
    (
      $|
      $|\{"=".repeat(80)}
      $|SUMMARY
      $|\{"=".repeat(80)}
      $|Total packages: \{results.length()}
      $|Successful: \{successful}
      $|Failed: \{failed.length()}
      $|Parallelism: \{config.parallelism}
      $|
    ),
  )
  if failed.length() > 0 {
    @stdio.stdout.write("\nFailed packages:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.pkg_path}: \{f.error}\n")
    }
  }
}
