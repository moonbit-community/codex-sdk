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
/// CLI arguments structure for task solver
struct Arguments {
  /// Task description or path to file containing task
  mut task : String
  /// Working directory for task execution
  mut working_dir : String?
  /// Show help message
  mut help : Bool
  /// Model to use for task solving
  mut model : String?
  /// Verbose output mode
  mut verbose : Bool
  /// Skip git checks
  mut skip_git_repo_check : Bool?
  /// Sandbox mode (WorkspaceWrite or DangerousFullAccess)
  mut sandbox_mode : @codex.SandboxMode?
  /// Resume an existing thread by ID
  mut resume_thread_id : String?
}

///|
fn parse_args(args : @args.Args) -> Arguments {
  let arguments = {
    task: "",
    working_dir: None,
    help: false,
    model: None,
    verbose: false,
    skip_git_repo_check: None,
    sandbox_mode: None,
    resume_thread_id: None,
  }

  // Parse flags
  if args.flags.get("help") is Some(true) {
    arguments.help = true
  }
  if args.flags.get("verbose") is Some(true) {
    arguments.verbose = true
  }
  arguments.skip_git_repo_check = args.flags.get("skip-git-check")

  // Parse options
  arguments.working_dir = args.options.get("working-dir")
  arguments.model = args.options.get("model")
  if args.options.get("sandbox-mode") is Some(mode) &&
    mode is ("DangerousFullAccess" | "WorkspaceWrite" | "ReadOnly") {
    match mode {
      "DangerousFullAccess" =>
        arguments.sandbox_mode = Some(@codex.SandboxMode::DangerFullAccess)
      "WorkspaceWrite" =>
        arguments.sandbox_mode = Some(@codex.SandboxMode::WorkspaceWrite)
      "ReadOnly" => arguments.sandbox_mode = Some(@codex.SandboxMode::ReadOnly)
      _ => ()
    }
  }
  if args.options.get("resume") is Some(value) {
    arguments.resume_thread_id = Some(value)
  }

  // Parse positional arguments (task description or file path)
  if args.positional.length() > 0 {
    arguments.task = args.positional[0]
  }
  arguments
}

///|
/// Read task description from various sources
async fn read_task(arguments : Arguments) -> String {
  if arguments.task == "-" {
    @stdio.stdin.read_all().text()
  } else {
    // Return the task as-is (direct task description)
    arguments.task
  }
}

///|
/// Build the system prompt that gives the agent awareness of its capabilities
fn build_system_context() -> String {
  (
    #|You are an intelligent task solver with special capabilities.
    #|
    #|## Your Capabilities:
    #|1. **File Operations**: You can read, write, and modify files in the workspace.
    #|2. **MoonBit Ecosystem**: You can use MoonBit commands:
    #|   - Use `moon new` to create new MoonBit project
    #|   - Use `moon check` to validate code
    #|   - Use `moon test` to run tests
    #|   - Use `moon fmt` to format code
    #|   - Use `moon info` to update interface files
    #|3. **Git Operations**: You can clone repos, create branches, commit, and push.
    #|4. **Other MCP Tools**: You can call other MCP tools as needed.
    #|5. **Self-Improvement**: You can use MoonBit to create new tools.
    #|   - Use `peter-jerry-ye/codex` to create AI agent tools.
    #|
    #|## Task Solving Approach:
    #|1. **Analyze** the task requirements carefully 
    #|2. **Plan** your approach - break down complex tasks into steps
    #|3. **Execute** - implement the solution step by step
    #|4. **Verify** - test that your solution works
    #|5. **Document** - if you create a new tool, document it
    #|
    #|## Special Instructions:
    #|- If the task requires a new tool that doesn't exist, CREATE IT!
    #|- Follow MoonBit coding conventions
    #|- Run `moon fmt && moon info` after creating/modifying code
    #|- Prefer creating reusable tools over one-off solutions
    #|Now, please solve the task that follows.
    #|
  )
}

///|
/// Main task solver workflow
async fn solve_task(
  task : String,
  model? : String,
  verbose : Bool,
  working_directory? : String,
  sandbox_mode? : @codex.SandboxMode,
  skip_git_repo_check? : Bool,
  resume_thread_id? : String,
) -> Unit {
  try {
    if task.is_empty() {
      @error.fail("No task provided")
    }
    let mode = if sandbox_mode is Some(mode) {
      mode.to_json()
    } else {
      "Unknown"
    }
    @stdio.stdout.write(
      (
        $|=== MoonBit Task Solver ===
        $|
        $|Working directory: \{working_directory.unwrap_or(@env.current_dir().unwrap_or("Unknown"))}
        $|Model: \{model.unwrap_or("Unknown")}
        $|Sandbox mode: \{mode}
        $|Task:
        $|\{task}
        $|
        $|---
        $|
      ),
    )

    // Build the enhanced prompt with system context
    let system_context = build_system_context()
    let full_prompt =
      $|\{system_context}
      $|
      $|## TASK:
      $|\{task}
      $|
    if verbose {
      @stdio.stdout.write("=== System Context ===\n\{system_context}\n\n")
    }

    // Initialize Codex with appropriate sandbox mode
    let codex = @codex.Codex::new(
      options=@codex.CodexOptions::new(
        codex_path_override="./alternative_codex.sh",
      ),
    )
    let options = @codex.ThreadOptions::new(
      model?,
      sandbox_mode?,
      working_directory?,
      skip_git_repo_check?,
    )
    let thread = if resume_thread_id is Some(thread_id) {
      @stdio.stdout.write("Resuming thread: \{thread_id}\n")
      codex.resume_thread(thread_id, options~)
    } else {
      codex.start_thread(options~)
    }
    @stdio.stdout.write("Starting AI agent...\n\n")
    let events = thread.run(full_prompt) catch {
      e => @error.fail_with("Failed to send user message", e)
    }
    let final_response = events.final_response
    let usage : @codex.Usage? = events.usage

    // Print summary
    @stdio.stdout.write(
      (
        $|=== Agent Response ===
        $|\{final_response}
        $|
      ),
    )
    if usage is Some(u) {
      @stdio.stdout.write(
        (
          $|=== Usage Stats ===
          $|Input tokens: \{u.input_tokens}
          $|Output tokens: \{u.output_tokens}
          $|
        ),
      )
      if u.cached_input_tokens > 0 {
        @stdio.stdout.write("Cached tokens: \{u.cached_input_tokens}\n")
      }
    }
    @stdio.stdout.write(
      (
        $|Thread ID: \{thread.id().unwrap_or("Unknown")}
        $|=== Task Complete ===
        $|
      ),
    )
  } catch {
    error => @stdio.stderr.write("❌ Error during task execution: \{error}\n")
  }
}

///|
/// Main entry point with CLI argument parsing and interactive mode
async fn main {
  let help_message =
    $|
    $|Usage: moon run cmd/task_solver -- [OPTIONS] [TASK]
    $|
    $|An intelligent task solver that can accept tasks and solve them, with the ability
    $|to create new tools in this repository when needed.
    $|
    $|Arguments:
    $|  [TASK]                    Task description (direct text) - if omitted, enters interactive mode
    $|
    $|Options:
    $|  --working-dir <path>      Working directory for task execution (default: .)
    $|  --model <model>           AI model to use (default: anthropic/claude-sonnet-4)
    $|  --resume <thread_id>      Resume an existing thread by ID
    $|  --sandbox-mode <mode>     Set sandbox mode (DangerousFullAccess, WorkspaceWrite, ReadOnly; default: WorkspaceWrite)
    $|  --skip-git-check          Skip git repository checks
    $|  -v, --verbose             Enable verbose output showing all actions
    $|  -h, --help                Show this help message
    $|
    $|Examples:
    $|  # Solve a task from command line
    $|  moon run cmd/task_solver -- "Create a tool that lists all functions in a MoonBit project"
    $|
    $|  # Interactive mode (no task argument)
    $|  moon run cmd/task_solver
    $|
    $|  # Use a different model
    $|  moon run cmd/task_solver -- --model "openai/gpt-4" "Document all exported functions"
    $|
    $|  # Resume an existing thread
    $|  moon run cmd/task_solver -- --resume <thread_id> "Continue the previous task"
    $|
    $|  # Use dangerous full access mode
    $|  moon run cmd/task_solver -- --sandbox-mode DangerousFullAccess "Delete all temp files"
    $|
    $|Special Features:
    $|  - Can create new tools under cmd/ directory when needed
    $|  - Aware of MoonBit project structure and conventions
    $|  - Can use git, moon, and other utilities from x/
    $|  - Has workspace write permissions for implementing solutions
    $|  - Interactive mode for multi-turn conversations
    $|
  // Parse CLI arguments
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["stdin", "help", "verbose", "v", "skip-git-check"],
    options=["working-dir", "model", "file", "sandbox-mode", "resume"],
    aliases={ "h": "help" },
  ) catch {
    e => {
      @stdio.stdout.write("Error parsing arguments: \{e}\n")
      @stdio.stdout.write("\{help_message}\n")
      return
    }
  }
  let arguments = parse_args(args)
  if arguments.help {
    @stdio.stdout.write("\{help_message}\n")
    return
  }

  // If no task provided, enter interactive mode
  if arguments.task.is_empty() {
    run_interactive_mode(arguments)
    return
  }

  // Read the task
  let task = read_task(arguments)
  if task.is_empty() {
    @error.fail("No task provided. Use --help for usage information")
  }
  // Execute the task solver
  solve_task(
    task,
    arguments.verbose,
    working_directory?=arguments.working_dir,
    model?=arguments.model,
    skip_git_repo_check?=arguments.skip_git_repo_check,
    sandbox_mode?=arguments.sandbox_mode,
    resume_thread_id?=arguments.resume_thread_id,
  )
}

///|
/// Interactive mode for multi-turn conversations
async fn run_interactive_mode(arguments : Arguments) -> Unit {
  try {
    // Initialize Codex with appropriate sandbox mode
    let codex = @codex.Codex::new(
      options=@codex.CodexOptions::new(
        codex_path_override="./alternative_codex.sh",
      ),
    )
    let options = @codex.ThreadOptions::new(
      model?=arguments.model,
      sandbox_mode?=arguments.sandbox_mode,
      working_directory?=arguments.working_dir,
      skip_git_repo_check?=arguments.skip_git_repo_check,
    )
    let thread = if arguments.resume_thread_id is Some(thread_id) {
      @stdio.stdout.write("Resuming thread: \{thread_id}\n")
      codex.resume_thread(thread_id, options~)
    } else {
      codex.start_thread(options~)
    }

    // Build the system context once
    let system_context = build_system_context()
    let mode = if arguments.sandbox_mode is Some(mode) {
      mode.to_json()
    } else {
      "Unknown"
    }
    @stdio.stdout.write(
      (
        $|=== MoonBit Task Solver (Interactive Mode) ===
        $|
        $|Model: \{arguments.model.unwrap_or("Unknown")}
        $|Sandbox mode: \{mode}
        $|Working directory: \{arguments.working_dir.unwrap_or(@env.current_dir().unwrap_or("Unknown"))}
        $|Thread ID: \{thread.id().unwrap_or("Unknown")}
        $|
        $|Type your tasks at the prompt. Press Ctrl+D or Ctrl+C to exit.
        $|
      ),
    )
    let reader = @stdio.stdin
    while true {
      @stdio.stdout.write(b"> ")
      try {
        guard reader.read_until("\n") is Some(line) else { break }
        if line.trim().is_empty() {
          continue
        }

        // Build the full prompt with system context
        let full_prompt =
          $|\{system_context}
          $|
          $|## TASK:
          $|\{line}
          $|
        let turn = @async.with_task_group(taskgroup => {
          taskgroup.add_defer(() => @stdio.stdout.write(b"\r"))
          taskgroup.spawn_bg(
            () => while true {
              @async.sleep(500)
              @stdio.stdout.write(b"\r\\")
              @async.sleep(500)
              @stdio.stdout.write(b"\r|")
              @async.sleep(500)
              @stdio.stdout.write(b"\r/")
              @async.sleep(500)
              @stdio.stdout.write(b"\r-")
            },
            no_wait=true,
          )
          thread.run(full_prompt)
        })
        @stdio.stdout.write("\r\{turn.final_response}\n")
        if turn.usage is Some(u) {
          @stdio.stdout.write(
            (
              $|=== Usage Stats (\{thread.id().unwrap_or("Unknown")}) ===
              $|Input tokens: \{u.input_tokens}
              $|Cached tokens: \{u.cached_input_tokens}
              $|Output tokens: \{u.output_tokens}
              $|===
              $|
            ),
          )
        }
      } catch {
        e => raise e
      }
    }
    @stdio.stdout.write(
      (
        #|
        #|=== Task Solver Session Complete ===
        #|
      ),
    )
  } catch {
    error =>
      @stdio.stderr.write("❌ Error during interactive session: \{error}\n")
  }
}
