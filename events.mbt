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
pub enum Event {
  /// Emitted when a new thread is started as the first event.
  ThreadStarted(thread_id~ : String)
  /// Emitted when a turn is started by sending a new prompt to the model.
  /// A turn encompasses all events that happen while the agent is processing the prompt.
  TurnStarted
  /// Emitted when a turn is completed. Typically right after the assistant's response.
  TurnCompleted(Usage)
  /// Indicates that a turn failed with an error.
  TurnFailed(ThreadError)
  /// Emitted when a new item is added to the thread. Typically the item is initially "in progress".
  ItemStarted(ThreadItem)
  /// Emitted when an item is updated.
  ItemUpdated(ThreadItem)
  /// Signals that an item has reached a terminal state—either success or failure.
  ItemCompleted(ThreadItem)
  /// Represents an unrecoverable error emitted directly by the event stream.
  ThreadErrorEvent(String)
}

///|
pub impl ToJson for Event with fn to_json(event) {
  match event {
    ThreadStarted(thread_id~) =>
      { "type": "thread.started", "thread_id": thread_id }
    TurnStarted => { "type": "turn.started" }
    TurnCompleted(usage) =>
      { "type": "turn.completed", "usage": usage.to_json() }
    TurnFailed(error) => { "type": "turn.failed", "error": error.to_json() }
    ItemStarted(item) => { "type": "item.started", "item": item.to_json() }
    ItemUpdated(item) => { "type": "item.updated", "item": item.to_json() }
    ItemCompleted(item) => { "type": "item.completed", "item": item.to_json() }
    ThreadErrorEvent(message) => { "type": "error", "message": message }
  }
}

///|
pub impl @json.FromJson for Event with fn from_json(value, path) {
  guard value is Object({ "type": String(ty), .. } as obj) else {
    raise JsonDecodeError(
      (
        path,
        "expected object containing 'type' field for Event, got \{@debug.to_repr(value)}",
      ),
    )
  }
  match ty {
    "thread.started" => {
      guard obj is { "thread_id": String(thread_id), .. } else {
        raise JsonDecodeError(
          (path, "expected ThreadStarted event, got \{@debug.to_repr(obj)}"),
        )
      }
      ThreadStarted(thread_id~)
    }
    "turn.started" => TurnStarted
    "turn.completed" => {
      guard obj is { "usage": usage_json, .. } else {
        raise JsonDecodeError(
          (path, "expected TurnCompleted event, got \{@debug.to_repr(obj)}"),
        )
      }
      let usage = @json.FromJson::from_json(usage_json, path.add_key("usage")) catch {
        error => raise JsonDecodeError((path, "error parsing usage: \{error}"))
      }
      TurnCompleted(usage)
    }
    "turn.failed" => {
      guard obj is { "error": error_json, .. } else {
        raise JsonDecodeError(
          (path, "expected TurnFailed event, got \{@debug.to_repr(obj)}"),
        )
      }
      let error = @json.FromJson::from_json(error_json, path.add_key("error")) catch {
        error => raise JsonDecodeError((path, "error parsing error: \{error}"))
      }
      TurnFailed(error)
    }
    "item.started" | "item.updated" | "item.completed" => {
      guard obj is { "item": item_json, .. } else {
        raise JsonDecodeError(
          (path, "expected Item event, got \{@debug.to_repr(obj)}"),
        )
      }
      let item = @json.FromJson::from_json(item_json, path.add_key("item")) catch {
        error => raise JsonDecodeError((path, "error parsing item: \{error}"))
      }
      match ty {
        "item.started" => ItemStarted(item)
        "item.updated" => ItemUpdated(item)
        "item.completed" => ItemCompleted(item)
        _ => raise JsonDecodeError((path, "unreachable"))
      }
    }
    "error" => {
      guard obj is { "message": String(message), .. } else {
        raise JsonDecodeError(
          (path, "expected ThreadErrorEvent, got \{@debug.to_repr(obj)}"),
        )
      }
      ThreadErrorEvent(message)
    }
    _ => raise JsonDecodeError((path, "expected Event"))
  }
}

///|
/// Describes the usage of tokens during a turn.
pub struct Usage {
  /// The number of input tokens used during the turn
  input_tokens : Int
  /// The number of cached input tokens used during the turn
  cached_input_tokens : Int
  /// The number of input tokens written to the prompt cache during the turn.
  /// Older Codex versions omit this field; omitted values decode as zero.
  cache_write_input_tokens : Int
  /// The number of output tokens used during the turn
  output_tokens : Int
  /// The number of reasoning output tokens used during the turn
  reasoning_output_tokens : Int
} derive(Debug)

///|
pub impl ToJson for Usage with fn to_json(usage) {
  {
    "input_tokens": usage.input_tokens,
    "cached_input_tokens": usage.cached_input_tokens,
    "cache_write_input_tokens": usage.cache_write_input_tokens,
    "output_tokens": usage.output_tokens,
    "reasoning_output_tokens": usage.reasoning_output_tokens,
  }
}

///|
pub impl FromJson for Usage with fn from_json(value, path) {
  guard value
    is {
      "input_tokens": Number(input_tokens, ..),
      "cached_input_tokens": Number(cached_input_tokens, ..),
      "cache_write_input_tokens"? : cache_write_input_tokens,
      "output_tokens": Number(output_tokens, ..),
      "reasoning_output_tokens": Number(reasoning_output_tokens, ..),
      ..
    } else {
    raise JsonDecodeError((path, "expected token usage"))
  }
  let cache_write_input_tokens = match cache_write_input_tokens {
    Some(Number(value, ..)) => value.to_int()
    Some(Null) | None => 0
    _ =>
      raise JsonDecodeError(
        (
          path.add_key("cache_write_input_tokens"),
          "expected integer token count",
        ),
      )
  }
  {
    input_tokens: input_tokens.to_int(),
    cached_input_tokens: cached_input_tokens.to_int(),
    cache_write_input_tokens,
    output_tokens: output_tokens.to_int(),
    reasoning_output_tokens: reasoning_output_tokens.to_int(),
  }
}

///|
pub struct ThreadError {
  message : String
} derive(ToJson, FromJson)
