///|
/// State manager for repository processing
/// This module handles database operations and state management

///|
/// State manager for repository processing
priv struct StateManager {
  db : @sqlite.Database
  db_lock : @semaphore.Semaphore // Semaphore with value 1 acts as a mutex
}

///|
/// Create a new state manager
fn StateManager::new(db_path : String) -> StateManager {
  StateManager::{
    db: @sqlite.Database::new(db_path),
    db_lock: @semaphore.Semaphore::new(1), // Only 1 concurrent DB operation
  }
}

///|
/// Initialize the database with schema
async fn StateManager::init(self : StateManager) -> Unit {
  self.db.exec(schema_sql) catch {
    e => @error.fail_with("Failed to initialize database schema", e)
  }

  // Run migration to handle deprecated states
  self.migrate_deprecated_states() catch {
    e => @error.fail_with("Failed to migrate deprecated states", e)
  }
}

///|
/// Migrate deprecated states to current states
/// This ensures backward compatibility with existing databases
async fn StateManager::migrate_deprecated_states(self : StateManager) -> Unit {
  let now = now()

  // Note: RETRY state is NOT migrated here
  // Worker code handles RETRY by inferring the actual state from set fields
  // This prevents losing progress (e.g., RETRY in BRANCHING shouldn't go back to PENDING)

  // First, recover any corrupted states caused by previous bad migrations
  // Check all PENDING repos - if they have fields set, they should be in a more advanced state
  self.recover_corrupted_states() catch {
    e =>
      @stdio.stderr.write("warning Failed to recover corrupted states: \{e}\n")
  }

  // Migrate deprecated PR states to PR_OPEN
  let pr_states = deprecated_pr_states()
  let mut pr_idx = 0
  while pr_idx < pr_states.length() {
    let old_state = pr_states[pr_idx]
    let pr_sql = "UPDATE repositories SET state = 'PR_OPEN', updated_at = '\{now}' WHERE state = '\{old_state}';"
    self.db.exec(pr_sql) catch {
      e => @error.reraise(e)
    }
    let pr_count_str = self.db.exec_string("SELECT changes();")
    let pr_count = @strconv.parse_int(pr_count_str.trim(chars=" \r\n\t")) catch {
      _ => 0
    }
    if pr_count > 0 {
      @stdio.stdout.write(
        "info Migrated \{pr_count} repositories from \{old_state} to PR_OPEN\n",
      )
    }
    pr_idx = pr_idx + 1
  }

  // Migrate deprecated intermediate states to FIXING
  let intermediate_states = deprecated_intermediate_states()
  let mut int_idx = 0
  while int_idx < intermediate_states.length() {
    let old_state = intermediate_states[int_idx]
    let int_sql = "UPDATE repositories SET state = 'FIXING', updated_at = '\{now}' WHERE state = '\{old_state}';"
    self.db.exec(int_sql) catch {
      e => @error.reraise(e)
    }
    let int_count_str = self.db.exec_string("SELECT changes();")
    let int_count = @strconv.parse_int(int_count_str.trim(chars=" \r\n\t")) catch {
      _ => 0
    }
    if int_count > 0 {
      @stdio.stdout.write(
        "info Migrated \{int_count} repositories from \{old_state} to FIXING\n",
      )
    }
    int_idx = int_idx + 1
  }
}

///|
/// Recover corrupted states caused by bad migrations
/// This checks if state matches the actual progress (based on set fields)
async fn StateManager::recover_corrupted_states(self : StateManager) -> Unit {
  let now = now()

  // Get all repos that might have corrupted states
  // A PENDING repo with fields set is likely corrupted
  let sql = "SELECT id, url, name, state, local_path, default_branch, current_branch, pr_url FROM repositories WHERE state IN ('PENDING', 'CLONING', 'BRANCHING');"
  let rows = self.db.query(sql)
  let mut recovered = 0
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "name": String(name),
          "state": String(current_state),
          "local_path"? : local_path,
          "default_branch"? : default_branch,
          "current_branch"? : current_branch,
          "pr_url"? : pr_url,
          ..
        }
      ) => {
        let repo_id = id.to_int()

        // Infer what state this repo should be in based on fields
        let has_pr_url = match pr_url {
          Some(String(url)) => !url.is_empty()
          _ => false
        }
        let has_current_branch = match current_branch {
          Some(String(b)) => !b.is_empty()
          _ => false
        }
        let has_default_branch = match default_branch {
          Some(String(db)) => !db.is_empty()
          _ => false
        }
        let has_local_path = match local_path {
          Some(String(lp)) => !lp.is_empty()
          _ => false
        }
        let inferred_state_enum = infer_state_from_fields(
          has_pr_url, has_current_branch, has_default_branch, has_local_path,
        )
        let inferred_state = inferred_state_enum.to_string()

        // Parse current state
        let current_state_enum = RepoState::from_str(current_state) catch {
          _ => Pending
        }

        // Check if recovery is needed
        let needs_recovery = needs_state_recovery(
          current_state_enum, inferred_state_enum,
        )
        if needs_recovery {
          @stdio.stdout.write(
            "info Recovering corrupted state for [\{name}]: \{current_state} → \{inferred_state}\n",
          )

          // Update to inferred state
          let update_sql = "UPDATE repositories SET state = '\{inferred_state}', updated_at = '\{now}' WHERE id = \{repo_id};"
          self.db.exec(update_sql) catch {
            e => {
              @stdio.stderr.write(
                "warning Failed to recover state for \{name}: \{e}\n",
              )
              continue
            }
          }

          // Log the recovery
          let log_sql = "INSERT INTO state_transitions (repo_id, from_state, to_state, timestamp, details) VALUES (\{repo_id}, '\{current_state}', '\{inferred_state}', '\{now}', 'Recovered from corrupted state');"
          self.db.exec(log_sql) catch {
            e =>
              @stdio.stderr.write(
                "warning Failed to log recovery for \{name}: \{e}\n",
              )
          }
          recovered = recovered + 1
        }
      }
      _ => continue
    }
  }
  if recovered > 0 {
    @stdio.stdout.write(
      "info Recovered \{recovered} repositories from corrupted states\n",
    )
  }
}

///|
/// Add a new repository to the database
async fn StateManager::add_repository(
  self : StateManager,
  url : String,
  name : String,
  task_description : String,
) -> Int? {
  let now = now()
  // Escape single quotes in strings to prevent SQL injection
  let escaped_url = escape_sql(url)
  let escaped_name = escape_sql(name)
  let escaped_task = escape_sql(task_description)

  // Use INSERT OR IGNORE to handle duplicate (url, task_description) pairs
  let sql = "INSERT OR IGNORE INTO repositories (url, name, state, task_description, created_at, updated_at) VALUES ('\{escaped_url}', '\{escaped_name}', 'PENDING', '\{escaped_task}', '\{now}', '\{now}');"
  self.db.exec(sql) catch {
    e => @error.fail_with("Failed to add repository \{url} to database", e)
  }

  // Get the last inserted row ID
  // If it was ignored (duplicate), last_insert_rowid() returns 0
  try {
    let id_str = self.db.exec_string("SELECT last_insert_rowid();")
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
/// Transition a repository to a new state
async fn StateManager::transition(
  self : StateManager,
  repo_id : Int,
  to_state : RepoState,
  details? : String,
) -> Unit {
  self.db_lock.acquire()
  defer self.db_lock.release()
  let now = now()
  let state_str = to_state.to_string()

  // Get current state for logging
  let from_state = self.get_repo_state_unlocked(repo_id).to_string() catch {
      e => @error.reraise(e)
    }

  // Update repository state
  let update_sql = "UPDATE repositories SET state = '\{state_str}', updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(update_sql) catch {
    e => @error.reraise(e)
  }

  // Log transition
  let details_sql = match details {
    Some(d) => {
      let escaped = escape_sql(d)
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
/// Get the current state of a repository (internal, no lock)
async fn StateManager::get_repo_state_unlocked(
  self : StateManager,
  repo_id : Int,
) -> RepoState {
  let sql = "SELECT state FROM repositories WHERE id = \{repo_id};"
  RepoState::from_str(self.db.exec_string(sql).trim(chars=" \r\n\t")) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get the current state of a repository
async fn StateManager::get_repo_state(
  self : StateManager,
  repo_id : Int,
) -> RepoState {
  self.db_lock.acquire()
  defer self.db_lock.release()
  self.get_repo_state_unlocked(repo_id) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get repositories in a specific state
async fn StateManager::get_repos_in_state(
  self : StateManager,
  state : RepoState,
) -> Array[RepositoryRecord] {
  let state_str = state.to_string()
  let sql = "SELECT id, url, name, state, task_description, pr_number, pr_url, pr_state, attempt_count, created_at, updated_at FROM repositories WHERE state = '\{state_str}';"
  let rows = self.db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "name": String(name),
          "state": String(state_str),
          "task_description"? : task_description,
          "pr_number"? : pr_number,
          "pr_url"? : pr_url,
          "pr_state"? : pr_state,
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          name,
          state: RepoState::from_str(state_str) catch {
            StrConvError(_) => Pending
          },
          local_path: None,
          default_branch: None,
          current_branch: None,
          task_description: if task_description is Some(String(s)) {
            Some(s)
          } else {
            None
          },
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          pr_url: match pr_url {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          pr_state: match pr_state {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
        })
      _ => continue
    }
  }
  repos
}

///|
/// Count repositories by state
async fn StateManager::count_by_state(
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
async fn StateManager::total_count(self : StateManager) -> Int {
  self.db.count("repositories")
}

///|
/// Get all unique tasks
async fn StateManager::get_all_tasks(self : StateManager) -> Array[String] {
  let sql = "SELECT DISTINCT task_description FROM repositories ORDER BY task_description;"
  let rows = self.db.query(sql)
  let tasks = []
  for row in rows {
    match row {
      Object({ "task_descriptin": String(task), .. }) => tasks.push(task)
      _ => continue
    }
  }
  tasks
}

///|
/// Count repositories by task and state
async fn StateManager::count_by_task_and_state(
  self : StateManager,
  task : String,
  state : RepoState,
) -> Int {
  let state_str = state.to_string()
  let escaped_task = escape_sql(task)
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
async fn StateManager::log(
  self : StateManager,
  repo_id : Int,
  level : String,
  message : String,
) -> Unit {
  self.db_lock.acquire()
  defer self.db_lock.release()
  let now = now()
  let escaped_level = escape_sql(level)
  let escaped_message = escape_sql(message)
  let sql = "INSERT INTO work_log (repo_id, timestamp, level, message) VALUES (\{repo_id}, '\{now}', '\{escaped_level}', '\{escaped_message}');"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Update repository field
async fn StateManager::update_field(
  self : StateManager,
  repo_id : Int,
  field : String,
  value : String,
) -> Unit {
  let now = now()
  let escaped_value = escape_sql(value)
  let sql = "UPDATE repositories SET \{field} = '\{escaped_value}', updated_at = '\{now}' WHERE id = \{repo_id};"
  self.db.exec(sql) catch {
    e => @error.reraise(e)
  }
}

///|
/// Get full repository record by ID
async fn StateManager::get_repository_full(
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
          "local_path"? : local_path,
          "default_branch"? : default_branch,
          "current_branch"? : current_branch,
          "task_description"? : task_description,
          "pr_number"? : pr_number,
          "pr_url"? : pr_url,
          "pr_state"? : pr_state,
          ..
        }
      )
    ) =>
      Some(RepositoryRecord::{
        id: id.to_int(),
        url,
        name,
        state: RepoState::from_str(state_str) catch {
          StrConvError(_) => Pending
        },
        local_path: match local_path {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
        default_branch: match default_branch {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
        current_branch: match current_branch {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
        task_description: match task_description {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
        pr_number: match pr_number {
          Some(Number(n, ..)) => Some(n.to_int())
          _ => None
        },
        pr_url: match pr_url {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
        pr_state: match pr_state {
          Some(String(s)) if !s.is_empty() => Some(s)
          _ => None
        },
      })
    _ => None
  }
}

///|
/// Get repository record by ID (alias for get_repository_full that raises error if not found)
async fn StateManager::get_repository(
  self : StateManager,
  repo_id : Int,
) -> RepositoryRecord {
  match self.get_repository_full(repo_id) {
    Some(repo) => repo
    None => @error.fail("Repository with id \{repo_id} not found")
  }
}

///|
/// Update multiple repository fields at once
async fn StateManager::update_repository(
  self : StateManager,
  repo_id : Int,
  updates : Array[(String, String)],
) -> Unit {
  if updates.is_empty() {
    return
  }
  self.db_lock.acquire()
  defer self.db_lock.release()
  let now = now()
  let set_clauses = []
  for update in updates {
    let (field, value) = update
    let escaped_value = escape_sql(value)
    set_clauses.push("\{field} = '\{escaped_value}'")
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
async fn StateManager::get_processable_repos(
  self : StateManager,
  limit : Int,
) -> Array[RepositoryRecord] {
  // Get all repositories that are not complete
  // This includes PR_OPEN repos which need to check their status
  let sql = "SELECT id, url, name, state, local_path, default_branch, current_branch, task_description, pr_number, pr_url, pr_state, attempt_count, iteration FROM repositories WHERE state != 'COMPLETE' ORDER BY created_at ASC LIMIT \{limit};"
  let rows = self.db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "name": String(name),
          "state": String(state_str),
          "local_path"? : local_path,
          "default_branch"? : default_branch,
          "current_branch"? : current_branch,
          "task_description"? : task_description,
          "pr_number"? : pr_number,
          "pr_url"? : pr_url,
          "pr_state"? : pr_state,
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          name,
          state: RepoState::from_str(state_str) catch {
            StrConvError(_) => Pending
          },
          local_path: match local_path {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          default_branch: match default_branch {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          current_branch: match current_branch {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          task_description: match task_description {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          pr_url: match pr_url {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          pr_state: match pr_state {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
        })
      _ => continue
    }
  }
  repos
}

///|
async fn StateManager::get_repos_with_pr(
  self : StateManager,
  limit : Int,
) -> Array[RepositoryRecord] {
  // Get all repositories that are not complete
  // This includes PR_OPEN repos which need to check their status
  let sql = "SELECT id, url, name, state, local_path, default_branch, current_branch, task_description, pr_number, pr_url, pr_state, attempt_count, iteration FROM repositories WHERE pr_url IS NOT NULL ORDER BY created_at ASC LIMIT \{limit};"
  let rows = self.db.query(sql)
  let repos = []
  for row in rows {
    match row {
      Object(
        {
          "id": Number(id, ..),
          "url": String(url),
          "name": String(name),
          "state": String(state_str),
          "local_path"? : local_path,
          "default_branch"? : default_branch,
          "current_branch"? : current_branch,
          "task_description"? : task_description,
          "pr_number"? : pr_number,
          "pr_url"? : pr_url,
          "pr_state"? : pr_state,
          ..
        }
      ) =>
        repos.push(RepositoryRecord::{
          id: id.to_int(),
          url,
          name,
          state: RepoState::from_str(state_str) catch {
            StrConvError(_) => Pending
          },
          local_path: match local_path {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          default_branch: match default_branch {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          current_branch: match current_branch {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          task_description: match task_description {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          pr_number: match pr_number {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          },
          pr_url: match pr_url {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
          pr_state: match pr_state {
            Some(String(s)) if !s.is_empty() => Some(s)
            _ => None
          },
        })
      _ => continue
    }
  }
  repos
}
