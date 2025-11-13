# Parallel Fix - Design & Implementation

> **Note**: This is the single source of documentation for the parallel repository fixer.
> Implementation status is tracked at the bottom of this document.

## Executive Summary

A robust batch repository fixer that uses AI agents to fix issues across multiple repositories in parallel. Supports both:
- **Quick mode**: One-off batch fixes (current implementation)
- **Stateful mode**: Persistent, reentrant processing with SQLite (foundation complete)

## Current Gaps

| Issue | Impact | Solution |
|-------|--------|----------|
| No state persistence | Lost progress on crash | SQLite database |
| Not reentrant | Can't resume mid-operation | State machine |
| No PR tracking | Manual monitoring needed | GitHub API sync |
| No iteration support | Can't continue after merge | Automatic rebase + new iteration |
| Limited error recovery | Failed repos require manual intervention | Smart retry with backoff |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     CLI Interface                        │
│  init │ add │ run │ status │ retry │ clean │ sync-prs   │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Worker Manager                          │
│  - Picks tasks from queue                                │
│  - Manages parallelism                                   │
│  - State-driven processing                               │
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

```
PENDING → CLONING → CLONED → BRANCHING → BRANCHED
                                             ↓
                                          FIXING
                                             ↓
                                          FIXED
                                             ↓
                                        COMMITTING
                                             ↓
                                        COMMITTED
                                             ↓
                                         PUSHING
                                             ↓
                                         PUSHED
                                             ↓
                                       PR_CREATING
                                             ↓
                                         PR_OPEN ←─────┐
                                             ↓          │
                    ┌────────────────────────┼──────────┤
                    │                        │          │
                    ▼                        ▼          │
            PR_CHANGES_REQUESTED      PR_CONFLICTS     │
                    │                        │          │
                    └────────▶ FIXING ◀──────┘          │
                                  │                     │
                              PR_APPROVED               │
                                  │                     │
                              PR_MERGED ────────────────┘
                                  │        (rebase +    
                                  │         check work)
                                  ▼
                              COMPLETE
```

Error states from any point: `FAILED`, `RETRY`

## Database Schema (SQLite)

### Core Tables

**repositories** - Main tracking table
```sql
id, url, name, state, local_path, default_branch, current_branch,
task_description, pr_number, pr_url, pr_state, thread_id,
attempt_count, last_error, iteration, created_at, updated_at
```

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
    Cloning => wait_or_verify()  // Another worker
    _ if >= Cloned => discover_existing()
  }
}
```

### 2. PR Lifecycle Management

```moonbit
fn sync_pr_state(repo_id) {
  pr = gh_api.get_pr(pr_number)
  
  if pr.review_decision == "CHANGES_REQUESTED" {
    transition(PrChangesRequested)
    schedule_ai_fix()
  }
  
  if pr.mergeable == false {
    transition(PrConflicts)
    schedule_rebase()
  }
  
  if pr.merged {
    transition(PrMerged)
    handle_merged()  // New iteration or complete
  }
}
```

### 3. Automatic Iterations

```moonbit
fn handle_merged_pr(repo_id) {
  git_pull(default_branch)
  
  if still_has_issues() {
    increment_iteration()
    transition(Branched)  // Start fresh cycle
  } else {
    transition(Complete)
    archive()
  }
}
```

### 4. Smart Retry

```moonbit
fn should_retry(repo_id) {
  attempts = get_attempts(repo_id)
  if attempts >= 3 { return false }
  
  backoff = pow(5, attempts) * 60  // 1min, 5min, 15min
  if now() < last_attempt + backoff { return false }
  
  increment_attempts()
  transition(Retry)
  true
}
```

## CLI Commands

```bash
# Setup
parallel_fix init --work-dir /tmp/fixes

# Add repos
parallel_fix add repos.txt --task "Fix linting"

# Process (reentrant - can stop/start anytime)
parallel_fix run --parallelism 8

# Monitor
parallel_fix status                    # Summary
parallel_fix status --verbose          # Detailed
parallel_fix status --repo owner/repo  # Specific

# Manage
parallel_fix sync-prs                  # Update PR states
parallel_fix retry --failed            # Retry failures
parallel_fix clean --completed         # Remove done repos
parallel_fix reset owner/repo --to pending

# Iterations
parallel_fix iterate --merged          # Force new iteration
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
- [ ] Smart retry logic
- [ ] Cleanup automation

## Benefits Summary

| Feature | Before | After |
|---------|--------|-------|
| Crash recovery | ❌ Lost all progress | ✅ Resume from last state |
| PR monitoring | ❌ Manual checking | ✅ Auto-sync from GitHub |
| Merged PRs | ❌ Manual cleanup | ✅ Auto-iterate or complete |
| Failures | ❌ Manual retry | ✅ Smart retry with backoff |
| Parallel safety | ⚠️ Basic semaphore | ✅ Database-backed queue |
| Debugging | ⚠️ Console logs | ✅ Persistent audit trail |
| Progress visibility | ⚠️ End summary only | ✅ Real-time status |

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
cd /workspace/batch-fixes
parallel_fix init
parallel_fix add repos.txt --task "Migrate to new API"
parallel_fix run --parallelism 8

# ... work happens ...
# ... system crashes ...

# Day 2: Resume seamlessly
parallel_fix run --parallelism 8  # Continues where it left off

# Day 3: Check status
parallel_fix status
# Output:
#   Total: 50
#   Complete: 15 | PR_MERGED: 20 | PR_OPEN: 10
#   Processing: 3 | Failed: 2

# Sync PR states
parallel_fix sync-prs

# Some PRs merged, auto-check for new work
parallel_fix iterate --merged
# → 5 repos need more work, starting iteration 2

# Clean up fully done repos
parallel_fix clean --completed
# → Removed 15 repos from queue

# Retry failures
parallel_fix retry --failed
```

## Questions to Consider

1. **SQLite in MoonBit**: Need binding or use FFI?
2. **Worker distribution**: Single machine or multi-machine?
3. **Webhook support**: GitHub webhooks for PR updates?
4. **UI/Dashboard**: Web interface for monitoring?
5. **Notification**: Email/Slack when batches complete?

## Implementation Status

### ✅ Phase 1: Foundation (Complete)

**SQLite Infrastructure**
- ✅ CLI-based SQLite wrapper (`x/sqlite/`)
  - `exec()`, `exec_string()`, `query()` with JSON support
  - `query_csv()`, `transaction()`, automatic sqlite3 detection
- ✅ Database schema with 5 tables
  - repositories, state_transitions, work_log, task_queue, config
  - Indexes for performance
- ✅ State manager with 20-state machine
  - `transition()`, `get_repos_in_state()`, `count_by_state()`
  - Automatic state transition logging

**CLI Subcommands**
- ✅ `init` - Initialize workspace and database
- ✅ `add` - Add repositories from file
- ✅ `status` - Show current state (with --verbose)
- ✅ `help` - Show subcommand documentation
- ✅ Subcommand routing using `stop_early=true`

**Quick Mode (Original)**
- ✅ Parallel processing with semaphores
- ✅ Two-phase AI workflow (WorkspaceWrite → DangerFullAccess)
- ✅ Git operations (clone, branch, commit, push, PR)
- ✅ Error handling and summary reporting

### 🚧 Phase 2: Reentrant Operations (In Progress)

- ✅ Worker with state-driven processing in `worker.mbt`
  - `process_repository_stateful()` with phase handlers
  - Reentrant clone (checks if already cloned)
  - Reentrant branch (checks if branch exists)
  - Reentrant commit (checks if changes exist)
- ✅ Individual phase handlers (clone, branch, fix, commit, push, PR)
- ✅ `run` subcommand with worker pool
  - Batch processing with semaphore-based concurrency
  - Retry logic with configurable max attempts
  - Error handling with state transitions to Retry
- ✅ Resume from last state on crash (all operations check current state)
- [ ] PR sync integration (requires testing with actual PRs)

### 📋 Phase 3: PR Integration (Planned)

- [ ] GitHub API integration via `gh api`
- [ ] `sync-prs` command to update PR states
- [ ] Handle review states (changes requested, approved)
- [ ] Conflict detection and resolution

### 🎯 Phase 4: Advanced Features (Planned)

- [ ] Automatic iterations after PR merge
- [ ] `retry --failed` with exponential backoff
- [ ] `clean --completed` to remove finished repos
- [ ] `reset` command to change repo state
- [ ] Cleanup automation

## Usage Examples

### Quick Mode (One-Off Batch Fix)

```bash
# Direct execution without persistence
moon run real_world/parallel_fix -- repos.txt \
  --task "Fix linting errors" \
  --parallelism 8
```

### Stateful Mode (Reentrant Processing)

```bash
# Initialize workspace
moon run real_world/parallel_fix -- init --work-dir /tmp/fixes

# Add repositories
moon run real_world/parallel_fix -- add repos.txt --task "Fix linting"

# Check status
moon run real_world/parallel_fix -- status --verbose

# Start/resume processing
moon run real_world/parallel_fix -- run --parallelism 8

# Sync PR states (planned)
# moon run real_world/parallel_fix -- sync-prs
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
