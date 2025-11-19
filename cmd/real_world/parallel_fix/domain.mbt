///|
/// Domain models and types for the parallel repository fixer
/// This module contains core business types with no dependencies on infrastructure

///|
/// Repository processing states
/// Simplified: only track major business states in database
/// Internal steps (commit, push, create PR) are not tracked as states
pub enum RepoState {
  Pending
  Cloning
  Branching
  Fixing // Internal: commit → push → create PR → transition to PrOpen
  PrOpen // AI continuously monitors and decides next action
  Complete
  Retry
  // Deprecated states (auto-migrated on read)
  Committing
  Pushing
  PrCreating
  PrChangesRequested
  PrApproved
  PrConflicts
  PrMerged
} derive(Eq)

///|
/// Convert RepoState to string for database storage
pub impl Show for RepoState with output(self : RepoState, logger) {
  logger.write_string(
    match self {
      Pending => "PENDING"
      Cloning => "CLONING"
      Branching => "BRANCHING"
      Fixing => "FIXING"
      Committing => "COMMITTING"
      Pushing => "PUSHING"
      PrCreating => "PR_CREATING"
      PrOpen => "PR_OPEN"
      PrChangesRequested => "PR_CHANGES_REQUESTED"
      PrApproved => "PR_APPROVED"
      PrConflicts => "PR_CONFLICTS"
      PrMerged => "PR_MERGED"
      Complete => "COMPLETE"
      Retry => "RETRY"
    },
  )
}

///|
/// Parse RepoState from string
pub impl @strconv.FromStr for RepoState with from_str(s) {
  match s {
    "PENDING" => Pending
    "CLONING" => Cloning
    "BRANCHING" => Branching
    "FIXING" => Fixing
    "COMMITTING" => Committing
    "PUSHING" => Pushing
    "PR_CREATING" => PrCreating
    "PR_OPEN" => PrOpen
    "PR_CHANGES_REQUESTED" => PrChangesRequested
    "PR_APPROVED" => PrApproved
    "PR_CONFLICTS" => PrConflicts
    "PR_MERGED" => PrMerged
    "COMPLETE" => Complete
    "RETRY" => Retry
    _ => raise @strconv.StrConvError("Unknown RepoState: \{s}")
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
/// Configuration for repository processing
pub struct WorkerConfig {
  work_dir : String
  branch_prefix : String
  codex : @codex.Codex
  state_mgr : StateManager
}

///|
/// PR state information fetched from GitHub
pub struct PrStateInfo {
  state : String // OPEN, CLOSED, MERGED
  mergeable : String // MERGEABLE, CONFLICTING, UNKNOWN
  review_decision : String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or empty string
}

///|
/// Get list of deprecated PR states
pub fn deprecated_pr_states() -> Array[String] {
  ["PR_CHANGES_REQUESTED", "PR_APPROVED", "PR_CONFLICTS", "PR_MERGED"]
}

///|
/// Get list of deprecated intermediate states
pub fn deprecated_intermediate_states() -> Array[String] {
  ["COMMITTING", "PUSHING", "PR_CREATING"]
}

///|
/// All processable states (not complete)
pub fn is_processable_state(state : RepoState) -> Bool {
  match state {
    Complete => false
    _ => true
  }
}

///|
/// Check if state is deprecated
pub fn is_deprecated_state(state : RepoState) -> Bool {
  match state {
    Committing | Pushing | PrCreating | PrChangesRequested | PrApproved | 
    PrConflicts | PrMerged => true
    _ => false
  }
}

///|
/// Get the target state for a deprecated state
pub fn migrate_deprecated_state(state : RepoState) -> RepoState {
  match state {
    Committing | Pushing | PrCreating => Fixing
    PrChangesRequested | PrApproved | PrConflicts | PrMerged => PrOpen
    _ => state
  }
}
