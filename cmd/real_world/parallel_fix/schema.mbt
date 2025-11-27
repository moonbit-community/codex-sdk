///|
/// Database schema for the parallel repository fixer

///|
/// SQL schema for creating all tables
/// Simplified: only tracks repository, task, pr_number, and completion status
let schema_sql : String =
  #|CREATE TABLE IF NOT EXISTS repositories (
  #|    id INTEGER PRIMARY KEY AUTOINCREMENT,
  #|    url TEXT NOT NULL,
  #|    task TEXT NOT NULL,
  #|    target_url TEXT NOT NULL,
  #|    pr_number INTEGER,
  #|    completed INTEGER NOT NULL DEFAULT 0,
  #|    created_at TEXT NOT NULL,
  #|    updated_at TEXT NOT NULL,
  #|    UNIQUE(url, task)
  #|);
  #|CREATE INDEX IF NOT EXISTS idx_repos_completed ON repositories(completed);
  #|CREATE INDEX IF NOT EXISTS idx_repos_url ON repositories(url);
  #|
