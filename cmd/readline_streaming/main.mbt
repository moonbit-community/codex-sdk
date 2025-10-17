///|
async fn main {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4"),
  )
  let reader = @io.BufferedReader::new(@pipe.stdin)
  while true {
    @pipe.stdout.write(b"> ")
    try {
      let length = reader.find(b"\n")
      let line = @encoding/utf8.decode(reader[:length])
      reader.drop(length + 1)
      if line.trim_space().is_empty() {
        continue
      }
      let turn = thread.run_streamed(line)
      while turn.events.next() is Some(event) {
        if event is @codex.Event::TurnStarted {
          @pipe.stdout.write("info:: Turn started\n")
        } else if event is @codex.Event::TurnCompleted(usage) {
          @pipe.stdout.write(
            "info:: Turn completed. Usage: \{usage.to_json().stringify()}\n",
          )
        } else if event is @codex.Event::ItemStarted(item) {
          if item is @codex.ThreadItem::CommandExecutionItem(command~, ..) {
            @pipe.stdout.write("info:: Command ")
            // store cursor position
            @pipe.stdout.write("\u{1b}[s")
            @pipe.stdout.write("started: \{command}\n")
          }
        } else if event is @codex.Event::ItemCompleted(item) {
          if item is @codex.ThreadItem::CommandExecutionItem(status~, ..) {
            // restore cursor position
            @pipe.stdout.write("\u{1b}[u")
            // remove `started`, which is 7 characters
            @pipe.stdout.write("\u{1b}[7P")
            if status is Completed {
              // insert spaces, which is 9 characters
              @pipe.stdout.write("\u{1b}[9@")
              @pipe.stdout.write("completed")
            } else {
              // insert spaces, which is 6 characters
              @pipe.stdout.write("\u{1b}[6@")
              @pipe.stdout.write("failed")
            }
            // move cursor to the next line
            @pipe.stdout.write("\u{1b}[E")
          } else if item is @codex.AgentMessageItem(text~, ..) {
            @pipe.stdout.write("info:: Agent message completed\n")
            @pipe.stdout.write(text)
            @pipe.stdout.write("\n")
          }
        }
      }
    } catch {
      @io.ReaderClosed => {
        let line = reader.read_all().text()
        if !line.trim_space().is_empty() {
          let turn = thread.run(line)
          @pipe.stdout.write(turn.final_response)
          @pipe.stdout.write("\n")
        }
        break
      }
      e => raise e
    }
  }
}
