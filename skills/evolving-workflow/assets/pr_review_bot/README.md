# PR Review Bot

Automated PR review workflow that reviews GitHub pull requests and posts comments, with SQLite state tracking for resume capability.

## What It Does

1. Fetches open PRs from a GitHub repository
2. Syncs PR list to SQLite database for state tracking
3. Reviews each PR using Codex (analyzes the diff)
4. Posts review comments to GitHub
5. Tracks which PRs have been reviewed to avoid duplicates

## Why SQLite?

The PR review creates external side effects (GitHub comments) that aren't reflected in local files. SQLite tracking ensures:

- **Resume after crash**: If killed mid-run, restart picks up where it left off
- **No duplicate comments**: Already-reviewed PRs are skipped
- **Retry failed reviews**: Failed PRs can be retried on next run
- **Audit trail**: Track when each PR was reviewed, by whom, with what result

## Usage

```bash
# Review all open PRs (dry run first!)
DRY_RUN=1 GITHUB_REPO=owner/repo moon run .

# Actually post reviews
GITHUB_REPO=owner/repo moon run .

# Custom database location
DB_PATH=./my_reviews.db GITHUB_REPO=owner/repo moon run .

# Lower parallelism to avoid rate limits
PARALLELISM=1 GITHUB_REPO=owner/repo moon run .
```

## Prerequisites

- `gh` CLI authenticated with GitHub
- `sqlite3` CLI installed

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_REPO` | Repository to review (owner/repo format) | **required** |
| `CODEX_WORKDIR` | Working directory for Codex | `.` |
| `PARALLELISM` | Max concurrent reviews | `2` |
| `MAX_RETRY` | Retry attempts for failed reviews | `2` |
| `DRY_RUN` | Analyze without posting comments | `false` |
| `DB_PATH` | SQLite database path | `./pr_reviews.db` |

## Database Schema

```sql
CREATE TABLE pull_requests (
  pr_number INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending, reviewing, reviewed, failed
  comment_id INTEGER,                        -- GitHub comment ID when posted
  error_message TEXT,                        -- Error details if failed
  attempts INTEGER NOT NULL DEFAULT 0,       -- Retry count
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

## Querying State

```bash
# See all reviewed PRs
sqlite3 pr_reviews.db "SELECT pr_number, title FROM pull_requests WHERE status='reviewed';"

# See failed PRs
sqlite3 pr_reviews.db "SELECT pr_number, error_message FROM pull_requests WHERE status='failed';"

# Reset failed PRs for retry
sqlite3 pr_reviews.db "UPDATE pull_requests SET status='pending', attempts=0 WHERE status='failed';"

# Check a specific PR
sqlite3 pr_reviews.db "SELECT * FROM pull_requests WHERE pr_number=123;"
```

## Customization

### Change Review Prompt

Edit `process.mbt` `run_review` function to change what Codex analyzes.

### Change Comment Format

Edit `post_review_comment` in `process.mbt`.

### Add Filters

Edit `fetch_and_sync_prs` in `tasks.mbt` to filter PRs (by label, author, etc.).

## File Structure

| File | Purpose |
|------|---------|
| `config.mbt` | Environment configuration |
| `db.mbt` | SQLite schema and operations |
| `tasks.mbt` | Fetch PRs from GitHub, sync to DB |
| `parallel.mbt` | Bounded concurrency helper |
| `process.mbt` | Review execution and comment posting |
| `main.mbt` | Orchestration with resume logic |

## Running Periodically

This bot is designed to be run periodically (e.g., via cron):

```bash
# Run every hour
0 * * * * cd /path/to/pr_review_bot && GITHUB_REPO=owner/repo moon run . >> /var/log/pr_review.log 2>&1
```

The SQLite database ensures each PR is only reviewed once, even across multiple runs.
