async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  let turn = thread.run("Write a 2-sentence summary of MoonBit.") catch {
    e => raise e
  }
  @stdio.stdout.write("\{turn.final_response}\n")
}
