///|
test "parse started command execution with empty output" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.started",
        #|  "item": {
        #|    "id": "cmd-1",
        #|    "type": "command_execution",
        #|    "command": "pwd",
        #|    "aggregated_output": "",
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

///|
test "parse declined command execution" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.completed",
        #|  "item": {
        #|    "id": "cmd-1",
        #|    "type": "command_execution",
        #|    "command": "pwd",
        #|    "aggregated_output": "",
        #|    "status": "declined"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemCompleted(CommandExecutionItem(status~, exit_code~, ..)) => {
      guard status is Declined else {
        fail("expected declined command execution")
      }
      debug_inspect(exit_code, content="None")
    }
    _ => fail("expected completed command execution")
  }
}
