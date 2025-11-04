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
pub fn parse_diagnostics(output : String) -> Array[Diagnostic] {
  let result = []
  let lines = output.split("\n")
  for line_text in lines {
    // Parse format: path/to/file.mbt:line:col: level: message
    // or: path/to/file.mbt:line: level: message
    let parts = []
    for part in line_text.split(":") {
      parts.push(part)
    }
    if parts.length() >= 4 {
      let file = parts[0].to_string()
      let line_str = parts[1].trim_space().to_string()

      // Try to parse line number
      let line = @strconv.parse_int(line_str) catch {
        _ => continue // Skip lines that don't have valid line numbers
      }

      // Check if next part is column or level
      let mut rest_start = 2
      let column : Int? = try {
        let col = @strconv.parse_int(parts[2].trim_space().to_string())
        rest_start = 3
        Some(col)
      } catch {
        _ => None
      }
      if rest_start < parts.length() {
        let level_part = parts[rest_start].trim_space().to_string()
        // Detect level keywords
        let level = if level_part.contains("error") ||
          level_part.contains("Error") {
          "error"
        } else if level_part.contains("warning") ||
          level_part.contains("Warning") {
          "warning"
        } else if level_part.contains("info") || level_part.contains("Info") {
          "info"
        } else {
          continue // Not a diagnostic line
        }

        // Collect remaining parts as message
        let message_parts = []
        let mut i = rest_start + 1
        while i < parts.length() {
          message_parts.push(parts[i].to_string())
          i = i + 1
        }
        let message = message_parts.join(":").trim_space().to_string()
        result.push(Diagnostic::{ file, line, column, level, message })
      }
    }
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
