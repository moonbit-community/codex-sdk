///|
async fn main {
  let env = @sys.get_env_vars()
  let concurrency = read_env_int(env, "DAG_CONCURRENCY", 2)
  let working_directory = env.get("DAG_WORKDIR").unwrap_or(".")
  let model = env.get("MODEL")
  let dag = @app.sample_dag()
  let options = @app.RunOptions::new(working_directory, concurrency, model?)
  @stdio.stdout.write(@app.describe_dag(dag))
  @stdio.stdout.write(
    "\nRunning DAG with concurrency \{options.concurrency} in \{options.working_directory}\n\n",
  )
  let codex = @codex.Codex::new()
  let results = @app.run_dag(dag, codex, options)
  @stdio.stdout.write("\nResults:\n")
  for node in dag.nodes {
    let output = results.get(node.id).unwrap_or("<missing output>")
    @stdio.stdout.write("\n=== \{node.id}: \{node.title} ===\n\{output}\n")
  }
}

///|
fn read_env_int(env : Map[String, String], key : String, fallback : Int) -> Int {
  match env.get(key) {
    Some(value) => @strconv.parse_int(value) catch { _ => fallback }
    None => fallback
  }
}
