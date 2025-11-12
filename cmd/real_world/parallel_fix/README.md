# Parallel Repository Fixer

A powerful tool for automatically fixing issues across multiple repositories in parallel using AI agents powered by the Codex SDK.

## Features

- **Parallel Processing**: Fix multiple repositories concurrently with configurable parallelism
- **Two-Phase AI Workflow**: Separates code fixing (WorkspaceWrite mode) from git operations (DangerFullAccess mode) for security
- **AI-Powered Fixes**: Uses Codex AI agents to understand and fix issues automatically
- **Git Integration**: Automatically clones, creates branches, commits, pushes, and creates pull requests
- **Flexible Task Description**: Specify any task for the AI agents to perform
- **Progress Tracking**: Real-time progress updates and comprehensive summary reports

## Prerequisites

- MoonBit toolchain installed
- Git installed and configured
- GitHub CLI (`gh`) installed and authenticated (for PR creation)
- Codex SDK configured with API access

## Installation

This tool is part of the codex-sdk repository. No separate installation is needed.

## Usage

### Basic Usage

```bash
moon run real_world/parallel_fix -- repos.txt --task "Fix linting errors"
```

### Command Line Options

```
Usage: moon run real_world/parallel_fix -- [OPTIONS] <repos-file>

<repos-file>    Path to file containing repository URLs (one per line)

Options:
  --task <description>           Task description for AI agent (required)
  --parallelism <n>              Number of parallel tasks (default: 4)
  --branch-prefix <prefix>       Branch name prefix (default: "ai-fix")
  --work-dir <path>              Working directory for clones (default: /tmp/parallel-fix)
  --force-fresh                  Delete existing clones and start fresh
  --help                         Print this help message
```

### Repository List File Format

Create a text file with one repository URL per line:

```
https://github.com/user/repo1.git
https://github.com/user/repo2.git
https://github.com/organization/repo3.git
# Comments are supported
https://github.com/user/repo4.git
```

Empty lines and lines starting with `#` are ignored.

## Examples

### Fix Linting Errors Across Repositories

```bash
moon run real_world/parallel_fix -- repos.txt \
  --task "Fix all ESLint errors and warnings" \
  --parallelism 8
```

### Update Dependencies

```bash
moon run real_world/parallel_fix -- repos.txt \
  --task "Update all npm dependencies to latest versions and fix any breaking changes" \
  --parallelism 4 \
  --branch-prefix "deps-update"
```

### Add Documentation

```bash
moon run real_world/parallel_fix -- repos.txt \
  --task "Add JSDoc comments to all public functions and classes" \
  --parallelism 6
```

### Force Fresh Start

```bash
moon run real_world/parallel_fix -- repos.txt \
  --task "Migrate to TypeScript" \
  --force-fresh \
  --parallelism 2
```

## How It Works

The tool uses a **two-phase approach** with intelligent sandbox mode switching for security and reliability:

### Phase 1: Code Fixing (WorkspaceWrite Mode)

1. **Repository Cloning**: The tool clones (or reuses existing clones of) all repositories listed in the input file

2. **Branch Creation**: For each repository, a new branch is created with the format `<branch-prefix>-<timestamp>`

3. **AI Agent Execution (Safer Mode)**: An AI agent is started in **WorkspaceWrite** sandbox mode, which allows:
   - Reading and writing files in the workspace
   - Executing commands (tests, linters, build tools)
   - Viewing git status and diffs
   - **But NOT** pushing to remote or creating PRs

4. **Task Completion**: The agent works on the task, making multiple attempts if needed (up to 5 attempts by default), focusing on:
   - Fixing all errors and warnings
   - Running tests to ensure they pass
   - Following project coding standards

### Transition: Tool Takes Over

5. **Automatic Formatting & Committing**: Once the AI completes the fixes, the tool takes over to:
   - Run project-specific formatters (e.g., `moon fmt` for MoonBit projects)
   - Update project metadata (e.g., `moon info` for MoonBit projects)
   - Commit all changes with a descriptive message

### Phase 2: Push & PR Creation (DangerFullAccess Mode)

6. **Thread Resumption**: The same AI agent thread is resumed internally, but now in **DangerFullAccess** mode, which allows:
   - All git remote operations
   - Pushing to remote repositories
   - Creating pull requests

7. **Push & PR Creation**: The agent:
   - Pushes the committed changes to the remote repository
   - Creates a pull request using GitHub CLI or provides the PR creation URL

## Sandbox Modes

The tool uses a **two-phase sandbox mode strategy** for better security and control:

### Phase 1: WorkspaceWrite Mode

The AI agent starts in `WorkspaceWrite` mode, which allows:
- Reading and writing files in the workspace
- Executing shell commands (tests, linters, build tools)
- Viewing git status and diffs
- **No remote git operations** (cannot push or create PRs)

This safer mode ensures the AI cannot accidentally push broken code or create PRs prematurely.

### Transition: Tool Control

After Phase 1, the tool takes control to:
- Run formatters (`moon fmt`, `prettier`, etc.)
- Update metadata (`moon info`, etc.)
- Commit all changes properly

### Phase 2: DangerFullAccess Mode

The same AI thread is resumed internally in `DangerFullAccess` mode, which allows:
- All git remote operations
- Pushing to remote repositories
- Creating pull requests
- Full system access

This ensures git operations only happen after code is properly formatted and committed.

**Note**: Thread resumption is only used internally between Phase 1 and Phase 2. Each run of the tool starts fresh threads for all repositories.

## Output and Logging

The tool provides detailed progress information:
- `info [repo]`: Normal operation messages
- `warning [repo]`: Non-fatal issues
- `error [repo]`: Failures that prevent completion
- `✓ [n/total] repo`: Successful completion
- `✗ [n/total] repo`: Failed completion

At the end, a comprehensive summary is printed showing:
- Total repositories processed
- Successful completions with PR URLs
- Failures with error messages

## Best Practices

1. **Start Small**: Test with a small number of repositories first
2. **Clear Tasks**: Provide specific, actionable task descriptions
3. **Adjust Parallelism**: Balance speed with API rate limits and system resources
4. **Monitor Progress**: Watch the output for any errors or warnings
5. **Review PRs**: Always review the generated pull requests before merging
6. **Fresh Starts**: Use `--force-fresh` if you want to discard previous clones

## Troubleshooting

### PRs Not Being Created

- Ensure GitHub CLI (`gh`) is installed: `brew install gh` (macOS) or equivalent
- Authenticate with GitHub: `gh auth login`
- Verify you have push access to the repositories

### Cloning Failures

- Check that repository URLs are correct and accessible
- Ensure you have proper Git credentials configured
- Use SSH URLs if you have SSH keys set up

### AI Agent Errors

- Check Codex SDK configuration and API access
- Verify the task description is clear and achievable
- Increase the attempt limit in code if needed for complex tasks

## Architecture

The tool is organized into several modules:

- **main.mbt**: CLI argument parsing, orchestration, and summary reporting
- **repo.mbt**: Git operations (clone, branch, commit, push, PR creation)
- **task.mbt**: AI agent execution, thread management, and task completion verification
- **utils.mbt**: Error handling utilities

## License

Same as the parent codex-sdk project.
