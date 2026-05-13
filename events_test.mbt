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

///|
test "parse completed collab tool call" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.completed",
        #|  "item": {
        #|    "id": "collab-1",
        #|    "type": "collab_tool_call",
        #|    "tool": "spawn_agent",
        #|    "sender_thread_id": "thread-parent",
        #|    "receiver_thread_ids": ["thread-child"],
        #|    "prompt": "draft a plan",
        #|    "agents_states": {
        #|      "thread-child": {
        #|        "status": "running",
        #|        "message": null
        #|      }
        #|    },
        #|    "status": "completed"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemCompleted(
      CollabToolCallItem(
        tool~,
        sender_thread_id~,
        receiver_thread_ids~,
        prompt~,
        status~,
        ..
      )
    ) => {
      guard tool is SpawnAgent else { fail("expected spawn_agent collab tool") }
      guard status is Completed else {
        fail("expected completed collab tool call")
      }
      debug_inspect(
        sender_thread_id,
        content=(
          #|"thread-parent"
        ),
      )
      debug_inspect(
        receiver_thread_ids,
        content=(
          #|["thread-child"]
        ),
      )
      debug_inspect(
        prompt,
        content=(
          #|Some("draft a plan")
        ),
      )
    }
    _ => fail("expected completed collab tool call")
  }
}

///|
test "parse in-progress file change" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.started",
        #|  "item": {
        #|    "id": "patch-1",
        #|    "type": "file_change",
        #|    "changes": [
        #|      { "path": "README.md", "kind": "update" }
        #|    ],
        #|    "status": "in_progress"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemStarted(FileChangeItem(status~, changes~, ..)) => {
      guard status is InProgress else {
        fail("expected in-progress file change")
      }
      debug_inspect(
        changes.length(),
        content=(
          #|1
        ),
      )
    }
    _ => fail("expected started file change")
  }
}

///|
test "parse in-progress mcp tool call with null result and error" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.started",
        #|  "item": {
        #|    "id": "mcp-1",
        #|    "type": "mcp_tool_call",
        #|    "server": "docs",
        #|    "tool": "search",
        #|    "arguments": { "query": "codex" },
        #|    "result": null,
        #|    "error": null,
        #|    "status": "in_progress"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemStarted(McpToolCallItem(result~, status~, ..)) => {
      guard status is InProgress else {
        fail("expected in-progress MCP tool call")
      }
      guard result is None else { fail("expected no MCP result") }
    }
    _ => fail("expected started MCP tool call")
  }
}

///|
test "parse turn completed usage with reasoning tokens" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "turn.completed",
        #|  "usage": {
        #|    "input_tokens": 10,
        #|    "cached_input_tokens": 3,
        #|    "output_tokens": 7,
        #|    "reasoning_output_tokens": 5
        #|  }
        #|}
      ),
    ),
  )
  match event {
    TurnCompleted(usage) =>
      debug_inspect(
        usage,
        content=(
          #|{input_tokens: 10, cached_input_tokens: 3, output_tokens: 7, reasoning_output_tokens: 5}
        ),
      )
    _ => fail("expected turn completed event")
  }
}

///|
test "parse failed mcp tool call with null result" {
  let event : Event = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "item.completed",
        #|  "item": {
        #|    "id": "mcp-1",
        #|    "type": "mcp_tool_call",
        #|    "server": "docs",
        #|    "tool": "search",
        #|    "arguments": { "query": "codex" },
        #|    "result": null,
        #|    "error": { "message": "permission denied" },
        #|    "status": "failed"
        #|  }
        #|}
      ),
    ),
  )
  match event {
    ItemCompleted(McpToolCallItem(result~, status~, ..)) => {
      guard status is Failed else { fail("expected failed MCP tool call") }
      guard result is Some(Err("permission denied")) else {
        fail("expected MCP error result")
      }
    }
    _ => fail("expected completed MCP tool call")
  }
}
