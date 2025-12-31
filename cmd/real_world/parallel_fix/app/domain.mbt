///|
/// Domain models and types for the parallel repository fixer
/// Simplified: no state machine, just track basic info

///|
/// Repository record from database
priv struct RepositoryRecord {
  id : Int
  url : String
  task : String
  target_url : String
  pr_number : Int?
  completed : Bool
}

///|
/// Configuration for repository processing
priv struct WorkerConfig {
  work_dir : String
  branch_prefix : String
  agent : Agent
  db : @sqlite.Database
}
