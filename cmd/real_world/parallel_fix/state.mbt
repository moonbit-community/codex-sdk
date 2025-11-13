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
pub async fn StateManager::init(self : StateManager) -> Bool {
  self.db.exec(schema_sql)
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
  let sql = "INSERT INTO repositories (url, name, state, task_description, created_at, updated_at) VALUES ('\{url}', '\{name}', 'PENDING', '\{task_description}', '\{now}', '\{now}');"
  if !self.db.exec(sql) {
    return None
  }

  // Get the last inserted row ID
  match self.db.exec_string("SELECT last_insert_rowid();") {
    Some(id_str) => {
      let id = @strconv.parse_int(id_str) catch { _ => return None }
      Some(id)
    }
    None => None
  }
}

///|
/// Transition a repository to a new state
pub async fn StateManager::transition(
  self : StateManager,
  repo_id : Int,
  to_state : RepoState,
  details : String?,
) -> Bool {
  let now = now()
  let state_str = to_state.to_string()

  // Get current state for logging
  let from_state = match self.get_repo_state(repo_id) {
    Some(state) => state.to_string()
    None => "NULL"
  }

  // Update repository state
  let update_sql = "UPDATE repositories SET state = '\{state_str}', updated_at = '\{now}' WHERE id = \{repo_id};"
  if !self.db.exec(update_sql) {
    return false
  }

  // Log transition
  let details_sql = match details {
    Some(d) => "'\{d}'"
    None => "NULL"
  }
  let log_sql = "INSERT INTO state_transitions (repo_id, from_state, to_state, timestamp, details) VALUES (\{repo_id}, '\{from_state}', '\{state_str}', '\{now}', \{details_sql});"
  self.db.exec(log_sql)
}

///|
/// Get the current state of a repository
pub async fn StateManager::get_repo_state(
  self : StateManager,
  repo_id : Int,
) -> RepoState? {
  let sql = "SELECT state FROM repositories WHERE id = \{repo_id};"
  match self.db.exec_string(sql) {
    Some(state_str) => RepoState::from_string(state_str)
    None => None
  }
}

///|
/// Get repositories in a specific state
pub async fn StateManager::get_repos_in_state(
  self : StateManager,
  state : RepoState,
) -> Array[RepositoryRecord] {
  let state_str = state.to_string()
  let sql = "SELECT id, url, name, state FROM repositories WHERE state = '\{state_str}';"
  let rows = self.db.query_csv(sql)
  let repos = []
  // Skip header row (index 0)
  for i = 1; i < rows.length(); i = i + 1 {
    let row = rows[i]
    if row.length() >= 4 {
      let id = @strconv.parse_int(row[0]) catch { _ => continue 0 }
      let repo_state = RepoState::from_string(row[3]).unwrap_or(Pending)
      repos.push(RepositoryRecord::{
        id,
        url: row[1],
        name: row[2],
        state: repo_state,
        local_path: None,
        default_branch: None,
        current_branch: None,
        task_description: None,
        pr_number: None,
        pr_url: None,
        pr_state: None,
        thread_id: None,
        attempt_count: 0,
        iteration: 1,
        last_error: None,
        created_at: "",
        updated_at: "",
      })
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
  match self.db.exec_string(sql) {
    Some(count_str) => @strconv.parse_int(count_str) catch { _ => 0 }
    None => 0
  }
}

///|
/// Get total repository count
pub async fn StateManager::total_count(self : StateManager) -> Int {
  self.db.count("repositories")
}

///|
/// Log a work message
pub async fn StateManager::log(
  self : StateManager,
  repo_id : Int,
  level : String,
  message : String,
) -> Bool {
  let now = now()
  let sql = "INSERT INTO work_log (repo_id, timestamp, level, message) VALUES (\{repo_id}, '\{now}', '\{level}', '\{message}');"
  self.db.exec(sql)
}

///|
/// Update repository field
pub async fn StateManager::update_field(
  self : StateManager,
  repo_id : Int,
  field : String,
  value : String,
) -> Bool {
  let now = now()
  let sql = "UPDATE repositories SET \{field} = '\{value}', updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(sql)
}

///|
/// Increment attempt count
pub async fn StateManager::increment_attempts(
  self : StateManager,
  repo_id : Int,
) -> Bool {
  let now = now()
  let sql = "UPDATE repositories SET attempt_count = attempt_count + 1, updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(sql)
}
