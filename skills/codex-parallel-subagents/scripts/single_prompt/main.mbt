async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )
  let turn = thread.run("Write a 2-sentence summary of MoonBit.") catch {
    e => raise e
  }
  @stdio.stdout.write("\{turn.final_response}\n")
}
