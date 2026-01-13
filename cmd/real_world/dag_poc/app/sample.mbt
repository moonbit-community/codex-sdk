///|
/// Return the list of sample DAGs.
pub fn sample_dags() -> Array[(String, Dag)] {
  [
    ("basic", basic_dag()),
    ("review_mbti", review_mbti_dag()),
    ("add_docs", add_docs_dag()),
  ]
}

///|
/// Lookup a sample DAG by name.
pub fn sample_dag(name : String) -> Dag? {
  for item in sample_dags() {
    let (sample_name, dag) = item
    if sample_name == name {
      return Some(dag)
    }
  }
  None
}

///|
/// Return just the sample names for help output.
pub fn sample_names() -> Array[String] {
  let names : Array[String] = []
  for item in sample_dags() {
    let (sample_name, _) = item
    names.push(sample_name)
  }
  names
}

///|
/// Sample DAG showing parallel roots and a dependent aggregation step.
fn basic_dag() -> Dag {
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

///|
/// Real-world inspired DAG: review MBTI files in parallel then summarize.
fn review_mbti_dag() -> Dag {
  Dag::{
    nodes: [
      DagNode::{
        id: "collect_mbti_targets",
        title: "Collect MBTI targets",
        deps: [],
        prompt: "List up to 5 pkg.generated.mbti files under cmd/real_world and add a short note on each package. Use plain text.",
      },
      DagNode::{
        id: "review_parallel_fix_mbti",
        title: "Review parallel_fix MBTI",
        deps: ["collect_mbti_targets"],
        prompt: "Review cmd/real_world/parallel_fix/app/pkg.generated.mbti. Provide 2-3 API risks or missing doc details.",
      },
      DagNode::{
        id: "review_add_docs_mbti",
        title: "Review add_docs MBTI",
        deps: ["collect_mbti_targets"],
        prompt: "Review cmd/real_world/add_docs/app/pkg.generated.mbti. Provide 2-3 API risks or missing doc details.",
      },
      DagNode::{
        id: "mbti_summary",
        title: "Aggregate review summary",
        deps: ["review_parallel_fix_mbti", "review_add_docs_mbti"],
        prompt: "Summarize the top 2 issues from the reviews and suggest one test or validation step.",
      },
    ],
  }
}

///|
/// Real-world inspired DAG: draft docs for git helpers then create a summary.
fn add_docs_dag() -> Dag {
  Dag::{
    nodes: [
      DagNode::{
        id: "scan_git_api",
        title: "Scan git API",
        deps: [],
        prompt: "Read cmd/real_world/add_docs/app/git.mbt and list public functions with a one-line responsibility.",
      },
      DagNode::{
        id: "draft_repo_at_doc",
        title: "Draft docs for Repo::at",
        deps: ["scan_git_api"],
        prompt: "Draft a docstring for Repo::at with a short example call (plain text).",
      },
      DagNode::{
        id: "draft_existing_branches_doc",
        title: "Draft docs for Repo::existing_branches",
        deps: ["scan_git_api"],
        prompt: "Draft a docstring for Repo::existing_branches with a short example call (plain text).",
      },
      DagNode::{
        id: "docs_summary",
        title: "Compose docs summary",
        deps: ["draft_repo_at_doc", "draft_existing_branches_doc"],
        prompt: "Write a short README snippet (2 bullets) describing the git helper utilities.",
      },
    ],
  }
}
