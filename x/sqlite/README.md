# SQLite Module - JSON Support

## Overview

The `x/sqlite` module now uses proper JSON parsing via `@json.parse()` instead of CSV parsing for structured queries.

## API Updates

### Query Functions

```moonbit
/// Query database and return results as JSON array
pub async fn Database::query(self : Database, sql : String) -> Array[Json]?

/// Query database and get a single row as JSON object  
pub async fn Database::query_one(self : Database, sql : String) -> Json?
```

### Usage Example

```moonbit
let db = @sqlite.Database::new("test.db")

// Query multiple rows
match db.query("SELECT * FROM users;") {
  Some(rows) => {
    for row in rows {
      // Pattern match on JSON objects
      guard row is Object({ "name": String(name), "age": Number(age, ..), .. }) else {
        continue
      }
      println("User: \{name}, Age: \{age}")
    }
  }
  None => println("Query failed")
}

// Query single row
match db.query_one("SELECT * FROM config WHERE key = 'version';") {
  Some(Object({ "value": String(version), .. })) => 
    println("Version: \{version}")
  _ => println("Not found")
}
```

## Benefits

✅ **Type-safe** - Pattern matching on JSON with compile-time checks  
✅ **Cleaner** - No manual CSV parsing or string splitting  
✅ **Robust** - Handles complex values (nulls, numbers, nested objects)  
✅ **Standard** - Uses MoonBit's built-in JSON library

## Migration from CSV

Old CSV approach (removed):
```moonbit
let rows = db.query_csv("SELECT * FROM table;")
// Returns Array[Array[String]] - manual parsing needed
```

New JSON approach:
```moonbit
let rows = db.query("SELECT * FROM table;")
// Returns Array[Json]? - pattern match directly
```
