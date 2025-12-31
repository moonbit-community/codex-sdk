///|
async fn main {
  let command_opt = @app.parse_cli_args(@sys.get_cli_args()[1:])
  match command_opt {
    None => {
      @stdio.stdout.write(@app.help_message())
      return
    }
    Some(command) => {
      let codex = @codex.Codex::new(
        options=@codex.CodexOptions::new(
          codex_path_override="./alternative_codex.sh",
        ),
      )
      @app.run(codex, command)
    }
  }
}
