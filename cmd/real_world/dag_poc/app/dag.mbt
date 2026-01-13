///|
/// A single step in the DAG workflow.
pub struct DagNode {
  id : String
  title : String
  deps : Array[String]
  prompt : String
}

///|
/// A DAG definition.
pub struct Dag {
  nodes : Array[DagNode]
}

///|
/// Options for running the DAG.
pub struct RunOptions {
  concurrency : Int
  working_directory : String
  model : String?
}

///|
priv struct Graph {
  nodes : Map[String, DagNode]
  dependents : Map[String, Array[String]]
  remaining : Map[String, Int]
}

///|
pub fn RunOptions::new(
  working_directory : String,
  concurrency : Int,
  model? : String,
) -> RunOptions {
  { concurrency, working_directory, model }
}

///|
/// Describe the DAG in a readable format.
pub fn describe_dag(dag : Dag) -> String {
  let mut output = "DAG definition:\n"
  for node in dag.nodes {
    let deps = if node.deps.is_empty() {
      "(no deps)"
    } else {
      node.deps.join(", ")
    }
    output = output + "- \{node.id} [\{node.title}] <- \{deps}\n"
  }
  output
}

///|
/// Execute the DAG by running ready nodes using Codex.
pub async fn run_dag(
  dag : Dag,
  codex : @codex.Codex,
  options : RunOptions,
) -> Map[String, String] {
  let total = dag.nodes.length()
  if total == 0 {
    return {}
  }
  let graph = build_graph(dag)
  let mut ready : Array[String] = []
  for node in dag.nodes {
    if node.deps.is_empty() {
      ready.push(node.id)
    }
  }
  let results : Map[String, String] = {}
  let mut completed = 0
  let mut wave = 0
  let concurrency = if options.concurrency < 1 {
    1
  } else {
    options.concurrency
  }
  while !ready.is_empty() {
    wave = wave + 1
    let ready_list = ready.join(", ")
    @stdio.stdout.write("Wave \{wave} ready: \{ready_list}\n")
    let wave_results : Array[(String, String)] = []
    @async.with_task_group(fn(task_group) {
      let semaphore = @semaphore.Semaphore::new(concurrency)
      for node_id in ready {
        let node = require_node(graph.nodes, node_id)
        task_group.spawn_bg(allow_failure=true, fn() {
          semaphore.acquire()
          defer semaphore.release()
          @stdio.stdout.write("info [\{node_id}] start - \{node.title}\n")
          let output = run_node(node, results, codex, options) catch {
            e => {
              @stdio.stderr.write("error [\{node_id}] failed: \{e}\n")
              "ERROR: \{e}"
            }
          }
          wave_results.push((node_id, output))
          @stdio.stdout.write("info [\{node_id}] done\n")
        })
      }
    })
    let next_ready : Array[String] = []
    for node_result in wave_results {
      let (node_id, output) = node_result
      results[node_id] = output
      completed = completed + 1
      let children = graph.dependents.get(node_id).unwrap_or([])
      for child in children {
        let remaining = graph.remaining.get(child).unwrap_or(0) - 1
        graph.remaining[child] = remaining
        if remaining == 0 {
          next_ready.push(child)
        }
      }
    }
    ready = next_ready
  }
  if completed != total {
    @error.fail(
      "DAG did not complete (\{completed}/\{total}). Check for cycles or missing deps.",
    )
  }
  results
}

///|
async fn run_node(
  node : DagNode,
  results : Map[String, String],
  codex : @codex.Codex,
  options : RunOptions,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=options.working_directory,
      sandbox_mode=WorkspaceWrite,
      model?=options.model,
    ),
  )
  let prompt = build_prompt(node, results)
  let response = thread.run(prompt)
  response.final_response.trim(char_set=" \t\r\n").to_string()
}

///|
fn build_prompt(node : DagNode, results : Map[String, String]) -> String {
  let mut prompt =
    $|You are one step in a DAG workflow.
    $|Rules:
    $|- Read-only; do not edit files.
    $|- Reply in plain text, max 8 lines.
    $|
    $|Task: \{node.prompt}
  if node.deps.is_empty() {
    return prompt
  }
  prompt = prompt + "\n\nDependency outputs:\n"
  for dep in node.deps {
    let dep_output = results.get(dep).unwrap_or("<missing output>")
    prompt = prompt + "- " + dep + ":\n" + dep_output + "\n"
  }
  prompt
}

///|
fn build_graph(dag : Dag) -> Graph raise {
  let nodes : Map[String, DagNode] = {}
  for node in dag.nodes {
    if nodes.get(node.id) is Some(_) {
      @error.fail("Duplicate node id: \{node.id}")
    }
    nodes[node.id] = node
  }
  let dependents : Map[String, Array[String]] = {}
  let remaining : Map[String, Int] = {}
  for node in dag.nodes {
    remaining[node.id] = node.deps.length()
    for dep in node.deps {
      if nodes.get(dep) is None {
        @error.fail("Unknown dependency: \{dep} (required by \{node.id})")
      }
      let list = dependents.get(dep).unwrap_or([])
      list.push(node.id)
      dependents[dep] = list
    }
  }
  { nodes, dependents, remaining }
}

///|
fn require_node(
  nodes : Map[String, DagNode],
  node_id : String,
) -> DagNode raise {
  match nodes.get(node_id) {
    Some(node) => node
    None => @error.fail("Missing node for id: \{node_id}")
  }
}
