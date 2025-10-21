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
async fn main {
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(base_url="https://openrouter.ai/api/v1"),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(model="anthropic/claude-sonnet-4"),
  )
  let reader = @io.BufferedReader::new(@pipe.stdin)
  while true {
    @pipe.stdout.write(b"\x1b]133;A\x07> \x1b]133;B\x07")
    try {
      let length = reader.find(b"\n")
      let line = @encoding/utf8.decode(reader[:length])
      reader.drop(length + 1)
      if line.trim_space().is_empty() {
        continue
      }
      @pipe.stdout.write(b"\x1b]133;C\x07")
      let turn = thread.run_streamed(line)
      try {
        while turn.events.next() is Some(event) {
          match event {
            TurnStarted => @pipe.stdout.write("info:: Turn started\n")
            TurnCompleted(usage) =>
              @pipe.stdout.write(
                "info:: Turn completed. Usage: \{usage.to_json().stringify()}\n",
              )
            ItemStarted(item) =>
              if item is @codex.ThreadItem::CommandExecutionItem(command~, ..) {
                @pipe.stdout.write("info:: Command ")
                // store cursor position
                @pipe.stdout.write("\u{1b}[s")
                @pipe.stdout.write("started: \{command}\n")
              }
            ItemCompleted(item) =>
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
            TurnFailed(e) => {
              @pipe.stderr.write("error:: \{e.message}")
              fail(e.message)
            }
            ThreadErrorEvent(e) => {
              @pipe.stderr.write("error:: \{e}")
              fail(e)
            }
            ThreadStarted(..) => ()
            ItemUpdated(_) => ()
          }
        }
      } catch {
        e => {
          while turn.events.returns() is Some(_) {
            // drain remaining events
          }
          raise e
        }
      }
      @pipe.stdout.write(b"\x1b]133;D;0\x07")
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
