async fn main {
  let env = @sys.get_env_vars()
  let codex = @codex.Codex::new(
    options=@codex.CodexOptions::new(
      codex_path_override?=env.get("CODEX_PATH"),
      base_url?=env.get("CODEX_BASE_URL"),
      api_key?=env.get("CODEX_API_KEY"),
    ),
  )
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=env.get("MODEL"),
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      working_directory?=env.get("CODEX_WORKDIR"),
      skip_git_repo_check=true,
    ),
  )
  let prompt = "Explain what a Codex CLI path override does in 2 sentences."
  let turn = thread.run(prompt) catch { e => raise e }
  @stdio.stdout.write("\{turn.final_response}\n")
}
