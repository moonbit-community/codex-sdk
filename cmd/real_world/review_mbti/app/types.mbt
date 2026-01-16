///|
/// Summary of a single package's public API
pub struct PackageSummary {
  pkg_path : String
  file_path : String
  summary : String
} derive(Show)

///|
/// A group of related packages to be reviewed together
pub struct PackageGroup {
  name : String
  packages : Array[String] // pkg_paths
  rationale : String
} derive(Show)

///|
/// Result of reviewing a group of packages
pub struct GroupReview {
  group_name : String
  packages : Array[String]
  review : String
  success : Bool
  error : String
} derive(Show)
