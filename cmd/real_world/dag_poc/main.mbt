///|
async fn main {
  let env = @sys.get_env_vars()
  let concurrency = read_env_int(env, "DAG_CONCURRENCY", 2)
  let working_directory = env.get("DAG_WORKDIR").unwrap_or(".")
  let model = env.get("MODEL")
  let options = @app.RunOptions::new(working_directory, concurrency, model?)
  let codex = @codex.Codex::new()
  let sample = env.get("DAG_SAMPLE").unwrap_or("basic")
  if sample == "all" {
    for item in @app.sample_dags() {
      let (name, dag) = item
      run_sample(name, dag, codex, options)
    }
    return
  }
  match @app.sample_dag(sample) {
    Some(dag) => run_sample(sample, dag, codex, options)
    None => {
      let names = @app.sample_names().join(", ")
      @stdio.stdout.write(
        "Unknown DAG sample '\{sample}'. Available: \{names}. Use DAG_SAMPLE=all to run all.\n",
      )
    }
  }
}

///|
async fn run_sample(
  name : String,
  dag : @app.Dag,
  codex : @codex.Codex,
  options : @app.RunOptions,
) -> Unit {
  @stdio.stdout.write("\n=== SAMPLE: \{name} ===\n")
  @stdio.stdout.write(@app.describe_dag(dag))
  @stdio.stdout.write(
    "\nRunning DAG with concurrency \{options.concurrency} in \{options.working_directory}\n\n",
  )
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
