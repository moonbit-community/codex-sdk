///|
/// Pure state machine logic for repository processing
/// This module contains business rules for state transitions without database coupling

///|
/// Infer actual state from repository fields
/// Used to recover from corrupted or deprecated RETRY state
pub fn infer_state_from_fields(
  has_pr_url : Bool,
  has_current_branch : Bool,
  has_default_branch : Bool,
  has_local_path : Bool
) -> RepoState {
  if has_pr_url {
    PrOpen
  } else if has_current_branch {
    Fixing
  } else if has_default_branch {
    Branching
  } else if has_local_path {
    Cloning
  } else {
    Pending
  }
}

///|
/// Determine if a repository needs to be recovered from corrupted state
/// Returns true if current state doesn't match the actual progress
pub fn needs_state_recovery(
  current_state : RepoState,
  inferred_state : RepoState
) -> Bool {
  match current_state {
    Pending => inferred_state != Pending
    Cloning =>
      inferred_state != Pending && inferred_state != Cloning
    Branching =>
      inferred_state != Pending && inferred_state != Cloning &&
      inferred_state != Branching
    _ => false
  }
}

///|
/// Get string representation of a state for SQL queries
pub fn state_to_sql_string(state : RepoState) -> String {
  state.to_string()
}

///|
/// Determine next state after PR status check
/// Used by AI monitoring logic to decide whether to continue, fix, or complete
pub fn determine_state_from_pr_info(
  pr_state : String,
  mergeable : String,
  review_decision : String
) -> RepoState {
  if pr_state == "MERGED" || pr_state == "CLOSED" {
    Complete
  } else if review_decision == "CHANGES_REQUESTED" || mergeable == "CONFLICTING" {
    Fixing
  } else {
    PrOpen
  }
}

///|
/// Check if state transition is valid
/// Returns true if the transition follows the normal flow
pub fn is_valid_transition(from : RepoState, to : RepoState) -> Bool {
  match (from, to) {
    // Normal forward flow
    (Pending, Cloning) => true
    (Cloning, Branching) => true
    (Branching, Fixing) => true
    (Fixing, PrOpen) => true
    (PrOpen, Complete) => true
    // Can always complete from any state
    (_, Complete) => true
    // Can go back to Fixing from PrOpen for addressing issues
    (PrOpen, Fixing) => true
    // Same state (idempotent)
    _ => from == to
  }
}

///|
/// Get human-readable description of a state
pub fn state_description(state : RepoState) -> String {
  match state {
    Pending => "Waiting to be processed"
    Cloning => "Cloning repository"
    Branching => "Creating feature branch"
    Fixing => "AI working on fixes"
    PrOpen => "Pull request open, AI monitoring"
    Complete => "Task completed"
    Retry => "Deprecated: needs state recovery"
    Committing => "Deprecated: should be Fixing"
    Pushing => "Deprecated: should be Fixing"
    PrCreating => "Deprecated: should be Fixing"
    PrChangesRequested => "Deprecated: should be PrOpen"
    PrApproved => "Deprecated: should be PrOpen"
    PrConflicts => "Deprecated: should be PrOpen"
    PrMerged => "Deprecated: should be Complete"
  }
}

///|
/// Get the list of states to show in status reports
/// Returns tuples of (state, display_label)
pub fn get_status_states() -> Array[(RepoState, String)] {
  [
    (Pending, "Pending"),
    (Cloning, "Cloning"),
    (Branching, "Branching"),
    (Fixing, "Fixing"),
    (PrOpen, "PR Open"),
    (Complete, "Complete"),
  ]
}
