///|
struct DocTarget {
  index : Int
  path : String
}

///|
struct DocUpdateResult {
  index : Int
  path : String
  ok : Bool
  error : String?
} derive(ToJson)

///|
struct WorkflowReport {
  targets : Int
  updated : Array[DocUpdateResult]
  maintenance_ok : Bool
  maintenance_output : String
  interface_review_summary : String?
  verified : Bool
  verification_output : String
} derive(ToJson)
