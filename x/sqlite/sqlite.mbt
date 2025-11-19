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
pub async fn ensure() -> Unit {
  let (status, data) = @process.collect_output_merged("which", ["sqlite3"]) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        #|Error: sqlite3 CLI not found. Please install SQLite to proceed.
        $|\{data.text()}
        #|
      ),
    )
  }
}

///|
/// Execute a SQL statement (no results expected)
/// Returns true if successful
pub async fn Database::exec(self : Database, sql : String) -> Unit {
  let (status, data) = @process.collect_output_merged("sqlite3", [
    self.path,
    sql,
  ]) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: \{data.text()}")
        $|SQL: \{sql}
        $|
      ),
    )
  }
}

///|
/// Execute a SQL statement and return output as string
/// Useful for single-value queries
pub async fn Database::exec_string(self : Database, sql : String) -> String {
  let (status, data) = @process.collect_output_merged("sqlite3", [
    self.path,
    sql,
  ]) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: \{data.text()}")
        $|SQL: \{sql}
        $|
      ),
    )
  }
  data.text()
}

///|
/// Query database and return results in JSON mode
/// Returns rows as array of objects
pub async fn Database::query(self : Database, sql : String) -> Array[Json] {
  // Use -json mode for structured output
  let (status, stdout, stderr) = @process.collect_output("sqlite3", [
    "-json",
    self.path,
    sql,
  ]) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: \{stdout.text()}\{stderr.text()}")
        $|SQL: \{sql}
        $|
      ),
    )
  }
  // Parse JSON array of objects
  let output = stdout.text()
  if output.is_blank() {
    return []
  }
  let json = @json.parse(output.trim(chars=" \t\r\n")) catch {
    e => @error.fail_with("Failed to parse: \{output}", e)
  }
  match json {
    Array(rows) => rows
    _ => @error.fail("Expected JSON array from query, got: \{json.stringify()}")
  }
}

///|
/// Query database and get a single row as JSON object
pub async fn Database::query_one(self : Database, sql : String) -> Json? {
  match self.query(sql) {
    [first, ..] => Some(first)
    _ => None
  }
}

///|
/// Execute SQL from a file
pub async fn Database::exec_file(
  self : Database,
  sql_file_path : String,
) -> Unit {
  // Read SQL file and execute commands line by line
  let content = @fs.read_file(sql_file_path).text() catch {
    e => @error.reraise(e)
  }

  // Execute all SQL at once
  self.exec(content)
}

///|
/// Check if database file exists
pub async fn Database::ensure(self : Database) -> Unit {
  if !(@fs.exists(self.path) catch { e => @error.reraise(e) }) {
    @error.fail("Database file not found at path: \{self.path}")
  }
}

///|
/// Get the number of rows from a table
pub async fn Database::count(self : Database, table : String) -> Int {
  let sql = "SELECT COUNT(*) FROM \{table};"
  let count_str = self.exec_string(sql).trim(chars=" \t\n\r")
  @strconv.from_str(count_str) catch {
    e => @error.reraise(e)
  }
}

///|
/// Begin a transaction
pub async fn Database::begin_transaction(self : Database) -> Unit {
  self.exec("BEGIN TRANSACTION;")
}

///|
/// Commit a transaction
pub async fn Database::commit(self : Database) -> Unit {
  self.exec("COMMIT;")
}

///|
/// Rollback a transaction
pub async fn Database::rollback(self : Database) -> Unit {
  self.exec("ROLLBACK;")
}

///|
/// Execute multiple SQL statements in a transaction
pub async fn Database::transaction(
  self : Database,
  statements : Array[String],
) -> Unit {
  self.begin_transaction()
  try {
    for stmt in statements {
      self.exec(stmt)
    }
    self.commit()
  } catch {
    e => {
      self.rollback() catch {
        e => @error.reraise(e)
      }
      @error.reraise(e)
    }
  }
}
