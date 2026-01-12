///|
/// Configuration: parsed from environment variables and command-line arguments.
/// Command-line arguments take precedence over environment variables.

///|
struct Config {
  /// Target repository path
  workdir : String
  /// Max concurrent reviews
  parallelism : Int
  /// Skip first N targets
  offset : Int
  /// Process at most N targets (-1 = all)
  limit : Int
  /// Retry attempts per review
  max_retry : Int
  /// Dry run mode - list targets without reviewing
  dry_run : Bool
  /// Use git worktree for AI isolation
  use_worktree : Bool
  /// Output directory for review reports
  output_dir : String
}

///|
/// Parse configuration from environment and command-line arguments.
/// Returns None if --help was requested.
fn Config::parse(env : Map[String, String], args : Array[String]) -> Config? {
  // Check for --help first
  if args.iter().any(fn(a) { a == "--help" || a == "-h" }) {
    print_help()
    return None
  }

  // Parse args into a map
  let arg_map = parse_args(args)

  // Helper to get value from args first, then env, then default
  let get_string = fn(
    arg_name : String,
    env_name : String,
    default : String,
  ) -> String {
    match arg_map.get(arg_name) {
      Some(v) => v
      None =>
        match env.get(env_name) {
          Some(v) => v
          None => default
        }
    }
  }
  let get_int = fn(arg_name : String, env_name : String, default : Int) -> Int {
    let s : String? = match arg_map.get(arg_name) {
      Some(v) => Some(v)
      None => env.get(env_name)
    }
    match s {
      Some(v) => @strconv.parse_int(v) catch { _ => default }
      None => default
    }
  }
  let get_bool = fn(arg_name : String, env_name : String) -> Bool {
    let s : String? = match arg_map.get(arg_name) {
      Some(v) => Some(v)
      None => env.get(env_name)
    }
    match s {
      Some(v) => v == "1" || v == "true"
      None => false
    }
  }
  Some({
    workdir: get_string("workdir", "CODEX_WORKDIR", "."),
    parallelism: get_int("parallelism", "PARALLELISM", 4),
    offset: get_int("offset", "TASK_OFFSET", 0),
    limit: get_int("limit", "TASK_LIMIT", -1),
    max_retry: get_int("max-retry", "MAX_RETRY", 2),
    dry_run: get_bool("dry-run", "DRY_RUN"),
    use_worktree: get_bool("use-worktree", "USE_WORKTREE"),
    output_dir: get_string("output-dir", "OUTPUT_DIR", "./reviews"),
  })
}

///|
/// Parse command-line arguments into a map.
/// Supports: --flag value, --flag=value
fn parse_args(args : Array[String]) -> Map[String, String] {
  let result : Map[String, String] = {}
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--") && arg.length() > 2 {
      let key_value = strip_prefix(arg, "--")
      if key_value.contains("=") {
        // Split on first = only
        let parts = key_value.split("=").collect()
        if parts.length() >= 2 {
          let key = parts[0].to_string()
          // Join remaining parts in case value contains =
          let mut value = ""
          for j = 1; j < parts.length(); j = j + 1 {
            if j > 1 {
              value = value + "="
            }
            value = value + parts[j].to_string()
          }
          result[key] = value
        }
      } else if i + 1 < args.length() && not(args[i + 1].has_prefix("--")) {
        result[key_value] = args[i + 1]
        i += 1
      } else {
        // Flag without value, treat as "true"
        result[key_value] = "true"
      }
    }
    i += 1
  }
  result
}

///|
fn strip_prefix(s : String, prefix : String) -> String {
  if s.has_prefix(prefix) {
    let chars = s.to_array()
    let result : Array[Char] = []
    for i = prefix.length(); i < chars.length(); i = i + 1 {
      result.push(chars[i])
    }
    String::from_array(result)
  } else {
    s
  }
}

///|
/// Print help message.
fn print_help() -> Unit {
  let help =
    #|Code Review Bot - Automated code review workflow
    #|
    #|USAGE:
    #|  moon run . [OPTIONS]
    #|
    #|OPTIONS:
    #|  --workdir <PATH>       Target repository path (env: CODEX_WORKDIR) [default: .]
    #|  --parallelism <N>      Max concurrent reviews (env: PARALLELISM) [default: 4]
    #|  --offset <N>           Skip first N targets (env: TASK_OFFSET) [default: 0]
    #|  --limit <N>            Process at most N targets, -1 for all (env: TASK_LIMIT) [default: -1]
    #|  --max-retry <N>        Retry attempts per review (env: MAX_RETRY) [default: 2]
    #|  --dry-run              List targets without reviewing (env: DRY_RUN)
    #|  --use-worktree         Use git worktree for AI isolation (env: USE_WORKTREE)
    #|  --output-dir <PATH>    Output directory for reports (env: OUTPUT_DIR) [default: ./reviews]
    #|  -h, --help             Print this help message
    #|
    #|EXAMPLES:
    #|  moon run .                                    # Review all directories
    #|  moon run . --dry-run                          # List what would be reviewed
    #|  moon run . --limit 2 --output-dir ./test      # Review first 2, output to ./test
    #|  CODEX_WORKDIR=/path/to/repo moon run .        # Review a specific repo
  println(help)
}
