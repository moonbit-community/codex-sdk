///|
/// Data types for the multi-phase workflow.

///|
/// Summary of a single item from Phase 1.
pub struct ItemSummary {
  item : String
  content : String // Cached content
  summary : String
} derive(Show)

///|
/// A group of related items from Phase 2.
pub struct ItemGroup {
  name : String
  items : Array[String]
  rationale : String
} derive(Show)

///|
/// Result of processing a group in Phase 3.
pub struct GroupResult {
  group_name : String
  items : Array[String]
  result : String
  success : Bool
  error : String
} derive(Show)
