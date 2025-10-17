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

// codexOptions.ts

///|
/// Options for configuring the Codex client.
struct CodexOptions {
  /// Override the path to the codex executable
  codex_path_override : String?
  /// Base URL for the API
  base_url : String?
  /// API key for authentication
  api_key : String?
} derive (
  ToJson(rename_fields="camelCase"),
  @json.FromJson(rename_fields="camelCase"),
)

///|
pub fn CodexOptions::new(
  codex_path_override? : String,
  base_url? : String,
  api_key? : String,
) -> CodexOptions {
  CodexOptions::{ codex_path_override, base_url, api_key }
}

// threadOptions.ts

///|
/// Approval mode for actions that require user consent.
pub(all) enum ApprovalMode {
  /// Never ask for approval
  Never
  /// Ask for approval on request
  OnRequest
  /// Ask for approval on failure
  OnFailure
  /// Ask for approval for untrusted actions
  Untrusted
}

///|
pub impl ToJson for ApprovalMode with to_json(mode) {
  match mode {
    Never => "never"
    OnRequest => "on-request"
    OnFailure => "on-failure"
    Untrusted => "untrusted"
  }
}

///|
pub impl @json.FromJson for ApprovalMode with from_json(value, path) {
  match value {
    String("never") => Never
    String("on-request") => OnRequest
    String("on-failure") => OnFailure
    String("untrusted") => Untrusted
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected approval mode string, got \{value}"),
      )
  }
}

///|
/// Sandbox mode that controls the level of access the agent has.
pub(all) enum SandboxMode {
  /// Read-only access
  ReadOnly
  /// Write access to workspace
  WorkspaceWrite
  /// Full access (dangerous)
  DangerFullAccess
}

///|
pub impl ToJson for SandboxMode with to_json(mode) {
  match mode {
    ReadOnly => "read-only"
    WorkspaceWrite => "workspace-write"
    DangerFullAccess => "danger-full-access"
  }
}

///|
pub impl @json.FromJson for SandboxMode with from_json(value, path) {
  match value {
    String("read-only") => ReadOnly
    String("workspace-write") => WorkspaceWrite
    String("danger-full-access") => DangerFullAccess
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected sandbox mode string, got \{value}"),
      )
  }
}

///|
/// Options for configuring a thread.
struct ThreadOptions {
  /// The model to use for the thread
  model : String?
  /// The sandbox mode
  sandbox_mode : SandboxMode?
  /// The working directory
  working_directory : String?
  /// Whether to skip git repository check
  skip_git_repo_check : Bool?
} derive (
  ToJson(rename_fields="camelCase"),
  @json.FromJson(rename_fields="camelCase"),
)

///|
pub fn ThreadOptions::new(
  model? : String,
  sandbox_mode? : SandboxMode,
  working_directory? : String,
  skip_git_repo_check? : Bool,
) -> ThreadOptions {
  ThreadOptions::{ model, sandbox_mode, working_directory, skip_git_repo_check }
}

// turnOptions.ts

///|
/// Options for configuring a turn.
struct TurnOptions {
  /// JSON schema describing the expected agent output
  output_schema : Json?
} derive (
  ToJson(rename_fields="camelCase"),
  @json.FromJson(rename_fields="camelCase"),
)

///|
pub fn TurnOptions::new(output_schema? : Json) -> TurnOptions {
  TurnOptions::{ output_schema, }
}
