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
pub type AppServerRequestHandler = async (AppServerRequest) -> AppServerResponse

///|
/// Run a scoped Codex app-server runtime.
///
/// The runtime is the ergonomic app-server layer. It owns the shared
/// notification stream, routes turn-scoped events into per-turn streams, and
/// routes server-initiated requests to turn-scoped handlers before falling back
/// to the optional connection-level request handler.
pub async fn[R] Codex::with_app_server_runtime(
  self : Codex,
  options? : AppServerOptions = AppServerOptions::default(),
  request_handler? : AppServerRequestHandler,
  body : async (CodexAppServerRuntime) -> R,
) -> R {
  @async.with_task_group(tg => {
    let connection = self.spawn_app_server(tg, options~)
    defer connection.close()
    let _ = connection.initialize(options.initialize_params())
    connection.initialized()
    let runtime = CodexAppServerRuntime::new(connection)
    tg.spawn_bg(() => runtime.pump_events())
    tg.spawn_bg(() => runtime.serve_requests(request_handler))
    body(runtime)
  })
}

///|
pub struct CodexAppServerRuntime {
  priv connection : CodexAppConnection
  priv global_events : @async.Queue[AppServerEvent]
  priv mut turn_streams : Array[AppRegisteredTurnStream]
  priv mut next_stream_id : Int
}

///|
fn CodexAppServerRuntime::new(
  connection : CodexAppConnection,
) -> CodexAppServerRuntime {
  {
    connection,
    global_events: @async.Queue::new(kind=Unbounded),
    turn_streams: [],
    next_stream_id: 1,
  }
}

///|
priv struct AppRegisteredTurnStream {
  stream_id : Int
  thread_id : String
  mut turn_id : String?
  events : @async.Queue[AppServerEvent]
  request_handler : AppServerRequestHandler?
}

///|
pub struct CodexAppRuntimeThread {
  thread : AppThread
  model : String
  model_provider : String
  service_tier : String?
  cwd : String
  instruction_sources : ArrayView[String]
  approval_policy : AppApprovalPolicy
  approvals_reviewer : AppApprovalsReviewer
  sandbox : AppSandboxPolicy
  reasoning_effort : AppReasoningEffort?
  priv runtime : CodexAppServerRuntime
}

///|
pub struct AppTurnStartOptions {
  cwd : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox_policy : AppSandboxPolicy?
  model : String?
  service_tier : AppNullableString?
  effort : AppReasoningEffort?
  summary : AppReasoningSummary?
  personality : AppPersonality?
  output_schema : Json?
} derive(Default, Debug)

///|
pub fn AppTurnStartOptions::new(
  cwd? : String,
  approval_policy? : AppApprovalPolicy,
  approvals_reviewer? : AppApprovalsReviewer,
  sandbox_policy? : AppSandboxPolicy,
  model? : String,
  service_tier? : AppNullableString,
  effort? : AppReasoningEffort,
  summary? : AppReasoningSummary,
  personality? : AppPersonality,
  output_schema? : Json,
) -> AppTurnStartOptions {
  {
    cwd,
    approval_policy,
    approvals_reviewer,
    sandbox_policy,
    model,
    service_tier,
    effort,
    summary,
    personality,
    output_schema,
  }
}

///|
fn AppTurnStartOptions::params(
  self : AppTurnStartOptions,
  thread_id : String,
  input : Array[AppUserInput],
) -> AppTurnStartParams {
  {
    thread_id,
    input,
    cwd: self.cwd,
    approval_policy: self.approval_policy,
    approvals_reviewer: self.approvals_reviewer,
    sandbox_policy: self.sandbox_policy,
    model: self.model,
    service_tier: self.service_tier,
    effort: self.effort,
    summary: self.summary,
    personality: self.personality,
    output_schema: self.output_schema,
  }
}

///|
pub struct AppTurnStream {
  thread_id : String
  turn_id : String
  priv runtime : CodexAppServerRuntime
  priv stream_id : Int
  priv events : @async.Queue[AppServerEvent]
}

///|
/// Start a turn and return a turn-scoped event stream.
///
/// The runtime registers the stream before sending `turn/start`, so early
/// notifications cannot be lost while the RPC response is still in flight.
async fn CodexAppServerRuntime::start_turn_stream(
  self : CodexAppServerRuntime,
  params : AppTurnStartParams,
  request_handler? : AppServerRequestHandler,
) -> AppTurnStream raise Error {
  let events : @async.Queue[AppServerEvent] = @async.Queue::new(kind=Unbounded)
  let stream_id = self.register_pending_turn_stream(
    params.thread_id,
    events,
    request_handler,
  )
  let response = self.connection.turn_start(params) catch {
    e => {
      self.close_turn_stream_by_id(stream_id, true)
      raise @error.reraise(e)
    }
  }
  self.bind_turn_stream(stream_id, response.turn.id)
  {
    thread_id: params.thread_id,
    turn_id: response.turn.id,
    runtime: self,
    stream_id,
    events,
  }
}

///|
/// Receive the next event for this turn.
pub async fn AppTurnStream::next(self : AppTurnStream) -> AppServerEvent? {
  let event = self.events.get() catch { _ => return None }
  Some(event)
}

///|
/// Close this client-side turn stream without interrupting the server-side turn.
pub fn AppTurnStream::close(self : AppTurnStream) -> Unit {
  self.runtime.close_turn_stream(self)
}

///|
/// Interrupt the server-side turn and close this client-side stream.
pub async fn AppTurnStream::interrupt(self : AppTurnStream) -> Unit {
  self.runtime.turn_interrupt(
    AppTurnInterruptParams::new(self.thread_id, self.turn_id),
  )
  self.close()
}

///|
/// Receive the next non-turn or unregistered app-server event.
pub async fn CodexAppServerRuntime::next_global_event(
  self : CodexAppServerRuntime,
) -> AppServerEvent? {
  let event = self.global_events.get() catch { _ => return None }
  Some(event)
}

///|
/// Close a turn stream registration without interrupting the server-side turn.
fn CodexAppServerRuntime::close_turn_stream(
  self : CodexAppServerRuntime,
  stream : AppTurnStream,
) -> Unit {
  self.close_turn_stream_by_id(stream.stream_id, false)
}

///|
pub async fn CodexAppServerRuntime::start_thread(
  self : CodexAppServerRuntime,
  params? : AppThreadStartParams,
) -> CodexAppRuntimeThread {
  self.thread_start(params?).runtime_thread(self)
}

///|
pub async fn CodexAppServerRuntime::resume_thread(
  self : CodexAppServerRuntime,
  params : AppThreadResumeParams,
) -> CodexAppRuntimeThread {
  self.connection.thread_resume(params).runtime_thread(self)
}

///|
pub fn CodexAppRuntimeThread::id(self : CodexAppRuntimeThread) -> String {
  self.thread.id
}

///|
pub async fn CodexAppRuntimeThread::read(
  self : CodexAppRuntimeThread,
  include_turns? : Bool = false,
) -> AppThreadReadResponse {
  self.runtime.thread_read(
    AppThreadReadParams::new(self.thread.id, include_turns),
  )
}

///|
pub async fn CodexAppRuntimeThread::start_turn(
  self : CodexAppRuntimeThread,
  input : Array[AppUserInput],
  options? : AppTurnStartOptions = AppTurnStartOptions::default(),
) -> AppTurnStartResponse {
  self.runtime.turn_start(options.params(self.thread.id, input))
}

///|
/// Start a streamed turn using app-server method naming.
///
/// Prefer `run_streamed` for application code that is organized around thread
/// handles rather than JSON-RPC method names.
pub async fn CodexAppRuntimeThread::start_turn_stream(
  self : CodexAppRuntimeThread,
  input : Array[AppUserInput],
  options? : AppTurnStartOptions = AppTurnStartOptions::default(),
  request_handler? : AppServerRequestHandler,
) -> AppTurnStream raise Error {
  self.runtime.start_turn_stream(
    options.params(self.thread.id, input),
    request_handler?,
  )
}

///|
/// Start a turn on this thread and return a turn-scoped event stream.
pub async fn CodexAppRuntimeThread::run_streamed(
  self : CodexAppRuntimeThread,
  input : Array[AppUserInput],
  options? : AppTurnStartOptions = AppTurnStartOptions::default(),
  request_handler? : AppServerRequestHandler,
) -> AppTurnStream raise Error {
  self.runtime.start_turn_stream(
    options.params(self.thread.id, input),
    request_handler?,
  )
}

///|
pub async fn CodexAppServerRuntime::thread_list(
  self : CodexAppServerRuntime,
  params? : AppThreadListParams,
) -> AppThreadListResponse {
  self.connection.thread_list(params?)
}

///|
pub async fn CodexAppServerRuntime::thread_start(
  self : CodexAppServerRuntime,
  params? : AppThreadStartParams,
) -> AppThreadStartResponse {
  self.connection.thread_start(params?)
}

///|
pub async fn CodexAppServerRuntime::thread_read(
  self : CodexAppServerRuntime,
  params : AppThreadReadParams,
) -> AppThreadReadResponse {
  self.connection.thread_read(params)
}

///|
pub async fn CodexAppServerRuntime::turn_start(
  self : CodexAppServerRuntime,
  params : AppTurnStartParams,
) -> AppTurnStartResponse {
  self.connection.turn_start(params)
}

///|
pub async fn CodexAppServerRuntime::turn_interrupt(
  self : CodexAppServerRuntime,
  params : AppTurnInterruptParams,
) -> Unit {
  self.connection.turn_interrupt(params)
}

///|
pub async fn CodexAppServerRuntime::model_list(
  self : CodexAppServerRuntime,
  params? : AppModelListParams,
) -> AppModelListResponse {
  self.connection.model_list(params?)
}

///|
fn AppThreadStartResponse::runtime_thread(
  self : AppThreadStartResponse,
  runtime : CodexAppServerRuntime,
) -> CodexAppRuntimeThread {
  {
    thread: self.thread,
    model: self.model,
    model_provider: self.model_provider,
    service_tier: self.service_tier,
    cwd: self.cwd,
    instruction_sources: self.instruction_sources,
    approval_policy: self.approval_policy,
    approvals_reviewer: self.approvals_reviewer,
    sandbox: self.sandbox,
    reasoning_effort: self.reasoning_effort,
    runtime,
  }
}

///|
fn AppThreadResumeResponse::runtime_thread(
  self : AppThreadResumeResponse,
  runtime : CodexAppServerRuntime,
) -> CodexAppRuntimeThread {
  {
    thread: self.thread,
    model: self.model,
    model_provider: self.model_provider,
    service_tier: self.service_tier,
    cwd: self.cwd,
    instruction_sources: self.instruction_sources,
    approval_policy: self.approval_policy,
    approvals_reviewer: self.approvals_reviewer,
    sandbox: self.sandbox,
    reasoning_effort: self.reasoning_effort,
    runtime,
  }
}

///|
async fn CodexAppServerRuntime::pump_events(
  self : CodexAppServerRuntime,
) -> Unit {
  while self.connection.next_event() is Some(event) {
    if self.dispatch_turn_event(event) {
      ()
    } else {
      self.global_events.put(event)
    }
  }
  self.close_all_turn_streams()
  self.global_events.close(clear=false)
}

///|
async fn CodexAppServerRuntime::serve_requests(
  self : CodexAppServerRuntime,
  request_handler : AppServerRequestHandler?,
) -> Unit {
  while self.connection.next_request() is Some(request) {
    self.handle_runtime_request(request, request_handler)
  }
}

///|
async fn CodexAppServerRuntime::handle_runtime_request(
  self : CodexAppServerRuntime,
  request : AppServerRequest,
  request_handler : AppServerRequestHandler?,
) -> Unit {
  match self.turn_request_handler(request) {
    Some(handler) => self.connection.handle_request(request, handler)
    None =>
      match request_handler {
        Some(handler) => self.connection.handle_request(request, handler)
        None =>
          self.connection.respond_error(request.id, {
            code: -32601,
            message: "Unhandled app-server request",
            data: None,
          })
      }
  }
}

///|
fn CodexAppServerRuntime::register_pending_turn_stream(
  self : CodexAppServerRuntime,
  thread_id : String,
  events : @async.Queue[AppServerEvent],
  request_handler : AppServerRequestHandler?,
) -> Int raise Error {
  for stream in self.turn_streams {
    if stream.thread_id == thread_id && stream.turn_id is None {
      @error.fail("turn stream already pending for thread \{thread_id}")
    }
  }
  let stream_id = self.next_stream_id
  self.next_stream_id += 1
  self.turn_streams.push({
    stream_id,
    thread_id,
    turn_id: None,
    events,
    request_handler,
  })
  stream_id
}

///|
fn CodexAppServerRuntime::bind_turn_stream(
  self : CodexAppServerRuntime,
  stream_id : Int,
  turn_id : String,
) -> Unit raise Error {
  for stream in self.turn_streams {
    if stream.stream_id == stream_id {
      match stream.turn_id {
        Some(existing) =>
          if existing != turn_id {
            @error.fail(
              "turn stream bound to \{existing}, but turn/start returned \{turn_id}",
            )
          }
        None => stream.turn_id = Some(turn_id)
      }
      return
    }
  }
  @error.fail("turn stream closed before turn/start responded")
}

///|
async fn CodexAppServerRuntime::dispatch_turn_event(
  self : CodexAppServerRuntime,
  event : AppServerEvent,
) -> Bool {
  match event.turn_stream_key() {
    Some(key) => {
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id &&
          stream.turn_id == Some(key.turn_id) {
          stream.events.put(event)
          if event.ends_turn_stream(key) {
            self.close_turn_stream_by_id(stream.stream_id, false)
          }
          return true
        }
      }
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id && stream.turn_id is None {
          stream.turn_id = Some(key.turn_id)
          stream.events.put(event)
          if event.ends_turn_stream(key) {
            self.close_turn_stream_by_id(stream.stream_id, false)
          }
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
fn CodexAppServerRuntime::turn_request_handler(
  self : CodexAppServerRuntime,
  request : AppServerRequest,
) -> AppServerRequestHandler? {
  match request.turn_stream_key() {
    Some(key) => {
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id &&
          stream.turn_id == Some(key.turn_id) {
          return stream.request_handler
        }
      }
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id && stream.turn_id is None {
          stream.turn_id = Some(key.turn_id)
          return stream.request_handler
        }
      }
      None
    }
    None => None
  }
}

///|
fn CodexAppServerRuntime::close_turn_stream_by_id(
  self : CodexAppServerRuntime,
  stream_id : Int,
  clear : Bool,
) -> Unit {
  let remaining : Array[AppRegisteredTurnStream] = []
  for stream in self.turn_streams {
    if stream.stream_id == stream_id {
      stream.events.close(clear~)
    } else {
      remaining.push(stream)
    }
  }
  self.turn_streams = remaining
}

///|
fn CodexAppServerRuntime::close_all_turn_streams(
  self : CodexAppServerRuntime,
) -> Unit {
  let streams = self.turn_streams
  self.turn_streams = []
  for stream in streams {
    stream.events.close(clear=false)
  }
}

///|
priv struct AppTurnStreamKey {
  thread_id : String
  turn_id : String
}

///|
fn AppServerRequest::turn_stream_key(
  self : AppServerRequest,
) -> AppTurnStreamKey? {
  match self.details {
    AppCommandExecutionApprovalRequest(request) =>
      Some({ thread_id: request.thread_id, turn_id: request.turn_id })
    AppFileChangeApprovalRequest(request) =>
      Some({ thread_id: request.thread_id, turn_id: request.turn_id })
    AppToolRequestUserInputRequest(request) =>
      Some({ thread_id: request.thread_id, turn_id: request.turn_id })
    AppDynamicToolCallRequest(request) =>
      Some({ thread_id: request.thread_id, turn_id: request.turn_id })
    AppPermissionsRequestApprovalRequest(request) =>
      Some({ thread_id: request.thread_id, turn_id: request.turn_id })
    AppMcpServerElicitationRequest(request) =>
      match request.turn_id {
        Some(turn_id) => Some({ thread_id: request.thread_id, turn_id })
        None => None
      }
    AppChatgptAuthTokensRefreshRequest(_) => None
  }
}

///|
fn AppServerEvent::turn_stream_key(self : AppServerEvent) -> AppTurnStreamKey? {
  match self {
    AppTurnStarted(thread_id~, turn~) => Some({ thread_id, turn_id: turn.id })
    AppTurnCompleted(thread_id~, turn~) => Some({ thread_id, turn_id: turn.id })
    AppHookStarted(thread_id~, turn_id~, ..) =>
      app_optional_turn_key(thread_id, turn_id)
    AppHookCompleted(thread_id~, turn_id~, ..) =>
      app_optional_turn_key(thread_id, turn_id)
    AppThreadGoalUpdated(thread_id~, turn_id~, ..) =>
      app_optional_turn_key(thread_id, turn_id)
    AppTurnDiffUpdated(thread_id~, turn_id~, ..) => Some({ thread_id, turn_id })
    AppTurnPlanUpdated(thread_id~, turn_id~, ..) => Some({ thread_id, turn_id })
    AppTurnError(thread_id~, turn_id~, ..) => Some({ thread_id, turn_id })
    AppItemStarted(event) =>
      Some({ thread_id: event.thread_id, turn_id: event.turn_id })
    AppItemCompleted(event) =>
      Some({ thread_id: event.thread_id, turn_id: event.turn_id })
    AppItemGuardianApprovalReviewStarted(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppItemGuardianApprovalReviewCompleted(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppRawResponseItemCompleted(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppAgentMessageDelta(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppPlanDelta(thread_id~, turn_id~, ..) => Some({ thread_id, turn_id })
    AppCommandExecutionOutputDelta(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppTerminalInteraction(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppFileChangeOutputDelta(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppFileChangePatchUpdated(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppMcpToolCallProgress(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppContextCompacted(thread_id~, turn_id~) => Some({ thread_id, turn_id })
    AppReasoningSummaryTextDelta(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppReasoningSummaryPartAdded(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppReasoningTextDelta(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppModelRerouted(thread_id~, turn_id~, ..) => Some({ thread_id, turn_id })
    AppModelVerification(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    AppThreadTokenUsageUpdated(thread_id~, turn_id~, ..) =>
      Some({ thread_id, turn_id })
    _ => None
  }
}

///|
fn app_optional_turn_key(
  thread_id : String,
  turn_id : String?,
) -> AppTurnStreamKey? {
  match turn_id {
    Some(turn_id) => Some({ thread_id, turn_id })
    None => None
  }
}

///|
fn AppServerEvent::ends_turn_stream(
  self : AppServerEvent,
  key : AppTurnStreamKey,
) -> Bool {
  match self {
    AppTurnCompleted(thread_id~, turn~) =>
      thread_id == key.thread_id && turn.id == key.turn_id
    AppTurnError(thread_id~, turn_id~, ..) =>
      thread_id == key.thread_id && turn_id == key.turn_id
    _ => false
  }
}
