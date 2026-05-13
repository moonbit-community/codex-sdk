///|
test "parse started command execution without output" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.started",
        #|  "item": {
        #|    "id": "cmd-1",
        #|    "type": "command_execution",
        #|    "command": "pwd",
        #|    "status": "in_progress"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemStarted(
      CommandExecutionItem(
        id~,
        command~,
        aggregated_output~,
        exit_code~,
        status~
      )
    ) => {
      debug_inspect(
        id,
        content=(
          #|"cmd-1"
        ),
      )
      debug_inspect(
        command,
        content=(
          #|"pwd"
        ),
      )
      debug_inspect(
        aggregated_output,
        content=(
          #|""
        ),
      )
      debug_inspect(exit_code, content="None")
      guard status is InProgress else {
        fail("expected in-progress command execution")
      }
    }
    _ => fail("expected started command execution")
  }
}
