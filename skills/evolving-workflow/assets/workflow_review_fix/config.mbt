///|
struct Config {
  workdir : String
  task_offset : Int
  task_limit : Int
}

///|
fn parse_int_with_default(s : String?, default : Int) -> Int {
  match s {
    Some(v) => @strconv.parse_int(v) catch { _ => default }
    None => default
  }
}

///|
fn read_config(env : Map[String, String]) -> Config {
  let workdir = env.get("CODEX_WORKDIR").unwrap_or(".")
  let task_offset = parse_int_with_default(env.get("TASK_OFFSET"), 0)
  let task_limit = parse_int_with_default(env.get("TASK_LIMIT"), -1)
  { workdir, task_offset, task_limit }
}
