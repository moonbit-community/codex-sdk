///|
/// SQLite database schema and operations for PR tracking.

///|
/// PR status in database
enum PrStatus {
  Pending
  Reviewing
  Reviewed
  Failed
}

///|
fn PrStatus::to_string(self : PrStatus) -> String {
  match self {
    Pending => "pending"
    Reviewing => "reviewing"
    Reviewed => "reviewed"
    Failed => "failed"
  }
}

///|
fn PrStatus::from_string(s : String) -> PrStatus {
  match s {
    "pending" => Pending
    "reviewing" => Reviewing
    "reviewed" => Reviewed
    "failed" => Failed
    _ => Pending
  }
}

///|
/// Initialize the database schema
async fn init_db(db : @sqlite.Database) -> Unit {
  let schema =
    #|CREATE TABLE IF NOT EXISTS pull_requests (
    #|  pr_number INTEGER PRIMARY KEY,
    #|  title TEXT NOT NULL,
    #|  author TEXT NOT NULL,
    #|  status TEXT NOT NULL DEFAULT 'pending',
    #|  comment_id INTEGER,
    #|  error_message TEXT,
    #|  attempts INTEGER NOT NULL DEFAULT 0,
    #|  created_at TEXT NOT NULL,
    #|  updated_at TEXT NOT NULL
    #|);
    #|CREATE INDEX IF NOT EXISTS idx_pr_status ON pull_requests(status);
  db.exec(schema) catch {
    e => @error.fail_with("Failed to initialize database", e)
  }
}

///|
/// Upsert a PR into the database
async fn upsert_pr(
  db : @sqlite.Database,
  pr_number : Int,
  title : String,
  author : String,
) -> Unit {
  let escaped_title = escape_sql(title)
  let escaped_author = escape_sql(author)
  db.exec(
    "INSERT INTO pull_requests (pr_number, title, author, status, attempts, created_at, updated_at) VALUES (\{pr_number}, '\{escaped_title}', '\{escaped_author}', 'pending', 0, datetime('now'), datetime('now')) ON CONFLICT(pr_number) DO UPDATE SET title = '\{escaped_title}', author = '\{escaped_author}', updated_at = datetime('now');",
  ) catch {
    e => @error.fail_with("Failed to upsert PR #\{pr_number}", e)
  }
}

///|
/// Get PRs that need review (pending or failed with retries left)
async fn get_pending_prs(
  db : @sqlite.Database,
  max_attempts : Int,
) -> Array[Int] {
  let rows = db.query(
    "SELECT pr_number FROM pull_requests WHERE status = 'pending' OR (status = 'failed' AND attempts < \{max_attempts}) ORDER BY pr_number;",
  ) catch {
    e => @error.fail_with("Failed to query pending PRs", e)
  }
  rows.map(fn(row) {
    match row {
      { "pr_number": Number(n, ..), .. } => n.to_int()
      _ => @error.fail("Invalid row format")
    }
  })
}

///|
/// Update PR status
async fn update_pr_status(
  db : @sqlite.Database,
  pr_number : Int,
  status : PrStatus,
  comment_id : Int?,
  error_message : String?,
) -> Unit {
  let comment_sql = match comment_id {
    Some(id) => ", comment_id = \{id}"
    None => ""
  }
  let error_sql = match error_message {
    Some(msg) => ", error_message = '\{escape_sql(msg)}'"
    None => ""
  }
  db.exec(
    "UPDATE pull_requests SET status = '\{status.to_string()}', attempts = attempts + 1, updated_at = datetime('now')\{comment_sql}\{error_sql} WHERE pr_number = \{pr_number};",
  ) catch {
    e => @error.fail_with("Failed to update PR #\{pr_number} status", e)
  }
}

///|
/// Check if a PR has already been reviewed (has a comment)
async fn is_pr_reviewed(db : @sqlite.Database, pr_number : Int) -> Bool {
  let result = db.query_one(
    "SELECT comment_id FROM pull_requests WHERE pr_number = \{pr_number} AND status = 'reviewed' AND comment_id IS NOT NULL;",
  ) catch {
    _ => None
  }
  match result {
    Some(_) => true
    None => false
  }
}

///|
/// Get review statistics
async fn get_stats(db : @sqlite.Database) -> (Int, Int, Int, Int) {
  let pending = count_status(db, "pending")
  let reviewing = count_status(db, "reviewing")
  let reviewed = count_status(db, "reviewed")
  let failed = count_status(db, "failed")
  (pending, reviewing, reviewed, failed)
}

///|
async fn count_status(db : @sqlite.Database, status : String) -> Int {
  let result = db.exec_string(
    "SELECT COUNT(*) FROM pull_requests WHERE status = '\{status}';",
  ) catch {
    _ => "0"
  }
  @strconv.parse_int(result.trim(chars=" \t\n\r")) catch {
    _ => 0
  }
}

///|
/// Escape single quotes for SQL
fn escape_sql(s : String) -> String {
  s.replace_all(old="'", new="''")
}
