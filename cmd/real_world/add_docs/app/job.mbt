///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
pub struct Job {
  project_root : String
  packages : Array[String]
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
  pkg_path : String
  config : Job
  idx : Int
  mut status : TaskStatus
  mut worktree : WorktreeInfo?
  mut attempt : Int
}

///|
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => arguments
  }
  ensure_repo(arguments.path) catch {
    e => @error.fail_with("Failed to open git repository", e)
  }
  ensure_module(arguments.path) catch {
    e => @error.fail_with("Failed to read Moon module", e)
  }
  let packages = list_package_paths(arguments.path)
  Job::{
    project_root: arguments.path,
    packages,
    parallelism: arguments.parallelism,
  }
}

///|
pub async fn Job::task_start(config : Job, idx : Int) -> TaskHandle {
  let pkg_path = config.packages[idx]
  let total = config.packages.length()
  @stdio.stdout.write(
    "info [\{idx + 1}/\{total}] - Starting documentation for \{pkg_path}\n",
  )
  TaskHandle::{
    pkg_path,
    config,
    idx,
    status: TaskStatus::Running,
    worktree: None,
    attempt: 0,
  }
}

///|
pub struct TaskEnv {
  worktree_path : String
}

///|
pub async fn TaskHandle::setup(self : TaskHandle) -> TaskEnv {
  let pkg_path = self.pkg_path
  let worktree = create_worktree(self.config.project_root, pkg_path) catch {
    e => @error.reraise(e)
  }
  self.worktree = Some(worktree)
  self.status = TaskStatus::WorktreeCreated(worktree)
  if worktree.reused_branch {
    @stdio.stdout.write(
      "info [\{pkg_path}] - Branch \{worktree.branch_name} already exists, creating worktree only...\n",
    )
  } else {
    @stdio.stdout.write(
      "info [\{pkg_path}] - Creating worktree and branch \{worktree.branch_name}...\n",
    )
  }
  @stdio.stdout.write(
    "info [\{pkg_path}] - Created git worktree at \{worktree.tmp_path}\n",
  )
  TaskEnv::{ worktree_path: worktree.tmp_path }
}

///|
pub fn TaskHandle::prompt(self : TaskHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    docs_prompt(self.pkg_path)
  } else {
    completion_followup()
  }
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
  let pkg_path = self.pkg_path
  match session_id {
    Some(id) =>
      @stdio.stdout.write(
        "info [\{pkg_path}] - [\{id}] - AI declared fin for package at \{pkg_path}\n",
      )
    None =>
      @stdio.stdout.write(
        "info [\{pkg_path}] - AI declared fin for package at \{pkg_path}\n",
      )
  }
  verify_package(self.config.project_root, pkg_path) catch {
    e => {
      self.cleanup(force=true)
      return TaskResult::{
        pkg_path,
        success: false,
        error: "Verification failed: \{e}",
      }
    }
  }
  self.cleanup(force=false)
  self.status = TaskStatus::Completed
  @stdio.stdout.write("info [\{pkg_path}] - Task finished normally\n")
  TaskResult::{ pkg_path, success: true, error: "" }
}

///|
pub async fn TaskHandle::error(self : TaskHandle, error : Error) -> TaskResult {
  @stdio.stderr.write("error [\{self.pkg_path}] - Exception: \{error}\n")
  self.cleanup(force=true)
  TaskResult::{
    pkg_path: self.pkg_path,
    success: false,
    error: error.to_string(),
  }
}

///|
async fn TaskHandle::cleanup(self : TaskHandle, force? : Bool) -> Unit {
  match self.worktree {
    Some(worktree) =>
      if not(
          remove_worktree(self.config.project_root, worktree.tmp_path, force?),
        ) {
        @stdio.stderr.write(
          "warning [\{self.pkg_path}] - Failed to remove git worktree at \{worktree.tmp_path}\n",
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
