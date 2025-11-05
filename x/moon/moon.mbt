// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// Represents a MoonBit project (module)
pub struct MoonProject {
  /// Root directory path of the project
  root : String
  /// Project name from moon.mod.json
  name : String
}

///|
/// Represents a package within a MoonBit project
pub struct Package {
  /// The project this package belongs to
  project : MoonProject
  /// Relative path from project root (e.g. "", "src/utils")
  path : String
}

///|
/// Result of validation operations (check, test, format)
pub struct ValidationResult {
  passed : Bool
  stdout : String
  stderr : String
  exit_code : Int
}

///|
/// Represents a diagnostic message from the compiler
pub struct Diagnostic {
  /// File path where the issue occurred
  file : String
  /// Line number (1-indexed)
  line : Int
  /// Column number (1-indexed, optional)
  column : Int?
  /// Diagnostic level: "error", "warning", "info"
  level : String
  /// The diagnostic message
  message : String
}

///|
/// Parse diagnostics from moon check/test output
///
/// # Arguments
/// * `output` - The stderr output from moon check/test
///
/// # Returns
/// Array of diagnostics found in the output
///
/// # Format
/// Parses the box-drawing format used by moon with Error/Warning markers
/// followed by location information in brackets
pub fn parse_diagnostics(output : String) -> Array[Diagnostic] {
  let result = []
  let lines = []
  for line in output.split("\n") {
    lines.push(line.to_string())
  }
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]

    // Look for "Error: [XXXX]" or "Warning: [XXXX]"
    let level = if line.has_prefix("Error:") {
      "error"
    } else if line.has_prefix("Warning:") {
      "warning"
    } else {
      i = i + 1
      continue
    }

    // Next line should have the location: "   ╭─[ /path/to/file.mbt:line:col ]"
    i = i + 1
    if i >= lines.length() {
      break
    }
    let location_line = lines[i]
    // Extract the part between [ and ] using split
    if !location_line.contains("[") || !location_line.contains("]") {
      continue
    }
    let parts1 = []
    for part in location_line.split("[") {
      parts1.push(part.to_string())
    }
    if parts1.length() < 2 {
      continue
    }
    let parts2 = []
    for part in parts1[1].split("]") {
      parts2.push(part.to_string())
    }
    if parts2.length() < 1 {
      continue
    }
    let location = parts2[0].trim_space()

    // Parse location format: /path/to/file.mbt:line:col or /path/to/file.mbt:line
    let parts = []
    for part in location.split(":") {
      parts.push(part.to_string())
    }
    if parts.length() < 2 {
      continue
    }
    let file = parts[0]
    let line_num = @strconv.parse_int(parts[1]) catch { _ => continue }
    let column : Int? = if parts.length() >= 3 {
      Some(@strconv.parse_int(parts[2])) catch {
        _ => None
      }
    } else {
      None
    }

    // Collect the message from lines with ╰── marker
    let message_parts = []
    i = i + 1
    while i < lines.length() {
      let msg_line = lines[i]
      if msg_line.contains("───╯") {
        break
      }
      if msg_line.contains("╰──") {
        // Extract message after the arrow by splitting
        let arrow_parts = []
        for part in msg_line.split("╰──") {
          arrow_parts.push(part.to_string())
        }
        if arrow_parts.length() >= 2 {
          let msg = arrow_parts[1].trim_space()
          if !msg.is_empty() {
            message_parts.push(msg)
          }
        }
      }
      i = i + 1
    }
    let message = message_parts.join(" ")
    if !message.is_empty() {
      result.push(Diagnostic::{ file, line: line_num, column, level, message })
    }
    i = i + 1
  }
  result
}

///|
/// Get only errors from diagnostics
pub fn get_errors(diagnostics : Array[Diagnostic]) -> Array[Diagnostic] {
  diagnostics.filter(fn(d) { d.level == "error" })
}

///|
/// Get only warnings from diagnostics
pub fn get_warnings(diagnostics : Array[Diagnostic]) -> Array[Diagnostic] {
  diagnostics.filter(fn(d) { d.level == "warning" })
}

///|
/// Validators that can be applied to verify project state
pub(all) enum Validator {
  /// Run `moon check`
  MoonCheck
  /// Run `moon test`
  MoonTest
  /// Run `moon format`
  MoonFormat
  /// Verify git working tree is clean
  GitClean
  /// Custom validation function
  Custom((String) -> Bool)
}

///|
/// Discover a MoonBit project at the given path
///
/// # Arguments
/// * `path` - Path to search for moon.mod.json
///
/// # Returns
/// Some(MoonProject) if found, None otherwise
pub async fn MoonProject::discover(path : String) -> MoonProject? {
  if @fs.exists("\{path}/moon.mod.json") {
    let content = @fs.read_file("\{path}/moon.mod.json").text()
    let schema = @json.parse(content)
    guard schema is Object({ "name": String(name), .. }) else {
      fail("Invalid moon.mod.json at \{path} with content \{schema}")
    }
    Some(MoonProject::{ root: path, name })
  } else {
    None
  }
}

///|
/// Get all packages in this project
///
/// # Returns
/// Array of packages found in the project
pub async fn MoonProject::packages(self : MoonProject) -> Array[Package] {
  let result = []
  async fn visit(
    project : MoonProject,
    path : String,
    result : Array[Package],
  ) {
    let entries = @fs.readdir("\{project.root}\{path}", include_hidden=false)

    // Skip submodules
    if !path.is_empty() && entries.contains("moon.mod.json") {
      return
    }

    // Found a package
    if entries.contains("moon.pkg.json") {
      result.push(Package::{ project, path })
    }

    // Recurse into subdirectories
    for entry in entries {
      let subpath = if path.is_empty() {
        "/\{entry}"
      } else {
        "\{path}/\{entry}"
      }
      let kind = @fs.kind("\{project.root}\{subpath}")
      if kind is Directory {
        visit(project, subpath, result)
      }
    }
  }

  visit(self, "", result)
  result
}

///|
/// Run `moon check` on the project
pub async fn MoonProject::check(self : MoonProject) -> ValidationResult {
  run_moon_command(self.root, ["check"])
}

///|
/// Run `moon test` on the project
pub async fn MoonProject::test_(self : MoonProject) -> ValidationResult {
  run_moon_command(self.root, ["test"])
}

///|
/// Run `moon fmt` on the project
pub async fn MoonProject::format(self : MoonProject) -> ValidationResult {
  run_moon_command(self.root, ["fmt"])
}

///|
/// Run `moon info` to update generated interface files
pub async fn MoonProject::update_info(self : MoonProject) -> ValidationResult {
  run_moon_command(self.root, ["info"])
}

///|
/// Helper to run moon commands and capture output
async fn run_moon_command(
  root : String,
  args : Array[String],
) -> ValidationResult {
  let full_args = Array::new(capacity=args.length() + 2)
  for arg in args {
    full_args.push(arg)
  }
  full_args.push("-C")
  full_args.push(root)
  let (exit_code, stdout, stderr) = @process.collect_output("moon", full_args)
  let stdout = stdout.text()
  let stderr = stderr.text()
  ValidationResult::{ passed: exit_code == 0, stdout, stderr, exit_code }
}
