///|
async fn ensure_module(path : String) -> Unit {
  if not(@fs.exists("\{path}/moon.mod.json")) {
    fail("No Moon module found at \{path}\n")
  }
  let schema = @json.parse(@fs.read_file("\{path}/moon.mod.json").text())
  guard schema is { "name": String(_), .. } else {
    fail("Invalid moon.mod.json at \{path} with content \{schema}")
  }
}

///|
async fn list_package_paths(root : String) -> Array[String] {
  let result = []
  async fn visit(path : String) {
    let entries = @fs.readdir("\{root}\{path}", include_hidden=false)
    if !path.is_empty() && entries.contains("moon.mod.json") {
      return
    }
    if entries.contains("moon.pkg.json") {
      result.push(path)
    }
    for entry in entries {
      let subpath = "\{path}/\{entry}"
      let kind = @fs.kind("\{root}\{subpath}")
      if kind is Directory {
        visit(subpath)
      }
    }
  }

  visit("")
  result
}
