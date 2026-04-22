///|
/// Represents parsed command line arguments
pub struct Args {
  /// Positional arguments (non-flag/option arguments)
  positional : Array[String]
  /// Boolean flags (e.g., --verbose, -v)
  flags : Map[String, Bool]
  /// String options with values (e.g., --output=file.txt, -o file.txt)
  options : Map[String, String]
  /// Array options that can appear multiple times (e.g., --include src --include lib)
  collections : Map[String, Array[String]]
}

///|
/// Parse command line arguments with simple configuration
pub fn parse(
  args : ArrayView[String],
  flags? : ArrayView[String] = [],
  options? : ArrayView[String] = [],
  collections? : ArrayView[String] = [],
  aliases? : Map[String, String] = {},
  negatable? : ArrayView[String] = [],
  double_dash? : Bool = true,
  stop_early? : Bool = false,
) -> Args raise {
  let positional : Array[String] = []
  let flags_map : Map[String, Bool] = {}
  let options_map : Map[String, String] = {}
  let collections_map : Map[String, Array[String]] = {}

  // Create sets for O(1) lookup
  let flag_set = Set::from_array(flags.map(s => s[:]))
  let option_set = Set::from_array(options.map(s => s[:]))
  let collection_set = Set::from_array(collections.map(s => s[:]))
  let negatable_set = Set::from_array(negatable.map(s => s[:]))

  // Helper to resolve aliases
  fn resolve_alias(name : StringView) -> String {
    aliases.get_from_string(name).unwrap_or(name.to_string())
  }

  let mut args = args[:]
  while args is [arg, .. rest] {
    args = rest
    // Handle double dash
    if arg is "--" && double_dash {
      // After --, everything is positional
      positional.push_iter(args.iter())
      break
    }

    // Stop early if requested and we hit a non-option
    if stop_early && !arg.has_prefix("-") {
      positional.push(arg)
      positional.push_iter(args.iter())
      break
    }
    if arg is [.. "--", .. rest] && rest.length() > 0 {
      // Handle long options (--name or --name=value)
      // Extract name and value
      let eq = rest.find("=")
      let name = if eq is Some(pos) { rest[:pos] } else { rest }
      let value = if eq is Some(pos) { Some(rest[pos + 1:]) } else { None }

      // Handle --no- prefix for negatable flags
      if name is [.. "no-", .. base_name] {
        let base_resolved = resolve_alias(base_name)
        if negatable_set.contains(base_resolved) {
          flags_map[base_resolved] = false
          continue
        }
      }
      let resolved = resolve_alias(name)
      if flag_set.contains(resolved) {
        // if it's a flag
        flags_map[resolved] = true
      } else if option_set.contains(resolved) {
        // if it's an option
        let value = match value {
          Some(v) => v
          None => {
            guard args is [next_arg, .. rest_args] else {
              fail("Option --\{name} requires a value")
            }
            args = rest_args
            next_arg
          }
        }
        options_map[resolved] = value.to_string()
      } else if collection_set.contains(resolved) {
        // if it's a collection
        let value = match value {
          Some(v) => v
          None => {
            guard args is [next_arg, .. rest_args] else {
              fail("Collection --\{name} requires a value")
            }
            args = rest_args
            next_arg
          }
        }
        match collections_map.get_from_string(resolved) {
          Some(arr) => arr.push(value.to_string())
          None => collections_map[resolved] = [value.to_string()]
        }
      } else {
        // Unknown option - treat as positional
        positional.push(arg)
      }
    } else if arg is [.. "-", .. rest] && rest.length() > 0 {
      // Handle short options
      loop rest {
        [] => ()
        [ch] => {
          let resolved = resolve_alias(ch.to_string())
          if flag_set.contains(resolved) {
            flags_map[resolved] = true
          } else if option_set.contains(resolved) {
            // Option requires a value
            guard args is [next_arg, .. rest_args] else {
              fail("Option -\{ch} requires a value")
            }
            options_map[resolved] = next_arg
            args = rest_args
          } else if collection_set.contains(resolved) {
            // Collection requires a value
            guard args is [next_arg, .. rest_args] else {
              fail("Collection -\{ch} requires a value")
            }
            let value = next_arg
            match collections_map.get_from_string(resolved) {
              Some(arr) => arr.push(value)
              None => collections_map[resolved] = [value]
            }
            args = rest_args
          } else {
            // Unknown flag - treat as positional
            positional.push(arg)
          }
        }
        [ch, .. rest] => {
          let resolved = resolve_alias(ch.to_string())
          if flag_set.contains(resolved) {
            flags_map[resolved] = true
            continue rest
          } else if option_set.contains(resolved) {
            // Option requires a value
            fail("Option -\{ch} in combined short flags requires a value")
          } else if collection_set.contains(resolved) {
            // Collection requires a value
            fail("Collection -\{ch} in combined short flags requires a value")
          } else {
            // Unknown flag - treat as positional
            positional.push(arg)
            break
          }
        }
      }
    } else {
      // Everything else is positional
      positional.push(arg)
    }
  }
  {
    positional,
    flags: flags_map,
    options: options_map,
    collections: collections_map,
  }
}
