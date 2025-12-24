///|
/// Main entry point
async fn main {
  let help_message =
    $|
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
  // Parse CLI arguments
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["all", "changed", "verbose", "help"],
    options=["files", "concurrency", "output"],
    aliases={ "h": "help", "v": "verbose", "o": "output", "c": "concurrency" },
  )
  if args.flags.get("help") is Some(true) {
    @stdio.stdout.write("\{help_message}\n")
    return
  }
  let argument = parse_args(args)
  let project_root = argument.path

  // Make output directory absolute if it's relative
  let output_dir = if argument.output.has_prefix("/") {
    argument.output
  } else {
    "\{project_root}/\{argument.output}"
  }

  // Determine which files to review
  let files_to_review : Array[String] = if argument.files.length() > 0 {
    @stdio.stdout.write(
      "Reviewing \{argument.files.length()} specified file(s)\n",
    )
    argument.files.map(fn(f) { "\{project_root}/\{f}" })
  } else if argument.changed {
    let changed = get_changed_mbti_files(project_root) catch {
      e => {
        @stdio.stderr.write("Failed to get changed files:\n\{e}\n")
        []
      }
    }
    @stdio.stdout.write("Found \{changed.length()} changed mbti file(s)\n")
    changed
  } else {
    let all_files = []
    find_mbti_files(project_root, all_files)
    @stdio.stdout.write("Found \{all_files.length()} mbti file(s) to review\n")
    all_files
  }
  if files_to_review.is_empty() {
    @stdio.stdout.write("No files to review. Exiting.\n")
    return
  }
  @stdio.stdout.write("Using concurrency limit: \{argument.concurrency}\n\n")

  // Initialize reviewer (encapsulates Codex usage)
  let reviewer = Reviewer::new()

  // Process files with concurrency control
  let results = process_concurrently(
    files_to_review,
    project_root,
    reviewer,
    output_dir,
    argument.concurrency,
    argument.verbose,
  )

  // Display results summary
  let successful = results.filter(fn(r) { r.success }).length()
  let failed = results.filter(fn(r) { !r.success })
  let rel_output_dir = if output_dir.has_prefix(project_root) {
    try! output_dir[project_root.length() + 1:].to_string()
  } else {
    output_dir
  }
  @stdio.stdout.write(
    (
      $|
      $|\{"=".repeat(80)}
      $|SUMMARY
      $|\{"=".repeat(80)}
      $|Total files \{results.length()}
      $|Successful: \{successful}
      $|Failed: \{failed.length()}
      $|Concurrency: \{argument.concurrency}
      $|Output Directory: \{rel_output_dir}
      $|
    ),
  )
  if failed.length() > 0 {
    @stdio.stdout.write("\n❌ Failed reviews:\n")
    for f in failed {
      @stdio.stdout.write("  - \{f.file}: \{f.error}\n")
    }
  }
  @stdio.stdout.write("\n💾 Reviews saved to: \{output_dir}\n")
}
