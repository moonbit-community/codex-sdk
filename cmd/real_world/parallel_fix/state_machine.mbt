///|
/// Pure state machine logic for repository processing
/// This module contains business rules for state transitions without database coupling

///|
/// Infer actual state from repository fields
/// Used to recover from corrupted or deprecated RETRY state
fn infer_state_from_fields(
  has_pr_url : Bool,
  has_current_branch : Bool,
  has_default_branch : Bool,
  has_local_path : Bool,
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
fn needs_state_recovery(
  current_state : RepoState,
  inferred_state : RepoState,
) -> Bool {
  match current_state {
    Pending => inferred_state != Pending
    Cloning => inferred_state != Pending && inferred_state != Cloning
    Branching =>
      inferred_state != Pending &&
      inferred_state != Cloning &&
      inferred_state != Branching
    _ => false
  }
}

///|
/// Get the list of states to show in status reports
/// Returns tuples of (state, display_label)
fn get_status_states() -> Array[(RepoState, String)] {
  [
    (Pending, "Pending"),
    (Cloning, "Cloning"),
    (Branching, "Branching"),
    (Fixing, "Fixing"),
    (PrOpen, "PR Open"),
    (Complete, "Complete"),
  ]
}
