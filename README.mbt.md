# MoonBit Codex SDK

This is the Codex SDK for MoonBit, ported from the TypeScript SDK.

The SDK communicates with Codex by spawning it in non-interactive mode using
`codex exec`. The target Codex version is `codex-cli 0.150.1`.

Codex must be installed and available on your PATH. If not, install with:

```bash
pnpm install -g @openai/codex@0.150.1
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
  @async.with_task_group(tg => {
    let streamed_turn = thread.run_streamed("Hello?", tg)
    while streamed_turn.events.next() is Some(event) {
      println(event.to_json().stringify())
    }
  }) catch {
    e => println(e)
  }
}
```

## Architecture Overview

### Process boundary and transport

The MoonBit SDK is a thin but strongly typed wrapper around `codex exec`:

1. `@codex.CodexExec::run` spawns the CLI with `--experimental-json`,
   automatically wiring API endpoint overrides, API keys, sandbox flags, working
   directory overrides, and thread resumption arguments.
2. The CLI's JSONL stream is fed through `@generator.AsyncGenerator` so the SDK
   can yield events as soon as they arrive. This keeps Codex long-running
   commands responsive while avoiding blocking MoonBit's async runtime.
3. Each line is decoded into the rich `@codex.Event` / `@codex.ThreadItem`
   hierarchy (`events.mbt` and `items.mbt`), which means MoonBit callers never
   manipulate raw JSON.

The native JSON event parser targets the `codex-cli 0.150.1` non-interactive
event stream, checked against the upstream `openai/codex` release tag
`rust-v0.150.1`. Usage includes prompt-cache writes when reported by the CLI,
while older CLIs that omit that counter decode it as zero.

The `Codex`/`Thread`/`Turn` trio mirrors the CLI lifecycle: a `Codex` holds
process-level configuration, a `Thread` models a Codex conversation, and a
`Turn` captures the completed response plus token usage metrics.

### Thread lifecycle and safety

- `Thread::run_streamed` owns the async generator returned by `CodexExec::run`.
  The method updates the cached thread id when `ThreadStarted` surfaces, so a
  later `Thread::run` call automatically resumes the same conversation.
- `Thread::run` is implemented on top of the streaming primitive. It drains the
  generator, records `AgentMessageItem` content as the `Turn.final_response`,
  retains the full item history for post-processing (e.g., capturing diffs or
  tool invocations), and surfaces `TurnFailed` by raising an error after
  draining the iterator to prevent resource leaks.
- Structured cleanup exists everywhere a temporary artifact is created; for
  example, `@codex::create_output_schema_file` creates
  `/tmp/codex-output-schema-*` directories and ensures they are removed even
  when errors occur.

### Events, items, and observability

The CLI emits high-level telemetry that is mirrored by the SDK:

- `Event::ThreadStarted`, `TurnStarted`, `TurnCompleted`, and `TurnFailed` make
  it trivial to instrument throughput, retries, and token usage.
- `ThreadItem` variants capture everything the agent does:
  `CommandExecutionItem` surfaces shell commands with exit codes,
  `FileChangeItem` contains per-file diffs, `McpToolCallItem` shows MCP tool
  usage, and `TodoListItem` exposes the agent's internal plan.
- All enums (sandbox mode, approval mode, command status, etc.) expose
  `ToJson`/`FromJson` so you can persist structured logs or forward them to
  observability backends without lossy string manipulation.

### Structured output and schema enforcement

`TurnOptions.output_schema` accepts an arbitrary JSON schema. When provided,
`Thread::run` / `run_streamed` transparently:

1. Creates a temporary schema file on disk.
2. Passes `--output-schema /tmp/.../schema.json` to the CLI.
3. Deletes the schema file after the turn completes or fails (even if exceptions
   arise).

This makes it safe to require JSON output without managing files yourself. The
final assistant message still flows through `ThreadItem::AgentMessageItem`, so
you can parse it with `@json.parse` once the turn completes.

### Configuration layers

- `CodexOptions` sets global API concerns (binary override, base URL, API key)
  once per process.
- `ThreadOptions` controls per-thread concerns such as the model, sandbox levels
  (`read-only`, `workspace-write`, `danger-full-access`), working directory
  routing, and Git safety checks.
- `TurnOptions` tunes per-turn behavior, currently focusing on structured output
  but intentionally keeping room for future features (e.g., custom completion
  criteria). Because configuration objects implement `ToJson`/`FromJson`, they
  can be marshalled into other systems (task schedulers, Codex automation)
  without reimplementing serialization.

## Advanced Usage Patterns

### Instrument streaming events

You can subscribe to the event stream for telemetry, custom retry logic, or UI
overlays without waiting for a completed turn:

```mbt check
///|
#skip
async test {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  @async.with_task_group(tg => {
    let turn = thread.run_streamed("Summarize today's commits", tg)
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
  })
}
```

### Enforce structured responses

The temporary-schema mechanism lets you demand JSON (or any schema-valid
structure) without extra boilerplate:

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

These primitives compose cleanly with your own orchestration layers, since
everything in the SDK is expressed as plain MoonBit structs and async functions.

### Connect to Codex app-server

The app-server surface is separate from `codex exec --experimental-json`. It runs as a
persistent JSON-RPC process. Prefer `Codex::with_app_server_session` for app
integrations: the SDK owns the task group, starts the app-server process, sends
the required `initialize` request plus `initialized` notification, runs the
shared notification pump, and closes stdin when your callback returns.

The SDK starts the process through `codex app-server --listen stdio://`, using
`CodexOptions::codex_path_override` or `AppServerOptions::executable_path_override`
when you need a non-default Codex CLI path. Request handlers are async, so
approval flows may do I/O before returning a JSON-RPC response.

The session is the ergonomic concurrency layer:

- `start_thread` and `resume_thread` return thread handles that own their
  thread id.
- Session-level RPCs such as `plugin_list`, `marketplace_add`, `config_read`,
  and `fs_read_file` are available directly on the session without exposing the
  raw shared event stream.
- `CodexAppThread::run_streamed` starts a turn and returns a per-turn
  stream. It registers the stream before sending `turn/start`, so early
  notifications are not lost while the RPC response is in flight.
- Turn-scoped server requests, such as approvals and user-input requests, are
  routed to the handler passed to the thread's streamed turn.
- Thread-scoped server requests fall back to the handler set on the thread.
- Session-level server requests fall back to the optional `request_handler`
  passed to `with_app_server_session`.
- `next_global_event` on the session receives non-turn or unregistered
  app-server notifications.

Because app-server carries more than turn-stream events, request handling is
kept on a separate channel from notifications. When a notification is
semantically the same as the existing exec stream, use
`AppServerEvent::thread_event` to bridge it back to `Event`.

For lower-level integrations, `Codex::with_app_server` exposes the raw
`CodexAppConnection`. Its `next_event` method is a shared connection-level
stream: use a single consumer and fan events out yourself if multiple turns are
active.

The typed app-server surface targets the stable v2 schema shipped with Codex
0.150.1. It includes current initialize capabilities, rich text/image/audio
inputs, client message ids, thread sources and sections, newer reasoning levels,
and the latest approval metadata. Set `experimental_api=true` in
`AppInitializeCapabilities` to opt into experimental methods and fields.

`CodexAppSession::request` and `CodexAppConnection::request` expose every
app-server method as raw JSON when a dedicated typed convenience method is not
available. Likewise, unrecognized notifications and server requests are
delivered as `AppRawNotification` and `AppRawServerRequest`; handlers can reply
with `AppRawServerResponse`, or reject one with `AppRawServerError`. This keeps
additions in the release protocol usable without silently discarding them.

The shared request transport automatically retries the app-server's retryable
`-32001` overload response with bounded exponential backoff.

The real app-server e2e test is marked `#skip` because it uses the local Codex
CLI and can make authenticated model requests. It reads `skills/list` and runs
a tiny streamed `hello` turn. Run it explicitly with
`moon test app_server_e2e_test.mbt --include-skipped`. Set
`CODEX_SDK_E2E_CODEX_PATH` when testing a non-default binary, and
`CODEX_SDK_E2E_MODEL` when testing a specific model.

```mbt check
///|
#skip
async test {
  @codex.Codex::new().with_app_server_session(async fn(session) {
    let _ = session.plugin_list(@codex.AppPluginListParams::{
      cwds: None,
      marketplace_kinds: None,
    })
    let thread = session.start_thread()
    let review_thread = session.start_thread()
    let turn_input = [@codex.AppUserInput::AppInputText(text="hello")]
    let turn = thread.run_streamed(turn_input, request_handler=fn(request) {
      match request.details {
        @codex.AppServerRequestDetails::AppCommandExecutionApprovalRequest(_) =>
          @codex.AppServerResponse::AppCommandExecutionApprovalResponse(
            decision=@codex.AppCommandExecutionApprovalDecision::AppCommandDecline,
          )
        @codex.AppServerRequestDetails::AppFileChangeApprovalRequest(_) =>
          @codex.AppServerResponse::AppFileChangeApprovalResponse(
            decision=@codex.AppFileChangeApprovalDecision::AppFileChangeDecline,
          )
        @codex.AppServerRequestDetails::AppToolRequestUserInputRequest(_) =>
          @codex.AppServerResponse::AppToolRequestUserInputResponse(answers={})
        @codex.AppServerRequestDetails::AppDynamicToolCallRequest(_) =>
          @codex.AppServerResponse::AppDynamicToolCallResponse(
            content_items=[
              @codex.AppDynamicToolCallOutputContentItem::AppDynamicToolCallOutputText(
                text="declined",
              ),
            ],
            success=false,
          )
        @codex.AppServerRequestDetails::AppPermissionsRequestApprovalRequest(_) =>
          @codex.AppServerResponse::AppPermissionsRequestApprovalResponse(
            permissions=@codex.AppGrantedPermissionProfile::{
              network: None,
              file_system: None,
            },
            scope=@codex.AppPermissionGrantScope::AppPermissionGrantTurn,
            strict_auto_review=None,
          )
        @codex.AppServerRequestDetails::AppChatgptAuthTokensRefreshRequest(_) =>
          @codex.AppServerResponse::AppChatgptAuthTokensRefreshResponse(
            access_token="",
            chatgpt_account_id="",
            chatgpt_plan_type=None,
          )
        @codex.AppServerRequestDetails::AppAttestationGenerateRequest(_) =>
          @codex.AppServerResponse::AppAttestationGenerateResponse(token="")
        @codex.AppServerRequestDetails::AppMcpServerElicitationRequest(_) =>
          @codex.AppServerResponse::AppMcpServerElicitationResponse(
            action=@codex.AppMcpServerElicitationAction::AppMcpElicitationDecline,
            content=None,
            meta=None,
          )
        @codex.AppServerRequestDetails::AppRawServerRequest(..) =>
          @codex.AppServerResponse::AppRawServerResponse({})
      }
    })
    let review_turn = review_thread.run_streamed([
      @codex.AppUserInput::AppInputText(text="review this"),
    ])

    while turn.next() is Some(event) {
      match event.thread_event() {
        Some(@codex.Event::ItemStarted(item)) =>
          println(item.to_json().stringify())
        _ => ()
      }
    }
    review_turn.close()

    while session.next_global_event() is Some(event) {
      ignore(event)
    }
  })
}
```

```mbt check
///|
#skip
async test {
  @codex.Codex::new().with_app_server(async fn(connection) {
    while connection.next_event() is Some(event) {
      ignore(event)
    }
  })
}
```
