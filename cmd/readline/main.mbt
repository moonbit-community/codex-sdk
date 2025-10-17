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
    @pipe.stdout.write(b"> ")
    try {
      let length = reader.find(b"\n")
      let line = @encoding/utf8.decode(reader[:length])
      reader.drop(length + 1)
      if line.trim_space().is_empty() {
        continue
      }
      let turn = @async.with_task_group(taskgroup => {
        taskgroup.add_defer(() => @pipe.stdout.write(b"\r"))
        taskgroup.spawn_bg(
          () => while true {
            @async.sleep(500)
            @pipe.stdout.write(b"\r\\")
            @async.sleep(500)
            @pipe.stdout.write(b"\r|")
            @async.sleep(500)
            @pipe.stdout.write(b"\r/")
            @async.sleep(500)
            @pipe.stdout.write(b"\r-")
          },
          no_wait=true,
        )
        thread.run(line)
      })
      @pipe.stdout.write(turn.final_response)
      @pipe.stdout.write("\n")
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
