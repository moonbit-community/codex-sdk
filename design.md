# Codex SDK High-Level API Design

## Goal

Enable AI agents to quickly generate MoonBit project automation scripts with minimal boilerplate.
Instead of 200+ lines of orchestration code, AI should generate ~10-20 lines that handle common patterns.

## Core Use Case

An AI agent receives: "Migrate these 5 MoonBit projects to use the new async API"

The AI generates:
```moonbit
async fn main {
  let projects = ["proj1", "proj2", "proj3", "proj4", "proj5"]
  @codex.Tasks::run_on_projects(
    projects,
    task="Migrate to new async API following migration guide",
    parallelism=3,
    git_workflow=true
  )
}
```

This replaces manual: git setup, parallelism, retries, validation, cleanup, error handling.

## Architecture

```
peter-jerry-ye/codex (core SDK - exists)
├── Codex, Thread, Turn, Events (✓ exists)
├── CodexOptions, ThreadOptions (✓ exists)

peter-jerry-ye/codex/moonbit (new - MoonBit project abstractions)
├── MoonProject - project discovery & management
├── Package - package-level operations  
├── ValidationResult - check/test/format results
└── Validator - composable validation rules

peter-jerry-ye/codex/git (new - Git workflow patterns)
├── GitRepo - repository operations
├── GitWorkflow - branch/worktree management
├── IsolatedWorkspace - temporary workspace with cleanup
└── with_workspace() - RAII pattern for safe operations

peter-jerry-ye/codex/tasks (new - high-level task templates)
├── TaskDefinition - declarative task specification
├── ParallelExecutor - concurrent execution with semaphore
├── run_per_package() - common package iteration pattern
└── Built-in templates: add_docs, migrate_api, add_tests, refactor

peter-jerry-ye/codex/utils (new - common utilities)
├── TaskLogger - consistent progress reporting
├── RetryPolicy - configurable retry logic
└── ResultCollector - aggregate results from parallel tasks
```

## Key APIs

### 1. MoonBit Project Management (`moonbit` package)

```moonbit
pub struct MoonProject { root: String, name: String }
pub struct Package { project: MoonProject, path: String }

pub fn MoonProject::discover(path: String) -> MoonProject?
pub fn MoonProject::packages() -> Array[Package]
pub async fn MoonProject::check() -> ValidationResult
pub async fn MoonProject::test() -> ValidationResult
pub async fn MoonProject::format() -> ValidationResult

pub enum Validator { MoonCheck; MoonTest; MoonFormat; GitClean; Custom((String) -> Bool) }
pub struct ValidationResult { passed: Bool, stdout: String, stderr: String }
```

### 2. Git Workflow (`git` package)

```moonbit
pub struct GitRepo { path: String }
pub struct IsolatedWorkspace { path: String, cleanup: () -> Unit }

pub async fn GitRepo::discover(path: String) -> GitRepo?
pub async fn GitRepo::existing_branches() -> Array[String]

// RAII pattern - auto cleanup
pub async fn with_workspace[T](
  pkg: Package,
  branch: String,
  work: async (IsolatedWorkspace) -> T
) -> T
```

### 3. Task Orchestration (`tasks` package)

```moonbit
pub struct TaskDefinition {
  project_path: String
  codex_model: String?
  parallelism: Int
  git_branch_prefix: String?
  validators: Array[Validator]
  max_retries: Int
}

// Main entry point for parallel package processing
pub async fn run_per_package(
  project: MoonProject,
  task: (Package) -> String,  // Generate prompt per package
  options: TaskOptions
) -> Array[Result[Turn, Error]]

// Simplified for common case
pub async fn run_on_projects(
  project_paths: Array[String],
  task: String,  // Same prompt for all
  parallelism?: Int,
  git_workflow?: Bool
) -> Array[Result[Turn, Error]]
```

### 4. Smart Retry & Validation

```moonbit
pub struct CodexTask {
  thread: Thread
  validators: Array[Validator]
  max_attempts: Int
  completion_check: (Turn) -> Bool
}

pub async fn CodexTask::run_until_valid(
  prompt: String
) -> Turn raise Error
```

## Example: AI-Generated Scripts

### Scenario 1: Add Documentation (Replaces 200-line add_docs example)

```moonbit
async fn main {
  let project = @codex/moonbit.MoonProject::discover(".")!
  @codex/tasks.run_per_package(
    project,
    task=fn(pkg) => "Add docs to \{pkg.path}",
    options=@codex/tasks.TaskOptions::{
      model: "anthropic/claude-sonnet-4",
      parallelism: 4,
      git_branch_prefix: "docs-",
      validators: [MoonCheck, MoonTest, MoonFormat],
      completion_keywords: ["TASK COMPLETED"],
      max_retries: 3
    }
  )
}
```

### Scenario 2: Multi-Project Migration

```moonbit
async fn main {
  @codex/tasks.run_on_projects(
    ["proj-a", "proj-b", "proj-c"],
    task="Migrate from sync IO to async IO per migration-guide.md",
    parallelism=2,
    git_workflow=true
  )
}
```

## Implementation Notes

- All workspace operations use RAII pattern (`with_workspace`) to guarantee cleanup
- Parallel execution uses semaphore to control concurrency
- Validators run after each turn, trigger retry with error context if failed
- Git workflows automatically handle: branch existence check, worktree creation, cleanup
- Progress logging is automatic via TaskLogger attached to each thread
- Each package gets isolated workspace to prevent interference
