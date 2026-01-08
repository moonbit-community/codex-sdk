///|
struct PackageSummary {
  path : String
  summary : String
}

///|
/// Find all directories containing moon.pkg.json using `find` command
async fn find_packages(root : String) -> Array[String] {
  let (exit_code, stdout, _stderr) = @process.collect_output("find", [
    root, "-name", "moon.pkg.json", "-type", "f", "-not", "-path", "*/.mooncakes/*",
    "-not", "-path", "*/_build/*", "-not", "-path", "*/target/*",
  ])
  if exit_code != 0 {
    return []
  }
  let packages : Array[String] = []
  for line in stdout.text().split("\n") {
    let line = line.to_string().trim()
    if !line.is_empty() {
      // Get directory containing moon.pkg.json
      let parts : Array[String] = []
      for part in line.split("/") {
        parts.push(part.to_string())
      }
      if parts.length() > 0 {
        let _ = parts.pop() // Remove "moon.pkg.json"
        let dir = parts.join("/")
        if !dir.is_empty() {
          packages.push(dir)
        }
      }
    }
  }
  packages
}

///|
/// Read pkg.generated.mbti if it exists
async fn read_mbti(pkg_dir : String) -> String? {
  let path = "\{pkg_dir}/pkg.generated.mbti"
  let content = @fs.read_file(path).text() catch { _ => return None }
  Some(content)
}

///|
/// Read .mbt source files in a package directory
async fn read_sources(pkg_dir : String) -> String {
  let sources : Array[String] = []
  let entries = @fs.readdir(pkg_dir, include_hidden=false) catch {
    _ => return ""
  }
  for entry in entries {
    if entry.has_suffix(".mbt") &&
      !entry.has_suffix("_test.mbt") &&
      !entry.has_suffix("_wbtest.mbt") {
      let content = @fs.read_file("\{pkg_dir}/\{entry}").text() catch {
        _ => continue
      }
      sources.push("// \{entry}\n\{content}")
    }
  }
  sources.join("\n\n")
}

///|
/// Summarize a single package using Codex
async fn summarize_package(
  codex : @codex.Codex,
  pkg_dir : String,
  workdir : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      skip_git_repo_check=true,
    ),
  )
  let mbti = read_mbti(pkg_dir) catch { _ => None }
  let sources = read_sources(pkg_dir) catch { _ => "" }
  let prompt = match mbti {
    Some(mbti_content) => {
      let p =
        $|Summarize this MoonBit package in 2-4 bullet points.
        $|
        $|Package path: \{pkg_dir}
        $|
        $|Generated interface (pkg.generated.mbti):
        $|\{mbti_content}
        $|
        $|Source code (if needed for context):
        $|\{sources}
      p
    }
    None => {
      let p =
        $|Summarize this MoonBit package in 2-4 bullet points.
        $|
        $|Package path: \{pkg_dir}
        $|
        $|Source code:
        $|\{sources}
      p
    }
  }
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
/// Create a final summary of all packages using Codex
async fn summarize_all(
  codex : @codex.Codex,
  summaries : Array[PackageSummary],
  workdir : String,
) -> String {
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=workdir,
      sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
      skip_git_repo_check=true,
    ),
  )
  let content : Array[String] = []
  for s in summaries {
    content.push("## \{s.path}\n\{s.summary}")
  }
  let prompt =
    $|Based on the following package summaries, provide an overall summary of this MoonBit project in 5-7 bullet points.
    $|
    $|\{content.join("\n\n")}
  let turn = thread.run(prompt) catch { e => return "ERROR: \{e}" }
  turn.final_response
}

///|
async fn main {
  let workdir = @sys.get_env_vars().get("CODEX_WORKDIR").unwrap_or(".")
  let packages = find_packages(workdir) catch { _ => [] }
  if packages.is_empty() {
    @stdio.stdout.write("No packages found.\n")
    return
  }
  let codex = @codex.Codex::new()
  let summaries : Array[PackageSummary] = []
  let parallelism = 4
  @async.with_task_group(fn(task_group) {
    let semaphore = @async.Semaphore::new(parallelism)
    for pkg_dir in packages {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let summary = summarize_package(codex, pkg_dir, workdir) catch {
          e => "ERROR: \{e}"
        }
        summaries.push(PackageSummary::{ path: pkg_dir, summary })
      })
    }
  })
  @stdio.stdout.write("== Package Summaries ==\n")
  for s in summaries {
    @stdio.stdout.write("\n## \{s.path}\n\{s.summary}\n")
  }
  let overall = summarize_all(codex, summaries, workdir) catch {
    e => "ERROR: \{e}"
  }
  @stdio.stdout.write("\n== Overall Project Summary ==\n\{overall}\n")
}
