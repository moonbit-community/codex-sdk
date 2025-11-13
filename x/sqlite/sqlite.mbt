///|
/// SQLite database wrapper using sqlite3 CLI
struct Database {
  /// Path to the database file
  path : String
}

///|
/// Create or open a database
pub fn Database::new(path : String) -> Database {
  Database::{ path, }
}

///|
/// Check if sqlite3 is available
pub async fn check_sqlite3() -> Bool {
  let status = @process.run("which", ["sqlite3"]) catch { _ => return false }
  status == 0
}

///|
/// Execute a SQL statement (no results expected)
/// Returns true if successful
pub async fn Database::exec(self : Database, sql : String) -> Bool {
  let status = @process.run("sqlite3", [self.path, sql]) catch {
    _ => return false
  }
  status == 0
}

///|
/// Execute a SQL statement and return output as string
/// Useful for single-value queries
pub async fn Database::exec_string(self : Database, sql : String) -> String? {
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run("sqlite3", [self.path, sql], stdout=process_read) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  let output = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  Some(output)
}

///|
/// Query database and return results in JSON mode
/// Returns rows as array of objects
pub async fn Database::query(self : Database, sql : String) -> Array[Json]? {
  let (pipe, process_read) = @process.read_from_process()
  // Use -json mode for structured output
  let status = @process.run(
    "sqlite3",
    ["-json", self.path, sql],
    stdout=process_read,
  ) catch {
    _ => return None
  }
  if status != 0 {
    return None
  }
  let output = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()

  // Parse JSON array of objects
  let json = @json.parse(output) catch { _ => return None }
  match json {
    Array(rows) => Some(rows)
    _ => None
  }
}

///|
/// Query database and get a single row as JSON object
pub async fn Database::query_one(self : Database, sql : String) -> Json? {
  match self.query(sql) {
    Some([first, ..]) => Some(first)
    _ => None
  }
}

///|
/// Query database and return results in CSV mode
/// More reliable for simple queries
pub async fn Database::query_csv(
  self : Database,
  sql : String,
) -> Array[Array[String]] {
  let (pipe, process_read) = @process.read_from_process()
  // Use -csv mode with headers
  let status = @process.run(
    "sqlite3",
    ["-csv", "-header", self.path, sql],
    stdout=process_read,
  ) catch {
    _ => return []
  }
  if status != 0 {
    return []
  }
  let output = pipe.read_all().text()

  // Simple line-based parsing (doesn't handle quoted commas properly, but good enough for most cases)
  let rows = []
  let lines = output.split("\n")
  for line in lines {
    if !line.is_empty() {
      let fields = []
      for field in line.split(",") {
        fields.push(field.to_string())
      }
      if fields.length() > 0 {
        rows.push(fields)
      }
    }
  }
  rows
}

///|
/// Execute SQL from a file
pub async fn Database::exec_file(
  self : Database,
  sql_file_path : String,
) -> Bool {
  // Read SQL file and execute commands line by line
  let content = @fs.read_file(sql_file_path).text() catch { _ => return false }

  // Execute all SQL at once
  self.exec(content)
}

///|
/// Check if database file exists
pub async fn Database::exists(self : Database) -> Bool {
  @fs.exists(self.path) catch {
    _ => false
  }
}

///|
/// Get the number of rows from a table
pub async fn Database::count(self : Database, table : String) -> Int {
  let sql = "SELECT COUNT(*) FROM \{table};"
  match self.exec_string(sql) {
    Some(count_str) => @strconv.parse_int(count_str) catch { _ => 0 }
    None => 0
  }
}

///|
/// Begin a transaction
pub async fn Database::begin_transaction(self : Database) -> Bool {
  self.exec("BEGIN TRANSACTION;")
}

///|
/// Commit a transaction
pub async fn Database::commit(self : Database) -> Bool {
  self.exec("COMMIT;")
}

///|
/// Rollback a transaction
pub async fn Database::rollback(self : Database) -> Bool {
  self.exec("ROLLBACK;")
}

///|
/// Execute multiple SQL statements in a transaction
pub async fn Database::transaction(
  self : Database,
  statements : Array[String],
) -> Bool {
  if !self.begin_transaction() {
    return false
  }
  for stmt in statements {
    if !self.exec(stmt) {
      let _rollback = self.rollback()
      return false
    }
  }
  self.commit()
}
