///|
/// Job configuration and all phase handles.

///|
pub suberror AppErrors {
  NeedHelp(String)
} derive(Show)

///|
/// Job holds the configuration for the entire workflow.
pub struct Job {
  project_root : String
  items : Array[String]
  parallelism : Int
  output_dir : String
  verbose : Bool
}

///|
pub async fn initialize() -> Job {
  let arguments_opt = parse_cli_args(@sys.get_cli_args()[1:])
  let arguments = match arguments_opt {
    None => raise AppErrors::NeedHelp(help_message())
    Some(arguments) => apply_env_overrides(arguments)
  }
  let items = discover_items(arguments.path)
  Job::{
    project_root: arguments.path,
    items,
    parallelism: arguments.parallelism,
    output_dir: arguments.output,
    verbose: arguments.verbose,
  }
}

// =============================================================================
// Phase 1: Summarize (fan out)
// =============================================================================

///|
pub struct SummarizeHandle {
  item : String
  config : Job
  idx : Int
  mut attempt : Int
  content : String // Cached content
  mut last_error : String
}

///|
pub async fn Job::summarize_start(config : Job, idx : Int) -> SummarizeHandle {
  let item = config.items[idx]
  if config.verbose {
    let total = config.items.length()
    @stdio.stdout.write("info [\{idx + 1}/\{total}] - Summarizing \{item}\n")
  }
  // Cache content at setup
  let content = read_item_content(config.project_root, item)
  SummarizeHandle::{ item, config, idx, attempt: 0, content, last_error: "" }
}

///|
pub fn SummarizeHandle::prompt(self : SummarizeHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    // === CUSTOMIZE: Your summarization prompt ===
    let prompt =
      $|Briefly summarize this item in 2-3 sentences.
      $|Focus on: what it contains, its primary purpose.
      $|
      $|Item: \{self.item}
      $|
      $|Content:
      $|```
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
    "\{error_context}Please provide a brief 2-3 sentence summary. Respond with ONLY the summary."
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
) -> ItemSummary {
  ItemSummary::{ item: self.item, content: self.content, summary }
}

///|
pub async fn SummarizeHandle::error(
  self : SummarizeHandle,
  e : Error,
) -> ItemSummary {
  @stdio.stderr.write("error [\{self.item}] - Summarize failed: \{e}\n")
  ItemSummary::{ item: self.item, content: self.content, summary: "(failed to summarize)" }
}

// =============================================================================
// Phase 2: Plan (sequential - single agent)
// =============================================================================

///|
pub struct PlanHandle {
  summaries : Array[ItemSummary]
  config : Job
  mut attempt : Int
  mut last_error : String
}

///|
pub async fn Job::plan_start(
  config : Job,
  summaries : Array[ItemSummary],
) -> PlanHandle {
  // Filter out failed summaries
  let valid_summaries = summaries.filter(fn(s) {
    not(s.summary.has_prefix("(failed"))
  })
  let skipped = summaries.length() - valid_summaries.length()
  if skipped > 0 {
    @stdio.stdout.write("Skipping \{skipped} items that failed to summarize\n")
  }
  @stdio.stdout.write("Planning: grouping \{valid_summaries.length()} items...\n")
  PlanHandle::{ summaries: valid_summaries, config, attempt: 0, last_error: "" }
}

///|
pub fn PlanHandle::prompt(self : PlanHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    let summaries_text = self.summaries
      .map(fn(s) { "- `\{s.item}`: \{s.summary}" })
      .join("\n")
    let item_list = self.summaries.map(fn(s) { "\"\{s.item}\"" }).join(", ")
    // === CUSTOMIZE: Your grouping prompt ===
    let prompt =
      $|You are planning how to group these items for processing.
      $|Below are summaries of all items. Group related items together.
      $|
      $|Guidelines:
      $|- Aim for 3-5 items per group
      $|- Group by similarity or relationship
      $|- An item MAY appear in multiple groups if needed
      $|- Standalone items can be their own group
      $|
      $|Items:
      $|\{summaries_text}
      $|
      $|IMPORTANT: Use EXACT item names from the list above: [\{item_list}]
      $|
      $|Respond with a JSON array of groups:
      $|```json
      $|[
      $|  {"name": "Group Name", "items": ["exact/item/name"], "rationale": "Why grouped"}
      $|]
      $|```
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    let item_list = self.summaries.map(fn(s) { "\"\{s.item}\"" }).join(", ")
    let prompt =
      $|\{error_context}Please provide the grouping as a JSON array.
      $|
      $|Use EXACT item names: [\{item_list}]
      $|
      $|Format: [{"name": "...", "items": [...], "rationale": "..."}]
    prompt
  }
}

///|
pub suberror PlanError {
  InvalidJson(String)
  MissingItems(Array[String])
} derive(Show)

///|
pub fn PlanHandle::validate(
  self : PlanHandle,
  response : String,
) -> Array[ItemGroup] raise PlanError {
  let json_str = extract_json_array(response)
  let json = @json.parse(json_str) catch {
    e => {
      self.last_error = "Invalid JSON: \{e}"
      raise PlanError::InvalidJson(e.to_string())
    }
  }
  let groups = parse_item_groups(json) catch {
    e => {
      self.last_error = "Invalid group format: \{e}"
      raise PlanError::InvalidJson(e.to_string())
    }
  }
  // Verify all items are covered
  let all_items : Map[String, Bool] = {}
  for s in self.summaries {
    all_items[s.item] = false
  }
  for g in groups {
    for item in g.items {
      all_items[item] = true
    }
  }
  let missing = all_items
    .iter()
    .filter(fn(kv) { not(kv.1) })
    .map(fn(kv) { kv.0 })
    .collect()
  if not(missing.is_empty()) {
    let missing_str = missing.join(", ")
    self.last_error = "Missing items: \{missing_str}"
    raise PlanError::MissingItems(missing)
  }
  groups
}

///|
pub async fn PlanHandle::finish(
  _self : PlanHandle,
  groups : Array[ItemGroup],
) -> Array[ItemGroup] {
  @stdio.stdout.write("Planning complete: \{groups.length()} groups created\n")
  for g in groups {
    @stdio.stdout.write("  - \{g.name}: \{g.items.length()} items\n")
  }
  groups
}

///|
pub async fn PlanHandle::error(
  _self : PlanHandle,
  e : Error,
) -> Array[ItemGroup] {
  @stdio.stderr.write("error - Planning failed: \{e}\n")
  []
}

// =============================================================================
// Phase 3: Process (fan out by group)
// =============================================================================

///|
pub struct ProcessHandle {
  group : ItemGroup
  config : Job
  idx : Int
  mut attempt : Int
  content_sections : String // Cached content for all items in group
  mut last_error : String
}

///|
pub async fn Job::process_start(
  config : Job,
  idx : Int,
  group : ItemGroup,
) -> ProcessHandle {
  @stdio.stdout.write("info [\{idx + 1}] - Processing group: \{group.name}\n")
  // Pre-load content of all items in the group
  let mut content_sections = ""
  for item in group.items {
    let content = read_item_content(config.project_root, item)
    let section =
      $|
      $|### \{item}
      $|```
      $|\{content}
      $|```
      $|
    content_sections = content_sections + section
  }
  ProcessHandle::{ group, config, idx, attempt: 0, content_sections, last_error: "" }
}

///|
pub fn ProcessHandle::prompt(self : ProcessHandle) -> String {
  let current = self.attempt
  self.attempt += 1
  if current == 0 {
    // === CUSTOMIZE: Your group processing prompt ===
    let prompt =
      $|Process this group of related items together.
      $|
      $|**Group:** \{self.group.name}
      $|**Rationale:** \{self.group.rationale}
      $|**Items:** \{self.group.items.join(", ")}
      $|
      $|## Item Contents
      $|\{self.content_sections}
      $|
      $|Please provide:
      $|1. Analysis of consistency across these related items
      $|2. Any issues or inconsistencies between them
      $|3. Suggestions for improvement
    prompt
  } else {
    let error_context = if self.last_error.is_empty() {
      ""
    } else {
      "Previous attempt failed: \{self.last_error}\n\n"
    }
    "\{error_context}Please complete the analysis of this group."
  }
}

///|
pub suberror ProcessError {
  EmptyResponse
} derive(Show)

///|
pub fn ProcessHandle::validate(
  self : ProcessHandle,
  response : String,
) -> String raise ProcessError {
  let trimmed = response.trim(char_set=" \t\n\r").to_string()
  if trimmed.is_empty() {
    self.last_error = "Empty response"
    raise ProcessError::EmptyResponse
  }
  trimmed
}

///|
pub async fn ProcessHandle::finish(
  self : ProcessHandle,
  result : String,
) -> GroupResult {
  let group_result = GroupResult::{
    group_name: self.group.name,
    items: self.group.items,
    result,
    success: true,
    error: "",
  }
  // === CUSTOMIZE: Save results to file ===
  save_group_result(group_result, self.config.output_dir) catch {
    e => @stdio.stderr.write("warning: Failed to save result for \{self.group.name}: \{e}\n")
  }
  group_result
}

///|
pub async fn ProcessHandle::error(self : ProcessHandle, e : Error) -> GroupResult {
  @stdio.stderr.write("error [\{self.group.name}] - Processing failed: \{e}\n")
  GroupResult::{
    group_name: self.group.name,
    items: self.group.items,
    result: "",
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
  results : Array[GroupResult],
) -> Unit {
  if results.is_empty() {
    @stdio.stdout.write("No results.\n")
    return
  }
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { not(r.success) })
  let summary =
    $|
    $|\{"=".repeat(60)}
    $|SUMMARY
    $|\{"=".repeat(60)}
    $|Total groups processed: \{results.length()}
    $|Successful: \{successful}
    $|Failed: \{failed.length()}
    $|Output Directory: \{config.output_dir}
    $|
  @stdio.stdout.write(summary)
  if not(failed.is_empty()) {
    @stdio.stdout.write("\nFailed groups:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.group_name}: \{f.error}\n")
    }
  }
}

// =============================================================================
// Helpers
// =============================================================================

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
fn parse_item_groups(json : Json) -> Array[ItemGroup] raise {
  guard json is Json::Array(arr) else { @error.fail("Expected JSON array") }
  let groups : Array[ItemGroup] = []
  for item in arr {
    guard item
      is {
        "name": String(name),
        "items": Array(items_arr),
        "rationale": String(rationale),
        ..
      } else {
      @error.fail("Invalid group format")
    }
    let items : Array[String] = []
    for i in items_arr {
      guard i is String(s) else { continue }
      items.push(s)
    }
    groups.push(ItemGroup::{ name, items, rationale })
  }
  groups
}

///|
async fn save_group_result(result : GroupResult, output_dir : String) -> Unit {
  if not(result.success) {
    return
  }
  mkdir_recursive(output_dir) catch { e => @error.reraise(e) }
  let file_name = result.group_name
    .replace_all(old=" ", new="_")
    .replace_all(old="/", new="_")
    .to_lower() +
    ".md"
  let output_path = "\{output_dir}/\{file_name}"
  let items_list = result.items.map(fn(i) { "- `\{i}`" }).join("\n")
  let content =
    $|# Result: \{result.group_name}
    $|
    $|**Items:**
    $|\{items_list}
    $|
    $|---
    $|
    $|\{result.result}
    $|
  @fs.write_file(output_path, @encoding/utf8.encode(content), permission=0o700) catch {
    e => @error.reraise(e)
  }
}

///|
async fn mkdir_recursive(path : String) -> Unit raise {
  if @fs.exists(path) {
    return
  }
  // Find parent
  let chars = path.to_array()
  let mut last_slash = -1
  for i, c in chars {
    if c == '/' {
      last_slash = i
    }
  }
  if last_slash > 0 {
    let parent = try! path[0:last_slash].to_string()
    mkdir_recursive(parent)
  }
  @fs.mkdir(path, permission=0o755)
}

///|
async fn discover_items(path : String) -> Array[String] {
  let items : Array[String] = []
  find_items_recursive(path, "", items) catch { _ => () }
  items
}

///|
async fn find_items_recursive(
  base : String,
  relative : String,
  out : Array[String],
) -> Unit raise {
  let dir = if relative.is_empty() { base } else { "\{base}/\{relative}" }
  let entries = @fs.readdir(dir, include_hidden=false)
  let has_sources = entries.iter().any(fn(name) { name.has_suffix(".mbt") })
  if has_sources {
    out.push(relative)
  }
  for name in entries {
    if name == "_build" || name == "target" || name == ".mooncakes" || name == ".git" {
      continue
    }
    let rel_path = if relative.is_empty() { name } else { "\{relative}/\{name}" }
    let full_path = "\{base}/\{rel_path}"
    if @fs.kind(full_path) == Directory {
      find_items_recursive(base, rel_path, out)
    }
  }
}

///|
async fn read_item_content(project_root : String, item : String) -> String {
  let path = if item.is_empty() { project_root } else { "\{project_root}/\{item}" }
  let entries = @fs.readdir(path, include_hidden=false) catch { _ => return "" }
  for entry in entries {
    if entry.has_suffix(".mbt") {
      let file_path = "\{path}/\{entry}"
      return @fs.read_file(file_path).text() catch { _ => "" }
    }
  }
  ""
}
