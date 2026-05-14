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
/// Completed turn.
pub struct Turn {
  /// All items produced during the turn
  items : Array[ThreadItem]
  /// The final response text from the agent
  final_response : String
  /// Token usage information, if available
  usage : Usage?
}

///|
/// Alias for `Turn` to describe the result of `run()`.
pub type RunResult = Turn

///|
/// The result of the `run_streamed` method.
#alias(RunStreamedResult)
pub struct StreamedTurn {
  /// An async iterator of events produced during the turn
  events : @generator.AsyncGenerator[Event]
}

///|
/// An input to send to the agent.
pub type Input = Array[UserInput]

///|
pub(all) enum UserInput {
  Text(String)
  LocalImage(path~ : String)
}

///|
/// Represent a thread of conversation with the agent. One thread can have multiple consecutive turns.
struct Thread {
  exec : CodexExec
  options : CodexOptions
  mut id : String?
  thread_options : ThreadOptions
}

///|
/// Returns the ID of the thread. Populated after the first turn starts.
pub fn Thread::id(self : Thread) -> String? {
  self.id
}

///|
/// Create a new Thread instance.
///
/// # Arguments
/// * `exec` - The CodexExec instance for running commands
/// * `options` - Configuration options for the Codex client
/// * `thread_options` - Options specific to this thread
/// * `id` - Optional thread ID to resume an existing thread
fn Thread::new(
  exec : CodexExec,
  options : CodexOptions,
  thread_options : ThreadOptions,
  id? : String,
) -> Thread {
  { exec, options, id, thread_options }
}

///|
/// Provides the input to the agent and streams events as they are produced during the turn.
///
/// # Arguments
/// * `input` - The user input/prompt to send to the agent
/// * `turn_options` - Options for configuring this turn
/// * `taskgroup` - The TaskGroup to run the streaming generator in
///
/// # Returns
/// A StreamedTurn containing an async iterator of events
pub async fn[G] Thread::run_streamed(
  self : Thread,
  prompt : String,
  extra_input? : Input = [],
  turn_options? : TurnOptions = { output_schema: None },
  taskgroup : @async.TaskGroup[G],
) -> StreamedTurn {
  {
    events: self.run_streamed_internal(
      prompt, extra_input, turn_options, taskgroup,
    ),
  }
}

///|
/// Internal implementation of run_streamed that returns the event iterator directly.
async fn[G] Thread::run_streamed_internal(
  self : Thread,
  prompt : String,
  input : Input,
  turn_options : TurnOptions,
  taskgroup : @async.TaskGroup[G],
) -> @generator.AsyncGenerator[Event] {
  let input = normalize_input(prompt, input)
  let generator = self.exec.run(
    {
      input: input.0,
      images: input.1,
      thread_id: self.id,
      codex_options: self.options,
      thread_options: self.thread_options,
      turn_options,
    },
    taskgroup,
  ) catch {
    e => @error.reraise(e)
  }
  @generator.AsyncGenerator::new(
    async fn(yield_) {
      try {
        while generator.next() is Some(item) {
          let event = @json.from_json(@json.parse(item)) catch {
            error =>
              @error.fail("Failed to parse item: \{item}, error: \{error}")
          }
          if event is ThreadStarted(thread_id~) {
            self.id = Some(thread_id)
          }
          yield_(event)
        }
        ignore(generator.returns())
      } catch {
        @generator.Return => ignore(generator.returns())
        e => {
          ignore(generator.returns())
          @error.reraise(e)
        }
      }
    },
    taskgroup,
  )
}

///|
/// Provides the input to the agent and returns the completed turn.
///
/// # Arguments
/// * `input` - The user input/prompt to send to the agent
/// * `turn_options` - Options for configuring this turn
///
/// # Returns
/// A Turn containing all items, the final response, and usage information
pub async fn Thread::run(
  self : Thread,
  prompt : String,
  extra_input? : Input = [],
  turn_options? : TurnOptions = { output_schema: None },
) -> Turn raise Error {
  @async.with_task_group(taskgroup => {
    let generator = self.run_streamed_internal(
      prompt, extra_input, turn_options, taskgroup,
    )
    let items : Array[ThreadItem] = []
    let mut final_response = ""
    let mut usage : Usage? = None
    while generator.next() is Some(event) {
      match event {
        ItemCompleted(item) => {
          if item is AgentMessageItem(text~, ..) {
            final_response = text
          }
          items.push(item)
        }
        TurnCompleted(u) => usage = Some(u)
        TurnFailed(error) => @error.fail(error.message)
        ThreadErrorEvent(e) => @error.fail(e)
        _ => ()
      }
    }
    ignore(generator.returns())
    { items, final_response, usage }
  })
}

///|
fn normalize_input(prompt : String, input : Input) -> (String, Array[String]) {
  let parts : Array[String] = [prompt]
  let images : Array[String] = []
  for part in input {
    match part {
      Text(text) => parts.push(text)
      LocalImage(path~) => images.push(path)
    }
  }
  (parts.join("\n\n"), images)
}
