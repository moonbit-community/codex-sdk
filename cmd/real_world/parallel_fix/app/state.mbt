///|
/// Simplified database operations for repository tracking

///|
/// Add a new repository to the database
async fn add_repository(
  db : @sqlite.Database,
  url : String,
  task : String,
  task_title : String?,
) -> Int? {
  let now = @async.now()
  let escaped_url = escape_sql(url)
  let escaped_task = escape_sql(task)
  let escaped_task_title = task_title.map(fn(title) { escape_sql(title) })
  let escaped_target_url = escape_sql(url)
  let task_title_sql = match escaped_task_title {
    Some(title) => "'\{title}'"
    None => "NULL"
  }

  // Use INSERT OR IGNORE to handle duplicate (url, task) pairs
  let sql =
    $|INSERT OR IGNORE INTO repositories (url, task, task_title, target_url, completed, created_at, updated_at) VALUES ('\{escaped_url}', '\{escaped_task}', \{task_title_sql}, '\{escaped_target_url}', 0, '\{now}', '\{now}');
    $|SELECT last_insert_rowid();
    $|
  let id_str = db.exec_string(sql) catch {
    e => @error.fail_with("Failed to add repository \{url} to database", e)
  }

  // Get the last inserted row ID
  try {
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
  let sql = "SELECT id, url, task, task_title, target_url, pr_number, last_pr_head_sha, last_pr_comment_count, completed FROM repositories WHERE completed = 0 ORDER BY created_at ASC;"
  let rows = db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "task": String(task),
          "task_title"? : task_title,
          "target_url": String(target_url),
          "pr_number"? : pr_number,
          "last_pr_head_sha"? : last_pr_head_sha,
          "last_pr_comment_count"? : last_pr_comment_count,
          "completed": Number(completed, ..),
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          task,
          task_title: match task_title {
            Some(String(value)) => Some(value)
            _ => None
          },
          target_url,
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          last_pr_head_sha: match last_pr_head_sha {
            Some(String(value)) => Some(value)
            _ => None
          },
          last_pr_comment_count: match last_pr_comment_count {
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
/// Update target URL for a repository
async fn update_target_url(
  db : @sqlite.Database,
  repo_id : Int,
  target_url : String,
) -> Unit {
  let now = @async.now()
  let escaped_target_url = escape_sql(target_url)
  let sql = "UPDATE repositories SET target_url = '\{escaped_target_url}', updated_at = '\{now}' WHERE id = \{repo_id};"
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
  let sql = "SELECT id, url, task, task_title, target_url, pr_number, last_pr_head_sha, last_pr_comment_count, completed FROM repositories ORDER BY completed ASC, created_at ASC;"
  let rows = db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "task": String(task),
          "task_title"? : task_title,
          "target_url": String(target_url),
          "pr_number"? : pr_number,
          "last_pr_head_sha"? : last_pr_head_sha,
          "last_pr_comment_count"? : last_pr_comment_count,
          "completed": Number(completed, ..),
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          task,
          task_title: match task_title {
            Some(String(value)) => Some(value)
            _ => None
          },
          target_url,
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          last_pr_head_sha: match last_pr_head_sha {
            Some(String(value)) => Some(value)
            _ => None
          },
          last_pr_comment_count: match last_pr_comment_count {
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
/// Save a codex session ID for a repository task
async fn save_codex_session(
  db : @sqlite.Database,
  repo_id : Int,
  session_id : String,
) -> Unit {
  let now = @async.now()
  let escaped_session_id = escape_sql(session_id)
  let sql = "INSERT INTO codex_sessions (repository_id, session_id, created_at) VALUES (\{repo_id}, '\{escaped_session_id}', '\{now}');"
  db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Update cached PR metadata for a repository
async fn update_pr_cache(
  db : @sqlite.Database,
  repo_id : Int,
  head_sha : String,
  comment_count : Int,
) -> Unit {
  let now = @async.now()
  let escaped_head_sha = escape_sql(head_sha)
  let sql = "UPDATE repositories SET last_pr_head_sha = '\{escaped_head_sha}', last_pr_comment_count = \{comment_count}, updated_at = '\{now}' WHERE id = \{repo_id};"
  db.exec(sql) catch {
    e => @error.reraise(e)
  }
}
