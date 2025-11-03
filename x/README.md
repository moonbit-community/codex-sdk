# Codex SDK High-Level APIs

This directory contains high-level APIs that make it easy to build MoonBit project automation tools using the Codex SDK. These APIs are designed to enable AI agents to quickly generate complete automation scripts with minimal boilerplate.

## Packages

### `x/moon` - MoonBit Project Management

Utilities for discovering and working with MoonBit projects and packages.

**Key Types:**
- `MoonProject` - Represents a MoonBit module
- `Package` - Represents a package within a project
- `ValidationResult` - Results from validation operations
- `Validator` - Enum of validation types (MoonCheck, MoonTest, MoonFormat, GitClean, Custom)

**Example:**
```moonbit
let project = @moon.MoonProject::discover(".")!
let packages = project.packages()
let check_result = project.check()
let test_result = project.test_()
```

### `x/git` - Git Workflow Automation

Utilities for working with Git repositories and creating isolated workspaces.

**Key Types:**
- `GitRepo` - Represents a Git repository
- `IsolatedWorkspace` - Temporary workspace created with git worktree

**Example:**
```moonbit
let repo = @git.GitRepo::discover(".")!
let branches = repo.existing_branches()
let is_clean = repo.is_clean()

// Create isolated workspace for safe operations
let workspace = repo.create_workspace("/tmp/work", "my-branch", create_branch=true)!
// ... do work ...
workspace.cleanup()
```

### `x/tasks` - High-Level Task Orchestration

**This is not yet fully implemented.** The design is in place but the implementation has been simplified to avoid complex async coordination issues.

**Planned Features:**
- Parallel execution of tasks across packages
- Automatic retry with validation
- Git workflow integration
- Progress tracking

**Intended Usage (when complete):**
```moonbit
let project = @moon.MoonProject::discover(".")!

let results = @tasks.run_per_package(
  project,
  fn(pkg) => "Add documentation to \{pkg.path}",
  options=@tasks.TaskOptions::{
    model: Some("anthropic/claude-sonnet-4"),
    parallelism: 4,
    git_branch_prefix: Some("docs-"),
    validators: [@moon.Validator::MoonCheck, @moon.Validator::MoonTest],
    max_retries: 3,
    // ... other options
  }
)
```

## Current Status

- ✅ `x/moon` - Fully implemented and working
- ✅ `x/git` - Fully implemented and working  
- ⚠️ `x/tasks` - Partially implemented (type definitions exist but runtime logic needs work)

## Examples

See the `cmd/example_simple_tasks` and `cmd/example_multi_project` directories for example usage.

## Development

To use these packages in your project:

```json
{
  "import": [
    "peter-jerry-ye/codex/x/moon",
    "peter-jerry-ye/codex/x/git"
  ]
}
```

The `x/tasks` package will be completed in a future update once the async semaphore and validation coordination logic is fully implemented.
