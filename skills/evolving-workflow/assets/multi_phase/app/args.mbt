///|
/// CLI arguments parsing and help message.

///|
priv struct Arguments {
  mut path : String
  mut parallelism : Int
  mut verbose : Bool
  mut output : String
} derive(Default)

///|
fn help_message() -> String {
  let message =
    #|Usage: moon run . -- [OPTIONS] <path>
    #|
    #|Multi-phase workflow: summarize → group → process.
    #|
    #|Arguments:
    #|  <path>                    Path to the project root
    #|
    #|Options:
    #|  -p, --parallelism <num>   Number of parallel agents (default: 4)
    #|  -v, --verbose             Show detailed progress
    #|  -o, --output <dir>        Output directory (default: ./output)
    #|  -h, --help                Print this help message
    #|
    #|Environment:
    #|  WORKFLOW_PARALLELISM      Override --parallelism
    #|  WORKFLOW_OUTPUT           Override --output
    #|  WORKFLOW_VERBOSE          Override --verbose (1/true/yes/on)
    #|
    #|Example:
    #|  moon run . -- -p 3 /path/to/project
    #|  moon run . -- -v .
    #|
  message
}

///|
fn parse_cli_args(cli_args : ArrayView[String]) -> Arguments? raise {
  let args = @args.parse(
    cli_args,
    flags=["verbose", "help"],
    options=["parallelism", "output"],
    aliases={ "h": "help", "v": "verbose", "p": "parallelism", "o": "output" },
  )
  if args.flags.get("help") is Some(true) {
    return None
  }
  let arguments = Arguments::default()
  let parallelism = args.options.get("parallelism").unwrap_or("4")
  arguments.parallelism = @strconv.parse_int(parallelism) catch {
    e => @error.fail_with("Invalid parallelism value", e)
  }
  if args.flags.get("verbose") is Some(true) {
    arguments.verbose = true
  }
  guard args.positional is [path] else {
    @error.fail("Path argument is required")
  }
  arguments.path = path
  arguments.output = args.options.get("output").unwrap_or("./output")
  Some(arguments)
}

///|
fn apply_env_overrides(arguments : Arguments) -> Arguments {
  let env = @sys.get_env_vars()
  if env.get("WORKFLOW_PARALLELISM") is Some(value) {
    arguments.parallelism = @strconv.parse_int(value) catch {
      _ => arguments.parallelism
    }
  }
  if env.get("WORKFLOW_OUTPUT") is Some(value) {
    arguments.output = value
  }
  if env.get("WORKFLOW_VERBOSE") is Some(value) {
    arguments.verbose = parse_env_bool(value).unwrap_or(arguments.verbose)
  }
  arguments
}

///|
fn parse_env_bool(value : String) -> Bool? {
  let v = value.trim(char_set=" \t\n\r").to_string().to_lower()
  if v == "1" || v == "true" || v == "yes" || v == "on" {
    Some(true)
  } else if v == "0" || v == "false" || v == "no" || v == "off" {
    Some(false)
  } else {
    None
  }
}
