///|
/// Database schema for the parallel repository fixer

///|
/// SQL schema for creating all tables
pub let schema_sql : String =
  #|CREATE TABLE IF NOT EXISTS repositories (
  #|    id INTEGER PRIMARY KEY AUTOINCREMENT,
  #|    url TEXT NOT NULL,
  #|    name TEXT NOT NULL,
  #|    task_description TEXT NOT NULL,
  #|    state TEXT NOT NULL,
  #|    created_at TEXT NOT NULL,
  #|    updated_at TEXT NOT NULL,
  #|    local_path TEXT,
  #|    default_branch TEXT,
  #|    current_branch TEXT,
  #|    pr_number INTEGER,
  #|    pr_url TEXT,
  #|    pr_state TEXT,
  #|    thread_id TEXT,
  #|    attempt_count INTEGER DEFAULT 0,
  #|    last_error TEXT,
  #|    last_success_at TEXT,
  #|    iteration INTEGER DEFAULT 1,
  #|    metadata TEXT,
  #|    UNIQUE(url, task_description)
  #|);
  #|CREATE TABLE IF NOT EXISTS state_transitions (
  #|    id INTEGER PRIMARY KEY AUTOINCREMENT,
  #|    repo_id INTEGER NOT NULL,
  #|    from_state TEXT,
  #|    to_state TEXT NOT NULL,
  #|    timestamp TEXT NOT NULL,
  #|    details TEXT,
  #|    FOREIGN KEY (repo_id) REFERENCES repositories(id)
  #|);
  #|CREATE TABLE IF NOT EXISTS work_log (
  #|    id INTEGER PRIMARY KEY AUTOINCREMENT,
  #|    repo_id INTEGER NOT NULL,
  #|    timestamp TEXT NOT NULL,
  #|    level TEXT NOT NULL,
  #|    message TEXT NOT NULL,
  #|    context TEXT,
  #|    FOREIGN KEY (repo_id) REFERENCES repositories(id)
  #|);
  #|CREATE TABLE IF NOT EXISTS task_queue (
  #|    id INTEGER PRIMARY KEY AUTOINCREMENT,
  #|    repo_id INTEGER NOT NULL UNIQUE,
  #|    priority INTEGER DEFAULT 0,
  #|    scheduled_at TEXT,
  #|    started_at TEXT,
  #|    completed_at TEXT,
  #|    worker_id TEXT,
  #|    FOREIGN KEY (repo_id) REFERENCES repositories(id)
  #|);
  #|CREATE TABLE IF NOT EXISTS config (
  #|    key TEXT PRIMARY KEY,
  #|    value TEXT NOT NULL,
  #|    updated_at TEXT NOT NULL
  #|);
  #|CREATE INDEX IF NOT EXISTS idx_repos_state ON repositories(state);
  #|CREATE INDEX IF NOT EXISTS idx_repos_updated ON repositories(updated_at);
  #|CREATE INDEX IF NOT EXISTS idx_repos_url ON repositories(url);
  #|CREATE INDEX IF NOT EXISTS idx_repos_task ON repositories(task_description);
  #|CREATE INDEX IF NOT EXISTS idx_queue_priority ON task_queue(priority DESC, scheduled_at);
  #|CREATE INDEX IF NOT EXISTS idx_transitions_repo ON state_transitions(repo_id, timestamp);
  #|CREATE INDEX IF NOT EXISTS idx_log_repo ON work_log(repo_id, timestamp);
  #|

///|
/// Get current timestamp in ISO 8601 format
pub fn now() -> String {
  // Use Unix timestamp for now (simplified)
  // TODO: Use proper ISO 8601 formatting when datetime library is available
  @async.now().to_string()
}
