///|
/// CLI arguments structure and parsing
struct Arguments {
  mut all : Bool
  mut changed : Bool
  mut files : Array[String]
  mut concurrency : Int
  mut verbose : Bool
  mut path : String
  mut output : String
} derive(Default)

///|
fn parse_args(args : @args.Args) -> Arguments raise {
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
      .map(fn(s) { s.trim(char_set=" \t\n\r").to_string() })
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
  arguments
}
