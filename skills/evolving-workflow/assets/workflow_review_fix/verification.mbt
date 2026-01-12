///|
struct Verification {
  cmd : String
  args : Array[String]
  cwd : String?
}

///|
fn default_verifications(workdir : String) -> Array[Verification] {
  [
    { cmd: "moon", args: ["test", "-C", workdir], cwd: None },
    { cmd: "moon", args: ["check", "-C", workdir], cwd: None },
  ]
}

///|
fn render_verification_output(
  command : String,
  args : Array[String],
  exit_code : Int,
  stdout : String,
  stderr : String,
) -> String {
  let arg_str = args.join(" ")
  let output =
    $|[verification] $ \{command} \{arg_str}
    $|exit_code=\{exit_code}
    $|--- stdout ---
    $|\{stdout}
    $|--- stderr ---
    $|\{stderr}
  output
}

///|
async fn run_verifications(
  workdir : String,
  verifications : Array[Verification],
) -> (Bool, String) {
  let outputs : Array[String] = []
  for verification in verifications {
    let cmd = verification.cmd
    let args = verification.args
    let arg_str = args.join(" ")
    let cwd = verification.cwd.unwrap_or(workdir)
    let (exit_code, stdout, stderr) = @process.collect_output(cmd, args, cwd~) catch {
      e => {
        outputs.push(
          "Failed to run verification: \{cmd} \{arg_str} (cwd=\{cwd})\n\{e}",
        )
        return (false, outputs.join("\n\n"))
      }
    }
    let stdout_text = stdout.text() catch { _ => "" }
    let stderr_text = stderr.text() catch { _ => "" }
    outputs.push(
      render_verification_output(cmd, args, exit_code, stdout_text, stderr_text),
    )
    if exit_code != 0 {
      return (false, outputs.join("\n\n"))
    }
  }
  (true, outputs.join("\n\n"))
}
