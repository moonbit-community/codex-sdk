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
  mut model : String
  /// Verbose output mode
  mut verbose : Bool
} derive(Default)

///|
fn parse_args(args : @args.Args) -> Arguments {
  let arguments = Arguments::default()

  // Set defaults
  arguments.task = ""
  arguments.use_stdin = false
  arguments.file = ""
  arguments.working_dir = "."
  arguments.help = false
  arguments.model = "anthropic/claude-sonnet-4"
  arguments.verbose = false

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

  // Parse options
  if args.options.get("working-dir") is Some(value) {
    arguments.working_dir = value
  }
  if args.options.get("model") is Some(value) {
    arguments.model = value
  }
  if args.options.get("file") is Some(value) {
    arguments.file = value
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
      @fs.read_file(arguments.file).text()
    } else {
      @stdio.stdout.write("Error: File not found: \{arguments.file}\n")
      ""
    }
  } else {
    // Return the task as-is (direct task description)
    arguments.task
  }
}

///|
/// Build the system prompt that gives the agent awareness of its capabilities
fn build_system_context(working_dir : String) -> String {
  let context = StringBuilder::new()
  context.write_string(
    "You are an intelligent task solver with special capabilities.\n\n",
  )
  context.write_string("## Your Capabilities:\n\n")
  context.write_string(
    "1. **File Operations**: You can read, write, and modify files in the workspace.\n\n",
  )
  context.write_string(
    "2. **Project Awareness**: You are working in a MoonBit project (codex-sdk).\n",
  )
  context.write_string(
    "   - This repository contains utilities for creating AI agent tools\n",
  )
  context.write_string("   - Current working directory: \{working_dir}\n\n")
  context.write_string(
    "3. **Self-Improvement**: You can create new tools under cmd/ directory.\n",
  )
  context.write_string("   - Study existing tools in cmd/ for examples\n")
  context.write_string(
    "   - Each tool needs: moon.pkg.json, main.mbt, and optionally README.md\n",
  )
  context.write_string(
    "   - You can use utilities from x/ (moon, git, args, error, tasks)\n",
  )
  context.write_string(
    "   - After creating a tool, test it with `moon run cmd/<tool_name>`\n\n",
  )
  context.write_string("4. **MoonBit Ecosystem**:\n")
  context.write_string("   - Use `moon check` to validate code\n")
  context.write_string("   - Use `moon test` to run tests\n")
  context.write_string("   - Use `moon fmt` to format code\n")
  context.write_string("   - Use `moon info` to update interface files\n\n")
  context.write_string(
    "5. **Git Operations**: You can clone repos, create branches, commit, and push.\n\n",
  )
  context.write_string("## Task Solving Approach:\n\n")
  context.write_string("1. **Analyze** the task requirements carefully\n")
  context.write_string(
    "2. **Plan** your approach - break down complex tasks into steps\n",
  )
  context.write_string("3. **Execute** - implement the solution step by step\n")
  context.write_string("4. **Verify** - test that your solution works\n")
  context.write_string(
    "5. **Document** - if you create a new tool, document it\n\n",
  )
  context.write_string("## Special Instructions:\n\n")
  context.write_string(
    "- If the task requires a new tool that doesn't exist, CREATE IT!\n",
  )
  context.write_string(
    "- Look at cmd/example_fix_warnings, cmd/example_simple_tasks, etc. as templates\n",
  )
  context.write_string("- Follow MoonBit coding conventions (see AGENTS.md)\n")
  context.write_string(
    "- Run `moon fmt && moon info` after creating/modifying code\n",
  )
  context.write_string(
    "- Prefer creating reusable tools over one-off solutions\n\n",
  )
  context.write_string("Now, please solve the task that follows.\n")
  context.to_string()
}

///|
/// Main task solver workflow
async fn solve_task(
  task : String,
  working_dir : String,
  model : String,
  verbose : Bool,
) -> Unit {
  if task.is_empty() {
    @stdio.stdout.write("Error: No task provided\n")
    return
  }
  @stdio.stdout.write("=== MoonBit Task Solver ===\n\n")
  @stdio.stdout.write("Working directory: \{working_dir}\n")
  @stdio.stdout.write("Model: \{model}\n\n")
  @stdio.stdout.write("Task:\n\{task}\n\n")
  @stdio.stdout.write("---\n\n")

  // Build the enhanced prompt with system context
  let system_context = build_system_context(working_dir)
  let full_prompt = "\{system_context}\n\n## TASK:\n\n\{task}"
  if verbose {
    @stdio.stdout.write("=== System Context ===\n\{system_context}\n\n")
  }

  // Initialize Codex with workspace write permissions
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model~,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory=working_dir,
    ),
  )
  @stdio.stdout.write("Starting AI agent...\n\n")

  // Run the task - use streaming to show progress
  let streamed_turn = thread.run_streamed(full_prompt)
  let events = streamed_turn.events
  let mut final_response = ""
  let mut thread_id : String? = None
  let mut usage : @codex.Usage? = None
  let items : Array[@codex.ThreadItem] = []
  try {
    while events.next() is Some(event) {
      match event {
        @codex.ThreadStarted(thread_id=tid) => {
          thread_id = Some(tid)
          @stdio.stdout.write(
            "Thread started with ID: \{tid}\n(Use this ID with 'codex resume \{tid}' to continue)\n\n",
          )
        }
        @codex.TurnStarted =>
          if verbose {
            @stdio.stdout.write("=== Turn Started ===\n\n")
          }
        @codex.ItemStarted(item) =>
          if verbose {
            match item {
              @codex.ReasoningItem(text~, ..) =>
                @stdio.stdout.write("💭 Reasoning: \{text}\n\n")
              @codex.CommandExecutionItem(command~, ..) =>
                @stdio.stdout.write("⚙️  Executing command: \{command}\n")
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
        @codex.ItemCompleted(item) => {
          items.push(item)
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
            // Even in non-verbose mode, capture final response
          } else if item is @codex.AgentMessageItem(text~, ..) {
            final_response = text
          }
        }
        @codex.TurnCompleted(u) => {
          usage = Some(u)
          if verbose {
            @stdio.stdout.write("=== Turn Completed ===\n\n")
          }
        }
        @codex.TurnFailed(error) => {
          @stdio.stdout.write("❌ Turn Failed: \{error.message}\n")
          return
        }
        @codex.ThreadErrorEvent(message) => {
          @stdio.stdout.write("❌ Thread Error: \{message}\n")
          return
        }
      }
    }

    // Print summary
    @stdio.stdout.write("=== Agent Response ===\n\n")
    @stdio.stdout.write("\{final_response}\n\n")
    if usage is Some(u) {
      @stdio.stdout.write("=== Usage Stats ===\n")
      @stdio.stdout.write("Input tokens: \{u.input_tokens}\n")
      @stdio.stdout.write("Output tokens: \{u.output_tokens}\n")
      if u.cached_input_tokens > 0 {
        @stdio.stdout.write("Cached tokens: \{u.cached_input_tokens}\n")
      }
    }
    if thread_id is Some(id) {
      @stdio.stdout.write("\nThread ID: \{id}\n")
    }
    @stdio.stdout.write("\n=== Task Complete ===\n")
  } catch {
    error => {
      while events.returns() is Some(_) {
        // Must drain the generator to avoid unhandled promise rejection
      }
      @stdio.stdout.write("❌ Error during task execution: \{error}\n")
      if thread_id is Some(id) {
        @stdio.stdout.write(
          "\nThread ID: \{id}\nYou can resume with: codex resume \{id}\n",
        )
      }
    }
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
    $|Special Features:
    $|  - Can create new tools under cmd/ directory when needed
    $|  - Aware of MoonBit project structure and conventions
    $|  - Can use git, moon, and other utilities from x/
    $|  - Has workspace write permissions for implementing solutions
    $|

  // Parse CLI arguments
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["stdin", "help", "verbose", "v"],
    options=["working-dir", "model", "file"],
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
    @stdio.stdout.write("Error: No task provided\n")
    @stdio.stdout.write("Use --help for usage information\n")
    return
  }

  // Execute the task solver
  solve_task(task, arguments.working_dir, arguments.model, arguments.verbose)
}
