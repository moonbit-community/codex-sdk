async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(),
  )
  let streamed = thread.run_streamed("Give a short plan for refactoring a CLI.")
  while streamed.events.next() is Some(event) {
    match event {
      ItemCompleted(_) => @stdio.stdout.write("completed item\n")
      TurnCompleted(_) => @stdio.stdout.write("turn completed\n")
      _ => ()
    }
  }
}
