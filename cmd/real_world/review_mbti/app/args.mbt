///|
/// CLI arguments structure and parsing
priv struct Arguments {
  mut concurrency : Int
  mut verbose : Bool
  mut path : String
  mut output : String
  mut prompt : String
} derive(Default)

///|
fn help_message() -> String {
  let message =
    #|Usage: moon run cmd/real_world/review_mbti -- [OPTIONS] <path>
    #|
    #|Review MoonBit interface files (pkg.generated.mbti) using Codex.
    #|Uses a 3-phase workflow: summarize packages → group related → review groups.
    #|
    #|Arguments:
    #|  <path>                    Path to the MoonBit module root
    #|
    #|Options:
    #|  -c, --concurrency <num>   Number of parallel agents (default: 5)
    #|  -v, --verbose             Show detailed progress
    #|  -o, --output <dir>        Output directory for reviews (default: mbti-reviews)
    #|  -p, --prompt <text>       Custom focus for the review (optional)
    #|  -h, --help                Print this help message
    #|
    #|Environment:
    #|  REVIEW_MBTI_CONCURRENCY   Override --concurrency
    #|  REVIEW_MBTI_OUTPUT        Override --output
    #|  REVIEW_MBTI_VERBOSE       Override --verbose (1/true/yes/on)
    #|  REVIEW_MBTI_PROMPT        Override --prompt
    #|
    #|Example:
    #|  moon run cmd/real_world/review_mbti -- -c 3 /path/to/moonbit-core
    #|  moon run cmd/real_world/review_mbti -- -p "Focus on error handling" .
    #|
  message
}

///|
fn parse_cli_args(cli_args : ArrayView[String]) -> Arguments? raise {
  let args = @args.parse(
    cli_args,
    flags=["verbose", "help"],
    options=["concurrency", "output", "prompt"],
    aliases={ "h": "help", "v": "verbose", "o": "output", "c": "concurrency", "p": "prompt" },
  )
  if args.flags.get("help") is Some(true) {
    return None
  }
  let arguments = Arguments::default()
  let concurrency = args.options.get("concurrency").unwrap_or("5")
  arguments.concurrency = @strconv.parse_int(concurrency) catch {
    e => @error.fail_with("Invalid concurrency value", e)
  }
  if args.flags.get("verbose") is Some(true) {
    arguments.verbose = true
  }
  guard args.positional is [path] else {
    @error.fail("Path argument is required")
  }
  arguments.path = path
  arguments.output = args.options.get("output").unwrap_or("mbti-reviews")
  arguments.prompt = args.options.get("prompt").unwrap_or("")
  Some(arguments)
}
