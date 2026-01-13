///|
/// Sample DAG showing parallel roots and a dependent aggregation step.
pub fn sample_dag() -> Dag {
  Dag::{
    nodes: [
      DagNode::{
        id: "scan_real_world",
        title: "Scan real_world examples",
        deps: [],
        prompt: "List the example directories under real_world and summarize each in one short sentence. Keep to 4 lines.",
      },
      DagNode::{
        id: "async_usage",
        title: "Async usage in parallel_fix",
        deps: [],
        prompt: "Read real_world/parallel_fix/main.mbt and summarize how concurrency is managed (task groups, semaphores). 3 bullets.",
      },
      DagNode::{
        id: "codex_usage",
        title: "Codex usage in add_docs",
        deps: [],
        prompt: "Read real_world/add_docs/main.mbt and summarize how Codex threads are created and used. 3 bullets.",
      },
      DagNode::{
        id: "workflow_sketch",
        title: "DAG workflow sketch",
        deps: ["scan_real_world", "async_usage", "codex_usage"],
        prompt: "Using the dependency outputs, propose a minimal DAG workflow (3-5 nodes) for running Codex tasks with concurrency. Provide nodes and dependencies in plain text.",
      },
    ],
  }
}
