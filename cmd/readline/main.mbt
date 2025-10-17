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
