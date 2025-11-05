///|
test "parse basic flags" {
  let result = parse(["--verbose", "-q", "file.txt"], flags=["verbose", "q"])
  inspect(result.flags.get("verbose"), content="Some(true)")
  inspect(result.flags.get("q"), content="Some(true)")
  inspect(result.positional, content="[\"file.txt\"]")
}

///|
test "parse options with values" {
  let result = parse(["--output", "file.txt", "-v"], flags=["v"], options=[
    "output",
  ])
  inspect(result.options.get("output"), content="Some(\"file.txt\")")
  inspect(result.flags.get("v"), content="Some(true)")
}

///|
test "parse collections" {
  let result = parse(["--include", "src", "--include", "lib"], collections=[
    "include",
  ])
  inspect(result.collections.get("include"), content="Some([\"src\", \"lib\"])")
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
  inspect(result.flags.get("verbose"), content="Some(true)")
  inspect(result.options.get("output"), content="Some(\"file.txt\")")
}

///|
test "parse negatable flags" {
  let result = parse(["--no-verbose"], flags=["verbose"], negatable=["verbose"])
  inspect(result.flags.get("verbose"), content="Some(false)")
}

///|
test "parse with double dash" {
  let result = parse(["--verbose", "--", "--not-a-flag"], flags=["verbose"])
  inspect(result.flags.get("verbose"), content="Some(true)")
  inspect(result.positional, content="[\"--not-a-flag\"]")
}

///|
test "parse key-value syntax" {
  let result = parse(["--output=file.txt"], options=["output"])
  inspect(result.options.get("output"), content="Some(\"file.txt\")")
}

///|
test "parse combined short flags" {
  let result = parse(["-vq"], flags=["v", "q"])
  inspect(result.flags.get("v"), content="Some(true)")
  inspect(result.flags.get("q"), content="Some(true)")
}

///|
test "demonstrate examples" {
  // This test demonstrates the examples work without running println
  let result1 = parse(
    ["--verbose", "-o", "output.txt", "input.txt"],
    flags=["verbose"],
    options=["output", "o"],
  )
  inspect(result1.flags.get("verbose"), content="Some(true)")
  inspect(result1.options.get("o"), content="Some(\"output.txt\")")
  inspect(result1.positional, content="[\"input.txt\"]")
  let result2 = parse(["--include", "src", "--include", "lib", "main.mbt"], collections=[
    "include",
  ])
  inspect(
    result2.collections.get("include"),
    content="Some([\"src\", \"lib\"])",
  )
  inspect(result2.positional, content="[\"main.mbt\"]")
}
