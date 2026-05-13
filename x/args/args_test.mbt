///|
test "parse basic flags" {
  let result = parse(["--verbose", "-q", "file.txt"], flags=["verbose", "q"])
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
  debug_inspect(result.flags.get("q"), content="Some(true)")
  debug_inspect(result.positional, content="[\"file.txt\"]")
}

///|
test "parse options with values" {
  let result = parse(["--output", "file.txt", "-v"], flags=["v"], options=[
    "output",
  ])
  debug_inspect(result.options.get("output"), content="Some(\"file.txt\")")
  debug_inspect(result.flags.get("v"), content="Some(true)")
}

///|
test "parse collections" {
  let result = parse(["--include", "src", "--include", "lib"], collections=[
    "include",
  ])
  debug_inspect(
    result.collections.get("include"),
    content="Some([\"src\", \"lib\"])",
  )
}

///|
test "parse with aliases" {
  let aliases = { "v": "verbose", "o": "output" }
  let result = parse(
    ["-v", "-o", "file.txt"],
    flags=["verbose"],
    options=["output"],
    aliases~,
  )
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
  debug_inspect(result.options.get("output"), content="Some(\"file.txt\")")
}

///|
test "parse negatable flags" {
  let result = parse(["--no-verbose"], flags=["verbose"], negatable=["verbose"])
  debug_inspect(result.flags.get("verbose"), content="Some(false)")
}

///|
test "parse with double dash" {
  let result = parse(["--verbose", "--", "--not-a-flag"], flags=["verbose"])
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
  debug_inspect(result.positional, content="[\"--not-a-flag\"]")
}

///|
test "parse key-value syntax" {
  let result = parse(["--output=file.txt"], options=["output"])
  debug_inspect(result.options.get("output"), content="Some(\"file.txt\")")
}

///|
test "parse combined short flags" {
  let result = parse(["-vq"], flags=["v", "q"])
  debug_inspect(result.flags.get("v"), content="Some(true)")
  debug_inspect(result.flags.get("q"), content="Some(true)")
}

///|
test "demonstrate examples" {
  // This test demonstrates the examples work without running println
  let result1 = parse(
    ["--verbose", "-o", "output.txt", "input.txt"],
    flags=["verbose"],
    options=["output", "o"],
  )
  debug_inspect(result1.flags.get("verbose"), content="Some(true)")
  debug_inspect(result1.options.get("o"), content="Some(\"output.txt\")")
  debug_inspect(result1.positional, content="[\"input.txt\"]")
  let result2 = parse(["--include", "src", "--include", "lib", "main.mbt"], collections=[
    "include",
  ])
  debug_inspect(
    result2.collections.get("include"),
    content="Some([\"src\", \"lib\"])",
  )
  debug_inspect(result2.positional, content="[\"main.mbt\"]")
}

///|
test "parse - and -1" {
  let result = parse(["-", "-1", "file.txt"])
  debug_inspect(result.positional, content="[\"-\", \"-1\", \"file.txt\"]")
}

///|
test "parse subcommands" {
  let result = parse(["--help", "hello"], stop_early=true, flags=["help"])
  debug_inspect(
    result.positional,
    content=(
      #|["hello"]
    ),
  )
}
