# Parallel Fix - Design & Implementation

> **Note**: This is the single source of documentation for the parallel
> repository fixer. Implementation status is tracked at the bottom of this
> document.

## Executive Summary

A robust repository fixer that uses AI agents to fix issues across multiple
repositories in parallel with persistent state management and reentrant
processing.

**Key Features:**

- Stateful processing with SQLite database
- Support for (repository, task) pairs - same repo can have multiple tasks
- Reentrant execution - safe to stop and resume
- Parallel processing with configurable concurrency
- Separation of temporary work directory and persistent data directory

## Current Gaps

| Issue                  | Impact                                   | Solution                         |
| ---------------------- | ---------------------------------------- | -------------------------------- |
| No state persistence   | Lost progress on crash                   | SQLite database                  |
| Not reentrant          | Can't resume mid-operation               | State machine                    |
| No PR tracking         | Manual monitoring needed                 | GitHub API sync                  |
| No iteration support   | Can't continue after merge               | Automatic rebase + new iteration |
| Limited error recovery | Failed repos require manual intervention | Smart retry with backoff         |

## Directory Structure

The tool separates working files from persistent data:

**Work Directory** (`--work-dir`, default: `/tmp/parallel-fix`)

- Stores cloned repositories during processing
- Can be temporary (e.g., `/tmp`)
- Safe to delete - repos will be re-cloned as needed
- Large disk space needed during processing
- Can be cleaned up after PRs are created

**Data Directory** (`--data-dir`, default: `~/.parallel-fix`)

- Stores SQLite database with all state
- Should be persistent (e.g., home directory)
- Small size (typically < 10MB)
- Contains all progress, history, and task descriptions
- Critical - do not delete unless resetting everything

**Benefits of Separation:**

- Clean up large clones without losing progress
- Keep database in persistent storage (home directory)
- Run from different machines with shared database (e.g., network drive)
- Use fast local SSD for clones, slower storage for database

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     CLI Interface                       │
│  init │ add │ run │ status │ retry │ clean │ sync-prs   │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Worker Manager                         │
│  - Picks tasks from queue                               │
│  - Manages parallelism                                  │
│  - State-driven processing                              │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  State Manager  │────▶│  Repo Manager   │
│  - SQLite DB    │     │  - Git ops      │
│  - Transitions  │     │  - PR ops       │
│  - History      │     │  - AI ops       │
└─────────────────┘     └─────────────────┘
```

## State Machine

**Main Flow:**

```
PENDING → CLONING → BRANCHING → FIXING → PR_OPEN → COMPLETE
                                   ↓         ↓
                                   ↓         [AI fetches PR state,
                                   ↓          decides action, may loop back to FIXING]
                                   ↓         ↓
                                   └─────────┘

Internal (not tracked in DB): commit → push → create PR happens within FIXING→PR_OPEN transition
```

**Control Flow Philosophy:**

**Before PR (AI Full Control):**

- States: PENDING → CLONING → BRANCHING → FIXING → COMMITTING → PUSHING →
  PR_CREATING
- AI has full control over the workflow
- During FIXING: AI can decide to go directly to COMPLETE if there's nothing to
  fix
- Transitions are deterministic based on task completion

**After PR (AI Decides, GitHub Informs):**

- State: PR_OPEN
- GitHub manages the actual PR state (reviews, merges, conflicts)
- When processing PR_OPEN: AI fetches current PR information from GitHub
- AI decides based on fetched state:
  - If merged → transition to COMPLETE
  - If changes requested or conflicts → go back to FIXING to address issues
  - If approved or still open with no issues → transition to COMPLETE
- For the current iteration, AI controls the decision-making, GitHub provides
  the state

**State Descriptions:**

- `PENDING`: Initial state, waiting to be processed
- `CLONING`: Repository being cloned to work directory
- `BRANCHING`: Feature branch being created
- `FIXING`: AI agent running fixes on the codebase
  - **AI Decision Point**: Check if there's actually work to do
    - If no changes needed → transition to `COMPLETE` (task done, no PR required)
    - If changes found → internally commit, push, create PR → transition to `PR_OPEN`
  - Internal steps (not database states): commit → push → create PR
- `PR_OPEN`: PR exists, AI continuously monitors and decides next action
  - **AI Decision Point**: Fetch PR state from GitHub and decide:
    - If merged or closed → transition to `COMPLETE`
    - If changes requested, conflicts, or other issues → AI decides whether to go back to `FIXING` or stay in `PR_OPEN`
    - If approved or still being reviewed → AI decides to wait (stay in `PR_OPEN`) or complete
  - AI has full autonomy to decide the next action based on current PR state
- `COMPLETE`: Task finished successfully
  - Either: no changes needed (no PR created)
  - Or: PR merged/closed, or AI determined no further action needed
- `RETRY`: Transient error during current run, will be retried

**Error Handling:**

- `RETRY` state: For transient errors that should be retried in the same run
- No persistent failure state: Failures during a run are transient only
- Each run is a fresh start: No attempt counting or failure history persisted

**Key Design Decisions:**

- **AI has full autonomy**: Both before and after PR creation, AI makes all decisions
  - Before PR: AI decides if work is needed
  - After PR: AI fetches GitHub state and decides next action (wait, fix, or complete)
- **Simplified state machine**: Only 7 database states (PENDING, CLONING, BRANCHING, FIXING, PR_OPEN, COMPLETE, RETRY)
  - Removed COMMITTING, PUSHING, PR_CREATING - these are internal steps within FIXING→PR_OPEN transition
- **Internal transaction**: commit → push → create PR happens atomically when transitioning from FIXING to PR_OPEN
- **Two AI decision points**:
  - During FIXING: AI decides if work is needed
  - During PR_OPEN: AI fetches GitHub state and decides next action (loop back to FIXING, stay in PR_OPEN, or complete)
- **GitHub as information source**: After PR creation, GitHub provides state, AI makes decisions
- No `FAILED` state - failures are transient, not persisted across runs
- Simpler flow: fewer database states, more internal logic
- Better concurrency: fewer state transitions reduce database contention
- Fresh start philosophy: Each run processes all repositories without historical failure baggage

## Database Schema (SQLite)

### Core Tables

**repositories** - Main tracking table

```sql
id, url, name, task_description, state, local_path, default_branch, 
current_branch, pr_number, pr_url, pr_state, thread_id,
last_error, iteration, created_at, updated_at

UNIQUE(url, task_description)  -- Same repo can have multiple tasks
```

**Note:** No `attempt_count` field - each run is a fresh start without
persistent failure tracking.

**Key Design**: The primary unit is a **(repository, task) pair**, not just a
repository. This allows:

- Same repository with different tasks (e.g., "Fix linting" vs "Update deps")
- Each pair has independent state tracking
- Multiple PRs from the same repo for different purposes

**state_transitions** - Audit trail

```sql
id, repo_id, from_state, to_state, timestamp, details
```

**work_log** - Detailed logs

```sql
id, repo_id, timestamp, level, message, context
```

**task_queue** - Work scheduling

```sql
id, repo_id, priority, scheduled_at, started_at, completed_at, worker_id
```

## Key Features

### 1. Full Reentrancy

Every operation checks state first:

```moonbit
fn ensure_cloned(repo_id) {
  match get_state(repo_id) {
    Pending | Retry => clone_and_transition()
    Cloning => discover_existing()  // Reentrant - verify and advance
    _ if >= Branching => already_advanced()
  }
}
```

### 2. GitHub as Source of Truth (After PR Creation)

Once a PR is created, GitHub's actual state becomes the source of truth. The
system syncs state from GitHub:

```moonbit
fn sync_pr_state(repo_id, pr_number) {
  // Fetch actual PR state from GitHub
  pr = gh_api.get_pr(pr_number)
  
  // Update database state to match GitHub reality
  match pr.state {
    "OPEN" => {
      if pr.review_decision == "CHANGES_REQUESTED" {
        transition(PR_CHANGES_REQUESTED)
      } else if pr.review_decision == "APPROVED" {
        transition(PR_APPROVED)
      } else if pr.merged {
        transition(PR_MERGED)
      } else {
        transition(PR_OPEN)  // Still open
      }
    }
    "MERGED" => transition(PR_MERGED)
    "CLOSED" => transition(PR_OPEN)  // Reopen or handle
  }
}
```

**Key insight**: After PR creation, AI completes its current work, but database
state is determined by GitHub, not AI decision. This prevents inconsistency
between database and actual PR state.

### 3. AI Autonomy in FIXING Phase

Before any PR is created, AI has full autonomy to decide if the task is
complete:

```moonbit
fn do_fix(config, repo) {
  // Run AI fix...
  thread.run(task)
  
  // Check if there are changes
  if !has_changes() {
    transition(COMPLETE)  // AI decides: task is done, no PR needed
    return
  }
  
  transition(COMMITTING)  // Have changes to commit and PR
}
```

**Why this design:**

- AI has clear decision authority before PR creation
- If task is truly complete, no unnecessary PR is created
- Reduces PR clutter in repositories
- Clean separation: task completion (no PR) vs work in progress (needs PR)

### 4. Automatic Iterations

```moonbit
fn handle_merged_pr(repo_id) {
  git_pull(default_branch)
  
  if still_has_issues() {
    increment_iteration()
    transition(Branching)  // Start fresh cycle
  } else {
    transition(Complete)
    archive()
  }
}
```

### 5. Transient Error Handling

```moonbit
fn handle_error(repo_id, error) {
  // Log error for current run
  log_error(repo_id, error)
  
  // Transition to RETRY for same-run retry
  // No attempt counting - each new run starts fresh
  transition(Retry)
  
  // Next run will pick up from RETRY state as if it's new work
}
```

**Philosophy:** Failures are transient. No persistent failure state or attempt
counting. Each run processes all non-complete repositories regardless of
previous failures.

## CLI Commands

**Global Options** (set before subcommand):

- `--work-dir <path>` - Working directory for clones (default:
  `/tmp/parallel-fix`)
- `--data-dir <path>` - Data directory for database (default: `~/.parallel-fix`)

**Note**: `work-dir` is for temporary repository clones (can be cleaned), while
`data-dir` stores the persistent SQLite database.

```bash
# Setup
parallel_fix --work-dir /tmp/fixes --data-dir ~/my-fixes init

# Add repos (task is stored in database for each repo)
parallel_fix --data-dir ~/my-fixes add repos.txt --task "Fix linting errors"
parallel_fix --data-dir ~/my-fixes add more-repos.txt --task "Update dependencies"

# Process (reentrant - can stop/start anytime)
parallel_fix --work-dir /tmp/fixes --data-dir ~/my-fixes run --parallelism 8

# Monitor (shows task for each repository)
parallel_fix --data-dir ~/my-fixes status                    # Summary
parallel_fix --data-dir ~/my-fixes status --verbose          # Detailed with tasks
parallel_fix --data-dir ~/my-fixes status --repo owner/repo  # Specific (planned)

# Manage (planned)
parallel_fix --data-dir ~/my-fixes sync-prs                  # Update PR states
parallel_fix --data-dir ~/my-fixes clean --completed         # Remove done repos
parallel_fix --data-dir ~/my-fixes reset owner/repo --to pending

# Iterations (planned)
parallel_fix --data-dir ~/my-fixes iterate --merged          # Force new iteration
```

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)

- [ ] SQLite schema and migrations
- [ ] State manager with transitions
- [ ] Basic CLI (init, add, status)

### Phase 2: Reentrant Operations (Week 2)

- [ ] Reentrant clone/branch/commit
- [ ] Worker manager with queue
- [ ] Run command with parallelism

### Phase 3: PR Integration (Week 3)

- [ ] GitHub API integration
- [ ] PR status synchronization
- [ ] Review state handling

### Phase 4: Advanced Features (Week 4)

- [ ] Automatic iterations
- [ ] Conflict resolution
- [ ] Cleanup automation

## Benefits Summary

| Feature             | Before               | After                       |
| ------------------- | -------------------- | --------------------------- |
| Crash recovery      | ❌ Lost all progress | ✅ Resume from last state   |
| PR monitoring       | ❌ Manual checking   | ✅ Auto-sync from GitHub    |
| Merged PRs          | ❌ Manual cleanup    | ✅ Auto-iterate or complete |
| Failures            | ❌ Manual retry      | ✅ Fresh start each run     |
| Parallel safety     | ⚠️ Basic semaphore   | ✅ Database-backed queue    |
| Debugging           | ⚠️ Console logs      | ✅ Persistent audit trail   |
| Progress visibility | ⚠️ End summary only  | ✅ Real-time status         |

## Migration Path

1. Current code stays as "simple mode"
2. Add new "stateful mode" with flag: `--stateful`
3. Once stable, make stateful mode default
4. Keep simple mode for quick one-offs

## Dependencies

- **SQLite3** - State persistence (need MoonBit binding)
- **GitHub CLI (`gh`)** - Already used, extend with API mode
- **GitHub API** - Via `gh api` for advanced queries
- **Optional: `jq`** - JSON processing (can use MoonBit JSON instead)

## Example Workflow

```bash
# Day 1: Setup and start
cd /workspace/my-fixes
moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix init
moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix add repos.txt --task "Migrate to new API"
moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/.parallel-fix run --parallelism 8

# ... work happens ...
# ... system crashes ...

# Day 2: Resume seamlessly
moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/.parallel-fix run --parallelism 8  # Continues where it left off

# Day 3: Check status
moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix status
# Output:
#   Total: 50
#   Complete: 15 | PR_MERGED: 20 | PR_OPEN: 10
#   Processing: 3 | Retry: 2

# Sync PR states (planned)
# moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix sync-prs

# Some PRs merged, auto-check for new work (planned)
# moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix iterate --merged
# → 5 repos need more work, starting iteration 2

# Clean up fully done repos (planned)
# moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix clean --completed
# → Removed 15 repos from queue

# Re-run to process any RETRY repos (fresh start, no failure history)
moon run real_world/parallel_fix -- --work-dir /tmp/fixes --data-dir ~/.parallel-fix run --parallelism 8
```

## Questions to Consider

1. **SQLite in MoonBit**: Need binding or use FFI?
2. **Worker distribution**: Single machine or multi-machine?
3. **Webhook support**: GitHub webhooks for PR updates?
4. **UI/Dashboard**: Web interface for monitoring?
5. **Notification**: Email/Slack when processing completes?

## Implementation Status

### ✅ Phase 1: Foundation (Complete)

**SQLite Infrastructure**

- ✅ CLI-based SQLite wrapper (`x/sqlite/`)
  - `exec()`, `exec_string()`, `query()` with JSON support
  - `query_csv()`, `transaction()`, automatic sqlite3 detection
- ✅ Database schema with 5 tables
  - repositories, state_transitions, work_log, task_queue, config
  - Indexes for performance
  - No attempt_count field - fresh start each run
- ✅ State manager with simplified 10-state machine
  - Active states: Pending, Cloning, Branching, Fixing, Committing, Pushing, PrCreating, PrOpen, Complete, Retry
  - Deprecated states (auto-migrated): PrChangesRequested, PrApproved, PrConflicts, PrMerged
  - `transition()`, `get_repos_in_state()`, `count_by_state()`
  - Automatic state transition logging
  - Semaphore-based locking to prevent database concurrency issues

**CLI Subcommands**

- ✅ `init` - Initialize workspace and database
  - Separate work-dir (clones) and data-dir (database)
  - Automatic directory creation with tilde expansion
- ✅ `add` - Add repositories from file
  - Per-repository task descriptions
  - Support for multiple tasks simultaneously
- ✅ `status` - Show current state (with --verbose)
  - Displays task description for each repository
  - Shows last error if any
  - Groups by task
- ✅ `help` - Show subcommand documentation
- ✅ Global options: `--work-dir` and `--data-dir`
  - Set before subcommand
  - Passed to all subcommands consistently
- ✅ Subcommand routing using `stop_early=true`
- ✅ Only stateful mode supported

### ✅ Phase 2: Reentrant Operations (Complete)

- ✅ Worker with state-driven processing in `worker.mbt`
  - `process_repository_stateful()` with phase handlers
  - Reentrant clone (checks if already cloned)
  - Reentrant branch (checks if branch exists)
  - Reentrant commit (checks if changes exist)
  - No attempt counting - fresh start each run
- ✅ Individual phase handlers (clone, branch, fix, commit, push, PR)
- ✅ `run` subcommand with worker pool
  - Batch processing with semaphore-based concurrency
  - Error handling with state transitions to Retry (transient within run)
  - No persistent failure tracking or max retry limits
- ✅ Resume from last state on crash (all operations check current state)
- ✅ Simplified state machine with direct action-to-action flow
  - Repos don't get stuck in intermediate states
  - Direct flow from action to action
  - Failures are transient only
- ✅ Database concurrency fixes
  - Semaphore-based locking in StateManager
  - All DB operations serialized to prevent "database is locked" errors
- ✅ Fresh start philosophy implemented
  - No attempt_count persistence
  - No max_retries configuration
  - Each run processes all non-complete repos regardless of previous failures

### ✅ Phase 3: PR Integration (Complete)

- ✅ **AI Decision Points Implemented**
  - During FIXING: AI can transition directly to COMPLETE if no changes needed
  - During PR_OPEN: AI fetches GitHub state and decides next action
  - Enhanced task prompt instructs AI to check if work is needed
  - Simple heuristic detection for "NO_CHANGES_NEEDED" response
- ✅ **PR State Management via GitHub API**
  - `fetch_pr_state()` function using `gh pr view --json state,mergeable,reviewDecision`
  - Parses fields: state (OPEN/MERGED/CLOSED), mergeable (MERGEABLE/CONFLICTING/UNKNOWN), reviewDecision (APPROVED/CHANGES_REQUESTED/REVIEW_REQUIRED or empty)
  - Used in PR_OPEN state to make intelligent decisions
  - Handles: state==MERGED → Complete, reviewDecision==CHANGES_REQUESTED → Fixing, mergeable==CONFLICTING → Fixing
  - Graceful fallback if gh CLI not available
- ✅ Simplified PR state handling
  - No separate database states for PR_CHANGES_REQUESTED, PR_APPROVED, PR_CONFLICTS, PR_MERGED
  - Single PR_OPEN state with dynamic GitHub state fetching
  - AI-driven decision making after PR creation based on current GitHub state

### 🎯 Phase 4: Advanced Features (Planned)

- [ ] Automatic iterations after PR merge
- [ ] `clean --completed` to remove finished repos
- [ ] `reset` command to change repo state
- [ ] Cleanup automation

## Usage Examples

### Stateful Mode

**Key Concepts:**

- `--work-dir`: Temporary directory for cloning repositories (can be cleaned)
- `--data-dir`: Persistent directory for SQLite database (keeps state across
  runs)
- **Primary unit**: (repository, task) pair - same repo can have multiple tasks
- Each (repo, task) pair has independent state tracking
- Multiple tasks can run simultaneously on different repositories

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
  add repos-task-b.txt --task "Update dependencies to latest"
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
# Status shows breakdown by task
moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  status

# Output:
#   Total repository-task pairs: 20  (10 repos × 2 tasks)
#   Unique tasks: 2
#   
#   BREAKDOWN BY TASK:
#     "Fix linting errors" - 10 repos
#     "Update dependencies" - 10 repos
```

**Common Operations:**

```bash
# Check status (shows task for each repository)
moon run real_world/parallel_fix -- \
  --data-dir ~/.parallel-fix \
  status --verbose

# Start/resume processing (uses work-dir for clones, data-dir for state)
moon run real_world/parallel_fix -- \
  --work-dir /tmp/fixes \
  --data-dir ~/.parallel-fix \
  run --parallelism 8

# You can clean work-dir anytime, state is preserved in data-dir
rm -rf /tmp/fixes

# Resume processing (will re-clone as needed)
moon run real_world/parallel_fix -- \
  --work-dir /tmp/fixes \
  --data-dir ~/.parallel-fix \
  run --parallelism 8

# Sync PR states (planned)
# moon run real_world/parallel_fix -- --data-dir ~/.parallel-fix sync-prs
```

## Files

**Implementation**

- `main.mbt` - CLI entry point, subcommand routing, quick mode
- `commands.mbt` - Subcommand handlers (init, add, status, run)
- `worker.mbt` - State-driven worker with phase handlers
- `schema.mbt` - SQLite database schema
- `state.mbt` - State manager and RepoState enum
- `repo.mbt` - Git operations
- `task.mbt` - AI agent task execution

**Supporting Modules**

- `x/sqlite/sqlite.mbt` - SQLite CLI wrapper with JSON support
- `x/git/` - Git repository operations
- `x/args/` - CLI argument parsing

## Notes

- SQL uses no comments (sqlite3 CLI limitation with `--`)
- All state transitions automatically logged to audit trail
- Database fully reentrant with `IF NOT EXISTS`
- Quick mode and stateful mode can coexist
- Thread resumption only used internally in quick mode
