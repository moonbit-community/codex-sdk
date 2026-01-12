///|
struct WorkItemInput {
  label : String
  review : String
  fix : String?
} derive(FromJson)

///|
struct WorkItem {
  index : Int
  label : String
  review : String
  fix : String?
}

///|
enum RunMode {
  Review
  Fix
  Both
}

///|
fn run_mode_to_string(mode : RunMode) -> String {
  match mode {
    Review => "review"
    Fix => "fix"
    Both => "both"
  }
}

///|
struct RunResult {
  label : String
  ok : Bool
  iterations : Int
  review_summary : String?
  interface_review_summary : String?
  last_failure_output : String?
  error : String?
} derive(ToJson)
