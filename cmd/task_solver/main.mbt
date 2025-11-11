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
  /// Read task from stdin instead of file or argument
  mut use_stdin : Bool
  /// Read task from a file (explicit file path)
  mut file : String
  /// Working directory for task execution
  mut working_dir : String
  /// Show help message
  mut help : Bool
  /// Model to use for task solving
  mut model : String?
  /// Verbose output mode
  mut verbose : Bool
  /// Skip git checks
  mut skip_git_check : Bool
  /// Sandbox mode (WorkspaceWrite or DangerousFullAccess)
  mut sandbox_mode : @codex.SandboxMode
  /// Resume an existing thread by ID
  mut resume_thread_id : String?
}

///|
fn parse_args(args : @args.Args) -> Arguments {
  let arguments = {
    task: "",
    use_stdin: false,
    file: "",
    working_dir: ".",
    help: false,
    model: None,
    verbose: false,
    skip_git_check: false,
    sandbox_mode: WorkspaceWrite,
    resume_thread_id: None,
  }

  // Parse flags
  if args.flags.get("stdin") is Some(true) {
    arguments.use_stdin = true
  }
  if args.flags.get("help") is Some(true) {
    arguments.help = true
  }
  if args.flags.get("verbose") is Some(true) ||
    args.flags.get("v") is Some(true) {
    arguments.verbose = true
  }
  if args.flags.get("skip-git-check") is Some(true) {
    arguments.skip_git_check = true
  }

  // Parse options
  if args.options.get("working-dir") is Some(value) {
    arguments.working_dir = value
  }
  if args.options.get("model") is Some(value) {
    arguments.model = Some(value)
  }
  if args.options.get("file") is Some(value) {
    arguments.file = value
  }
  if args.options.get("sandbox-mode") is Some(mode) &&
    mode is ("DangerousFullAccess" | "WorkspaceWrite" | "ReadOnly") {
    match mode {
      "DangerousFullAccess" =>
        arguments.sandbox_mode = @codex.SandboxMode::DangerFullAccess
      "WorkspaceWrite" =>
        arguments.sandbox_mode = @codex.SandboxMode::WorkspaceWrite
      "ReadOnly" => arguments.sandbox_mode = @codex.SandboxMode::ReadOnly
      _ => panic()
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
  if arguments.use_stdin {
    // Read from stdin - for now, just return empty since async stdin reading is complex
    @stdio.stdout.write("Note: stdin reading not yet implemented\n")
    ""
  } else if !arguments.file.is_empty() {
    // Read from file
    if @fs.exists(arguments.file) {
      @fs.read_file(arguments.file).text() catch {
        e => @error.fail_with("Failed to read file '\{arguments.file}'", e)
      }
    } else {
      @error.fail("File not found: \{arguments.file}")
    }
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
  working_dir : String,
  model : String?,
  verbose : Bool,
  skip_git_check : Bool,
  sandbox_mode : @codex.SandboxMode,
  resume_thread_id : String?,
) -> Unit {
  try {
    if task.is_empty() {
      @error.fail("No task provided")
    }
    let git_check_status = if skip_git_check { "SKIPPED" } else { "enabled" }
    @stdio.stdout.write(
      (
        #|=== MoonBit Task Solver ===
        #|
        $|Working directory: \{working_dir}
        $|Model: \{model}
        $|Sandbox mode: \{sandbox_mode.to_json().as_string().unwrap()}
        $|Git check: \{git_check_status}
        $|Task:
        $|\{task}
        $|
        #|---
        #|
      ),
    )

    // Build the enhanced prompt with system context
    let system_context = build_system_context()
    let full_prompt =
      $|\{system_context}
      #|
      #|## TASK:
      $|\{task}
      #|
    if verbose {
      @stdio.stdout.write("=== System Context ===\n\{system_context}\n\n")
    }

    // Initialize Codex with appropriate sandbox mode
    let codex = @codex.Codex::new()
    let options = @codex.ThreadOptions::new(
      model?,
      sandbox_mode~,
      working_directory=working_dir,
      skip_git_repo_check=skip_git_check,
    )
    let thread = if resume_thread_id is Some(thread_id) {
      @stdio.stdout.write("Resuming thread: \{thread_id}\n")
      codex.resume_thread(thread_id, options~)
    } else {
      codex.start_thread(options~)
    }
    @stdio.stdout.write("Starting AI agent...\n\n")
    let mut thread_id = thread.id()
    let events = thread.run_streamed(full_prompt) catch {
      e => @error.fail_with("Failed to send user message", e)
    }
    let mut final_response = ""
    let mut usage : @codex.Usage? = None
    try {
      while events.events.next() is Some(event) {
        match event {
          @codex.ThreadStarted(thread_id=tid) => {
            thread_id = Some(tid)
            @stdio.stdout.write(
              (
                #|=== Thread Started ===
                $|Thread ID: \{tid}
                #|
              ),
            )
          }
          @codex.TurnStarted =>
            if verbose {
              @stdio.stdout.write(
                (
                  #|=== Turn Started ===
                  #|
                ),
              )
            }
          @codex.ItemStarted(item) =>
            if verbose {
              match item {
                @codex.ReasoningItem(text~, ..) =>
                  @stdio.stdout.write("💭 Reasoning: \{text}\n\n")
                @codex.CommandExecutionItem(command~, ..) =>
                  @stdio.stdout.write("⚙️ Executing command: \{command}\n")
                @codex.FileChangeItem(changes~, ..) => {
                  @stdio.stdout.write("📝 File changes:\n")
                  for change in changes {
                    let kind_str = match change.kind {
                      @codex.Add => "Adding"
                      @codex.Delete => "Deleting"
                      @codex.Update => "Updating"
                    }
                    @stdio.stdout.write("   \{kind_str}: \{change.path}\n")
                  }
                  @stdio.stdout.write("\n")
                }
                @codex.TodoListItem(items~, ..) => {
                  @stdio.stdout.write("📋 Todo List:\n")
                  for i = 0; i < items.length(); i = i + 1 {
                    let todo = items[i]
                    let status = if todo.completed { "✓" } else { " " }
                    @stdio.stdout.write("   [\{status}] \{todo.text}\n")
                  }
                  @stdio.stdout.write("\n")
                }
                @codex.McpToolCallItem(server~, tool~, ..) =>
                  @stdio.stdout.write(
                    "🔧 Calling MCP tool: \{server}/\{tool}\n",
                  )
                @codex.WebSearchItem(query~, ..) =>
                  @stdio.stdout.write("🔍 Web search: \{query}\n")
                _ => ()
              }
            }
          @codex.ItemUpdated(item) =>
            if verbose {
              match item {
                @codex.TodoListItem(items~, ..) => {
                  @stdio.stdout.write("📋 Todo List Updated:\n")
                  for i = 0; i < items.length(); i = i + 1 {
                    let todo = items[i]
                    let status = if todo.completed { "✓" } else { " " }
                    @stdio.stdout.write("   [\{status}] \{todo.text}\n")
                  }
                  @stdio.stdout.write("\n")
                }
                @codex.CommandExecutionItem(aggregated_output~, ..) =>
                  if !aggregated_output.is_empty() {
                    @stdio.stdout.write("   Output: \{aggregated_output}\n")
                  }
                _ => ()
              }
            }
          @codex.ItemCompleted(item) =>
            if verbose {
              match item {
                @codex.AgentMessageItem(text~, ..) => {
                  final_response = text
                  @stdio.stdout.write("💬 Agent: \{text}\n\n")
                }
                @codex.CommandExecutionItem(status~, exit_code~, ..) => {
                  let status_str = match status {
                    @codex.Completed => "✓ Completed"
                    @codex.Failed => "✗ Failed"
                    @codex.InProgress => "In Progress"
                  }
                  @stdio.stdout.write("   Status: \{status_str}")
                  if exit_code is Some(code) {
                    @stdio.stdout.write(" (exit code: \{code})")
                  }
                  @stdio.stdout.write("\n\n")
                }
                @codex.ErrorItem(message~, ..) =>
                  @stdio.stdout.write("❌ Error: \{message}\n\n")
                _ => ()
              }
            } else if item is @codex.AgentMessageItem(text~, ..) {
              final_response = text
            }
          @codex.TurnCompleted(u) => {
            usage = Some(u)
            if verbose {
              @stdio.stdout.write("=== Turn Completed ===\n\n")
            }
          }
          @codex.TurnFailed(error) =>
            @error.fail("Turn failed: \{error.message}")
          @codex.ThreadErrorEvent(message) =>
            @error.fail("Thread error: \{message}")
        }
      }
    } catch {
      e => {
        while events.events.returns() is Some(_) {
          // Must drain the generator to avoid unhandled promise rejection
        }
        @error.reraise(e)
      }
    }

    // Print summary
    @stdio.stdout.write(
      (
        #|=== Agent Response ===
        $|\{final_response}
        $|
      ),
    )
    if usage is Some(u) {
      @stdio.stdout.write(
        (
          #|=== Usage Stats ===
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
        $|Thread ID: \{thread_id}
        #|=== Task Complete ===
        $|
      ),
    )
  } catch {
    error => @stdio.stdout.write("❌ Error during task execution: \{error}\n")
  }
}

///|
/// Main entry point with CLI argument parsing
async fn main {
  let help_message =
    $|
    $|Usage: moon run cmd/task_solver -- [OPTIONS] [TASK]
    $|
    $|An intelligent task solver that can accept tasks and solve them, with the ability
    $|to create new tools in this repository when needed.
    $|
    $|Arguments:
    $|  [TASK]                    Task description (direct text)
    $|
    $|Options:
    $|  --file <path>             Read task from a file
    $|  --stdin                   Read task from stdin instead of argument
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
    $|  # Solve a task from a file
    $|  moon run cmd/task_solver -- --file task.txt
    $|
    $|  # Read task from stdin
    $|  echo "Fix all warnings in this project" | moon run cmd/task_solver -- --stdin
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
    $|
  // Parse CLI arguments
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["stdin", "help", "verbose", "v", "skip-git-check"],
    options=["working-dir", "model", "file", "sandbox-mode", "resume"],
    aliases={ "h": "help" },
  )
  let arguments = parse_args(args)
  if arguments.help {
    @stdio.stdout.write("\{help_message}\n")
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
    arguments.working_dir,
    arguments.model,
    arguments.verbose,
    arguments.skip_git_check,
    arguments.sandbox_mode,
    arguments.resume_thread_id,
  )
}
