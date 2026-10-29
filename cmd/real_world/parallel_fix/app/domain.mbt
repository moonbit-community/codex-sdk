///|
/// Domain models and types for the parallel repository fixer
/// Simplified: no state machine, just track basic info

///|
/// Repository record from database
pub struct RepositoryRecord {
  id : Int32
  url : String
  task : String
  task_title : String?
  target_url : String
  pr_number : Int32?
  last_pr_head_sha : String?
  last_pr_comment_count : Int32?
  completed : Bool
}

///|
/// Configuration for repository processing
pub(all) struct WorkerConfig {
  work_dir : String
  branch_prefix : String
  db : @sqlite.Database
  force : Bool
}
