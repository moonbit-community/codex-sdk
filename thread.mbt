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
pub typealias Turn as RunResult

///|
/// The result of the `run_streamed` method.
pub struct StreamedTurn {
  /// An async iterator of events produced during the turn
  events : @generator.AsyncGenerator[Event]
}

///|
/// Alias for `StreamedTurn` to describe the result of `run_streamed()`.
pub typealias StreamedTurn as RunStreamedResult

///|
/// An input to send to the agent.
pub typealias String as Input

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
///
/// # Returns
/// A StreamedTurn containing an async iterator of events
pub async fn Thread::run_streamed(
  self : Thread,
  input : String,
  turn_options? : TurnOptions = TurnOptions::{ output_schema: None },
) -> StreamedTurn {
  { events: self.run_streamed_internal(input, turn_options) }
}

///|
/// Internal implementation of run_streamed that returns the event iterator directly.
async fn Thread::run_streamed_internal(
  self : Thread,
  input : String,
  turn_options : TurnOptions,
) -> @generator.AsyncGenerator[Event] {
  let schema_file = if turn_options.output_schema is Some(schema) &&
    !(schema is Null) {
    Some(create_output_schema_file(schema))
  } else {
    None
  }
  let options = self.thread_options
  let generator = self.exec.run({
    input,
    base_url: self.options.base_url,
    api_key: self.options.api_key,
    thread_id: self.id,
    model: options.model,
    sandbox_mode: options.sandbox_mode,
    working_directory: options.working_directory,
    skip_git_repo_check: options.skip_git_repo_check,
    output_schema_file: if schema_file is Some(sf) {
      Some(sf.schema_path)
    } else {
      None
    },
  })
  @generator.AsyncGenerator::new(async fn(yield_) {
    try {
      while generator.next() is Some(item) {
        let event = @json.from_json(@json.parse(item)) catch {
          error => fail("Failed to parse item: \{item}, error: \{error}")
        }
        if event is ThreadStarted(thread_id~) {
          self.id = Some(thread_id)
        }
        yield_(event)
      }
      if schema_file is Some(sf) {
        (sf.cleanup)()
      }
    } catch {
      e => {
        if schema_file is Some(sf) {
          (sf.cleanup)()
        }
        while generator.throws(e) is Some(_) {
          // Drain remaining items to avoid unhandled promise rejection
        }
      }
    }
  })
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
  input : String,
  turn_options? : TurnOptions = TurnOptions::{ output_schema: None },
) -> Turn raise Error {
  let generator = self.run_streamed_internal(input, turn_options)
  let items : Array[ThreadItem] = []
  let mut final_response = ""
  let mut usage : Usage? = None
  let mut turn_failure : ThreadError? = None
  while generator.next() is Some(event) {
    match event {
      ItemCompleted(item) => {
        if item is AgentMessageItem(text~, ..) {
          final_response = text
        }
        items.push(item)
      }
      TurnCompleted(u) => usage = Some(u)
      TurnFailed(error) => {
        turn_failure = Some(error)
        while generator.returns() is Some(_) {
          // Drain remaining items to avoid unhandled promise rejection
        }
        break
      }
      _ => ()
    }
  }
  if turn_failure is Some(error) {
    fail(error.message)
  }
  { items, final_response, usage }
}
