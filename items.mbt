// Copyright 2025 International Digital Economy Academy
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
    status~ : McpToolCallStatus
  )
  /// Captures a web search request. Completes when results are returned to the agent.
  WebSearchItem(id~ : String, query~ : String)
  /// Tracks the agent's running to-do list. Starts when the plan is issued, updates as steps change, and completes when the turn ends.
  TodoListItem(id~ : String, items~ : Array[TodoItem])
  /// Describes a non-fatal error surfaced as an item.
  ErrorItem(id~ : String, message~ : String)
}

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
    McpToolCallItem(id~, server~, tool~, status~) =>
      {
        "type": "mcp_tool_call",
        "id": id,
        "server": server,
        "tool": tool,
        "status": status,
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
    raise @json.JsonDecodeError((path, "expected ThreadItem"))
  }
  match ty {
    "agent_message" => {
      guard obj is { "id": String(id), "text": String(text), .. } else {
        raise @json.JsonDecodeError((path, "expected AgentMessageItem"))
      }
      AgentMessageItem(id~, text~)
    }
    "reasoning" => {
      guard obj is { "id": String(id), "text": String(text), .. } else {
        raise @json.JsonDecodeError((path, "expected ReasoningItem"))
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
        raise @json.JsonDecodeError(
          (path, "expected CommandExecutionItem, got \{obj}"),
        )
      }
      let exit_code = match exit_code {
        Some(Number(n, ..)) => Some(n.to_int())
        None => None
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("exit_code"),
              "expected integer or null for CommandExecutionItem.exit_code",
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
        raise @json.JsonDecodeError((path, "expected FileChangeItem"))
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
          ..
        } else {
        raise @json.JsonDecodeError((path, "expected McpToolCallItem"))
      }
      McpToolCallItem(
        id~,
        server~,
        tool~,
        status=@json.from_json(status, path=path.add_key("status")),
      )
    }
    "web_search" => {
      guard obj is { "id": String(id), "query": String(query), .. } else {
        raise @json.JsonDecodeError((path, "expected WebSearchItem"))
      }
      WebSearchItem(id~, query~)
    }
    "todo_list" => {
      guard obj is { "id": String(id), "items": items, .. } else {
        raise @json.JsonDecodeError((path, "expected TodoListItem"))
      }
      TodoListItem(
        id~,
        items=@json.from_json(items, path=path.add_key("items")),
      )
    }
    "error" => {
      guard obj is { "id": String(id), "message": String(message), .. } else {
        raise @json.JsonDecodeError((path, "expected  ErrorItem"))
      }
      ErrorItem(id~, message~)
    }
    _ => raise @json.JsonDecodeError((path, "unknown ThreadItem type: \{ty}"))
  }
}

///|
/// A set of file changes by the agent.
pub struct FileUpdateChange {
  path : String
  kind : PatchChangeKind
} derive(ToJson, @json.FromJson, Show)

///|
/// An item in the agent's to-do list.
pub struct TodoItem {
  text : String
  completed : Bool
} derive(ToJson, @json.FromJson, Show)

///|
/// The status of a command execution.
pub enum CommandExecutionStatus {
  InProgress
  Completed
  Failed
} derive(Show)

///|
pub impl ToJson for CommandExecutionStatus with to_json(status) {
  match status {
    Completed => "completed"
    InProgress => "in_progress"
    Failed => "failed"
  }
}

///|
pub impl @json.FromJson for CommandExecutionStatus with from_json(value, path) {
  match value {
    String("completed") => Completed
    String("in_progress") => InProgress
    String("failed") => Failed
    _ =>
      raise @json.JsonDecodeError(
        (
          path,
          "expected string 'completed', 'in_progress', or 'failed' for CommandExecutionStatus. Got \{value}",
        ),
      )
  }
}

///|
/// Indicates the type of the file change.
pub enum PatchChangeKind {
  Add
  Delete
  Update
} derive(Show)

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
      raise @json.JsonDecodeError(
        (
          path,
          "expected string 'add', 'delete', or 'update' for PatchChangeKind. Got \{value}",
        ),
      )
  }
}

///|
/// The status of a file change.
pub enum PatchApplyStatus {
  Completed
  Failed
} derive(Show)

///|
pub impl ToJson for PatchApplyStatus with to_json(status) {
  match status {
    Completed => "completed"
    Failed => "failed"
  }
}

///|
pub impl @json.FromJson for PatchApplyStatus with from_json(value, path) {
  match value {
    String("completed") => Completed
    String("failed") => Failed
    _ =>
      raise @json.JsonDecodeError(
        (
          path,
          "expected string 'completed' or 'failed' for PatchApplyStatus. Got \{value}",
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
} derive(Show)

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
      raise @json.JsonDecodeError(
        (
          path,
          "expected string 'completed', 'in_progress', or 'failed' for McpToolCallStatus. Got \{value}",
        ),
      )
  }
}
