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

///|
/// Arguments for executing a Codex command.
priv struct CodexExecArgs {
  /// The input prompt/message to send to Codex
  input : String
  // Images to send to Codex
  images : Array[String]
  /// Thread ID to resume, or None for a new thread
  thread_id : String?
  codex_options : CodexOptions
  thread_options : ThreadOptions
  turn_options : TurnOptions
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
async fn[T] CodexExec::run(
  self : Self,
  args : CodexExecArgs,
  taskgroup : @async.TaskGroup[T],
) -> @generator.AsyncGenerator[String] raise Error {
  // Build command arguments
  let command_args : Array[String] = ["exec", "--experimental-json"]

  if args.codex_options.config is Some(config) {
    for config_override in serialize_config_overrides(config) {
      command_args.push("--config")
      command_args.push(config_override)
    }
  }
  if args.codex_options.config_overrides is Some(overrides) {
    for config_override in overrides {
      command_args.push("--config")
      command_args.push(config_override)
    }
  }
  if args.codex_options.base_url is Some(base_url) {
    command_args.push("--config")
    command_args.push(
      "openai_base_url=\{codex_config_toml_value(base_url.to_json(), "openai_base_url")}",
    )
  }

  // Add optional arguments
  if args.thread_options.model is Some(model) {
    command_args.push("--model")
    command_args.push(model)
  }
  if args.thread_options.thread_source is Some(thread_source) &&
    args.thread_id is None {
    command_args.push("--thread-source")
    command_args.push(thread_source)
  }
  if args.thread_options.sandbox_mode is Some(sandbox_mode) {
    command_args.push("--sandbox")
    command_args.push(sandbox_mode.to_string())
  }
  if args.thread_options.working_directory is Some(working_directory) {
    command_args.push("--cd")
    command_args.push(working_directory)
  }
  if args.thread_options.additional_directories is Some(additional_directories) {
    for dir in additional_directories {
      command_args.push("--add-dir")
      command_args.push(dir)
    }
  }
  if args.thread_options.skip_git_repo_check is Some(true) {
    command_args.push("--skip-git-repo-check")
  }
  if args.turn_options.output_schema is Some(schema) {
    let file = create_output_schema_file(schema)
    taskgroup.add_defer(() => (file.cleanup)())
    command_args.push("--output-schema")
    command_args.push(file.schema_path)
  }
  if args.thread_options.model_reasoning_effort is Some(effort) {
    command_args.push("--config")
    command_args.push(
      "model_reasoning_effort=\{effort.to_string().to_json().stringify()}",
    )
  }
  if args.thread_options.network_access_enabled is Some(option) {
    command_args.push("--config")
    command_args.push("sandbox_workspace_write.network_access=\{option}")
  }
  if args.thread_options.web_search_mode is Some(mode) {
    command_args.push("--config")
    command_args.push("web_search=\{mode.to_string().to_json().stringify()}")
  } else if args.thread_options.web_search_enabled is Some(true) {
    command_args.push("--config")
    command_args.push("web_search=\"live\"")
  } else if args.thread_options.web_search_enabled is Some(false) {
    command_args.push("--config")
    command_args.push("web_search=\"disabled\"")
  }
  if args.thread_options.approval_policy is Some(approval_policy) {
    command_args.push("--config")
    command_args.push(
      "approval_policy=\{approval_policy.to_string().to_json().stringify()}",
    )
  }
  if args.thread_id is Some(thread_id) {
    command_args.push("resume")
    command_args.push(thread_id)
  }
  for image in args.images {
    command_args.push("--image")
    command_args.push(image)
  }

  // Add env
  let env = @sys.get_env_vars()
  let extra_env = args.codex_options.env.unwrap_or({})
  if env.get(INTERNAL_ORIGINATOR_ENV) is None {
    extra_env.set(INTERNAL_ORIGINATOR_ENV, MOONBIT_SDK_ORIGINATOR)
  }
  if args.codex_options.api_key is Some(api_key) {
    extra_env.set("CODEX_API_KEY", api_key)
  }

  // CodexExec
  @generator.AsyncGenerator::new(
    async fn(yield_) {
      let stdin = @process.write_to_process() catch {
        e => raise @error.reraise(e)
      }
      let stdout = @process.read_from_process() catch {
        e => raise @error.reraise(e)
      }
      @async.with_task_group(taskgroup => {
        taskgroup.spawn_bg(() => {
          let (exit_code, stderr) = @process.collect_stderr(
            self.executable_path,
            command_args,
            stdin=stdin.0,
            stdout=stdout.1,
            inherit_env=args.codex_options.env is None,
            extra_env~,
          )
          if exit_code != 0 {
            @error.fail("Codex CLI failed: \{stderr.text()}")
          }
        })
        taskgroup.spawn_bg(() => {
          defer stdin.1.close()
          stdin.1.write(args.input)
        })
        let reader = stdout.0
        defer reader.close()
        while reader.read_until("\n") is Some(text) {
          yield_(text) catch {
            @generator.Return => return
            e => raise @error.reraise(e)
          }
        }
      })
    },
    taskgroup,
  )
}

///|
fn serialize_config_overrides(
  config : Map[String, Json],
) -> Array[String] raise Error {
  let overrides : Array[String] = []
  for key, value in config {
    if key == "" {
      @error.fail("Codex config override keys must be non-empty strings")
    }
    flatten_config_override(value, key, overrides)
  }
  overrides
}

///|
fn flatten_config_override(
  value : Json,
  path : String,
  overrides : Array[String],
) -> Unit raise Error {
  match value {
    Object(entries) => {
      if entries.is_empty() {
        overrides.push("\{path}={}")
        return
      }
      for key, child in entries {
        if key == "" {
          @error.fail("Codex config override keys must be non-empty strings")
        }
        flatten_config_override(child, "\{path}.\{key}", overrides)
      }
    }
    _ => overrides.push("\{path}=\{codex_config_toml_value(value, path)}")
  }
}

///|
fn codex_config_toml_value(value : Json, path : String) -> String raise Error {
  match value {
    Null => @error.fail("Codex config override at \{path} cannot be null")
    String(_) | Number(_) | True | False => value.stringify()
    Array(items) => {
      let rendered : Array[String] = []
      for index, item in items {
        rendered.push(codex_config_toml_value(item, "\{path}[\{index}]"))
      }
      "[\{rendered.join(", ")}]"
    }
    Object(entries) => {
      let rendered : Array[String] = []
      for key, child in entries {
        if key == "" {
          @error.fail("Codex config override keys must be non-empty strings")
        }
        rendered.push(
          "\{key.to_json().stringify()} = \{codex_config_toml_value(child, "\{path}.\{key}")}",
        )
      }
      "{\{rendered.join(", ")}}"
    }
  }
}
