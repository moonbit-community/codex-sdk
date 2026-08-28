# Codex SDK Basics

Start here if you're new to the Codex SDK. This guide covers creating a client, running a single prompt, and basic configuration.

## Minimal example

```moonbit
async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  let turn = thread.run("Write a 2-sentence summary of MoonBit.") catch {
    e => raise e
  }
  @stdio.stdout.write("\{turn.final_response}\n")
}
```

## Required dependencies

`moon.pkg.json`:
```json
{
  "is-main": true,
  "import": [
    "moonbit-community/codex",
    "moonbitlang/async",
    "moonbitlang/async/stdio"
  ]
}
```

`moon.mod.json`:
```json
{
  "name": "your_project",
  "version": "0.1.0",
  "deps": {
    "moonbit-community/codex": "0.150.1",
    "moonbitlang/async": "0.21.1",
    "moonbitlang/x": "0.4.38"
  },
  "preferred-target": "native"
}
```

## Setup from scratch

```bash
moon new my_project --name my_project --user your_user
cd my_project
moon add moonbit-community/codex
moon add moonbitlang/async
moon add moonbitlang/x
```

## Configuration options

### Working directory

Set where the agent operates:
```moonbit
let thread = codex.start_thread(
  options=@codex.ThreadOptions::new(working_directory="/path/to/repo"),
)
```

### Sandbox mode

Control file access permissions:
```moonbit
let thread = codex.start_thread(
  options=@codex.ThreadOptions::new(
    sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
  ),
)
```

Available modes:
- `ReadOnly` - No file writes allowed
- `WorkspaceWrite` - Can write within working directory
- `DangerFullAccess` - Full filesystem access

### Skip git repo check

For non-git directories:
```moonbit
let thread = codex.start_thread(
  options=@codex.ThreadOptions::new(skip_git_repo_check=true),
)
```

## Key rules

1. **Async main** - Use `async fn main` since Codex calls are async
2. **One Codex client** - Create once, reuse across threads
3. **Handle errors** - Use `catch` to handle failures gracefully
4. **Native target** - Add `"preferred-target": "native"` to `moon.mod.json`

## Next steps

Once comfortable with basic usage, see the main SKILL.md for:
- Running multiple agents in parallel
- Batch processing with bounded concurrency
- Streaming events and progress tracking
