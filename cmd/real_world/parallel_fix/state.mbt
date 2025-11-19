///|
/// Simplified database operations for repository tracking

///|
/// Add a new repository to the database
async fn add_repository(
  db : @sqlite.Database,
  url : String,
  task : String,
) -> Int? {
  let now = @async.now()
  let escaped_url = escape_sql(url)
  let escaped_task = escape_sql(task)

  // Use INSERT OR IGNORE to handle duplicate (url, task) pairs
  let sql = "INSERT OR IGNORE INTO repositories (url, task, completed, created_at, updated_at) VALUES ('\{escaped_url}', '\{escaped_task}', 0, '\{now}', '\{now}');"
  db.exec(sql) catch {
    e => @error.fail_with("Failed to add repository \{url} to database", e)
  }

  // Get the last inserted row ID
  try {
    let id_str = db.exec_string("SELECT last_insert_rowid();")
    let id = @strconv.parse_int(id_str.trim(chars=" \r\n\t"))
    if id == 0 {
      None // Was a duplicate
    } else {
      Some(id) // New insertion
    }
  } catch {
    e => @error.reraise(e)
  }
}

///|
/// Get all repositories that are not completed
async fn get_incomplete_repos(db : @sqlite.Database) -> Array[RepositoryRecord] {
  let sql = "SELECT id, url, task, pr_number, completed FROM repositories WHERE completed = 0 ORDER BY created_at ASC;"
  let rows = db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "task": String(task),
          "pr_number"? : pr_number,
          "completed": Number(completed, ..),
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          task,
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          completed: completed.to_int() != 0,
        })
      _ => continue
    }
  }
  repos
}

///|
/// Mark a repository as completed
async fn mark_completed(db : @sqlite.Database, repo_id : Int) -> Unit {
  let now = @async.now()
  let sql = "UPDATE repositories SET completed = 1, updated_at = '\{now}' WHERE id = \{repo_id};"
  db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Mark a repository as incomplete
async fn mark_incomplete(db : @sqlite.Database, repo_id : Int) -> Unit {
  let now = @async.now()
  let sql = "UPDATE repositories SET completed = 0, updated_at = '\{now}' WHERE id = \{repo_id};"
  db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Update PR number for a repository
async fn update_pr_number(
  db : @sqlite.Database,
  repo_id : Int,
  pr_number : Int,
) -> Unit {
  let now = @async.now()
  let sql = "UPDATE repositories SET pr_number = \{pr_number}, updated_at = '\{now}' WHERE id = \{repo_id};"
  db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get total repository count
async fn total_count(db : @sqlite.Database) -> Int {
  db.count("repositories")
}

///|
/// Count completed repositories
async fn count_completed(db : @sqlite.Database) -> Int {
  let sql = "SELECT COUNT(*) FROM repositories WHERE completed = 1;"
  @strconv.parse_int(db.exec_string(sql).trim(chars=" \t\r\n")) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get all repositories for status display
async fn get_all_repos(db : @sqlite.Database) -> Array[RepositoryRecord] {
  let sql = "SELECT id, url, task, pr_number, completed FROM repositories ORDER BY completed ASC, created_at ASC;"
  let rows = db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "task": String(task),
          "pr_number"? : pr_number,
          "completed": Number(completed, ..),
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          task,
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          completed: completed.to_int() != 0,
        })
      _ => continue
    }
  }
  repos
}
