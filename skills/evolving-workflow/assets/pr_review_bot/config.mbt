///|
/// Configuration: parsed from environment variables and command-line arguments.
/// Command-line arguments take precedence over environment variables.

///|
struct Config {
  /// GitHub repository (owner/repo format)
  repo : String
  /// Working directory for git operations
  workdir : String
  /// Max concurrent reviews
  parallelism : Int
  /// Retry attempts per review
  max_retry : Int
  /// Dry run mode - analyze PRs without posting comments
  dry_run : Bool
  /// SQLite database path for state tracking
  db_path : String
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
    repo: get_string("repo", "GITHUB_REPO", ""),
    workdir: get_string("workdir", "CODEX_WORKDIR", "."),
    parallelism: get_int("parallelism", "PARALLELISM", 2),
    max_retry: get_int("max-retry", "MAX_RETRY", 2),
    dry_run: get_bool("dry-run", "DRY_RUN"),
    db_path: get_string("db-path", "DB_PATH", "./pr_reviews.db"),
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
        let parts = key_value.split("=").collect()
        if parts.length() >= 2 {
          let key = parts[0].to_string()
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
    #|PR Review Bot - Automated PR review workflow with SQLite state tracking
    #|
    #|USAGE:
    #|  moon run . [OPTIONS]
    #|
    #|OPTIONS:
    #|  --repo <OWNER/REPO>    GitHub repository (env: GITHUB_REPO) [required]
    #|  --workdir <PATH>       Working directory (env: CODEX_WORKDIR) [default: .]
    #|  --parallelism <N>      Max concurrent reviews (env: PARALLELISM) [default: 2]
    #|  --max-retry <N>        Retry attempts per review (env: MAX_RETRY) [default: 2]
    #|  --dry-run              Analyze without posting comments (env: DRY_RUN)
    #|  --db-path <PATH>       SQLite database path (env: DB_PATH) [default: ./pr_reviews.db]
    #|  -h, --help             Print this help message
    #|
    #|EXAMPLES:
    #|  moon run . --repo owner/repo --dry-run       # Dry run on a repo
    #|  moon run . --repo owner/repo                 # Post reviews
    #|  GITHUB_REPO=owner/repo moon run .            # Using env vars
    #|
    #|DATABASE:
    #|  State is tracked in SQLite to avoid duplicate reviews.
    #|  Query the database: sqlite3 pr_reviews.db "SELECT * FROM pull_requests"
  println(help)
}
