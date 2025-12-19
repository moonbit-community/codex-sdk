# MoonBit Codex SDK

This is the Codex SDK for MoonBit, ported from the TypeScript SDK.

The SDK communicates with Codex by spawning it in non-interactive mode using
`codex exec`. The target Codex version is 0.46.0.

Codex must be installed and available on your PATH. If not, install with:

```bash
pnpm install -g @openai/codex@0.46.0
```

## Usage

The simplest way to use Codex is to create a `@codex.Codex` and start a
`@codex.Thread`. Then create a `@codex.Turn` from the thread using
`@codex.Thread::run`. By default, the `OPENAI_API_KEY` environment variable is
read.

If you are already paid ChatGPT users, you can run the code below directly

```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  let turn = thread.run("Hello, what model are you using?")
  // I’m `GPT-5.2`, running inside the Codex CLI harness in your repo (`/Users/../codex-sdk`).
  println(turn.final_response)
  println(turn.items.to_json().stringify())
  println(turn.usage.to_json().stringify())
}
```
```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4.5"),
  )
  let turn = thread.run("Hello?")
  println(turn.final_response)
  println(turn.items.to_json().stringify())
  println(turn.usage.to_json().stringify())
}
```

For incremental usage, import the `@generator` package and use
`@codex.Thread::run_streamed`.

```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4.5"),
  )
  try {
    let streamed_turn = thread.run_streamed("Hello?")
    while streamed_turn.events.next() is Some(event) {
      println(event.to_json().stringify())
    }
  } catch {
    e => println(e)
  }
}
```

## Architecture Overview

### Process boundary and transport
The MoonBit SDK is a thin but strongly typed wrapper around `codex exec`:

1. `@codex.CodexExec::run` spawns the CLI with `--experimental-json`, automatically wiring API endpoint overrides, API keys, sandbox flags, working directory overrides, and thread resumption arguments.
2. The CLI's JSONL stream is fed through `@generator.AsyncGenerator` so the SDK can yield events as soon as they arrive. This keeps Codex long-running commands responsive while avoiding blocking MoonBit's async runtime.
3. Each line is decoded into the rich `@codex.Event` / `@codex.ThreadItem` hierarchy (`events.mbt` and `items.mbt`), which means MoonBit callers never manipulate raw JSON.

The `Codex`/`Thread`/`Turn` trio mirrors the CLI lifecycle: a `Codex` holds process-level configuration, a `Thread` models a Codex conversation, and a `Turn` captures the completed response plus token usage metrics.

### Thread lifecycle and safety
- `Thread::run_streamed` owns the async generator returned by `CodexExec::run`. The method updates the cached thread id when `ThreadStarted` surfaces, so a later `Thread::run` call automatically resumes the same conversation.
- `Thread::run` is implemented on top of the streaming primitive. It drains the generator, records `AgentMessageItem` content as the `Turn.final_response`, retains the full item history for post-processing (e.g., capturing diffs or tool invocations), and surfaces `TurnFailed` by raising an error after draining the iterator to prevent resource leaks.
- Structured cleanup exists everywhere a temporary artifact is created; for example, `@codex::create_output_schema_file` creates `/tmp/codex-output-schema-*` directories and ensures they are removed even when errors occur.

### Events, items, and observability
The CLI emits high-level telemetry that is mirrored by the SDK:

- `Event::ThreadStarted`, `TurnStarted`, `TurnCompleted`, and `TurnFailed` make it trivial to instrument throughput, retries, and token usage.
- `ThreadItem` variants capture everything the agent does: `CommandExecutionItem` surfaces shell commands with exit codes, `FileChangeItem` contains per-file diffs, `McpToolCallItem` shows MCP tool usage, and `TodoListItem` exposes the agent's internal plan.
- All enums (sandbox mode, approval mode, command status, etc.) expose `ToJson`/`FromJson` so you can persist structured logs or forward them to observability backends without lossy string manipulation.

### Structured output and schema enforcement
`TurnOptions.output_schema` accepts an arbitrary JSON schema. When provided, `Thread::run` / `run_streamed` transparently:

1. Creates a temporary schema file on disk.
2. Passes `--output-schema /tmp/.../schema.json` to the CLI.
3. Deletes the schema file after the turn completes or fails (even if exceptions arise).

This makes it safe to require JSON output without managing files yourself. The final assistant message still flows through `ThreadItem::AgentMessageItem`, so you can parse it with `@json.parse` once the turn completes.

### Configuration layers
- `CodexOptions` sets global API concerns (binary override, base URL, API key) once per process.
- `ThreadOptions` controls per-thread concerns such as the model, sandbox levels (`read-only`, `workspace-write`, `danger-full-access`), working directory routing, and Git safety checks.
- `TurnOptions` tunes per-turn behavior, currently focusing on structured output but intentionally keeping room for future features (e.g., custom completion criteria).
Because configuration objects implement `ToJson`/`FromJson`, they can be marshalled into other systems (task schedulers, Codex automation) without reimplementing serialization.

## Advanced Usage Patterns

### Instrument streaming events
You can subscribe to the event stream for telemetry, custom retry logic, or UI overlays without waiting for a completed turn:

```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  let turn = thread.run_streamed("Summarize today's commits")
  while turn.events.next() is Some(event) {
    match event {
      ItemStarted(item) => println("started: \{item.to_json().stringify()}")
      ItemCompleted(AgentMessageItem(text~, ..)) =>
        println("assistant: \{text}")
      TurnCompleted(usage) =>
        println("tokens in/out: \{usage.input_tokens}/\{usage.output_tokens}")
      TurnFailed(error) => fail("codex turn failed: \{error.message}")
      _ => ()
    }
  }
}
```

### Enforce structured responses
The temporary-schema mechanism lets you demand JSON (or any schema-valid structure) without extra boilerplate:

```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  let turn = thread.run(
    "Plan the next refactor as JSON",
    turn_options=@codex.TurnOptions::new(output_schema={
      "type": "object",
      "properties": {
        "summary": { "type": "string" },
        "files_to_touch": { "type": "array", "items": { "type": "string" } },
      },
      "required": ["summary", "files_to_touch"],
      "additionalProperties": false, // required to be supplied as valid schema
    }),
  )
  println(turn.final_response)
  let plan_json = @json.parse(turn.final_response)
  println(plan_json.stringify(indent=2))
}
```

These primitives compose cleanly with your own orchestration layers, since everything in the SDK is expressed as plain MoonBit structs and async functions.
