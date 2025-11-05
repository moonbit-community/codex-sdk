# Args - Command Line Argument Parser

A simple command line argument parser for MoonBit, similar to yargs and minimist.

## Features

- Parse boolean flags (e.g., `--verbose`, `-v`)
- Parse string options with values (e.g., `--output file.txt`, `-o file.txt`)
- Parse array options that can appear multiple times (e.g., `--include src --include lib`)
- Support for aliases (map short flags to long ones)
- Support for negatable flags (e.g., `--no-verbose`)
- Support for `--` to separate options from positional arguments
- Support for key-value syntax (e.g., `--output=file.txt`)
- Support for combined short flags (e.g., `-vq` for `-v -q`)

## Basic Usage

```moonbit
let args = parse(
  ["--verbose", "-o", "output.txt", "input.txt"],
  flags=["verbose"],
  options=["output"]
)

// Access parsed results
args.flags.get("verbose")      // Some(true)
args.options.get("output")     // Some("output.txt")
args.positional               // ["input.txt"]
```

## Advanced Usage

```moonbit
let args = parse(
  ["-v", "--include", "src", "--include", "lib", "--output=file.txt"],
  flags=["verbose"],
  options=["output"],
  collections=["include"],
  aliases={"v": "verbose"}
)

args.flags.get("verbose")         // Some(true)
args.options.get("output")        // Some("file.txt")
args.collections.get("include")   // Some(["src", "lib"])
```

## Configuration Options

- `flags`: Array of known boolean flags
- `options`: Array of known string options
- `collections`: Array of known array options
- `aliases`: Map of short names to long names
- `negatable`: Array of flags that can be negated with `--no-` prefix
- `double_dash`: Whether to support `--` separator (default: true)
- `stop_early`: Whether to stop parsing after first positional argument (default: false)

## Examples

### Basic flags and options
```moonbit
let result = parse(["--verbose", "-o", "file.txt"], flags=["verbose"], options=["output"])
```

### Collections (repeated options)
```moonbit
let result = parse(["--include", "src", "--include", "lib"], collections=["include"])
```

### Aliases
```moonbit
let result = parse(["-v"], flags=["verbose"], aliases={"v": "verbose"})
```

### Negatable flags
```moonbit
let result = parse(["--no-verbose"], flags=["verbose"], negatable=["verbose"])
```

### Double dash separator
```moonbit
let result = parse(["--verbose", "--", "--not-a-flag"], flags=["verbose"])
// result.flags.get("verbose") == Some(true)
// result.positional == ["--not-a-flag"]
```

### Key-value syntax
```moonbit
let result = parse(["--output=file.txt"], options=["output"])
```

### Combined short flags
```moonbit
let result = parse(["-vq"], flags=["v", "q"])
```