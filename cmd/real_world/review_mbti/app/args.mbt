///|
/// CLI arguments structure and parsing
pub struct Arguments {
  mut all : Bool
  mut changed : Bool
  mut files : Array[String]
  mut concurrency : Int
  mut verbose : Bool
  mut path : String
  mut output : String
} derive(Default)

///|
pub fn help_message() -> String {
  let message =
    #|Usage: moon run real_world/review_mbti -- [OPTIONS] <path>
    #|Review MoonBit interface files (pkg.generated.mbti) using Codex.
    #|
    #|Options:
    #|  --all                     Review all mbti files (default)
    #|  --changed                 Only review changed files in git
    #|  --files <files>           Specific files to review (comma-separated)
    #|  -c, --concurrency <num>   Number of concurrent reviews (default: 5)
    #|  -v, --verbose             Show detailed progress
    #|  -o, --output <dir>        Output directory for review files (default: mbti-reviews)
    #|  <path>                    Path to the project root
    #|
  message
}

///|
pub fn parse_cli_args(cli_args : ArrayView[String]) -> Arguments? raise {
  let args = @args.parse(
    cli_args,
    flags=["all", "changed", "verbose", "help"],
    options=["files", "concurrency", "output"],
    aliases={ "h": "help", "v": "verbose", "o": "output", "c": "concurrency" },
  )
  if args.flags.get("help") is Some(true) {
    return None
  }
  let arguments = Arguments::default()
  if args.flags.get("all") is Some(true) {
    arguments.all = true
  }
  if args.flags.get("changed") is Some(true) {
    arguments.changed = true
  }
  if args.options.get("files") is Some(value) {
    arguments.files = value
      .split(",")
      .map(fn(s) { s.trim(char_set=" \\t\\n\\r").to_string() })
      .collect()
  }
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
  Some(arguments)
}
