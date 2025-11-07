# Task Solver

An intelligent task solver that accepts tasks and solves them, with special awareness that it can create new tools in this repository when needed.

## Overview

The task solver is a meta-tool that can:
- Accept task descriptions from various sources (command line, file, stdin)
- Analyze and solve tasks using AI
- Create new tools under `cmd/` when needed
- Use all available utilities (moon, git, args, etc.)
- Self-improve by generating specialized tools

## Features

### Core Capabilities

1. **Task Acceptance**
   - Command line argument
   - File input
   - Standard input (stdin)

2. **Intelligent Problem Solving**
   - Breaks down complex tasks
   - Plans and executes solutions
   - Verifies results

3. **Self-Improvement**
   - Can create new tools under `cmd/`
   - Studies existing tools as templates
   - Follows MoonBit conventions automatically

4. **Repository Awareness**
   - Understands project structure
   - Uses available utilities from `x/`
   - Can work with git repositories
   - Integrates with MoonBit toolchain

## Usage

### Prerequisites

Before using the task solver, ensure you have:
1. **Codex installed** - The tool requires the Codex CLI
2. **API Key configured** - Set `OPENAI_API_KEY` or configure your preferred provider's API key
3. **MoonBit installed** - Required for running the tool

### Basic Usage

```bash
# Solve a task from command line
moon run cmd/task_solver -- "Create a tool that counts lines of code in a MoonBit project"

# Solve a task from a file
moon run cmd/task_solver -- my-task.txt

# Read task from stdin
echo "Fix all compiler warnings" | moon run cmd/task_solver -- --stdin
```

### Advanced Options

```bash
# Use a different AI model
moon run cmd/task_solver -- --model "openai/gpt-4" "Generate comprehensive documentation"

# Enable verbose mode to see all actions
moon run cmd/task_solver -- --verbose "Refactor the error handling module"

# Specify working directory
moon run cmd/task_solver -- --working-dir /path/to/project "Analyze code quality"
```

## Example Tasks

### Creating New Tools

```bash
moon run cmd/task_solver -- "Create a tool that generates API documentation from .mbti files"
```

The solver will:
1. Analyze existing tools in `cmd/`
2. Create a new directory with proper structure
3. Implement the tool following conventions
4. Test it with `moon check`
5. Document it with a README

### Project Operations

```bash
moon run cmd/task_solver -- "Find all unused functions in the codebase"
```

The solver will:
1. Discover the MoonBit project
2. Analyze all packages
3. Identify unused functions
4. Report findings

### Automated Workflows

```bash
moon run cmd/task_solver -- "Create a pre-commit hook that runs moon check and moon test"
```

The solver will:
1. Create a git hook script
2. Install it in .git/hooks
3. Test that it works
4. Document the setup

## How It Works

### System Context

The task solver provides the AI agent with:

1. **Capability Awareness**
   - File operations (read, write, modify)
   - MoonBit project utilities
   - Git operations
   - Tool creation abilities

2. **Project Context**
   - Repository structure
   - Available utilities in `x/`
   - Existing tools in `cmd/`
   - MoonBit conventions from AGENTS.md

3. **Execution Strategy**
   - Analyze task requirements
   - Plan the approach
   - Execute step by step
   - Verify the solution
   - Document if needed

### Tool Creation Pattern

When creating new tools, the solver follows this pattern:

```
cmd/new_tool/
├── moon.pkg.json    # Package configuration
├── main.mbt         # Main implementation
└── README.md        # Documentation
```

It studies existing tools like:
- `example_fix_warnings` - Complex workflow example
- `example_simple_tasks` - Basic utility example
- `naive` - Simple API usage

## Architecture

The task solver uses:
- **@codex**: For AI agent capabilities
- **@moon**: For MoonBit project operations
- **@git**: For version control operations
- **@args**: For command-line argument parsing
- **@fs**: For file system operations
- **@stdio**: For standard I/O

## Limitations

- Requires Codex to be installed and configured
- Needs OPENAI_API_KEY or similar API key in environment
- Works best with tasks that can be solved programmatically
- Complex tasks may require multiple iterations

## Tips for Effective Use

1. **Be Specific**: Provide clear, detailed task descriptions
2. **Provide Context**: Include relevant file paths or constraints
3. **Iterative Approach**: For complex tasks, break them into smaller pieces
4. **Review Output**: Always verify the solver's work
5. **Learn from Tools**: Study the tools it creates to improve your prompts

## Examples

### Example 1: Create a Code Statistics Tool

```bash
moon run cmd/task_solver -- "Create a tool called 'code_stats' that:
- Counts total lines of code in all .mbt files
- Shows breakdown by package
- Identifies the largest files
- Outputs in a nice table format"
```

### Example 2: Automated Refactoring

```bash
moon run cmd/task_solver -- "Refactor all error handling in x/error to use a custom Error type instead of strings"
```

### Example 3: Documentation Generator

```bash
moon run cmd/task_solver -- "Create a tool that generates a CHANGELOG.md from git commit history"
```

## Contributing

If you create interesting tasks that produce useful tools, consider:
- Sharing the task description
- Contributing the generated tool back to the repository
- Documenting interesting patterns you discover

## See Also

- [AGENTS.md](../../AGENTS.md) - MoonBit coding conventions
- [README.md](../../README.md) - Main project documentation
- [cmd/example_fix_warnings](../example_fix_warnings/README.md) - Example workflow tool
- [cmd/example_simple_tasks](../example_simple_tasks/README.md) - Example utility tool
