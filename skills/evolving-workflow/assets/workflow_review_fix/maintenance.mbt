///|
fn default_maintenance_steps(
  workdir : String,
) -> Array[(String, Array[String])] {
  [("moon", ["fmt", "-C", workdir]), ("moon", ["info", "-C", workdir])]
}

///|
fn render_step_output(
  label : String,
  command : String,
  args : Array[String],
  exit_code : Int,
  stdout : String,
  stderr : String,
) -> String {
  let arg_str = args.join(" ")
  let output =
    $|[\{label}] $ \{command} \{arg_str}
    $|exit_code=\{exit_code}
    $|--- stdout ---
    $|\{stdout}
    $|--- stderr ---
    $|\{stderr}
  output
}

///|
async fn run_maintenance_steps(
  _workdir : String,
  steps : Array[(String, Array[String])],
) -> (Bool, String) {
  let outputs : Array[String] = []
  for step in steps {
    let (cmd, args) = step
    let arg_str = args.join(" ")
    let (exit_code, stdout, stderr) = @process.collect_output(cmd, args) catch {
      e => {
        outputs.push("Failed to run maintenance step: \{cmd} \{arg_str}\n\{e}")
        return (false, outputs.join("\n\n"))
      }
    }
    let stdout_text = stdout.text() catch { _ => "" }
    let stderr_text = stderr.text() catch { _ => "" }
    outputs.push(
      render_step_output(
        "maintenance", cmd, args, exit_code, stdout_text, stderr_text,
      ),
    )
    if exit_code != 0 {
      return (false, outputs.join("\n\n"))
    }
  }
  (true, outputs.join("\n\n"))
}
