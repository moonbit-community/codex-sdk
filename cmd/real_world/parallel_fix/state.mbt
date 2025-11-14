///|
/// State management for repository processing

///|
/// Repository processing states
pub enum RepoState {
  Pending
  Cloning
  Cloned
  Branching
  Branched
  Fixing
  Fixed
  Committing
  Committed
  Pushing
  Pushed
  PrCreating
  PrOpen
  PrChangesRequested
  PrApproved
  PrConflicts
  PrMerged
  Complete
  Failed
  Retry
} derive(Show, Eq)

///|
/// Convert RepoState to string for database storage
pub fn RepoState::to_string(self : RepoState) -> String {
  match self {
    Pending => "PENDING"
    Cloning => "CLONING"
    Cloned => "CLONED"
    Branching => "BRANCHING"
    Branched => "BRANCHED"
    Fixing => "FIXING"
    Fixed => "FIXED"
    Committing => "COMMITTING"
    Committed => "COMMITTED"
    Pushing => "PUSHING"
    Pushed => "PUSHED"
    PrCreating => "PR_CREATING"
    PrOpen => "PR_OPEN"
    PrChangesRequested => "PR_CHANGES_REQUESTED"
    PrApproved => "PR_APPROVED"
    PrConflicts => "PR_CONFLICTS"
    PrMerged => "PR_MERGED"
    Complete => "COMPLETE"
    Failed => "FAILED"
    Retry => "RETRY"
  }
}

///|
/// Parse RepoState from string
pub fn RepoState::from_string(s : String) -> RepoState? {
  match s {
    "PENDING" => Some(Pending)
    "CLONING" => Some(Cloning)
    "CLONED" => Some(Cloned)
    "BRANCHING" => Some(Branching)
    "BRANCHED" => Some(Branched)
    "FIXING" => Some(Fixing)
    "FIXED" => Some(Fixed)
    "COMMITTING" => Some(Committing)
    "COMMITTED" => Some(Committed)
    "PUSHING" => Some(Pushing)
    "PUSHED" => Some(Pushed)
    "PR_CREATING" => Some(PrCreating)
    "PR_OPEN" => Some(PrOpen)
    "PR_CHANGES_REQUESTED" => Some(PrChangesRequested)
    "PR_APPROVED" => Some(PrApproved)
    "PR_CONFLICTS" => Some(PrConflicts)
    "PR_MERGED" => Some(PrMerged)
    "COMPLETE" => Some(Complete)
    "FAILED" => Some(Failed)
    "RETRY" => Some(Retry)
    _ => None
  }
}

///|
/// Repository record from database
pub struct RepositoryRecord {
  id : Int
  url : String
  name : String
  state : RepoState
  local_path : String?
  default_branch : String?
  current_branch : String?
  task_description : String?
  pr_number : Int?
  pr_url : String?
  pr_state : String?
  thread_id : String?
  attempt_count : Int
  last_error : String?
  iteration : Int
  created_at : String
  updated_at : String
}

///|
/// State manager for repository processing
pub struct StateManager {
  db : @sqlite.Database
}

///|
/// Create a new state manager
pub fn StateManager::new(db_path : String) -> StateManager {
  StateManager::{ db: @sqlite.Database::new(db_path) }
}

///|
/// Initialize the database with schema
pub async fn StateManager::init(self : StateManager) -> Unit {
  self.db.exec(schema_sql) catch {
    e => @error.fail_with("Failed to initialize database schema", e)
  }
}

///|
/// Add a new repository to the database
pub async fn StateManager::add_repository(
  self : StateManager,
  url : String,
  name : String,
  task_description : String,
) -> Int? {
  let now = now()
  // Escape single quotes in strings to prevent SQL injection
  let escaped_url = url.replace(old="'", new="''")
  let escaped_name = name.replace(old="'", new="''")
  let escaped_task = task_description.replace(old="'", new="''")

  // Use INSERT OR IGNORE to handle duplicate (url, task_description) pairs
  let sql = "INSERT OR IGNORE INTO repositories (url, name, state, task_description, created_at, updated_at) VALUES ('\{escaped_url}', '\{escaped_name}', 'PENDING', '\{escaped_task}', '\{now}', '\{now}');"
  self.db.exec(sql) catch {
    e => @error.fail_with("Failed to add repository \{url} to database", e)
  }

  // Get the last inserted row ID
  // If it was ignored (duplicate), last_insert_rowid() returns 0
  let id_str = self.db.exec_string("SELECT last_insert_rowid();")
  let id = @strconv.parse_int(id_str) catch { e => @error.reraise(e) }
  if id == 0 {
    None // Was a duplicate
  } else {
    Some(id) // New insertion
  }
}

///|
/// Transition a repository to a new state
pub async fn StateManager::transition(
  self : StateManager,
  repo_id : Int,
  to_state : RepoState,
  details : String?,
) -> Unit {
  let now = now()
  let state_str = to_state.to_string()

  // Get current state for logging
  let from_state = match self.get_repo_state(repo_id) {
    Some(state) => state.to_string()
    None => "NULL"
  }

  // Update repository state
  let update_sql = "UPDATE repositories SET state = '\{state_str}', updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(update_sql) catch {
    e => @error.reraise(e)
  }

  // Log transition
  let details_sql = match details {
    Some(d) => {
      let escaped = d.replace(old="'", new="''")
      "'\{escaped}'"
    }
    None => "NULL"
  }
  let log_sql = "INSERT INTO state_transitions (repo_id, from_state, to_state, timestamp, details) VALUES (\{repo_id}, '\{from_state}', '\{state_str}', '\{now}', \{details_sql});"
  self.db.exec(log_sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get the current state of a repository
pub async fn StateManager::get_repo_state(
  self : StateManager,
  repo_id : Int,
) -> RepoState? {
  let sql = "SELECT state FROM repositories WHERE id = \{repo_id};"
  RepoState::from_string(self.db.exec_string(sql))
}

///|
/// Get repositories in a specific state
pub async fn StateManager::get_repos_in_state(
  self : StateManager,
  state : RepoState,
) -> Array[RepositoryRecord] {
  let state_str = state.to_string()
  let sql = "SELECT id, url, name, state, task_description, attempt_count, last_error, created_at, updated_at FROM repositories WHERE state = '\{state_str}';"
  let rows = self.db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(Number(n, ..)) => n.to_int()
          _ => continue
        }
        let url = match obj.get("url") {
          Some(String(s)) => s
          _ => continue
        }
        let name = match obj.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let state_str = match obj.get("state") {
          Some(String(s)) => s
          _ => continue
        }
        let task_description = match obj.get("task_description") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let attempt_count = match obj.get("attempt_count") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let last_error = match obj.get("last_error") {
          Some(String(s)) => Some(s)
          _ => None
        }
        let created_at = match obj.get("created_at") {
          Some(String(s)) => s
          _ => ""
        }
        let updated_at = match obj.get("updated_at") {
          Some(String(s)) => s
          _ => ""
        }
        let repo_state = RepoState::from_string(state_str).unwrap_or(Pending)
        repos.push(RepositoryRecord::{
          id,
          url,
          name,
          state: repo_state,
          local_path: None,
          default_branch: None,
          current_branch: None,
          task_description,
          pr_number: None,
          pr_url: None,
          pr_state: None,
          thread_id: None,
          attempt_count,
          iteration: 1,
          last_error,
          created_at,
          updated_at,
        })
      }
      _ => continue
    }
  }
  repos
}

///|
/// Count repositories by state
pub async fn StateManager::count_by_state(
  self : StateManager,
  state : RepoState,
) -> Int {
  let state_str = state.to_string()
  let sql = "SELECT COUNT(*) FROM repositories WHERE state = '\{state_str}';"
  @strconv.parse_int(self.db.exec_string(sql).trim(chars=" \t\r\n")) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get total repository count
pub async fn StateManager::total_count(self : StateManager) -> Int {
  self.db.count("repositories")
}

///|
/// Get all unique tasks
pub async fn StateManager::get_all_tasks(self : StateManager) -> Array[String] {
  let sql = "SELECT DISTINCT task_description FROM repositories ORDER BY task_description;"
  let rows = self.db.query(sql)
  let tasks = []
  for row in rows {
    match row {
      Object(obj) =>
        match obj.get("task_description") {
          Some(String(task)) => tasks.push(task)
          _ => continue
        }
      _ => continue
    }
  }
  tasks
}

///|
/// Count repositories by task and state
pub async fn StateManager::count_by_task_and_state(
  self : StateManager,
  task : String,
  state : RepoState,
) -> Int {
  let state_str = state.to_string()
  let escaped_task = task.replace(old="'", new="''")
  let sql = "SELECT COUNT(*) FROM repositories WHERE task_description = '\{escaped_task}' AND state = '\{state_str}';"
  let result = self.db.exec_string(sql) catch { e => @error.reraise(e) }
  @strconv.from_str(result.trim(chars=" \t\r\n")) catch {
    @strconv.StrConvError(e) =>
      @error.fail_with(
        "Failed to parse count \{result} for task \{escaped_task} and state \{state_str}",
        Failure(e),
      )
  }
}

///|
/// Log a work message
pub async fn StateManager::log(
  self : StateManager,
  repo_id : Int,
  level : String,
  message : String,
) -> Unit {
  let now = now()
  let escaped_level = level.replace(old="'", new="''")
  let escaped_message = message.replace(old="'", new="''")
  let sql = "INSERT INTO work_log (repo_id, timestamp, level, message) VALUES (\{repo_id}, '\{now}', '\{escaped_level}', '\{escaped_message}');"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Update repository field
pub async fn StateManager::update_field(
  self : StateManager,
  repo_id : Int,
  field : String,
  value : String,
) -> Unit {
  let now = now()
  let escaped_value = value.replace(old="'", new="''")
  let sql = "UPDATE repositories SET \{field} = '\{escaped_value}', updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Increment attempt count
pub async fn StateManager::increment_attempts(
  self : StateManager,
  repo_id : Int,
) -> Unit {
  let now = now()
  let sql = "UPDATE repositories SET attempt_count = attempt_count + 1, updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get full repository record by ID
pub async fn StateManager::get_repository_full(
  self : StateManager,
  repo_id : Int,
) -> RepositoryRecord? {
  let sql = "SELECT id, url, name, state, local_path, default_branch, current_branch, task_description, pr_number, pr_url, pr_state, thread_id, attempt_count, last_error, iteration, created_at, updated_at FROM repositories WHERE id = \{repo_id};"
  match self.db.query_one(sql) {
    Some(
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "name": String(name),
          "state": String(state_str),
          "local_path": local_path,
          "default_branch": default_branch,
          "current_branch": current_branch,
          "task_description": task_description,
          "pr_number": pr_number,
          "pr_url": pr_url,
          "pr_state": pr_state,
          "thread_id": thread_id,
          "attempt_count": Number(attempt_count, ..),
          "last_error": last_error,
          "iteration": Number(iteration, ..),
          "created_at": String(created_at),
          "updated_at": String(updated_at),
          ..
        }
      )
    ) => {
      let state = RepoState::from_string(state_str).unwrap_or(Pending)
      let local_path = match local_path {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let default_branch = match default_branch {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let current_branch = match current_branch {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let task_description = match task_description {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let pr_number = match pr_number {
        Number(n, ..) => Some(n.to_int())
        Null => None
        _ => panic()
      }
      let pr_url = match pr_url {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let pr_state = match pr_state {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let thread_id = match thread_id {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      let last_error = match last_error {
        String(s) if !s.is_empty() => Some(s)
        Null => None
        _ => panic()
      }
      Some(RepositoryRecord::{
        id: id.to_int(),
        url,
        name,
        state,
        local_path,
        default_branch,
        current_branch,
        task_description,
        pr_number,
        pr_url,
        pr_state,
        thread_id,
        attempt_count: attempt_count.to_int(),
        last_error,
        iteration: iteration.to_int(),
        created_at,
        updated_at,
      })
    }
    _ => None
  }
}

///|
/// Update multiple repository fields at once
pub async fn StateManager::update_repository(
  self : StateManager,
  repo_id : Int,
  updates : Array[(String, String)],
) -> Unit {
  if updates.is_empty() {
    return
  }
  let now = now()
  let set_clauses = []
  for update in updates {
    let (field, value) = update
    set_clauses.push("\{field} = '\{value}'")
  }
  set_clauses.push("updated_at = '\{now}'")
  let separator = ", "
  let joined = set_clauses.join(separator)
  let sql = "UPDATE repositories SET \{joined} WHERE id = \{repo_id};"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get pending or retry repositories for processing
pub async fn StateManager::get_processable_repos(
  self : StateManager,
  limit : Int,
  include_failed : Bool,
) -> Array[RepositoryRecord] {
  let states = if include_failed {
    "('PENDING', 'RETRY', 'CLONED', 'BRANCHED', 'FIXED', 'COMMITTED', 'PUSHED', 'FAILED')"
  } else {
    "('PENDING', 'RETRY', 'CLONED', 'BRANCHED', 'FIXED', 'COMMITTED', 'PUSHED')"
  }
  let sql = "SELECT id, url, name, state, local_path, default_branch, current_branch, task_description, attempt_count, iteration FROM repositories WHERE state IN \{states} ORDER BY attempt_count ASC, created_at ASC LIMIT \{limit};"
  let rows = self.db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(Number(n, ..)) => n.to_int()
          _ => continue
        }
        let url = match obj.get("url") {
          Some(String(s)) => s
          _ => continue
        }
        let name = match obj.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let state_str = match obj.get("state") {
          Some(String(s)) => s
          _ => continue
        }
        let state = RepoState::from_string(state_str).unwrap_or(Pending)
        let local_path = match obj.get("local_path") {
          Some(String(s)) if !s.is_empty() => Some(s)
          Some(Null) | None => None
          _ => None
        }
        let default_branch = match obj.get("default_branch") {
          Some(String(s)) if !s.is_empty() => Some(s)
          Some(Null) | None => None
          _ => None
        }
        let current_branch = match obj.get("current_branch") {
          Some(String(s)) if !s.is_empty() => Some(s)
          Some(Null) | None => None
          _ => None
        }
        let task_description = match obj.get("task_description") {
          Some(String(s)) if !s.is_empty() => Some(s)
          Some(Null) | None => None
          _ => None
        }
        let attempt_count = match obj.get("attempt_count") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let iteration = match obj.get("iteration") {
          Some(Number(n, ..)) => n.to_int()
          _ => 1
        }
        repos.push(RepositoryRecord::{
          id,
          url,
          name,
          state,
          local_path,
          default_branch,
          current_branch,
          task_description,
          pr_number: None,
          pr_url: None,
          pr_state: None,
          thread_id: None,
          attempt_count,
          last_error: None,
          iteration,
          created_at: "",
          updated_at: "",
        })
      }
      _ => continue
    }
  }
  repos
}
