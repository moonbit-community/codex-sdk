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
  args : Array[String],
  flags? : Array[String] = [],
  options? : Array[String] = [],
  collections? : Array[String] = [],
  aliases? : Map[String, String] = {},
  negatable? : Array[String] = [],
  double_dash? : Bool = true,
  stop_early? : Bool = false,
) -> Args {
  let positional = []
  let flags_map = {}
  let options_map = {}
  let collections_map : Map[String, Array[String]] = {}

  // Create sets for O(1) lookup
  let flag_set = {}
  for flag in flags {
    flag_set[flag] = true
  }
  let option_set = {}
  for option in options {
    option_set[option] = true
  }
  let collection_set = {}
  for collection in collections {
    collection_set[collection] = true
  }
  let negatable_set = {}
  for neg in negatable {
    negatable_set[neg] = true
  }

  // Helper to resolve aliases
  fn resolve_alias(name : String) -> String {
    match aliases.get(name) {
      Some(target) => target
      None => name
    }
  }

  let mut i = 0
  let mut after_double_dash = false
  while i < args.length() {
    let arg = args[i]

    // Handle double dash
    if arg == "--" && double_dash {
      after_double_dash = true
      i = i + 1
      continue
    }

    // After --, everything is positional
    if after_double_dash {
      positional.push(arg)
      i = i + 1
      continue
    }

    // Stop early if requested and we hit a non-option
    if stop_early && not(arg.has_prefix("-")) {
      while i < args.length() {
        positional.push(args[i])
        i = i + 1
      }
      break
    }

    // Handle long options (--name or --name=value)
    if arg.has_prefix("--") && arg.length() > 2 {
      let mut name = ""
      let mut value_opt : String? = None

      // Extract name and value
      let mut found_eq = false
      for j = 2; j < arg.length(); j = j + 1 {
        if arg[j] == '=' && not(found_eq) {
          found_eq = true
          let mut val = ""
          for k = j + 1; k < arg.length(); k = k + 1 {
            match arg[k].to_char() {
              Some(c) => val = val + "\{c}"
              None => ()
            }
          }
          value_opt = Some(val)
          break
        } else if not(found_eq) {
          match arg[j].to_char() {
            Some(c) => name = name + "\{c}"
            None => ()
          }
        }
      }

      // Handle --no- prefix for negatable flags
      if name.has_prefix("no-") && name.length() > 3 {
        let mut base_name = ""
        for j = 3; j < name.length(); j = j + 1 {
          match name[j].to_char() {
            Some(c) => base_name = base_name + "\{c}"
            None => ()
          }
        }
        let base_resolved = resolve_alias(base_name)
        if negatable_set.contains(base_resolved) {
          flags_map[base_resolved] = false
          i = i + 1
          continue
        }
      }
      let resolved = resolve_alias(name)

      // Check if it's a flag
      if flag_set.contains(resolved) {
        flags_map[resolved] = true
        i = i + 1
        continue
      }

      // Check if it's an option
      if option_set.contains(resolved) {
        let value = match value_opt {
          Some(v) => v
          None => {
            i = i + 1
            if i >= args.length() {
              abort("Option --\{name} requires a value")
            }
            args[i]
          }
        }
        options_map[resolved] = value
        i = i + 1
        continue
      }

      // Check if it's a collection
      if collection_set.contains(resolved) {
        let value = match value_opt {
          Some(v) => v
          None => {
            i = i + 1
            if i >= args.length() {
              abort("Collection --\{name} requires a value")
            }
            args[i]
          }
        }
        match collections_map.get(resolved) {
          Some(arr) => arr.push(value)
          None => collections_map[resolved] = [value]
        }
        i = i + 1
        continue
      }

      // Unknown option - treat as positional
      positional.push(arg)
      i = i + 1
      continue
    }

    // Handle short options
    if arg.has_prefix("-") && arg.length() > 1 && arg != "--" {
      let mut j = 1
      while j < arg.length() {
        let name = match arg[j].to_char() {
          Some(c) => "\{c}"
          None => ""
        }
        let resolved = resolve_alias(name)
        if flag_set.contains(resolved) {
          flags_map[resolved] = true
          j = j + 1
        } else if option_set.contains(resolved) {
          if j == arg.length() - 1 {
            // Last character, look for next argument
            i = i + 1
            if i >= args.length() {
              abort("Option -\{name} requires a value")
            }
            options_map[resolved] = args[i]
            break
          } else {
            abort("Option -\{name} in combined short flags requires a value")
          }
        } else if collection_set.contains(resolved) {
          if j == arg.length() - 1 {
            i = i + 1
            if i >= args.length() {
              abort("Collection -\{name} requires a value")
            }
            let value = args[i]
            match collections_map.get(resolved) {
              Some(arr) => arr.push(value)
              None => collections_map[resolved] = [value]
            }
            break
          } else {
            abort(
              "Collection -\{name} in combined short flags requires a value",
            )
          }
        } else {
          // Unknown flag - treat as positional
          positional.push(arg)
          break
        }
      }
      i = i + 1
      continue
    }

    // Everything else is positional
    positional.push(arg)
    i = i + 1
  }
  {
    positional,
    flags: flags_map,
    options: options_map,
    collections: collections_map,
  }
}
