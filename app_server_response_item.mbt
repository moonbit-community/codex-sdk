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
pub(all) enum AppResponseItem {
  AppResponseMessage(
    role~ : String,
    content~ : ArrayView[AppResponseContentItem],
    phase~ : AppResponseMessagePhase?
  )
  AppResponseReasoning(
    summary~ : ArrayView[AppResponseReasoningSummary],
    content~ : ArrayView[AppResponseReasoningContent]?,
    encrypted_content~ : String?
  )
  AppResponseLocalShellCall(
    call_id~ : String?,
    status~ : AppResponseLocalShellStatus,
    action~ : AppResponseLocalShellAction
  )
  AppResponseFunctionCall(
    name~ : String,
    tool_namespace~ : String?,
    arguments~ : String,
    call_id~ : String
  )
  AppResponseToolSearchCall(
    call_id~ : String?,
    status~ : String?,
    execution~ : String,
    arguments~ : Json
  )
  AppResponseFunctionCallOutput(
    call_id~ : String,
    output~ : AppResponseFunctionCallOutputBody
  )
  AppResponseCustomToolCall(
    status~ : String?,
    call_id~ : String,
    name~ : String,
    input~ : String
  )
  AppResponseCustomToolCallOutput(
    call_id~ : String,
    name~ : String?,
    output~ : AppResponseFunctionCallOutputBody
  )
  AppResponseToolSearchOutput(
    call_id~ : String?,
    status~ : String,
    execution~ : String,
    tools~ : ArrayView[Json]
  )
  AppResponseWebSearchCall(
    status~ : String?,
    action~ : AppResponseWebSearchAction?
  )
  AppResponseImageGenerationCall(
    id~ : String,
    status~ : String,
    revised_prompt~ : String?,
    result~ : String
  )
  AppResponseCompaction(encrypted_content~ : String)
  AppResponseContextCompaction(encrypted_content~ : String?)
  AppResponseOther
} derive(Debug)

///|
pub impl FromJson for AppResponseItem with fn from_json(value, path) {
  guard value is Object({ "type": String(item_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected response item"))
  }
  match item_type {
    "message" => {
      guard obj
        is { "role": String(role), "content": content, "phase"? : phase, .. } else {
        raise JsonDecodeError((path, "expected message response item"))
      }
      AppResponseMessage(
        role~,
        content=@json.from_json(content, path=path.add_key("content")),
        phase=match phase {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("phase")))
        },
      )
    }
    "reasoning" => {
      guard obj
        is {
          "summary": summary,
          "content"? : content,
          "encrypted_content"? : encrypted_content,
          ..
        } else {
        raise JsonDecodeError((path, "expected reasoning response item"))
      }
      AppResponseReasoning(
        summary=@json.from_json(summary, path=path.add_key("summary")),
        content=match content {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("content")))
        },
        encrypted_content=app_optional_string(
          encrypted_content,
          path.add_key("encrypted_content"),
        ),
      )
    }
    "local_shell_call" => {
      guard obj
        is { "call_id"? : call_id, "status": status, "action": action, .. } else {
        raise JsonDecodeError((path, "expected local shell response item"))
      }
      AppResponseLocalShellCall(
        call_id=app_optional_string(call_id, path.add_key("call_id")),
        status=@json.from_json(status, path=path.add_key("status")),
        action=@json.from_json(action, path=path.add_key("action")),
      )
    }
    "function_call" => {
      guard obj
        is {
          "name": String(name),
          "namespace"? : item_namespace,
          "arguments": String(arguments),
          "call_id": String(call_id),
          ..
        } else {
        raise JsonDecodeError((path, "expected function call response item"))
      }
      AppResponseFunctionCall(
        name~,
        tool_namespace=app_optional_string(
          item_namespace,
          path.add_key("namespace"),
        ),
        arguments~,
        call_id~,
      )
    }
    "tool_search_call" => {
      guard obj
        is {
          "call_id"? : call_id,
          "status"? : status,
          "execution": String(execution),
          "arguments": arguments,
          ..
        } else {
        raise JsonDecodeError((path, "expected tool search call response item"))
      }
      AppResponseToolSearchCall(
        call_id=app_optional_string(call_id, path.add_key("call_id")),
        status=app_optional_string(status, path.add_key("status")),
        execution~,
        arguments~,
      )
    }
    "function_call_output" => {
      guard obj is { "call_id": String(call_id), "output": output, .. } else {
        raise JsonDecodeError(
          (path, "expected function call output response item"),
        )
      }
      AppResponseFunctionCallOutput(
        call_id~,
        output=@json.from_json(output, path=path.add_key("output")),
      )
    }
    "custom_tool_call" => {
      guard obj
        is {
          "status"? : status,
          "call_id": String(call_id),
          "name": String(name),
          "input": String(input),
          ..
        } else {
        raise JsonDecodeError((path, "expected custom tool call response item"))
      }
      AppResponseCustomToolCall(
        status=app_optional_string(status, path.add_key("status")),
        call_id~,
        name~,
        input~,
      )
    }
    "custom_tool_call_output" => {
      guard obj
        is { "call_id": String(call_id), "name"? : name, "output": output, .. } else {
        raise JsonDecodeError(
          (path, "expected custom tool call output response item"),
        )
      }
      AppResponseCustomToolCallOutput(
        call_id~,
        name=app_optional_string(name, path.add_key("name")),
        output=@json.from_json(output, path=path.add_key("output")),
      )
    }
    "tool_search_output" => {
      guard obj
        is {
          "call_id"? : call_id,
          "status": String(status),
          "execution": String(execution),
          "tools": tools,
          ..
        } else {
        raise JsonDecodeError(
          (path, "expected tool search output response item"),
        )
      }
      AppResponseToolSearchOutput(
        call_id=app_optional_string(call_id, path.add_key("call_id")),
        status~,
        execution~,
        tools=@json.from_json(tools, path=path.add_key("tools")),
      )
    }
    "web_search_call" => {
      guard obj is { "status"? : status, "action"? : action, .. } else {
        raise JsonDecodeError((path, "expected web search response item"))
      }
      AppResponseWebSearchCall(
        status=app_optional_string(status, path.add_key("status")),
        action=match action {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("action")))
        },
      )
    }
    "image_generation_call" => {
      guard obj
        is {
          "id": String(id),
          "status": String(status),
          "revised_prompt"? : revised_prompt,
          "result": String(result),
          ..
        } else {
        raise JsonDecodeError(
          (path, "expected image generation call response item"),
        )
      }
      AppResponseImageGenerationCall(
        id~,
        status~,
        revised_prompt=app_optional_string(
          revised_prompt,
          path.add_key("revised_prompt"),
        ),
        result~,
      )
    }
    "compaction" | "compaction_summary" => {
      guard obj is { "encrypted_content": String(encrypted_content), .. } else {
        raise JsonDecodeError((path, "expected compaction response item"))
      }
      AppResponseCompaction(encrypted_content~)
    }
    "context_compaction" => {
      guard obj is { "encrypted_content"? : encrypted_content, .. } else {
        raise JsonDecodeError(
          (path, "expected context compaction response item"),
        )
      }
      AppResponseContextCompaction(
        encrypted_content=app_optional_string(
          encrypted_content,
          path.add_key("encrypted_content"),
        ),
      )
    }
    "other" => AppResponseOther
    _ => raise JsonDecodeError((path, "expected response item type"))
  }
}

///|
pub(all) enum AppResponseContentItem {
  AppResponseInputText(text~ : String)
  AppResponseInputImage(image_url~ : String, detail~ : AppResponseImageDetail?)
  AppResponseOutputText(text~ : String)
} derive(Debug)

///|
pub impl FromJson for AppResponseContentItem with fn from_json(value, path) {
  guard value is Object({ "type": String(content_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected response content item"))
  }
  match content_type {
    "input_text" => {
      guard obj is { "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected response input text"))
      }
      AppResponseInputText(text~)
    }
    "input_image" => {
      guard obj is { "image_url": String(image_url), "detail"? : detail, .. } else {
        raise JsonDecodeError((path, "expected response input image"))
      }
      AppResponseInputImage(
        image_url~,
        detail=match detail {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("detail")))
        },
      )
    }
    "output_text" => {
      guard obj is { "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected response output text"))
      }
      AppResponseOutputText(text~)
    }
    _ => raise JsonDecodeError((path, "expected response content item type"))
  }
}

///|
pub(all) enum AppResponseImageDetail {
  AppResponseImageAuto
  AppResponseImageLow
  AppResponseImageHigh
  AppResponseImageOriginal
} derive(Debug)

///|
pub impl FromJson for AppResponseImageDetail with fn from_json(value, path) {
  match value {
    String("auto") => AppResponseImageAuto
    String("low") => AppResponseImageLow
    String("high") => AppResponseImageHigh
    String("original") => AppResponseImageOriginal
    _ => raise JsonDecodeError((path, "expected response image detail"))
  }
}

///|
pub(all) enum AppResponseMessagePhase {
  AppResponseCommentary
  AppResponseFinalAnswer
} derive(Debug)

///|
pub impl FromJson for AppResponseMessagePhase with fn from_json(value, path) {
  match value {
    String("commentary") => AppResponseCommentary
    String("final_answer") => AppResponseFinalAnswer
    _ => raise JsonDecodeError((path, "expected response message phase"))
  }
}

///|
pub(all) struct AppResponseReasoningSummary {
  text : String
} derive(Debug)

///|
pub impl FromJson for AppResponseReasoningSummary with fn from_json(value, path) {
  guard value is { "type": String("summary_text"), "text": String(text), .. } else {
    raise JsonDecodeError((path, "expected response reasoning summary"))
  }
  { text, }
}

///|
pub(all) enum AppResponseReasoningContent {
  AppResponseReasoningText(text~ : String)
  AppResponseReasoningPlainText(text~ : String)
} derive(Debug)

///|
pub impl FromJson for AppResponseReasoningContent with fn from_json(value, path) {
  guard value is { "type": String(content_type), "text": String(text), .. } else {
    raise JsonDecodeError((path, "expected response reasoning content"))
  }
  match content_type {
    "reasoning_text" => AppResponseReasoningText(text~)
    "text" => AppResponseReasoningPlainText(text~)
    _ =>
      raise JsonDecodeError((path, "expected response reasoning content type"))
  }
}

///|
pub(all) enum AppResponseLocalShellStatus {
  AppResponseLocalShellCompleted
  AppResponseLocalShellInProgress
  AppResponseLocalShellIncomplete
} derive(Debug)

///|
pub impl FromJson for AppResponseLocalShellStatus with fn from_json(value, path) {
  match value {
    String("completed") => AppResponseLocalShellCompleted
    String("in_progress") => AppResponseLocalShellInProgress
    String("incomplete") => AppResponseLocalShellIncomplete
    _ => raise JsonDecodeError((path, "expected response local shell status"))
  }
}

///|
pub(all) struct AppResponseLocalShellAction {
  command : ArrayView[String]
  timeout_ms : UInt64?
  working_directory : String?
  env : Map[String, String]?
  user : String?
} derive(Debug)

///|
pub impl FromJson for AppResponseLocalShellAction with fn from_json(value, path) {
  guard value
    is {
      "type": String("exec"),
      "command": command,
      "timeout_ms"? : timeout_ms,
      "working_directory"? : working_directory,
      "env"? : env,
      "user"? : user,
      ..
    } else {
    raise JsonDecodeError((path, "expected response local shell action"))
  }
  {
    command: @json.from_json(command, path=path.add_key("command")),
    timeout_ms: app_optional_uint64(timeout_ms, path.add_key("timeout_ms")),
    working_directory: app_optional_string(
      working_directory,
      path.add_key("working_directory"),
    ),
    env: match env {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("env")))
    },
    user: app_optional_string(user, path.add_key("user")),
  }
}

///|
pub(all) enum AppResponseFunctionCallOutputBody {
  AppResponseFunctionOutputText(String)
  AppResponseFunctionOutputContentItems(
    ArrayView[AppResponseFunctionCallOutputContentItem]
  )
} derive(Debug)

///|
pub impl FromJson for AppResponseFunctionCallOutputBody with fn from_json(
  value,
  path,
) {
  match value {
    String(text) => AppResponseFunctionOutputText(text)
    Array(_) =>
      AppResponseFunctionOutputContentItems(@json.from_json(value, path~))
    _ => raise JsonDecodeError((path, "expected function call output body"))
  }
}

///|
pub(all) enum AppResponseFunctionCallOutputContentItem {
  AppResponseFunctionOutputInputText(text~ : String)
  AppResponseFunctionOutputInputImage(
    image_url~ : String,
    detail~ : AppResponseImageDetail?
  )
} derive(Debug)

///|
pub impl FromJson for AppResponseFunctionCallOutputContentItem with fn from_json(
  value,
  path,
) {
  guard value is Object({ "type": String(content_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected function call output content item"))
  }
  match content_type {
    "input_text" => {
      guard obj is { "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected function output input text"))
      }
      AppResponseFunctionOutputInputText(text~)
    }
    "input_image" => {
      guard obj is { "image_url": String(image_url), "detail"? : detail, .. } else {
        raise JsonDecodeError((path, "expected function output input image"))
      }
      AppResponseFunctionOutputInputImage(
        image_url~,
        detail=match detail {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("detail")))
        },
      )
    }
    _ =>
      raise JsonDecodeError(
        (path, "expected function call output content item type"),
      )
  }
}

///|
pub(all) enum AppResponseWebSearchAction {
  AppResponseWebSearchSearch(query~ : String?, queries~ : ArrayView[String]?)
  AppResponseWebSearchOpenPage(url~ : String?)
  AppResponseWebSearchFindInPage(url~ : String?, pattern~ : String?)
  AppResponseWebSearchOther
} derive(Debug)

///|
pub impl FromJson for AppResponseWebSearchAction with fn from_json(value, path) {
  guard value is Object({ "type": String(action_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected response web search action"))
  }
  match action_type {
    "search" =>
      AppResponseWebSearchSearch(
        query=match obj {
          { "query"? : query, .. } =>
            app_optional_string(query, path.add_key("query"))
        },
        queries=match obj {
          { "queries"? : Some(Null), .. } | { "queries"? : None, .. } => None
          { "queries"? : Some(queries), .. } =>
            Some(@json.from_json(queries, path=path.add_key("queries")))
        },
      )
    "open_page" =>
      AppResponseWebSearchOpenPage(
        url=match obj {
          { "url"? : url, .. } => app_optional_string(url, path.add_key("url"))
        },
      )
    "find_in_page" =>
      AppResponseWebSearchFindInPage(
        url=match obj {
          { "url"? : url, .. } => app_optional_string(url, path.add_key("url"))
        },
        pattern=match obj {
          { "pattern"? : pattern, .. } =>
            app_optional_string(pattern, path.add_key("pattern"))
        },
      )
    "other" => AppResponseWebSearchOther
    _ =>
      raise JsonDecodeError((path, "expected response web search action type"))
  }
}
