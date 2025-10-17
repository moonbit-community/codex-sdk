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
/// Arguments for executing a Codex command.
struct CodexExecArgs {
  /// The input prompt/message to send to Codex
  input : String
  /// Base URL for the API
  base_url : String?
  /// API key for authentication
  api_key : String?
  /// Thread ID to resume, or None for a new thread
  thread_id : String?
  /// Model to use (e.g., "gpt-4")
  model : String?
  /// Sandbox mode that controls access level
  sandbox_mode : SandboxMode?
  /// Working directory to run commands in
  working_directory : String?
  /// Whether to skip git repository check
  skip_git_repo_check : Bool?
  /// Output schema file path
  output_schema_file : String?
}

///|
pub fn CodexExecArgs::new(
  input : String,
  base_url? : String,
  api_key? : String,
  thread_id? : String,
  model? : String,
  sandbox_mode? : SandboxMode,
  working_directory? : String,
  skip_git_repo_check? : Bool,
  output_schema_file? : String,
) -> CodexExecArgs {
  {
    input,
    base_url,
    api_key,
    thread_id,
    model,
    sandbox_mode,
    working_directory,
    skip_git_repo_check,
    output_schema_file,
  }
}

// Constants for environment variable names
// TODO: Use these when implementing process spawning with env vars

///|
const INTERNAL_ORIGINATOR_ENV : String = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"

///|
const MOONBIT_SDK_ORIGINATOR : String = "codex_sdk_moonbit"

///|
/// The CodexExec class handles spawning and communicating with the codex CLI.
priv struct CodexExec {
  executable_path : String
}

///|
/// Create a new CodexExec instance.
///
/// # Arguments
/// * `executable_path` - Optional path to the codex executable. Default to "codex".
fn CodexExec::new(executable_path? : String = "codex") -> CodexExec {
  // For simplicity, we assume "codex" is in PATH if not provided.
  { executable_path, }
}

///|
/// Run a Codex command and yield output lines as they arrive.
///
/// This spawns the codex CLI process, sends the input, and yields each line
/// of JSON output as it's received.
///
/// # Arguments
/// * `args` - The arguments for the Codex execution
///
/// # Returns
/// An iterator that yields String lines from the Codex output
fn CodexExec::run(
  self : Self,
  args : CodexExecArgs,
) -> @generator.AsyncGenerator[String] raise {
  // Build command arguments
  let command_args : Array[String] = ["exec", "--experimental-json"]

  // Add optional arguments
  if args.model is Some(model) {
    command_args.push("--model")
    command_args.push(model)
  }
  if args.sandbox_mode is Some(sandbox_mode) {
    command_args.push("--sandbox")
    command_args.push(sandbox_mode.to_string())
  }
  if args.working_directory is Some(working_directory) {
    command_args.push("--cd")
    command_args.push(working_directory)
  }
  if args.skip_git_repo_check is Some(true) {
    command_args.push("--skip-git-repo-check")
  }
  if args.output_schema_file is Some(output_schema_file) {
    command_args.push("--output-schema")
    command_args.push(output_schema_file)
  }
  if args.thread_id is Some(thread_id) {
    command_args.push("resume")
    command_args.push(thread_id)
  }

  // Add env
  let env = @sys.get_env_vars()
  let extra_env = {}
  if env.get(INTERNAL_ORIGINATOR_ENV) is None {
    extra_env.set(INTERNAL_ORIGINATOR_ENV, MOONBIT_SDK_ORIGINATOR)
  }
  if args.base_url is Some(base_url) {
    extra_env.set("OPENAI_BASE_URL", base_url)
  }
  if args.api_key is Some(api_key) {
    extra_env.set("CODEX_API_KEY", api_key)
  }
  let stdin = @process.write_to_process()
  let stdout = @process.read_from_process()
  let stderr = @process.read_from_process()
  let stderr_chunks = StringBuilder::new()

  // CodexExec
  @generator.AsyncGenerator::new(fn(yield_) {
    @async.with_task_group(taskgroup => {
      taskgroup.spawn_bg(() => {
        let exit_code = @process.run(
          self.executable_path,
          command_args,
          stdin=stdin.0,
          stdout=stdout.1,
          stderr=stderr.1,
          extra_env~,
        )
        if exit_code != 0 {
          fail("Codex CLI failed: \{stderr_chunks.to_string()}")
        }
      })
      taskgroup.spawn_bg(() => {
        stdin.1.write(args.input)
        stdin.1.close()
      })
      taskgroup.spawn_bg(() => {
        let reader = @io.BufferedReader::new(stderr.0)
        while (Some(reader.find(b"\n")) catch {
                @io.ReaderClosed => None
                e => raise e
              })
              is Some(length) {
          let text = @encoding/utf8.decode(reader[:length])
          stderr_chunks.write_string(text)
          reader.drop(length + 1)
        } else {
          let text = reader.read_all().text()
          stderr_chunks.write_string(text)
        }
      })
      taskgroup.spawn_bg(() => {
        let reader = @io.BufferedReader::new(stdout.0)
        try {
          while true {
            let length = reader.find(b"\n")
            let text = @encoding/utf8.decode(reader[:length])
            yield_(text)
            reader.drop(length + 1)
          }
        } catch {
          @io.ReaderClosed => {
            let text = reader.read_all().text()
            if !text.is_empty() {
              yield_(text)
            }
          }
          e => raise e
        }
      })
    })
  })
}

///|
/// Convert SandboxMode to its string representation for CLI arguments.
fn to_string(self : SandboxMode) -> String {
  match self {
    ReadOnly => "read-only"
    WorkspaceWrite => "workspace-write"
    DangerFullAccess => "danger-full-access"
  }
}
