// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
pub enum ThreadItem {
  /// Response from the agent. Either natural-language text or JSON when structured output is requested.
  AgentMessageItem(id~ : String, text~ : String)
  /// Agent's reasoning summary.
  ReasoningItem(id~ : String, text~ : String)
  /// A command executed by the agent.
  CommandExecutionItem(
    id~ : String,
    command~ : String,
    aggregated_output~ : String,
    exit_code~ : Int?,
    status~ : CommandExecutionStatus
  )
  /// A set of file changes by the agent. Emitted once the patch succeeds or fails.
  FileChangeItem(
    id~ : String,
    changes~ : Array[FileUpdateChange],
    status~ : PatchApplyStatus
  )
  /// Represents a call to an MCP tool. The item starts when the invocation is dispatched and completes when the MCP server reports success or failure.
  McpToolCallItem(
    id~ : String,
    server~ : String,
    tool~ : String,
    status~ : McpToolCallStatus,
    arguments~ : Json?,
    result~ : Result[McpToolCallResult, String]?
  )
  /// Represents a call to a Codex collab-agent tool.
  CollabToolCallItem(
    id~ : String,
    tool~ : CollabTool,
    sender_thread_id~ : String,
    receiver_thread_ids~ : Array[String],
    prompt~ : String?,
    agents_states~ : Map[String, CollabAgentState],
    status~ : CollabToolCallStatus
  )
  /// Captures a web search request. Completes when results are returned to the agent.
  WebSearchItem(id~ : String, query~ : String)
  /// Tracks the agent's running to-do list. Starts when the plan is issued, updates as steps change, and completes when the turn ends.
  TodoListItem(id~ : String, items~ : Array[TodoItem])
  /// Describes a non-fatal error surfaced as an item.
  ErrorItem(id~ : String, message~ : String)
} derive(Debug)

///|
pub impl ToJson for ThreadItem with to_json(item) {
  match item {
    AgentMessageItem(id~, text~) =>
      { "type": "agent_message", "id": id, "text": text }
    ReasoningItem(id~, text~) => { "type": "reasoning", "id": id, "text": text }
    CommandExecutionItem(id~, command~, aggregated_output~, exit_code~, status~) =>
      if exit_code is Some(exit_code) {
        {
          "type": "command_execution",
          "id": id,
          "command": command,
          "aggregated_output": aggregated_output,
          "exit_code": exit_code,
          "status": status,
        }
      } else {
        {
          "type": "command_execution",
          "id": id,
          "command": command,
          "aggregated_output": aggregated_output,
          "status": status,
        }
      }
    FileChangeItem(id~, changes~, status~) =>
      { "type": "file_change", "id": id, "changes": changes, "status": status }
    McpToolCallItem(id~, server~, tool~, status~, arguments~, result~) => {
      let item : Map[String, Json] = {
        "type": "mcp_tool_call",
        "id": id,
        "server": server,
        "tool": tool,
        "status": status,
      }
      if arguments is Some(arguments) {
        item.set("arguments", arguments)
      }
      if result is Some(Ok(res)) {
        item.set("result", res.to_json())
      } else if result is Some(Err(err)) {
        item.set("error", { "message": err })
      }
      Json::object(item)
    }
    CollabToolCallItem(
      id~,
      tool~,
      sender_thread_id~,
      receiver_thread_ids~,
      prompt~,
      agents_states~,
      status~
    ) => {
      let item : Map[String, Json] = {
        "type": "collab_tool_call",
        "id": id,
        "tool": tool,
        "sender_thread_id": sender_thread_id,
        "receiver_thread_ids": receiver_thread_ids,
        "agents_states": agents_states,
        "status": status,
      }
      if prompt is Some(prompt) {
        item.set("prompt", prompt.to_json())
      }
      Json::object(item)
    }
    WebSearchItem(id~, query~) =>
      { "type": "web_search", "id": id, "query": query }
    TodoListItem(id~, items~) =>
      { "type": "todo_list", "id": id, "items": items }
    ErrorItem(id~, message~) =>
      { "type": "error", "id": id, "message": message }
  }
}

///|
pub impl @json.FromJson for ThreadItem with from_json(value, path) {
  guard value is Object({ "type": String(ty), .. } as obj) else {
    raise JsonDecodeError((path, "expected ThreadItem"))
  }
  match ty {
    "agent_message" => {
      guard obj is { "id": String(id), "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected AgentMessageItem"))
      }
      AgentMessageItem(id~, text~)
    }
    "reasoning" => {
      guard obj is { "id": String(id), "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected ReasoningItem"))
      }
      ReasoningItem(id~, text~)
    }
    "command_execution" => {
      guard obj
        is {
          "id": String(id),
          "command": String(command),
          "aggregated_output": String(aggregated_output),
          "status": String(_) as status,
          "exit_code"? : exit_code,
          ..
        } else {
        raise JsonDecodeError(
          (path, "expected CommandExecutionItem, got \{@debug.to_repr(obj)}"),
        )
      }
      let exit_code = match exit_code {
        Some(Number(n, ..)) => Some(n.to_int())
        Some(Null) | None => None
        v =>
          raise JsonDecodeError(
            (
              path.add_key("exit_code"),
              "expected integer or null for CommandExecutionItem.exit_code. Got: \{@debug.to_repr(v)}",
            ),
          )
      }
      CommandExecutionItem(
        id~,
        command~,
        aggregated_output~,
        exit_code~,
        status=@json.from_json(status, path=path.add_key("status")),
      )
    }
    "file_change" => {
      guard obj
        is { "id": String(id), "changes": changes, "status": status, .. } else {
        raise JsonDecodeError((path, "expected FileChangeItem"))
      }
      FileChangeItem(
        id~,
        changes=@json.from_json(changes, path=path.add_key("changes")),
        status=@json.from_json(status, path=path.add_key("status")),
      )
    }
    "mcp_tool_call" => {
      guard obj
        is {
          "id": String(id),
          "server": String(server),
          "tool": String(tool),
          "status": status,
          "arguments"? : arguments,
          "result"? : result,
          "error"? : error,
          ..
        } else {
        raise JsonDecodeError((path, "expected McpToolCallItem"))
      }
      if error is Some(error) {
        guard error is Null || error is Object({ "message": String(_), .. }) else {
          raise JsonDecodeError(
            (
              path.add_key("error"),
              "expected null or error object with message string, got \{@debug.to_repr(error)}",
            ),
          )
        }
      }
      McpToolCallItem(
        id~,
        server~,
        tool~,
        status=@json.from_json(status, path=path.add_key("status")),
        arguments~,
        result=if error is Some(Object({ "message": String(msg), .. })) {
          Some(Err(msg))
        } else if result is Some(Null) {
          None
        } else if result is Some(res) {
          Some(Ok(@json.from_json(res, path=path.add_key("result"))))
        } else {
          None
        },
      )
    }
    "collab_tool_call" => {
      guard obj
        is {
          "id": String(id),
          "tool": tool,
          "sender_thread_id": String(sender_thread_id),
          "receiver_thread_ids": receiver_thread_ids,
          "prompt"? : prompt,
          "agents_states": agents_states,
          "status": status,
          ..
        } else {
        raise JsonDecodeError((path, "expected CollabToolCallItem"))
      }
      let prompt = match prompt {
        Some(String(prompt)) => Some(prompt)
        Some(Null) | None => None
        v =>
          raise JsonDecodeError(
            (
              path.add_key("prompt"),
              "expected string or null for CollabToolCallItem.prompt. Got: \{@debug.to_repr(v)}",
            ),
          )
      }
      CollabToolCallItem(
        id~,
        tool=@json.from_json(tool, path=path.add_key("tool")),
        sender_thread_id~,
        receiver_thread_ids=@json.from_json(
          receiver_thread_ids,
          path=path.add_key("receiver_thread_ids"),
        ),
        prompt~,
        agents_states=@json.from_json(
          agents_states,
          path=path.add_key("agents_states"),
        ),
        status=@json.from_json(status, path=path.add_key("status")),
      )
    }
    "web_search" => {
      guard obj is { "id": String(id), "query": String(query), .. } else {
        raise JsonDecodeError((path, "expected WebSearchItem"))
      }
      WebSearchItem(id~, query~)
    }
    "todo_list" => {
      guard obj is { "id": String(id), "items": items, .. } else {
        raise JsonDecodeError((path, "expected TodoListItem"))
      }
      TodoListItem(
        id~,
        items=@json.from_json(items, path=path.add_key("items")),
      )
    }
    "error" => {
      guard obj is { "id": String(id), "message": String(message), .. } else {
        raise JsonDecodeError((path, "expected ErrorItem"))
      }
      ErrorItem(id~, message~)
    }
    _ => raise JsonDecodeError((path, "unknown ThreadItem type: \{ty}"))
  }
}

///|
/// A set of file changes by the agent.
pub struct FileUpdateChange {
  path : String
  kind : PatchChangeKind
} derive(ToJson, FromJson, Debug)

///|
pub impl Show for FileUpdateChange with output(self, logger) {
  logger.write_string("{path: \"\{self.path}\", kind: \{self.kind}}")
}

///|
/// An item in the agent's to-do list.
pub struct TodoItem {
  text : String
  completed : Bool
} derive(ToJson, FromJson, Debug)

///|
pub impl Show for TodoItem with output(self, logger) {
  logger.write_string("{text: \"\{self.text}\", completed: \{self.completed}}")
}

///|
/// The status of a command execution.
pub enum CommandExecutionStatus {
  InProgress
  Completed
  Failed
  Declined
} derive(Debug)

///|
pub impl Show for CommandExecutionStatus with output(status, logger) {
  match status {
    InProgress => logger.write_string("InProgress")
    Completed => logger.write_string("Completed")
    Failed => logger.write_string("Failed")
    Declined => logger.write_string("Declined")
  }
}

///|
pub impl ToJson for CommandExecutionStatus with to_json(status) {
  match status {
    Completed => "completed"
    InProgress => "in_progress"
    Failed => "failed"
    Declined => "declined"
  }
}

///|
pub impl @json.FromJson for CommandExecutionStatus with from_json(value, path) {
  match value {
    String("completed") => Completed
    String("in_progress") => InProgress
    String("failed") => Failed
    String("declined") => Declined
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'completed', 'in_progress', 'failed', or 'declined' for CommandExecutionStatus. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// The status of a collab tool call.
pub enum CollabToolCallStatus {
  InProgress
  Completed
  Failed
} derive(Debug)

///|
pub impl Show for CollabToolCallStatus with output(status, logger) {
  match status {
    InProgress => logger.write_string("InProgress")
    Completed => logger.write_string("Completed")
    Failed => logger.write_string("Failed")
  }
}

///|
pub impl ToJson for CollabToolCallStatus with to_json(status) {
  match status {
    Completed => "completed"
    InProgress => "in_progress"
    Failed => "failed"
  }
}

///|
pub impl @json.FromJson for CollabToolCallStatus with from_json(value, path) {
  match value {
    String("completed") => Completed
    String("in_progress") => InProgress
    String("failed") => Failed
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'completed', 'in_progress', or 'failed' for CollabToolCallStatus. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// Supported collab tools.
pub enum CollabTool {
  SpawnAgent
  SendInput
  ResumeAgent
  Wait
  CloseAgent
} derive(Debug)

///|
pub impl Show for CollabTool with output(tool, logger) {
  match tool {
    SpawnAgent => logger.write_string("SpawnAgent")
    SendInput => logger.write_string("SendInput")
    ResumeAgent => logger.write_string("ResumeAgent")
    Wait => logger.write_string("Wait")
    CloseAgent => logger.write_string("CloseAgent")
  }
}

///|
pub impl ToJson for CollabTool with to_json(tool) {
  match tool {
    SpawnAgent => "spawn_agent"
    SendInput => "send_input"
    ResumeAgent => "resume_agent"
    Wait => "wait"
    CloseAgent => "close_agent"
  }
}

///|
pub impl @json.FromJson for CollabTool with from_json(value, path) {
  match value {
    String("spawn_agent") => SpawnAgent
    String("send_input") => SendInput
    String("resume_agent") => ResumeAgent
    String("wait") => Wait
    String("close_agent") => CloseAgent
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'spawn_agent', 'send_input', 'resume_agent', 'wait', or 'close_agent' for CollabTool. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// The status of a collab agent.
pub enum CollabAgentStatus {
  PendingInit
  Running
  Interrupted
  Completed
  Errored
  Shutdown
  NotFound
} derive(Debug)

///|
pub impl Show for CollabAgentStatus with output(status, logger) {
  match status {
    PendingInit => logger.write_string("PendingInit")
    Running => logger.write_string("Running")
    Interrupted => logger.write_string("Interrupted")
    Completed => logger.write_string("Completed")
    Errored => logger.write_string("Errored")
    Shutdown => logger.write_string("Shutdown")
    NotFound => logger.write_string("NotFound")
  }
}

///|
pub impl ToJson for CollabAgentStatus with to_json(status) {
  match status {
    PendingInit => "pending_init"
    Running => "running"
    Interrupted => "interrupted"
    Completed => "completed"
    Errored => "errored"
    Shutdown => "shutdown"
    NotFound => "not_found"
  }
}

///|
pub impl @json.FromJson for CollabAgentStatus with from_json(value, path) {
  match value {
    String("pending_init") => PendingInit
    String("running") => Running
    String("interrupted") => Interrupted
    String("completed") => Completed
    String("errored") => Errored
    String("shutdown") => Shutdown
    String("not_found") => NotFound
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'pending_init', 'running', 'interrupted', 'completed', 'errored', 'shutdown', or 'not_found' for CollabAgentStatus. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// Last known state of a collab agent.
pub struct CollabAgentState {
  status : CollabAgentStatus
  message : String?
} derive(Debug)

///|
pub impl ToJson for CollabAgentState with to_json(state) {
  let obj : Map[String, Json] = { "status": state.status }
  if state.message is Some(message) {
    obj.set("message", message.to_json())
  }
  Json::object(obj)
}

///|
pub impl @json.FromJson for CollabAgentState with from_json(value, path) {
  guard value is Object({ "status": status, "message"? : message, .. }) else {
    raise JsonDecodeError((path, "expected CollabAgentState"))
  }
  let message = match message {
    Some(String(message)) => Some(message)
    Some(Null) | None => None
    v =>
      raise JsonDecodeError(
        (
          path.add_key("message"),
          "expected string or null for CollabAgentState.message. Got: \{@debug.to_repr(v)}",
        ),
      )
  }
  { status: @json.from_json(status, path=path.add_key("status")), message }
}

///|
/// Indicates the type of the file change.
pub enum PatchChangeKind {
  Add
  Delete
  Update
} derive(Debug)

///|
pub impl Show for PatchChangeKind with output(kind, logger) {
  match kind {
    Add => logger.write_string("Add")
    Delete => logger.write_string("Delete")
    Update => logger.write_string("Update")
  }
}

///|
pub impl ToJson for PatchChangeKind with to_json(kind) {
  match kind {
    Add => "add"
    Delete => "delete"
    Update => "update"
  }
}

///|
pub impl @json.FromJson for PatchChangeKind with from_json(value, path) {
  match value {
    String("add") => Add
    String("delete") => Delete
    String("update") => Update
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'add', 'delete', or 'update' for PatchChangeKind. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// The status of a file change.
pub enum PatchApplyStatus {
  InProgress
  Completed
  Failed
} derive(Debug)

///|
pub impl Show for PatchApplyStatus with output(status, logger) {
  match status {
    InProgress => logger.write_string("InProgress")
    Completed => logger.write_string("Completed")
    Failed => logger.write_string("Failed")
  }
}

///|
pub impl ToJson for PatchApplyStatus with to_json(status) {
  match status {
    InProgress => "in_progress"
    Completed => "completed"
    Failed => "failed"
  }
}

///|
pub impl @json.FromJson for PatchApplyStatus with from_json(value, path) {
  match value {
    String("in_progress") => InProgress
    String("completed") => Completed
    String("failed") => Failed
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'in_progress', 'completed', or 'failed' for PatchApplyStatus. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
/// The status of an MCP tool call.
pub enum McpToolCallStatus {
  InProgress
  Completed
  Failed
} derive(Debug)

///|
pub impl Show for McpToolCallStatus with output(status, logger) {
  match status {
    InProgress => logger.write_string("InProgress")
    Completed => logger.write_string("Completed")
    Failed => logger.write_string("Failed")
  }
}

///|
pub impl ToJson for McpToolCallStatus with to_json(status) {
  match status {
    Completed => "completed"
    InProgress => "in_progress"
    Failed => "failed"
  }
}

///|
pub impl @json.FromJson for McpToolCallStatus with from_json(value, path) {
  match value {
    String("completed") => Completed
    String("in_progress") => InProgress
    String("failed") => Failed
    _ =>
      raise JsonDecodeError(
        (
          path,
          "expected string 'completed', 'in_progress', or 'failed' for McpToolCallStatus. Got \{@debug.to_repr(value)}",
        ),
      )
  }
}

///|
pub struct McpToolCallResult {
  content : Array[Json]
  structured_content : Json
} derive(Debug)

///|
pub impl ToJson for McpToolCallResult with to_json(result) {
  { "content": result.content, "structured_content": result.structured_content }
}

///|
pub impl FromJson for McpToolCallResult with from_json(value, path) {
  guard value
    is {
      "content": Array(content),
      "structured_content": structured_content,
      ..
    } else {
    raise JsonDecodeError(
      (
        path,
        "expected McpToolCallResult object with content and structured_content. Got \{@debug.to_repr(value)}",
      ),
    )
  }
  { content, structured_content }
}
