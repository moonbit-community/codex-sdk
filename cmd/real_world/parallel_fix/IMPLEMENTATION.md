# Parallel Repository Fixer - Implementation Summary

## Overview

Successfully created a comprehensive parallel repository fixer tool under `cmd/real_world/parallel_fix` that uses AI agents to automatically fix issues across multiple repositories.

## Files Created

### 1. `moon.pkg.json`
Package configuration with all necessary dependencies:
- `peter-jerry-ye/codex` - Main Codex SDK
- `moonbitlang/async/*` - Async operations (fs, process, semaphore, etc.)
- `peter-jerry-ye/codex/x/args` - CLI argument parsing
- `peter-jerry-ye/codex/x/error` - Error handling utilities

### 2. `main.mbt`
Main entry point with:
- CLI argument parsing (repo file, task description, parallelism, etc.)
- Repository list reading from file
- Parallel task orchestration using semaphores
- Comprehensive summary reporting

### 3. `repo.mbt`
Git repository operations:
- `clone_repository()` - Clone or reuse existing clones
- `create_branch()` - Create and checkout branches
- `has_changes()` - Check for uncommitted changes
- `commit_changes()` - Stage and commit all changes
- `push_branch()` - Push to remote repository
- `create_pull_request()` - Create PRs using GitHub CLI

### 4. `task.mbt`
AI agent task execution:
- `process_repository()` - Main task processor
- `execute_task_with_agent()` - Agent execution with retry logic
- `build_task_prompt()` - Comprehensive prompt generation
- Thread ID persistence for resumption
- Multiple attempt verification (up to 5 attempts)
- Support for different sandbox modes

### 5. `utils.mbt`
Error handling utilities:
- `Reraise` error type for error chaining
- `reraise()` - Re-raise errors with context
- `fail_with()` - Fail with message and cause

### 6. `README.md`
Comprehensive documentation including:
- Feature overview
- Installation and prerequisites
- Usage examples
- Command-line options
- How it works explanation
- Best practices
- Troubleshooting guide

### 7. `repos.example.txt`
Sample repository list file format

## Key Features

### 1. Parallel Processing
- Configurable parallelism (default: 4 concurrent tasks)
- Semaphore-based concurrency control
- Progress tracking with real-time updates

### 2. Two-Phase AI Agent Integration
**Phase 1: Code Fixing (WorkspaceWrite Mode)**
- AI agent works in safer WorkspaceWrite sandbox mode
- Can read/write files and run tests
- Cannot push or create PRs (prevents accidental pushes)
- Focuses on fixing errors, warnings, and running tests

**Transition: Tool Control**
- Tool runs formatters (`moon fmt`, etc.)
- Updates project metadata (`moon info`, etc.)
- Commits changes with descriptive message

**Phase 2: Push & PR (DangerFullAccess Mode)**
- Same AI thread resumed internally with full access
- Pushes committed changes to remote
- Creates pull request
- Maintains conversation context from Phase 1

### 3. Git Operations
- Automatic cloning or reuse of existing clones
- Branch creation with unique names
- Automatic committing by the tool (not AI)
- Push to remote by AI in Phase 2
- Pull request creation via GitHub CLI

### 4. Thread Resumption (Internal Only)
- Thread IDs are logged for debugging
- Thread is resumed internally between Phase 1 and Phase 2
- Maintains conversation context across both phases
- Each tool run starts fresh threads (no cross-run resumption)

### 5. Error Handling
- Graceful error handling with detailed messages
- Per-repository error reporting
- Comprehensive summary at the end
- Failed tasks don't block successful ones

### 6. Flexibility
- Accepts any task description
- Customizable branch prefixes
- Configurable working directory
- Force fresh clone option

## Usage Examples

### Basic Usage
```bash
moon run real_world/parallel_fix -- repos.txt --task "Fix linting errors"
```

### Advanced Usage
```bash
moon run real_world/parallel_fix -- repos.txt \
  --task "Update dependencies and fix breaking changes" \
  --parallelism 8 \
  --branch-prefix "deps-update" \
  --work-dir /tmp/my-fixes
```

## Architecture

```
main.mbt
  ├─> read_repos_file()
  ├─> ensure_work_dir()
  └─> parallel processing with semaphore
       └─> process_repository() (task.mbt)
            ├─> clone_repository() (repo.mbt)
            ├─> create_branch() (repo.mbt)
            │
            ├─> PHASE 1: execute_fix_phase() (task.mbt)
            │    ├─> start_thread(WorkspaceWrite mode)
            │    ├─> build_fix_phase_prompt()
            │    └─> verify completion (up to 5 attempts)
            │    └─> AI fixes code, runs tests, checks errors
            │
            ├─> TOOL TAKES OVER
            │    ├─> format_repository() (moon fmt, etc.)
            │    ├─> update_repository_info() (moon info, etc.)
            │    └─> commit_changes() (repo.mbt)
            │
            └─> PHASE 2: execute_push_phase() (task.mbt)
                 ├─> resume_thread(DangerFullAccess mode)
                 ├─> build_push_phase_prompt()
                 └─> AI pushes and creates PR
```

## Sandbox Mode Support

The tool uses a **two-phase security model**:

### Phase 1: WorkspaceWrite Mode
- **Purpose**: Safe code modification
- **Permissions**:
  - ✅ Read/write files in workspace
  - ✅ Execute commands (tests, linters, build)
  - ✅ View git status and diffs
  - ❌ No remote git operations (cannot push)
  - ❌ No PR creation
- **AI Task**: Fix code, resolve errors/warnings, run tests

### Tool Transition
- **Tool Actions**:
  - Run formatters (project-specific)
  - Update metadata files
  - Commit changes with descriptive message
  - Prepare for push phase

### Phase 2: DangerFullAccess Mode
- **Purpose**: Git operations and PR creation
- **Permissions**:
  - ✅ Full git remote access
  - ✅ Push to repositories
  - ✅ Create pull requests
  - ✅ All system access
- **AI Task**: Push changes and create PR

This separation ensures:
1. AI cannot accidentally push broken code
2. Code is always formatted and committed properly by the tool
3. AI gets full access only when code is ready for push

## Error Handling Strategy

1. **Per-Repository Isolation**: Failures in one repository don't affect others
2. **Detailed Logging**: Progress and errors logged with repository context
3. **Summary Reporting**: Clear success/failure breakdown at the end
4. **Graceful Degradation**: Missing tools (like `gh`) cause warnings, not failures

## Testing

To test the tool:

1. Create a test repository list:
```bash
echo "https://github.com/your-test/repo1.git" > test-repos.txt
```

2. Run with a simple task:
```bash
moon run real_world/parallel_fix -- test-repos.txt \
  --task "Add a README.md file if it doesn't exist" \
  --parallelism 1
```

3. Verify:
- Clone was successful
- Branch was created
- AI agent completed the task
- Changes were committed and pushed
- PR was created (if `gh` is installed)

## Future Enhancements

Possible improvements:
1. Support for different Git hosting platforms (GitLab, Bitbucket)
2. Dry-run mode to preview changes
3. Custom PR templates
4. Webhook notifications on completion
5. Progress persistence across tool restarts
6. Custom retry strategies per task type
7. Integration with CI/CD status checks

## Compilation Status

✓ All files compile successfully
✓ No type errors
✓ Only minor warnings (unused fields/functions for future use)
✓ Interface file generated correctly
✓ Follows MoonBit coding conventions
