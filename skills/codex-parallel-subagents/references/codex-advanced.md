# Codex SDK Advanced Patterns

Advanced configuration options, streaming events, and structured outputs.

## Codex client options

Configure the Codex client with custom settings:

```moonbit
let env = @sys.get_env_vars()
let codex = @codex.Codex::new(
  options=@codex.CodexOptions::new(
    codex_path_override?=env.get("CODEX_PATH"),  // Custom CLI path
    base_url?=env.get("CODEX_BASE_URL"),          // API endpoint
    api_key?=env.get("CODEX_API_KEY"),            // API key override
  ),
)
```

### Available CodexOptions

| Option | Description |
|--------|-------------|
| `codex_path_override` | Path to custom Codex CLI binary |
| `base_url` | Override API base URL |
| `api_key` | Override API key |

## Thread options

Configure thread behavior:

```moonbit
let thread = codex.start_thread(
  options=@codex.ThreadOptions::new(
    model="anthropic/claude-sonnet-4",
    sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
    working_directory="/path/to/project",
    skip_git_repo_check=true,
  ),
)
```

### Available ThreadOptions

| Option | Description |
|--------|-------------|
| `model` | Model to use (e.g., `anthropic/claude-sonnet-4`) |
| `sandbox_mode` | File access level (`ReadOnly`, `WorkspaceWrite`, `DangerFullAccess`) |
| `working_directory` | Directory for agent to operate in |
| `skip_git_repo_check` | Skip git repository validation |

## Streaming events

Process events as the agent works for real-time progress:

```moonbit
async fn run_with_progress(codex : @codex.Codex, prompt : String) -> String {
  let thread = codex.start_thread()
  let streamed = thread.run_streamed(prompt)
  let mut response = ""
  while streamed.events.next() is Some(event) {
    match event {
      ItemCompleted(item) => {
        @stdio.stderr.write("completed: \{item}\n")
      }
      TurnCompleted(turn) => {
        response = turn.final_response
        @stdio.stderr.write("turn completed\n")
      }
      _ => ()
    }
  }
  response
}
```

### Event types

| Event | Description |
|-------|-------------|
| `ItemCompleted(item)` | A thread item (message, tool call) completed |
| `TurnCompleted(turn)` | The entire turn completed, contains final response |

## Structured outputs

Request JSON responses and parse them:

```moonbit
async fn get_structured(codex : @codex.Codex) -> @json.JsonValue {
  let thread = codex.start_thread()
  let prompt =
    #|Return JSON with the shape:
    #|{ "title": string, "items": [string, string, string] }
    #|Topic: "MoonBit features"
  let turn = thread.run(prompt) catch { e => raise e }
  @json.parse(turn.final_response) catch { e => raise e }
}
```

### Parsing structured responses

```moonbit
fn parse_result(response : String) -> (String, Array[String])? {
  let json = @json.parse(response) catch { _ => return None }
  guard json is Object({ "title": String(title), "items": Array(items), .. }) else {
    return None
  }
  let parsed_items : Array[String] = []
  for item in items {
    if item is String(s) {
      parsed_items.push(s)
    }
  }
  Some((title, parsed_items))
}
```

## Combining patterns

Production example with options, streaming, and error handling:

```moonbit
async fn run_production_task(
  workdir : String,
  prompt : String,
) -> String {
  let env = @sys.get_env_vars()
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(
      codex_path_override?=env.get("CODEX_PATH"),
    ),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
    ),
  )
  let streamed = thread.run_streamed(prompt)
  let mut response = ""
  while streamed.events.next() is Some(event) {
    match event {
      TurnCompleted(turn) => response = turn.final_response
      _ => ()
    }
  }
  response
}
```

## Required imports

```json
{
  "import": [
    "peter-jerry-ye/codex",
    "moonbitlang/async",
    "moonbitlang/async/stdio",
    "moonbitlang/x/sys",
    "moonbitlang/core/json"
  ]
}
```
