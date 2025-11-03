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
  let reader = @io.BufferedReader::new(@stdio.stdin)
  while true {
    @stdio.stdout.write(b"\x1b]133;A\x07> \x1b]133;B\x07")
    try {
      let length = reader.find(b"\n")
      let line = @encoding/utf8.decode(reader[:length])
      reader.drop(length + 1)
      if line.trim_space().is_empty() {
        continue
      }
      @stdio.stdout.write(b"\x1b]133;C\x07")
      let turn = thread.run_streamed(line)
      try {
        while turn.events.next() is Some(event) {
          match event {
            TurnStarted => @stdio.stdout.write("info:: Turn started\n")
            TurnCompleted(usage) =>
              @stdio.stdout.write(
                "info:: Turn completed. Usage: \{usage.to_json().stringify()}\n",
              )
            ItemStarted(item) =>
              if item is @codex.ThreadItem::CommandExecutionItem(command~, ..) {
                @stdio.stdout.write("info:: Command ")
                // store cursor position
                @stdio.stdout.write("\u{1b}[s")
                @stdio.stdout.write("started: \{command}\n")
              }
            ItemCompleted(item) =>
              if item is @codex.ThreadItem::CommandExecutionItem(status~, ..) {
                // restore cursor position
                @stdio.stdout.write("\u{1b}[u")
                // remove `started`, which is 7 characters
                @stdio.stdout.write("\u{1b}[7P")
                if status is Completed {
                  // insert spaces, which is 9 characters
                  @stdio.stdout.write("\u{1b}[9@")
                  @stdio.stdout.write("completed")
                } else {
                  // insert spaces, which is 6 characters
                  @stdio.stdout.write("\u{1b}[6@")
                  @stdio.stdout.write("failed")
                }
                // move cursor to the next line
                @stdio.stdout.write("\u{1b}[E")
              } else if item is @codex.AgentMessageItem(text~, ..) {
                @stdio.stdout.write("info:: Agent message completed\n")
                @stdio.stdout.write(text)
                @stdio.stdout.write("\n")
              }
            TurnFailed(e) => {
              @stdio.stderr.write("error:: \{e.message}")
              fail(e.message)
            }
            ThreadErrorEvent(e) => {
              @stdio.stderr.write("error:: \{e}")
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
      @stdio.stdout.write(b"\x1b]133;D;0\x07")
    } catch {
      @io.ReaderClosed => {
        let line = reader.read_all().text()
        if !line.trim_space().is_empty() {
          let turn = thread.run(line)
          @stdio.stdout.write(turn.final_response)
          @stdio.stdout.write("\n")
        }
        break
      }
      e => raise e
    }
  }
}
