///|
fn parse_run_mode(s : String) -> RunMode {
  match s.trim() {
    "review" => Review
    "fix" => Fix
    "both" => Both
    _ => Both
  }
}

///|
fn parse_sandbox_mode(s : String) -> @codex.SandboxMode {
  match s.trim() {
    "read-only" => @codex.SandboxMode::ReadOnly
    "workspace-write" => @codex.SandboxMode::WorkspaceWrite
    "danger-full-access" => @codex.SandboxMode::DangerFullAccess
    _ => @codex.SandboxMode::WorkspaceWrite
  }
}

///|
/// Parse command line arguments (excluding offset/limit; use TASK_OFFSET/TASK_LIMIT env).
fn parse_args(
  args : Array[String],
) -> (String?, RunMode, Int, @codex.SandboxMode) {
  let mut file : String? = None
  let mut mode = Both
  let mut max_iterations = 3
  let mut fix_sandbox = @codex.SandboxMode::WorkspaceWrite
  loop args[:] {
    ["--file", val, .. rest] => {
      file = Some(val)
      continue rest
    }
    ["--mode", val, .. rest] => {
      mode = parse_run_mode(val)
      continue rest
    }
    ["--max-iterations", val, .. rest] => {
      max_iterations = @strconv.parse_int(val) catch { _ => 3 }
      continue rest
    }
    ["--fix-sandbox", val, .. rest] => {
      fix_sandbox = parse_sandbox_mode(val)
      continue rest
    }
    [_, .. rest] => continue rest
    [] => break
  }
  (file, mode, max_iterations, fix_sandbox)
}
