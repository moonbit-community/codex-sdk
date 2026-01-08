///|
async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread(options=@codex.ThreadOptions::new())
  let prompt =
    #|Return JSON with the shape:
    #|{ "title": string, "bullets": [string, string, string] }
    #|Topic: "Writing fast CLI tools"
  let turn = thread.run(prompt) catch { e => raise e }
  @stdio.stdout.write("\{turn.final_response}\n")
}
