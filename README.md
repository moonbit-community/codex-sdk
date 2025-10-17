# MoonBit Codex SDK

This is the codex SDK for MoonBit, ported from the typescript SDK.

The SDK communicates with the codex by spawning codex in the non-interactive
mode with `codex exec`. The targeted codex version is 0.46.0

It assumes that the codex is installed.

## Usage

To simplest way to use the codex is to create the `@codex.Codex` and start a
`@codex.Thread`. Then create `@codex.Turn` based on the `@codex.Thread` by using
`@codex.Thread::run`. By default, the `OPENAI_API_KEY` is read from the
environment.

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

To use it in an incremental way, import the `@generator` package, and use
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
