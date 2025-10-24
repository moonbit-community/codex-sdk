# MoonBit Codex SDK

This is the Codex SDK for MoonBit, ported from the TypeScript SDK.

The SDK communicates with Codex by spawning it in non-interactive mode using
`codex exec`. The target Codex version is 0.46.0.

Codex must be installed and available on your PATH.

## Usage

The simplest way to use Codex is to create a `@codex.Codex` and start a
`@codex.Thread`. Then create a `@codex.Turn` from the thread using
`@codex.Thread::run`. By default, the `OPENAI_API_KEY` environment variable is
read.

```moonbit
///|
async test {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4"),
  )
  let turn = thread.run("Hello?")
  println(turn.final_response)
  println(turn.items.to_json().stringify())
  println(turn.usage.to_json().stringify())
}
```

For incremental usage, import the `@generator` package and use
`@codex.Thread::run_streamed`.

```moonbit
///|
async test {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4"),
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
