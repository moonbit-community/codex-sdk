# Args - Command Line Argument Parser

A simple command line argument parser for MoonBit, similar to yargs and
minimist.

## Features

- Parse boolean flags (e.g., `--verbose`, `-v`)
- Parse string options with values (e.g., `--output file.txt`, `-o file.txt`)
- Parse array options that can appear multiple times (e.g.,
  `--include src --include lib`)
- Support for aliases (map short flags to long ones)
- Support for negatable flags (e.g., `--no-verbose`)
- Support for `--` to separate options from positional arguments
- Support for key-value syntax (e.g., `--output=file.txt`)
- Support for combined short flags (e.g., `-vq` for `-v -q`)

## Unknown Arguments

Unknown arguments are treated as positional arguments rather than causing
errors:

```moonbit nocheck
///|
test "unknown arguments become positional" {
  let result = parse(["--unknown", "-x", "normal"], flags=["verbose"])
  debug_inspect(
    result.positional,
    content="[\"--unknown\", \"-x\", \"normal\"]",
  )
  debug_inspect(result.flags.get("verbose"), content="None")
}
```

## Basic Usage

```moonbit nocheck
///|
test "basic usage example" {
  let args = parse(
    ["--verbose", "-o", "output.txt", "input.txt"],
    flags=["verbose"],
    options=["o"],
  )

  // Access parsed results
  debug_inspect(args.flags.get("verbose"), content="Some(true)")
  debug_inspect(args.options.get("o"), content="Some(\"output.txt\")")
  debug_inspect(args.positional, content="[\"input.txt\"]")
}
```

## Advanced Usage

```moonbit nocheck
///|
test "advanced usage example" {
  let args = parse(
    ["-v", "--include", "src", "--include", "lib", "--output=file.txt"],
    flags=["verbose"],
    options=["output"],
    collections=["include"],
    aliases={ "v": "verbose" },
  )
  debug_inspect(args.flags.get("verbose"), content="Some(true)")
  debug_inspect(args.options.get("output"), content="Some(\"file.txt\")")
  debug_inspect(
    args.collections.get("include"),
    content="Some([\"src\", \"lib\"])",
  )
}
```

## Configuration Options

- `flags`: Array of known boolean flags
- `options`: Array of known string options
- `collections`: Array of known array options
- `aliases`: Map of short names to long names
- `negatable`: Array of flags that can be negated with `--no-` prefix
- `double_dash`: Whether to support `--` separator (default: true)
- `stop_early`: Whether to stop parsing after first positional argument
  (default: false)

## Examples

### Basic flags and options

```moonbit nocheck
///|
test "basic flags and options" {
  let result = parse(["--verbose", "-o", "file.txt"], flags=["verbose"], options=[
    "o",
  ])
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
  debug_inspect(result.options.get("o"), content="Some(\"file.txt\")")
}
```

### Collections (repeated options)

```moonbit nocheck
///|
test "collections repeated options" {
  let result = parse(["--include", "src", "--include", "lib"], collections=[
    "include",
  ])
  debug_inspect(
    result.collections.get("include"),
    content="Some([\"src\", \"lib\"])",
  )
}
```

### Aliases

```moonbit nocheck
///|
test "aliases example" {
  let result = parse(["-v"], flags=["verbose"], aliases={ "v": "verbose" })
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
}
```

### Negatable flags

```moonbit nocheck
///|
test "negatable flags example" {
  let result = parse(["--no-verbose"], flags=["verbose"], negatable=["verbose"])
  debug_inspect(result.flags.get("verbose"), content="Some(false)")
}
```

### Double dash separator

```moonbit nocheck
///|
test "double dash separator example" {
  let result = parse(["--verbose", "--", "--not-a-flag"], flags=["verbose"])
  debug_inspect(result.flags.get("verbose"), content="Some(true)")
  debug_inspect(result.positional, content="[\"--not-a-flag\"]")
}
```

### Key-value syntax

```moonbit nocheck
///|
test "key-value syntax example" {
  let result = parse(["--output=file.txt"], options=["output"])
  debug_inspect(result.options.get("output"), content="Some(\"file.txt\")")
}
```

### Combined short flags

```moonbit nocheck
///|
test "combined short flags example" {
  let result = parse(["-vq"], flags=["v", "q"])
  debug_inspect(result.flags.get("v"), content="Some(true)")
  debug_inspect(result.flags.get("q"), content="Some(true)")
}
```
