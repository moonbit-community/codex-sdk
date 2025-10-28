///|
struct Module {
  root : String
  name : String
}

///|
struct Package {
  mod : Module
  path : String
}

///|
async fn Module::at(path : String) -> Module? {
  if @fs.exists("\{path}/moon.mod.json") {
    let schema = @json.parse(@fs.read_file("\{path}/moon.mod.json").text())
    guard schema is { "name": String(name), .. } else {
      fail("Invalid moon.mod.json at \{path} with content \{schema}")
    }
    Some(Module::{ root: path, name })
  } else {
    None
  }
}

///|
async fn Module::packages(mod : Self) -> Array[Package] {
  let result = []
  let root = mod.root
  async fn visit(path : String) {
    let entries = @fs.readdir("\{root}\{path}", include_hidden=false)
    if !path.is_empty() && entries.contains("moon.mod.json") {
      // Found a submodule, skip
      return
    }
    if entries.contains("moon.pkg.json") {
      // Found a package, add to result
      result.push(Package::{ mod, path })
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

///|
struct ExecResult {
  stdout : String
  stderr : String
  status : Int
}

///|
async fn Module::check(mod : Self) -> ExecResult {
  let stdout = @process.read_from_process()
  let stderr = @process.read_from_process()
  let value = @process.run(
    "moon",
    ["check", "-C", mod.root],
    stdout=stdout.1,
    stderr=stderr.1,
  )
  let stdout = stdout.0.read_all().text()
  let stderr = stderr.0.read_all().text()
  { stdout, stderr, status: value }
}

///|
async fn Module::test_(mod : Self) -> ExecResult {
  let stdout = @process.read_from_process()
  let stderr = @process.read_from_process()
  let value = @process.run(
    "moon",
    ["test", "-C", mod.root],
    stdout=stdout.1,
    stderr=stderr.1,
  )
  let stdout = stdout.0.read_all().text()
  let stderr = stderr.0.read_all().text()
  { stdout, stderr, status: value }
}

///|
async fn Module::format(mod : Self) -> ExecResult {
  let stdout = @process.read_from_process()
  let stderr = @process.read_from_process()
  let value = @process.run(
    "moon",
    ["fmt", "-C", mod.root],
    stdout=stdout.1,
    stderr=stderr.1,
  )
  let stdout = stdout.0.read_all().text()
  let stderr = stderr.0.read_all().text()
  { stdout, stderr, status: value }
}

///|
async fn Module::update_info(mod : Self) -> ExecResult {
  let stdout = @process.read_from_process()
  let stderr = @process.read_from_process()
  let value = @process.run(
    "moon",
    ["update-info", "-C", mod.root],
    stdout=stdout.1,
    stderr=stderr.1,
  )
  let stdout = stdout.0.read_all().text()
  let stderr = stderr.0.read_all().text()
  { stdout, stderr, status: value }
}
