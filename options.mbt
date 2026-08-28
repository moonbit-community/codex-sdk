// Copyright 2026 International Digital Economy Academy
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

// #region codexOptions.ts

///|
/// Options for configuring the Codex client.
struct CodexOptions {
  /// Override the path to the codex executable
  codex_path_override : String?
  /// Base URL for the API
  base_url : String?
  /// API key for authentication
  api_key : String?
  /// Structured Codex configuration overrides. Nested objects are flattened
  /// into dotted `--config` keys and values are serialized as TOML.
  config : Map[String, Json]?
  /// Raw `--config key=value` overrides passed through unchanged after
  /// structured overrides and before SDK-managed settings.
  config_overrides : Array[String]?
  /// Environment variables passed to the Codex CLI process. When provided, the SDK will not inherit variables.
  env : Map[String, String]?
} derive(Default)

///|
pub fn CodexOptions::new(
  codex_path_override? : String,
  base_url? : String,
  api_key? : String,
  config? : Map[String, Json],
  config_overrides? : Array[String],
  env? : Map[String, String],
) -> CodexOptions {
  { codex_path_override, base_url, api_key, config, config_overrides, env, }
}

// #endregion

// #region threadOptions.ts

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
pub impl Show for ApprovalMode with fn output(self, logger) {
  match self {
    Never => logger.write_string("never")
    OnRequest => logger.write_string("on-request")
    OnFailure => logger.write_string("on-failure")
    Untrusted => logger.write_string("untrusted")
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
} derive(Debug)

///|
/// Convert SandboxMode to its string representation for CLI arguments.
pub impl Show for SandboxMode with fn output(self : SandboxMode, logger) {
  match self {
    ReadOnly => logger.write_string("read-only")
    WorkspaceWrite => logger.write_string("workspace-write")
    DangerFullAccess => logger.write_string("danger-full-access")
  }
}

///|
pub(all) enum ModelReasoningEffort {
  Minimal
  Low
  Medium
  High
  Xhigh
  Max
  Ultra
}

///|
pub impl Show for ModelReasoningEffort with fn output(self, logger) {
  match self {
    Minimal => logger.write_string("minimal")
    Low => logger.write_string("low")
    Medium => logger.write_string("medium")
    High => logger.write_string("high")
    Xhigh => logger.write_string("xhigh")
    Max => logger.write_string("max")
    Ultra => logger.write_string("ultra")
  }
}

///|
/// Web search behavior for Codex turns.
pub(all) enum WebSearchMode {
  Disabled
  Cached
  Live
}

///|
pub impl Show for WebSearchMode with fn output(self, logger) {
  match self {
    Disabled => logger.write_string("disabled")
    Cached => logger.write_string("cached")
    Live => logger.write_string("live")
  }
}

///|
/// Options for configuring a thread.
struct ThreadOptions {
  /// The model to use for the thread
  model : String?
  /// Source classification applied when this thread is first created.
  thread_source : String?
  /// The sandbox mode
  sandbox_mode : SandboxMode?
  /// The working directory
  working_directory : String?
  /// Whether to skip git repository check
  skip_git_repo_check : Bool?
  /// The reasoning effort level for the model
  model_reasoning_effort : ModelReasoningEffort?
  /// Whether network access is enabled
  network_access_enabled : Bool?
  /// Whether web search is enabled
  web_search_enabled : Bool?
  /// Web search behavior. Takes precedence over `web_search_enabled`.
  web_search_mode : WebSearchMode?
  /// Approval policy for actions that require user consent
  approval_policy : ApprovalMode?
  /// Additional directories to mount into the agent's sandbox
  additional_directories : Array[String]?
} derive(Default)

///|
pub fn ThreadOptions::new(
  model? : String,
  thread_source? : String,
  sandbox_mode? : SandboxMode,
  working_directory? : String,
  skip_git_repo_check? : Bool,
  model_reasoning_effort? : ModelReasoningEffort,
  network_access_enabled? : Bool,
  web_search_enabled? : Bool,
  web_search_mode? : WebSearchMode,
  approval_policy? : ApprovalMode,
  additional_directories? : Array[String],
) -> ThreadOptions {
  {
    model,
    thread_source,
    sandbox_mode,
    working_directory,
    skip_git_repo_check,
    model_reasoning_effort,
    network_access_enabled,
    web_search_enabled,
    web_search_mode,
    approval_policy,
    additional_directories,
  }
}

// #endregion

// #region turnOptions.ts

// Note : we don't need abort signal due to the structural currency nature of MoonBit Async

///|
/// Options for configuring a turn.
struct TurnOptions {
  /// JSON schema describing the expected agent output
  output_schema : Json?
} derive(Default)

///|
/// Params:
/// - `output_schema` - JSON schema describing the expected agent output
pub fn TurnOptions::new(output_schema? : Json) -> TurnOptions {
  { output_schema, }
}

// #endregion
