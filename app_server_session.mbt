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
/// Run a scoped Codex app-server session.
///
/// The session is the ergonomic app-server layer. It owns the shared
/// notification stream, routes turn-scoped events into per-turn streams, and
/// routes server-initiated requests to turn-scoped handlers before falling back
/// to the optional session-level request handler.
pub async fn[R] Codex::with_app_server_session(
  self : Codex,
  options? : AppServerOptions = AppServerOptions::default(),
  request_handler? : AppServerRequestHandler,
  body : async (CodexAppSession) -> R,
) -> R {
  @async.with_task_group(tg => {
    let connection = self.spawn_app_server(tg, options~)
    defer connection.close()
    let _ = connection.initialize(options.initialize_params())
    connection.initialized()
    let session = CodexAppSession::new(connection)
    tg.spawn_bg(() => session.pump_events())
    tg.spawn_bg(() => session.serve_requests(request_handler))
    body(session)
  })
}

///|
pub struct CodexAppSession {
  priv connection : CodexAppConnection
  priv global_events : @async.Queue[AppServerEvent]
  priv mut turn_streams : Array[AppRegisteredTurnStream]
  priv mut thread_request_handlers : Array[AppRegisteredThreadRequestHandler]
  priv mut next_stream_id : Int
}

///|
fn CodexAppSession::new(connection : CodexAppConnection) -> CodexAppSession {
  {
    connection,
    global_events: @async.Queue::Queue(kind=Unbounded),
    turn_streams: [],
    thread_request_handlers: [],
    next_stream_id: 1,
  }
}

///|
priv struct AppRegisteredTurnStream {
  stream_id : Int
  thread_id : String
  mut turn_id : String?
  events : @async.Queue[AppQueuedTurnEvent]
  request_handler : AppServerRequestHandler?
}

///|
priv enum AppQueuedTurnEvent {
  AppQueuedTurnEvent(AppServerEvent)
  AppQueuedTurnClosed
}

///|
priv struct AppRegisteredThreadRequestHandler {
  thread_id : String
  request_handler : AppServerRequestHandler
}

///|
pub struct CodexAppThread {
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
  priv session : CodexAppSession
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
  priv session : CodexAppSession
  priv stream_id : Int
  priv events : @async.Queue[AppQueuedTurnEvent]
  priv mut events_closed : Bool
}

///|
/// Start a turn and return a turn-scoped event stream.
///
/// The session registers the stream before sending `turn/start`, so early
/// notifications cannot be lost while the RPC response is still in flight.
async fn CodexAppSession::run_turn_stream(
  self : CodexAppSession,
  params : AppTurnStartParams,
  request_handler? : AppServerRequestHandler,
) -> AppTurnStream raise Error {
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
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
    session: self,
    stream_id,
    events,
    events_closed: false,
  }
}

///|
/// Receive the next event for this turn.
pub async fn AppTurnStream::next(self : AppTurnStream) -> AppServerEvent? {
  if self.events_closed {
    return None
  }
  let queued = self.events.get() catch {
    _ => {
      self.events_closed = true
      return None
    }
  }
  match queued {
    AppQueuedTurnEvent(event) => Some(event)
    AppQueuedTurnClosed => {
      self.events_closed = true
      self.session.close_turn_stream_by_id(self.stream_id, false)
      None
    }
  }
}

///|
/// Close this client-side turn stream without interrupting the server-side turn.
pub fn AppTurnStream::close(self : AppTurnStream) -> Unit {
  self.session.close_turn_stream(self)
}

///|
/// Interrupt the server-side turn and close this client-side stream.
pub async fn AppTurnStream::interrupt(self : AppTurnStream) -> Unit {
  self.session.turn_interrupt(
    AppTurnInterruptParams::new(self.thread_id, self.turn_id),
  )
  self.close()
}

///|
/// Receive the next non-turn or unregistered app-server event.
pub async fn CodexAppSession::next_global_event(
  self : CodexAppSession,
) -> AppServerEvent? {
  let event = self.global_events.get() catch { _ => return None }
  Some(event)
}

///|
/// Close a turn stream registration without interrupting the server-side turn.
fn CodexAppSession::close_turn_stream(
  self : CodexAppSession,
  stream : AppTurnStream,
) -> Unit {
  self.close_turn_stream_by_id(stream.stream_id, false)
}

///|
pub async fn CodexAppSession::start_thread(
  self : CodexAppSession,
  params? : AppThreadStartParams,
  request_handler? : AppServerRequestHandler,
) -> CodexAppThread {
  self.thread_start(params?).session_thread(self, request_handler?)
}

///|
pub async fn CodexAppSession::resume_thread(
  self : CodexAppSession,
  params : AppThreadResumeParams,
  request_handler? : AppServerRequestHandler,
) -> CodexAppThread {
  self.connection.thread_resume(params).session_thread(self, request_handler?)
}

///|
pub fn CodexAppThread::id(self : CodexAppThread) -> String {
  self.thread.id
}

///|
pub async fn CodexAppThread::read(
  self : CodexAppThread,
  include_turns? : Bool = false,
) -> AppThreadReadResponse {
  self.session.thread_read(
    AppThreadReadParams::new(self.thread.id, include_turns),
  )
}

///|
/// Set or clear the thread-scoped fallback request handler.
pub fn CodexAppThread::set_request_handler(
  self : CodexAppThread,
  request_handler? : AppServerRequestHandler,
) -> Unit {
  self.session.set_thread_request_handler(self.thread.id, request_handler)
}

///|
pub async fn CodexAppThread::start_turn(
  self : CodexAppThread,
  input : Array[AppUserInput],
  options? : AppTurnStartOptions = AppTurnStartOptions::default(),
) -> AppTurnStartResponse {
  self.session.turn_start(options.params(self.thread.id, input))
}

///|
/// Start a turn on this thread and return a turn-scoped event stream.
pub async fn CodexAppThread::run_streamed(
  self : CodexAppThread,
  input : Array[AppUserInput],
  options? : AppTurnStartOptions = AppTurnStartOptions::default(),
  request_handler? : AppServerRequestHandler,
) -> AppTurnStream raise Error {
  self.session.run_turn_stream(
    options.params(self.thread.id, input),
    request_handler?,
  )
}

///|
pub async fn CodexAppSession::thread_list(
  self : CodexAppSession,
  params? : AppThreadListParams,
) -> AppThreadListResponse {
  self.connection.thread_list(params?)
}

///|
pub async fn CodexAppSession::thread_start(
  self : CodexAppSession,
  params? : AppThreadStartParams,
) -> AppThreadStartResponse {
  self.connection.thread_start(params?)
}

///|
pub async fn CodexAppSession::thread_read(
  self : CodexAppSession,
  params : AppThreadReadParams,
) -> AppThreadReadResponse {
  self.connection.thread_read(params)
}

///|
pub async fn CodexAppSession::turn_start(
  self : CodexAppSession,
  params : AppTurnStartParams,
) -> AppTurnStartResponse {
  self.connection.turn_start(params)
}

///|
pub async fn CodexAppSession::turn_interrupt(
  self : CodexAppSession,
  params : AppTurnInterruptParams,
) -> Unit {
  self.connection.turn_interrupt(params)
}

///|
pub async fn CodexAppSession::model_list(
  self : CodexAppSession,
  params? : AppModelListParams,
) -> AppModelListResponse {
  self.connection.model_list(params?)
}

///|
fn AppThreadStartResponse::session_thread(
  self : AppThreadStartResponse,
  session : CodexAppSession,
  request_handler? : AppServerRequestHandler,
) -> CodexAppThread {
  session.set_thread_request_handler(self.thread.id, request_handler)
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
    session,
  }
}

///|
fn AppThreadResumeResponse::session_thread(
  self : AppThreadResumeResponse,
  session : CodexAppSession,
  request_handler? : AppServerRequestHandler,
) -> CodexAppThread {
  session.set_thread_request_handler(self.thread.id, request_handler)
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
    session,
  }
}

///|
async fn CodexAppSession::pump_events(self : CodexAppSession) -> Unit {
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
async fn CodexAppSession::serve_requests(
  self : CodexAppSession,
  request_handler : AppServerRequestHandler?,
) -> Unit {
  while self.connection.next_request() is Some(request) {
    self.handle_session_request(request, request_handler)
  }
}

///|
async fn CodexAppSession::handle_session_request(
  self : CodexAppSession,
  request : AppServerRequest,
  request_handler : AppServerRequestHandler?,
) -> Unit {
  match self.turn_request_handler(request) {
    Some(handler) => self.connection.handle_request(request, handler)
    None =>
      match self.thread_request_handler(request) {
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
}

///|
fn CodexAppSession::set_thread_request_handler(
  self : CodexAppSession,
  thread_id : String,
  request_handler : AppServerRequestHandler?,
) -> Unit {
  let remaining : Array[AppRegisteredThreadRequestHandler] = []
  for handler in self.thread_request_handlers {
    if handler.thread_id != thread_id {
      remaining.push(handler)
    }
  }
  if request_handler is Some(handler) {
    remaining.push({ thread_id, request_handler: handler })
  }
  self.thread_request_handlers = remaining
}

///|
fn CodexAppSession::register_pending_turn_stream(
  self : CodexAppSession,
  thread_id : String,
  events : @async.Queue[AppQueuedTurnEvent],
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
fn CodexAppSession::bind_turn_stream(
  self : CodexAppSession,
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
async fn CodexAppSession::dispatch_turn_event(
  self : CodexAppSession,
  event : AppServerEvent,
) -> Bool {
  match event.turn_stream_key() {
    Some(key) => {
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id &&
          stream.turn_id == Some(key.turn_id) {
          stream.events.put(AppQueuedTurnEvent(event))
          if event.ends_turn_stream(key) {
            self.finish_turn_stream_by_id(stream.stream_id)
          }
          return true
        }
      }
      for stream in self.turn_streams {
        if stream.thread_id == key.thread_id && stream.turn_id is None {
          stream.turn_id = Some(key.turn_id)
          stream.events.put(AppQueuedTurnEvent(event))
          if event.ends_turn_stream(key) {
            stream.events.put(AppQueuedTurnClosed)
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
fn CodexAppSession::turn_request_handler(
  self : CodexAppSession,
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
fn CodexAppSession::thread_request_handler(
  self : CodexAppSession,
  request : AppServerRequest,
) -> AppServerRequestHandler? {
  match request.thread_id() {
    Some(thread_id) => {
      for handler in self.thread_request_handlers {
        if handler.thread_id == thread_id {
          return Some(handler.request_handler)
        }
      }
      None
    }
    None => None
  }
}

///|
fn CodexAppSession::close_turn_stream_by_id(
  self : CodexAppSession,
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
async fn CodexAppSession::finish_turn_stream_by_id(
  self : CodexAppSession,
  stream_id : Int,
) -> Unit {
  let remaining : Array[AppRegisteredTurnStream] = []
  for stream in self.turn_streams {
    if stream.stream_id == stream_id {
      stream.events.put(AppQueuedTurnClosed)
    } else {
      remaining.push(stream)
    }
  }
  self.turn_streams = remaining
}

///|
async fn CodexAppSession::close_all_turn_streams(
  self : CodexAppSession,
) -> Unit {
  let streams = self.turn_streams
  self.turn_streams = []
  for stream in streams {
    stream.events.put(AppQueuedTurnClosed)
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
    AppAttestationGenerateRequest(_) => None
  }
}

///|
fn AppServerRequest::thread_id(self : AppServerRequest) -> String? {
  match self.details {
    AppCommandExecutionApprovalRequest(request) => Some(request.thread_id)
    AppFileChangeApprovalRequest(request) => Some(request.thread_id)
    AppToolRequestUserInputRequest(request) => Some(request.thread_id)
    AppDynamicToolCallRequest(request) => Some(request.thread_id)
    AppPermissionsRequestApprovalRequest(request) => Some(request.thread_id)
    AppMcpServerElicitationRequest(request) => Some(request.thread_id)
    AppChatgptAuthTokensRefreshRequest(_) => None
    AppAttestationGenerateRequest(_) => None
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
    AppTurnError(thread_id~, turn_id~, will_retry~, ..) =>
      thread_id == key.thread_id && turn_id == key.turn_id && !will_retry
    _ => false
  }
}
