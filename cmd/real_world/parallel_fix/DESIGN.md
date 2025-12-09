# Parallel Fix - Design & Implementation

> **Note**: This is the single source of documentation for the parallel
> repository fixer.

## Executive Summary

A simple repository fixer that uses AI agents to fix issues across multiple
repositories in parallel with persistent database tracking.

**Key Features:**

- Simple database tracking with SQLite
- Support for (repository, task) pairs - same repo can have multiple tasks
- Reentrant execution - safe to stop and resume
- Parallel processing with configurable concurrency
- Separation of temporary work directory and persistent data directory

## Architecture Overview

**Simplified Design Philosophy:**

- **No complex state machine** - Just track: completed or not completed
- **GitHub is source of truth** - PR information fetched from GitHub when needed
- **Simple loop** - For each incomplete repo: check PR → create if needed → run
  AI → sync changes
- **Reentrant** - Can stop and resume anytime

```
┌─────────────────────────────────────────────────────────┐
│                     CLI Interface                       │
│           init │ add │ run │ status                     │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Worker Loop                            │
│  For each incomplete repository:                        │
│    1. Check if PR exists (via GitHub)                   │
│    2. Create draft PR if missing                        │
│    3. Get PR comments                                   │
│    4. Run AI to make changes                            │
│    5. Sync changes if AI made any                       │
│    6. Mark as completed if PR is merged                 │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  Database       │     │  Git & GitHub   │
│  - url          │     │  - Clone        │
│  - task         │     │  - Branch       │
│  - pr_number    │     │  - Commit       │
│  - completed    │     │  - Push         │
└─────────────────┘     │  - Create PR    │
                        │  - Fetch PR     │
                        └─────────────────┘
```

## Database Schema (Simplified)

**repositories** - Single table to track everything

```sql
CREATE TABLE repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT NOT NULL,
    task TEXT NOT NULL,
    pr_number INTEGER,
    completed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(url, task)
);
```

**codex_sessions** - Track Codex session IDs for each repository task run

```sql
CREATE TABLE codex_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repository_id INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);
```

**Key Design**: The primary unit is a **(repository, task) pair**, not just a
repository. This allows:

- Same repository with different tasks (e.g., "Fix linting" vs "Update deps")
- Each pair has independent tracking
- Multiple PRs from the same repo for different purposes
- Track all Codex session IDs for debugging and audit purposes

**No state machine, no audit logs, no queue** - Just the essentials!

## Directory Structure

The tool separates working files from persistent data:

**Work Directory** (`--work-dir`, default: `/tmp/parallel-fix`)

- Stores cloned repositories during processing
- Can be temporary (e.g., `/tmp`)
- Safe to delete - repos will be re-cloned as needed

**Data Directory** (`--data-dir`, default: `~/.parallel-fix`)

- Stores SQLite database with all state
- Should be persistent (e.g., home directory)
- Small size (typically < 1MB)
- Contains all progress and task descriptions

## Processing Flow

**Simple loop for each repository:**

1. **Check PR status**
   - If no PR number stored → need to create one
   - If PR number exists → fetch branch from GitHub using
     `gh pr view --json headRefName`

2. **Create draft PR if needed**
   - Clone repository (if not already cloned)
   - Create feature branch with timestamp
   - Make empty commit to enable PR creation
   - Push and create draft PR
   - Store PR number in database

3. **Get PR feedback**
   - Fetch PR comments using `gh pr view --comments`
   - This gives context for AI to continue work

4. **Run AI**
   - AI reviews the code, comments, and task
   - AI makes necessary changes
   - AI uses its judgment to decide if done

5. **Sync changes**
   - If AI made changes → commit and push
   - If PR is merged → mark as completed
   - If no changes → continue to next iteration

**Reentrant Design:**

- Each step checks current state before proceeding
- If interrupted, next run continues from where it left off
- Database tracks all progress

## CLI Commands

**Global Options** (set before subcommand):

- `--work-dir <path>` - Working directory for clones (default:
  `/tmp/parallel-fix`)
- `--data-dir <path>` - Data directory for database (default: `~/.parallel-fix`)

```bash
# Setup
parallel_fix --work-dir /tmp/fixes --data-dir ~/my-fixes init

# Add repos (task is stored in database for each repo)
parallel_fix --data-dir ~/my-fixes add repos.txt --task "Fix linting errors"
parallel_fix --data-dir ~/my-fixes add more-repos.txt --task "Update dependencies"

# Process (reentrant - can stop/start anytime)
parallel_fix --work-dir /tmp/fixes --data-dir ~/my-fixes run --parallelism 8

# Monitor
parallel_fix --data-dir ~/my-fixes status           # Summary
parallel_fix --data-dir ~/my-fixes status --verbose # Detailed
```

## GitHub Integration

**No need to store branch names** - GitHub is the source of truth:

- When PR exists: Use `gh pr view <pr_number> --json headRefName` to get branch
  name
- PR state: Use `gh pr view <pr_number> --json state,mergeable,isDraft`
- PR comments: Use `gh pr view <pr_number> --comments`

This avoids data duplication and ensures consistency with GitHub.

## Fork Handling and Distinguished Remote Names

**Automatic Fork Detection and Creation:**

When a repository is fixed and the user doesn't have write access:

1. The tool automatically detects if a fork exists for the current user
2. If no fork exists, it creates one using `gh repo fork`
3. The fork URL is stored in the database as `target_url`
4. All subsequent operations use the fork as the target

**Distinguished Remote Names:**

To support processing multiple repositories without remote name conflicts:

- Each repository gets a unique remote name based on its owner
- Format: `<remote_type>-<owner>` (e.g., `upstream-moonbit-community`)
- Original repo: `upstream-<owner>`
- Fork: `origin` (default clone remote)

**Example:**

```
Repository: https://github.com/moonbit-community/codex-sdk.git
├── origin (fork URL)
└── upstream-moonbit-community (original repo)

Repository: https://github.com/user/repo.git
├── origin (fork URL)
└── upstream-user (original repo)
```

**Benefits:**

- Multiple repositories can be processed in parallel without conflicts
- Each PR can independently rebase/merge with its remote/default branch
- Cleaner git remote management when handling multiple repos
- Enables proper synchronization of fork's default branch with original

## Key Features

### 1. Full Reentrancy

Every operation checks state first:

```moonbit
fn process_repository(config, repo) {
  match repo.pr_number {
    None => create_draft_pr()  // No PR yet
    Some(pr_num) => {
      branch = fetch_branch_from_github(pr_num)  // Get from GitHub
      continue_work()
    }
  }
}
```

### 2. Simplicity

- **One table** instead of complex state machine
- **Boolean completed flag** instead of 10+ states
- **GitHub API** instead of duplicating PR state
- **Simple loop** instead of state transitions

### 3. Parallel Safety

- SQLite handles concurrency automatically
- Semaphore limits concurrent workers
- Each worker processes one repository at a time

## Usage Examples

**Example 1: Different Tasks on Different Repos**

```bash
# Initialize workspace
moon run real_world/parallel_fix -- \
  --work-dir /tmp/fixes \
  --data-dir ~/.parallel-fix \
  init

# Add task A for some repositories
moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  add repos-task-a.txt --task "Fix linting errors"

# Add task B for different repositories
moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  add repos-task-b.txt --task "Update dependencies"

# Start processing
moon run real_world/parallel_fix -- \
  --work-dir /tmp/fixes \
  --data-dir ~/.parallel-fix \
  run --parallelism 8
```

**Example 2: Multiple Tasks on Same Repos**

```bash
# Add same repos with different tasks - creates separate (repo, task) pairs
moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  add repos.txt --task "Fix linting errors"

moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  add repos.txt --task "Update dependencies"

# Now each repo has TWO entries with different tasks
```

## Files

**Implementation**

- `main.mbt` - CLI entry point and subcommand routing
- `worker.mbt` - Simple loop: check PR → create if needed → run AI → sync
- `schema.mbt` - Single table database schema
- `state.mbt` - Database operations (add, get, update, mark_completed)
- `domain.mbt` - Data structures (RepositoryRecord, WorkerConfig)
- `utils.mbt` - Utility functions

**Supporting Modules**

- `x/sqlite/sqlite.mbt` - SQLite CLI wrapper
- `x/git/` - Git operations
- `x/gh/` - GitHub CLI wrapper
- `x/args/` - CLI argument parsing

## Benefits Summary

| Feature         | Simplified Design                    |
| --------------- | ------------------------------------ |
| Crash recovery  | ✅ Resume from database state        |
| PR tracking     | ✅ Fetch from GitHub when needed     |
| Simplicity      | ✅ One table, boolean completed flag |
| Parallel safety | ✅ SQLite + semaphore                |
| Debugging       | ✅ Simple to understand and fix      |

## Implementation Status

### ✅ Complete

- ✅ SQLite single-table schema with target_url field
- ✅ CLI commands: init, add, run, status
- ✅ Simple worker loop
- ✅ GitHub integration (gh CLI)
- ✅ Parallel processing with semaphore
- ✅ Reentrant design
- ✅ Codex session ID tracking for audit and debugging

### Features

#### Session ID Tracking

The tool now records every Codex session ID (thread ID) for each repository task run:

- **Database Table**: `codex_sessions` table stores session IDs linked to repository tasks
- **Automatic Recording**: Session IDs are saved after each AI task execution
- **Multiple Sessions**: Supports tracking multiple sessions per repository (e.g., initial run + subsequent iterations based on PR feedback)
- **Status Display**: Use `status --verbose` to view all session IDs for each repository
- **Use Cases**:
  - Debug AI behavior for specific repositories
  - Audit trail of all AI interactions
  - Resume or analyze previous sessions
- ✅ Separate work-dir and data-dir
- ✅ Automatic fork detection and creation
- ✅ Distinguished remote names for parallel processing
- ✅ Fork synchronization with original repository

### 🎯 Future Enhancements (Optional)

- [ ] `sync-prs` command to update PR numbers from GitHub
- [ ] `clean --completed` to remove finished repos
- [ ] Web dashboard for monitoring
- [ ] Webhook support for PR updates
- [ ] Support for SSH-based repository URLs
