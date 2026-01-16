///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
pub struct Job {
  project_root : String
  output_dir : String
  concurrency : Int
  verbose : Bool
  files : Array[String] // mbti file paths
}

///|
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => apply_env_overrides(arguments)
  }
  let files_to_review = resolve_files_to_review(arguments)
  Job::{
    project_root: arguments.path,
    output_dir: output_dir(arguments),
    concurrency: arguments.concurrency,
    verbose: arguments.verbose,
    files: files_to_review,
  }
}

// =============================================================================
// Phase 1: Summarize (fan out)
// =============================================================================

///|
pub struct SummarizeHandle {
  file_path : String
  pkg_path : String
  config : Job
  idx : Int
  mut attempt : Int
  content : String // cached file content
  mut last_error : String
}

///|
pub async fn Job::summarize_start(config : Job, idx : Int) -> SummarizeHandle {
  let file_path = config.files[idx]
  let pkg_path = extract_pkg_path(file_path, config.project_root)
  if config.verbose {
    let total = config.files.length()
    @stdio.stdout.write(
      "info [\{idx + 1}/\{total}] - Summarizing \{pkg_path}\n",
    )
  }
  // Read file content once at setup
  let content = @fs.read_file(file_path).text() catch { _ => "" }
  SummarizeHandle::{ file_path, pkg_path, config, idx, attempt: 0, content, last_error: "" }
}

///|
pub fn SummarizeHandle::prompt(self : SummarizeHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    let prompt =
      $|Briefly summarize this MoonBit package interface in 2-3 sentences.
      $|Focus on: what data structures/functions it provides, its primary purpose.
      $|
      $|Package: \{self.pkg_path}
      $|
      $|```moonbit
      $|\{self.content}
      $|```
      $|
      $|Respond with ONLY the summary, no preamble.
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    "\{error_context}Please provide a brief 2-3 sentence summary of the package. Respond with ONLY the summary."
  }
}

///|
pub suberror SummarizeError {
  EmptyResponse
} derive(Show)

///|
pub fn SummarizeHandle::validate(
  self : SummarizeHandle,
  response : String,
) -> String raise SummarizeError {
  let trimmed = response.trim(char_set=" \t\n\r").to_string()
  if trimmed.is_empty() {
    self.last_error = "Empty response"
    raise SummarizeError::EmptyResponse
  }
  trimmed
}

///|
pub fn SummarizeHandle::finish(
  self : SummarizeHandle,
  summary : String,
) -> PackageSummary {
  PackageSummary::{
    pkg_path: self.pkg_path,
    file_path: self.file_path,
    summary,
  }
}

///|
pub async fn SummarizeHandle::error(
  self : SummarizeHandle,
  e : Error,
) -> PackageSummary {
  @stdio.stderr.write("error [\{self.pkg_path}] - Summarize failed: \{e}\n")
  PackageSummary::{
    pkg_path: self.pkg_path,
    file_path: self.file_path,
    summary: "(failed to summarize)",
  }
}

// =============================================================================
// Phase 2: Plan (sequential - single agent)
// =============================================================================

///|
pub struct PlanHandle {
  summaries : Array[PackageSummary]
  config : Job
  mut attempt : Int
  mut last_error : String
}

///|
pub async fn Job::plan_start(
  config : Job,
  summaries : Array[PackageSummary],
) -> PlanHandle {
  // Filter out failed summaries
  let valid_summaries = summaries.filter(fn(s) {
    not(s.summary.has_prefix("(failed"))
  })
  let skipped = summaries.length() - valid_summaries.length()
  if skipped > 0 {
    @stdio.stdout.write(
      "Skipping \{skipped} packages that failed to summarize\n",
    )
  }
  @stdio.stdout.write(
    "\nPlanning: grouping \{valid_summaries.length()} packages for review...\n",
  )
  PlanHandle::{ summaries: valid_summaries, config, attempt: 0, last_error: "" }
}

///|
pub fn PlanHandle::prompt(self : PlanHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    let summaries_text = self.summaries
      .map(fn(s) { "- `\{s.pkg_path}`: \{s.summary}" })
      .join("\n")
    let pkg_list = self.summaries.map(fn(s) { "\"\{s.pkg_path}\"" }).join(", ")
    let prompt =
      $|You are planning a code review for a MoonBit project.
      $|Below are summaries of all packages. Group related packages that should be reviewed together.
      $|
      $|Guidelines:
      $|- Aim for 3-5 packages per group for effective review
      $|- Data structure variants (map, sortedmap, hashmap) should be grouped
      $|- Array variants (array, fixedarray, arrayview) should be grouped
      $|- A package MAY appear in multiple groups if it fits multiple categories
      $|- Standalone packages can be their own group
      $|
      $|Packages:
      $|\{summaries_text}
      $|
      $|IMPORTANT: Use EXACT package names from the list above: [\{pkg_list}]
      $|
      $|Respond with a JSON array of groups:
      $|```json
      $|[
      $|  {"name": "Group Name", "packages": ["exact/pkg/path"], "rationale": "Why grouped"}
      $|]
      $|```
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    let pkg_list = self.summaries.map(fn(s) { "\"\{s.pkg_path}\"" }).join(", ")
    let prompt =
      $|\{error_context}Please provide the grouping as a JSON array.
      $|
      $|Use EXACT package names: [\{pkg_list}]
      $|
      $|Format: [{"name": "...", "packages": [...], "rationale": "..."}]
    prompt
  }
}

///|
pub suberror PlanError {
  InvalidJson(String)
  MissingPackages(Array[String])
} derive(Show)

///|
pub fn PlanHandle::validate(
  self : PlanHandle,
  response : String,
) -> Array[PackageGroup] raise PlanError {
  // Extract JSON from response (may be wrapped in ```json ... ```)
  let json_str = extract_json_array(response)
  let json = @json.parse(json_str) catch {
    e => {
      self.last_error = "Invalid JSON: \{e}"
      raise PlanError::InvalidJson(e.to_string())
    }
  }
  let groups = parse_package_groups(json) catch {
    e => {
      self.last_error = "Invalid group format: \{e}"
      raise PlanError::InvalidJson(e.to_string())
    }
  }
  // Verify all packages are covered (each must appear in at least one group)
  let all_pkgs : Map[String, Bool] = {}
  for s in self.summaries {
    all_pkgs[s.pkg_path] = false
  }
  for g in groups {
    for pkg in g.packages {
      all_pkgs[pkg] = true
    }
  }
  let missing = all_pkgs
    .iter()
    .filter(fn(kv) { not(kv.1) })
    .map(fn(kv) { kv.0 })
    .collect()
  if not(missing.is_empty()) {
    let missing_str = missing.join(", ")
    self.last_error = "Missing packages: \{missing_str}"
    raise PlanError::MissingPackages(missing)
  }
  groups
}

///|
pub async fn PlanHandle::finish(
  _self : PlanHandle,
  groups : Array[PackageGroup],
) -> Array[PackageGroup] {
  @stdio.stdout.write("Planning complete: \{groups.length()} groups created\n")
  for g in groups {
    @stdio.stdout.write("  - \{g.name}: \{g.packages.length()} packages\n")
  }
  groups
}

///|
pub async fn PlanHandle::error(
  _self : PlanHandle,
  e : Error,
) -> Array[PackageGroup] {
  @stdio.stderr.write("error - Planning failed: \{e}\n")
  [] // Empty groups means we can't proceed
}

// =============================================================================
// Phase 3: Review (fan out by group)
// =============================================================================

///|
pub struct ReviewHandle {
  group : PackageGroup
  config : Job
  idx : Int
  mut attempt : Int
  content_sections : String // cached file contents
  mut last_error : String
}

///|
pub async fn Job::review_start(
  config : Job,
  idx : Int,
  group : PackageGroup,
) -> ReviewHandle {
  @stdio.stdout.write("info [\{idx + 1}] - Reviewing group: \{group.name}\n")
  // Pre-load content of all packages in the group
  let mut content_sections = ""
  for pkg_path in group.packages {
    let file_path = pkg_path_to_file(pkg_path, config.project_root)
    let content = @fs.read_file(file_path).text() catch {
      _ => "(file not found)"
    }
    let section =
      $|
      $|### \{pkg_path}
      $|```moonbit
      $|\{content}
      $|```
      $|
    content_sections = content_sections + section
  }
  ReviewHandle::{ group, config, idx, attempt: 0, content_sections, last_error: "" }
}

///|
pub fn ReviewHandle::prompt(self : ReviewHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    let prompt =
      $|Review this group of related MoonBit packages together.
      $|
      $|**Group:** \{self.group.name}
      $|**Rationale:** \{self.group.rationale}
      $|**Packages:** \{self.group.packages.join(", ")}
      $|
      $|## Package Interfaces
      $|\{self.content_sections}
      $|
      $|Please provide:
      $|1. Assessment of API consistency across these related packages
      $|2. Any inconsistencies or issues between them
      $|3. Suggestions for improvement
      $|
      $|Focus on how well these packages work together as a cohesive set.
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    "\{error_context}Please complete the review of this package group."
  }
}

///|
pub suberror ReviewError {
  EmptyResponse
} derive(Show)

///|
pub fn ReviewHandle::validate(
  self : ReviewHandle,
  response : String,
) -> String raise ReviewError {
  let trimmed = response.trim(char_set=" \t\n\r").to_string()
  if trimmed.is_empty() {
    self.last_error = "Empty response"
    raise ReviewError::EmptyResponse
  }
  trimmed
}

///|
pub async fn ReviewHandle::finish(
  self : ReviewHandle,
  review : String,
) -> GroupReview {
  let result = GroupReview::{
    group_name: self.group.name,
    packages: self.group.packages,
    review,
    success: true,
    error: "",
  }
  // Save to file
  save_group_review(result, self.config.output_dir) catch {
    e => @stdio.stderr.write("warning: Failed to save review for \{self.group.name}: \{e}\n")
  }
  result
}

///|
pub async fn ReviewHandle::error(self : ReviewHandle, e : Error) -> GroupReview {
  @stdio.stderr.write("error [\{self.group.name}] - Review failed: \{e}\n")
  GroupReview::{
    group_name: self.group.name,
    packages: self.group.packages,
    review: "",
    success: false,
    error: e.to_string(),
  }
}

// =============================================================================
// Summary
// =============================================================================

///|
pub async fn Job::summarize_results(
  config : Job,
  reviews : Array[GroupReview],
) -> Unit {
  if reviews.is_empty() {
    @stdio.stdout.write("No reviews completed.\n")
    return
  }
  let successful = reviews.filter(fn(r) { r.success }).length()
  let failed = reviews.filter(fn(r) { not(r.success) })
  let rel_output_dir = summary_output_dir(
    config.output_dir,
    config.project_root,
  )
  let summary =
    $|
    $|\{"=".repeat(80)}
    $|SUMMARY
    $|\{"=".repeat(80)}
    $|Total groups reviewed: \{reviews.length()}
    $|Successful: \{successful}
    $|Failed: \{failed.length()}
    $|Output Directory: \{rel_output_dir}
    $|
  @stdio.stdout.write(summary)
  if not(failed.is_empty()) {
    @stdio.stdout.write("\nFailed reviews:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.group_name}: \{f.error}\n")
    }
  }
}

// =============================================================================
// Helpers
// =============================================================================

///|
fn extract_pkg_path(file_path : String, project_root : String) -> String {
  let rel = if file_path.has_prefix(project_root) {
    try! file_path[project_root.length() + 1:].to_string()
  } else {
    file_path
  }
  rel.replace_all(old="/pkg.generated.mbti", new="")
}

///|
fn pkg_path_to_file(pkg_path : String, project_root : String) -> String {
  "\{project_root}/\{pkg_path}/pkg.generated.mbti"
}

///|
fn extract_json_array(response : String) -> String {
  // Try to find ```json ... ``` block
  let lines = response.split("\n").collect()
  let mut in_json = false
  let json_lines : Array[String] = []
  for line in lines {
    let trimmed = line.trim(char_set=" \t\r").to_string()
    if trimmed.has_prefix("```json") {
      in_json = true
      continue
    }
    if trimmed.has_prefix("```") && in_json {
      break
    }
    if in_json {
      json_lines.push(line.to_string())
    }
  }
  if not(json_lines.is_empty()) {
    return json_lines.join("\n")
  }
  // Fallback: find first [ and last ]
  let chars = response.to_array()
  let mut start : Int? = None
  let mut end : Int? = None
  for i, c in chars {
    if c == '[' && start is None {
      start = Some(i)
    }
    if c == ']' {
      end = Some(i)
    }
  }
  match (start, end) {
    (Some(s), Some(e)) => try! response[s:e + 1].to_string()
    _ => response
  }
}

///|
fn parse_package_groups(json : Json) -> Array[PackageGroup] raise {
  guard json is Json::Array(arr) else { @error.fail("Expected JSON array") }
  let groups : Array[PackageGroup] = []
  for item in arr {
    guard item
      is {
        "name": String(name),
        "packages": Array(pkgs),
        "rationale": String(rationale),
        ..
      } else {
      @error.fail("Invalid group format")
    }
    let packages : Array[String] = []
    for p in pkgs {
      guard p is String(s) else { continue }
      packages.push(s)
    }
    groups.push(PackageGroup::{ name, packages, rationale })
  }
  groups
}

///|
async fn save_group_review(review : GroupReview, output_dir : String) -> Unit {
  if not(review.success) {
    return
  }
  mkdir_recursive(output_dir) catch {
    e => @error.reraise(e)
  }
  let file_name = review.group_name
    .replace_all(old=" ", new="_")
    .replace_all(old="/", new="_")
    .to_lower() +
    ".review.md"
  let output_path = "\{output_dir}/\{file_name}"
  let packages_list = review.packages.map(fn(p) { "- `\{p}`" }).join("\n")
  let content =
    $|# Review: \{review.group_name}
    $|
    $|**Packages:**
    $|\{packages_list}
    $|
    $|---
    $|
    $|\{review.review}
    $|
  @fs.write_file(output_path, @encoding/utf8.encode(content), create=0o700) catch {
    e => @error.reraise(e)
  }
}

///|
fn apply_env_overrides(arguments : Arguments) -> Arguments {
  let env = @sys.get_env_vars()
  if env.get("REVIEW_MBTI_CONCURRENCY") is Some(value) {
    arguments.concurrency = @strconv.parse_int(value) catch {
      _ => arguments.concurrency
    }
  }
  if env.get("REVIEW_MBTI_OUTPUT") is Some(value) {
    arguments.output = value
  }
  if env.get("REVIEW_MBTI_VERBOSE") is Some(value) {
    arguments.verbose = parse_env_bool(value).unwrap_or(arguments.verbose)
  }
  if env.get("REVIEW_MBTI_CHANGED") is Some(value) {
    arguments.changed = parse_env_bool(value).unwrap_or(arguments.changed)
  }
  if env.get("REVIEW_MBTI_FILES") is Some(value) && arguments.files.is_empty() {
    arguments.files = value
      .split(",")
      .map(fn(s) { s.trim(char_set=" \\t\\n\\r").to_string() })
      .collect()
  }
  arguments
}

///|
fn parse_env_bool(value : String) -> Bool? {
  let v = value.trim(char_set=" \\t\\n\\r").to_string().to_lower()
  if v == "1" || v == "true" || v == "yes" || v == "on" {
    Some(true)
  } else if v == "0" || v == "false" || v == "no" || v == "off" {
    Some(false)
  } else {
    None
  }
}
