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
pub struct AppServerOptions {
  /// Override the path to the codex executable used for `codex app-server`.
  executable_path_override : String?
  /// Client metadata sent in the app-server `initialize` request.
  client_info : AppClientInfo?
  /// Optional client capabilities sent in the app-server `initialize` request.
  capabilities : AppInitializeCapabilities?
} derive(Default)

///|
pub fn AppServerOptions::new(
  executable_path_override? : String,
  client_info? : AppClientInfo,
  capabilities? : AppInitializeCapabilities,
) -> AppServerOptions {
  { executable_path_override, client_info, capabilities }
}

///|
fn AppServerOptions::initialize_params(
  self : AppServerOptions,
) -> AppInitializeParams {
  {
    client_info: match self.client_info {
      Some(client_info) => client_info
      None =>
        {
          name: "moonbit-codex-sdk",
          title: Some("MoonBit Codex SDK"),
          version: "0.128.0",
        }
    },
    capabilities: self.capabilities,
  }
}

///|
/// Run a scoped Codex app-server connection.
///
/// This is the app-server entry point. It creates a task group for the
/// app-server process, writer pump, and reader pump, performs the bootstrap
/// handshake, then closes the send side when the callback returns or raises.
pub async fn[R] Codex::with_app_server(
  self : Codex,
  options? : AppServerOptions = AppServerOptions::default(),
  request_handler? : async (AppServerRequest) -> AppServerResponse,
  body : async (CodexAppConnection) -> R,
) -> R {
  @async.with_task_group(tg => {
    let connection = self.spawn_app_server(tg, options~)
    defer connection.close()
    let _ = connection.initialize(options.initialize_params())
    connection.initialized()
    if request_handler is Some(handler) {
      tg.spawn_bg(() => connection.serve_requests(handler))
    }
    body(connection)
  })
}

///|
fn[G] Codex::spawn_app_server(
  self : Codex,
  taskgroup : @async.TaskGroup[G],
  options? : AppServerOptions = AppServerOptions::default(),
) -> CodexAppConnection raise Error {
  let executable_path = match options.executable_path_override {
    Some(path) => path
    None => self.options.codex_path_override.unwrap_or("codex")
  }
  let outgoing : @async.Queue[Json] = @async.Queue::Queue(kind=Unbounded)
  let events : @async.Queue[AppQueuedServerEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let requests : @async.Queue[AppServerRequest] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stdin = @process.write_to_process() catch {
    e => @error.fail("failed to open app-server stdin: \{e}")
  }
  let stdout = @process.read_from_process() catch {
    e => @error.fail("failed to open app-server stdout: \{e}")
  }
  let extra_env = self.options.env.unwrap_or({})
  if self.options.base_url is Some(base_url) {
    extra_env.set("OPENAI_BASE_URL", base_url)
  }
  if self.options.api_key is Some(api_key) {
    extra_env.set("CODEX_API_KEY", api_key)
  }
  let connection : CodexAppConnection = {
    outgoing,
    events,
    requests,
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  taskgroup.spawn_bg(() => {
    let (exit_code, stderr) = @process.collect_stderr(
      executable_path,
      ["app-server", "--listen", "stdio://"],
      stdin=stdin.0,
      stdout=stdout.1,
      inherit_env=self.options.env is None,
      extra_env~,
    )
    if exit_code != 0 {
      @error.fail("Codex app server failed: \{stderr.text()}")
    }
  })
  taskgroup.spawn_bg(() => {
    defer stdin.1.close()
    try {
      while true {
        let message = outgoing.get()
        stdin.1.write("\{message.stringify()}\n")
      }
    } catch {
      _ => ()
    }
  })
  taskgroup.spawn_bg(() => {
    let reader = stdout.0
    defer reader.close()
    try {
      while reader.read_until("\n") is Some(text) {
        let message : AppServerMessage = @json.from_json(@json.parse(text))
        connection.route_server_message(message)
      }
    } catch {
      e if @async.is_cancellation_error(e) => raise e
      e => {
        connection.close_pending_requests()
        events.put(AppQueuedClosed)
        requests.close(clear=false)
        raise @error.reraise(e)
      }
    }
    connection.close_pending_requests()
    events.put(AppQueuedClosed)
    requests.close(clear=false)
  })
  connection
}

///|
struct CodexAppConnection {
  outgoing : @async.Queue[Json]
  events : @async.Queue[AppQueuedServerEvent]
  requests : @async.Queue[AppServerRequest]
  mut pending : Array[AppPendingRequest]
  mut next_request_id : Int
  mut events_closed : Bool
}

///|
priv struct AppPendingRequest {
  id : AppRequestId
  replies : @async.Queue[AppPendingResponse]
}

///|
priv enum AppPendingResponse {
  AppPendingResult(Json)
  AppPendingError(AppRpcError)
}

///|
priv enum AppQueuedServerEvent {
  AppQueuedEvent(AppServerEvent)
  AppQueuedClosed
}

///|
/// Call one app-server JSON-RPC method and wait for its response.
///
/// This is the ergonomic request/response API for app-server operations. It
/// allocates an integer JSON-RPC id, sends a `ClientRequest`, and waits on a
/// per-request response queue. A single reader pump owns stdout and routes
/// responses by id, so multiple client-initiated RPC calls may be in flight at
/// once.
async fn CodexAppConnection::call(
  self : CodexAppConnection,
  rpc_method : String,
  params? : Json,
) -> Json {
  let id = AppRequestId::IntId(self.next_request_id.to_int64())
  self.next_request_id += 1
  let replies : @async.Queue[AppPendingResponse] = @async.Queue::Queue(
    kind=Unbounded,
  )
  self.pending.push({ id, replies })
  self.send(AppClientMessage::ClientRequest(id~, rpc_method~, params~)) catch {
    e => {
      self.drop_pending_request(id)
      raise @error.reraise(e)
    }
  }
  let response = replies.get() catch {
    _ =>
      @error.fail("Codex app server closed before responding to \{rpc_method}")
  }
  match response {
    AppPendingResult(result) => result
    AppPendingError(error) => @error.fail(format_app_rpc_error(error))
  }
}

///|
async fn CodexAppConnection::route_server_message(
  self : CodexAppConnection,
  message : AppServerMessage,
) -> Unit {
  match message {
    Response(id~, result~) =>
      if self.complete_pending_request(id, AppPendingResult(result)) {
        ()
      }
    ErrorResponse(id~, error~) =>
      if self.complete_pending_request(id, AppPendingError(error)) {
        ()
      }
    Request(request) => self.requests.put(request)
    UnsupportedRequest(id~, rpc_method~) =>
      self.respond_error(id, {
        code: -32601,
        message: "Unsupported app-server request: \{rpc_method}",
        data: None,
      })
    IgnoredNotification => ()
    Notification(event) => self.events.put(AppQueuedEvent(event))
  }
}

///|
async fn CodexAppConnection::complete_pending_request(
  self : CodexAppConnection,
  id : AppRequestId,
  response : AppPendingResponse,
) -> Bool {
  let mut replies : @async.Queue[AppPendingResponse]? = None
  let remaining : Array[AppPendingRequest] = []
  for pending in self.pending {
    if replies is None && pending.id == id {
      replies = Some(pending.replies)
    } else {
      remaining.push(pending)
    }
  }
  self.pending = remaining
  match replies {
    Some(replies) => {
      replies.put(response)
      true
    }
    None => false
  }
}

///|
fn CodexAppConnection::close_pending_requests(
  self : CodexAppConnection,
) -> Unit {
  let pending = self.pending
  self.pending = []
  for request in pending {
    request.replies.close(clear=true)
  }
}

///|
fn CodexAppConnection::drop_pending_request(
  self : CodexAppConnection,
  id : AppRequestId,
) -> Unit {
  let remaining : Array[AppPendingRequest] = []
  for request in self.pending {
    if request.id != id {
      remaining.push(request)
    }
  }
  self.pending = remaining
}

///|
/// Send the app-server `initialized` notification.
async fn CodexAppConnection::initialized(self : CodexAppConnection) -> Unit {
  self.notify("initialized")
}

///|
/// Call `thread/list`.
pub async fn CodexAppConnection::thread_list(
  self : CodexAppConnection,
  params? : AppThreadListParams,
) -> AppThreadListResponse {
  let params = match params {
    Some(params) => params
    None => AppThreadListParams::new()
  }
  @json.from_json(self.call_raw("thread/list", params=params.to_json()))
}

///|
/// Call `thread/start`.
pub async fn CodexAppConnection::thread_start(
  self : CodexAppConnection,
  params? : AppThreadStartParams,
) -> AppThreadStartResponse {
  let params = match params {
    Some(params) => params
    None => AppThreadStartParams::new()
  }
  @json.from_json(self.call_raw("thread/start", params=params.to_json()))
}

///|
/// Call `thread/resume`.
pub async fn CodexAppConnection::thread_resume(
  self : CodexAppConnection,
  params : AppThreadResumeParams,
) -> AppThreadResumeResponse {
  @json.from_json(self.call_raw("thread/resume", params=params.to_json()))
}

///|
/// Call `thread/archive`.
pub async fn CodexAppConnection::thread_archive(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> Unit {
  self.call_empty("thread/archive", params=params.to_json())
}

///|
/// Call `thread/unarchive`.
pub async fn CodexAppConnection::thread_unarchive(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadReadResponse {
  @json.from_json(self.call_raw("thread/unarchive", params=params.to_json()))
}

///|
/// Call `thread/unsubscribe`.
pub async fn CodexAppConnection::thread_unsubscribe(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadUnsubscribeResponse {
  @json.from_json(self.call_raw("thread/unsubscribe", params=params.to_json()))
}

///|
/// Call `thread/name/set`.
pub async fn CodexAppConnection::thread_set_name(
  self : CodexAppConnection,
  params : AppThreadSetNameParams,
) -> Unit {
  self.call_empty("thread/name/set", params=params.to_json())
}

///|
/// Call `thread/loaded/list`.
pub async fn CodexAppConnection::thread_loaded_list(
  self : CodexAppConnection,
  params? : AppThreadLoadedListParams,
) -> AppThreadLoadedListResponse {
  let params = match params {
    Some(params) => params
    None => AppThreadLoadedListParams::new()
  }
  @json.from_json(self.call_raw("thread/loaded/list", params=params.to_json()))
}

///|
/// Call `thread/read`.
pub async fn CodexAppConnection::thread_read(
  self : CodexAppConnection,
  params : AppThreadReadParams,
) -> AppThreadReadResponse {
  @json.from_json(self.call_raw("thread/read", params=params.to_json()))
}

///|
/// Call `turn/start`.
pub async fn CodexAppConnection::turn_start(
  self : CodexAppConnection,
  params : AppTurnStartParams,
) -> AppTurnStartResponse {
  @json.from_json(self.call_raw("turn/start", params=params.to_json()))
}

///|
/// Call `turn/steer`.
pub async fn CodexAppConnection::turn_steer(
  self : CodexAppConnection,
  params : AppTurnSteerParams,
) -> AppTurnSteerResponse {
  @json.from_json(self.call_raw("turn/steer", params=params.to_json()))
}

///|
/// Call `turn/interrupt`.
pub async fn CodexAppConnection::turn_interrupt(
  self : CodexAppConnection,
  params : AppTurnInterruptParams,
) -> Unit {
  self.call_empty("turn/interrupt", params=params.to_json())
}

///|
/// Call `skills/list`.
pub async fn CodexAppConnection::skills_list(
  self : CodexAppConnection,
  params? : AppSkillsListParams,
) -> AppSkillsListResponse {
  let params = match params {
    Some(params) => params
    None => AppSkillsListParams::new()
  }
  @json.from_json(self.call_raw("skills/list", params=params.to_json()))
}

///|
/// Call `app/list`.
pub async fn CodexAppConnection::app_list(
  self : CodexAppConnection,
  params? : AppListParams,
) -> AppListResponse {
  let params = match params {
    Some(params) => params
    None => AppListParams::new()
  }
  @json.from_json(self.call_raw("app/list", params=params.to_json()))
}

///|
/// Call `config/read`.
pub async fn CodexAppConnection::config_read(
  self : CodexAppConnection,
  params : AppConfigReadParams,
) -> AppConfigReadResponse {
  @json.from_json(self.call_raw("config/read", params=params.to_json()))
}

///|
/// Call `modelProvider/capabilities/read`.
pub async fn CodexAppConnection::model_provider_capabilities_read(
  self : CodexAppConnection,
) -> AppModelProviderCapabilitiesReadResponse {
  @json.from_json(self.call_raw("modelProvider/capabilities/read", params={}))
}

///|
pub struct AppThreadListResponse {
  data : ArrayView[AppThread]
  next_cursor : String?
  backwards_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadListResponse with fn from_json(value, path) {
  guard value
    is {
      "data": data,
      "nextCursor"? : next_cursor,
      "backwardsCursor"? : backwards_cursor,
      ..
    } else {
    raise JsonDecodeError((path, "expected thread/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
    backwards_cursor: app_optional_string(
      backwards_cursor,
      path.add_key("backwardsCursor"),
    ),
  }
}

///|
pub struct AppThreadStartResponse {
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
} derive(Debug)

///|
pub impl FromJson for AppThreadStartResponse with fn from_json(value, path) {
  app_thread_session_response(value, path, "expected thread/start response")
}

///|
pub struct AppThreadResumeResponse {
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
} derive(Debug)

///|
pub impl FromJson for AppThreadResumeResponse with fn from_json(value, path) {
  let response = app_thread_session_response(
    value, path, "expected thread/resume response",
  )
  {
    thread: response.thread,
    model: response.model,
    model_provider: response.model_provider,
    service_tier: response.service_tier,
    cwd: response.cwd,
    instruction_sources: response.instruction_sources,
    approval_policy: response.approval_policy,
    approvals_reviewer: response.approvals_reviewer,
    sandbox: response.sandbox,
    reasoning_effort: response.reasoning_effort,
  }
}

///|
fn app_thread_session_response(
  value : Json,
  path : @json.JsonPath,
  expected : String,
) -> AppThreadStartResponse raise @json.JsonDecodeError {
  guard value
    is {
      "thread": thread,
      "model": String(model),
      "modelProvider": String(model_provider),
      "serviceTier"? : service_tier,
      "cwd": String(cwd),
      "instructionSources"? : instruction_sources,
      "approvalPolicy": approval_policy,
      "approvalsReviewer": approvals_reviewer,
      "sandbox": sandbox,
      "reasoningEffort"? : reasoning_effort,
      ..
    } else {
    raise JsonDecodeError((path, expected))
  }
  {
    thread: @json.from_json(thread, path=path.add_key("thread")),
    model,
    model_provider,
    service_tier: app_optional_string(service_tier, path.add_key("serviceTier")),
    cwd,
    instruction_sources: match instruction_sources {
      Some(value) =>
        @json.from_json(value, path=path.add_key("instructionSources"))
      None => []
    },
    approval_policy: @json.from_json(
      approval_policy,
      path=path.add_key("approvalPolicy"),
    ),
    approvals_reviewer: @json.from_json(
      approvals_reviewer,
      path=path.add_key("approvalsReviewer"),
    ),
    sandbox: @json.from_json(sandbox, path=path.add_key("sandbox")),
    reasoning_effort: match reasoning_effort {
      Some(Null) | None => None
      Some(reasoning_effort) =>
        Some(
          @json.from_json(
            reasoning_effort,
            path=path.add_key("reasoningEffort"),
          ),
        )
    },
  }
}

///|
pub struct AppThreadReadResponse {
  thread : AppThread
} derive(Debug)

///|
pub impl FromJson for AppThreadReadResponse with fn from_json(value, path) {
  guard value is { "thread": thread, .. } else {
    raise JsonDecodeError((path, "expected thread/read response"))
  }
  { thread: @json.from_json(thread, path=path.add_key("thread")) }
}

///|
pub struct AppTurnStartResponse {
  turn : AppTurn
} derive(Debug)

///|
pub impl FromJson for AppTurnStartResponse with fn from_json(value, path) {
  guard value is { "turn": turn, .. } else {
    raise JsonDecodeError((path, "expected turn/start response"))
  }
  { turn: @json.from_json(turn, path=path.add_key("turn")) }
}

///|
pub struct AppThreadIdParams {
  thread_id : String
} derive(Debug)

///|
pub fn AppThreadIdParams::new(thread_id : String) -> AppThreadIdParams {
  { thread_id, }
}

///|
pub impl ToJson for AppThreadIdParams with fn to_json(params) {
  { "threadId": params.thread_id }
}

///|
pub struct AppThreadSetNameParams {
  thread_id : String
  name : String
} derive(Debug)

///|
pub fn AppThreadSetNameParams::new(
  thread_id : String,
  name : String,
) -> AppThreadSetNameParams {
  { thread_id, name }
}

///|
pub impl ToJson for AppThreadSetNameParams with fn to_json(params) {
  { "threadId": params.thread_id, "name": params.name }
}

///|
pub struct AppThreadResumeParams {
  thread_id : String
  model : String?
  model_provider : String?
  service_tier : AppNullableString?
  cwd : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox : SandboxMode?
  config : Map[String, Json]?
  base_instructions : String?
  developer_instructions : String?
  personality : AppPersonality?
} derive(Debug)

///|
pub fn AppThreadResumeParams::new(
  thread_id : String,
  model? : String,
  model_provider? : String,
  service_tier? : AppNullableString,
  cwd? : String,
  approval_policy? : AppApprovalPolicy,
  approvals_reviewer? : AppApprovalsReviewer,
  sandbox? : SandboxMode,
  config? : Map[String, Json],
  base_instructions? : String,
  developer_instructions? : String,
  personality? : AppPersonality,
) -> AppThreadResumeParams {
  {
    thread_id,
    model,
    model_provider,
    service_tier,
    cwd,
    approval_policy,
    approvals_reviewer,
    sandbox,
    config,
    base_instructions,
    developer_instructions,
    personality,
  }
}

///|
pub impl ToJson for AppThreadResumeParams with fn to_json(params) {
  let obj : Map[String, Json] = { "threadId": params.thread_id }
  if params.model is Some(model) {
    obj.set("model", model.to_json())
  }
  if params.model_provider is Some(model_provider) {
    obj.set("modelProvider", model_provider.to_json())
  }
  app_put_nullable_string(obj, "serviceTier", params.service_tier)
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  if params.approval_policy is Some(approval_policy) {
    obj.set("approvalPolicy", approval_policy.to_json())
  }
  if params.approvals_reviewer is Some(approvals_reviewer) {
    obj.set("approvalsReviewer", approvals_reviewer.to_json())
  }
  if params.sandbox is Some(sandbox) {
    obj.set("sandbox", sandbox.to_json())
  }
  if params.config is Some(config) {
    obj.set("config", config.to_json())
  }
  if params.base_instructions is Some(base_instructions) {
    obj.set("baseInstructions", base_instructions.to_json())
  }
  if params.developer_instructions is Some(developer_instructions) {
    obj.set("developerInstructions", developer_instructions.to_json())
  }
  if params.personality is Some(personality) {
    obj.set("personality", personality.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppThreadLoadedListParams {
  cursor : String?
  limit : UInt?
} derive(Debug)

///|
pub fn AppThreadLoadedListParams::new(
  cursor? : String,
  limit? : UInt,
) -> AppThreadLoadedListParams {
  { cursor, limit }
}

///|
pub impl ToJson for AppThreadLoadedListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cursor is Some(cursor) {
    obj.set("cursor", cursor.to_json())
  }
  if params.limit is Some(limit) {
    obj.set("limit", limit.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppThreadLoadedListResponse {
  data : ArrayView[String]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadLoadedListResponse with fn from_json(value, path) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected thread/loaded/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub struct AppThreadUnsubscribeResponse {
  status : AppThreadUnsubscribeStatus
} derive(Debug)

///|
pub impl FromJson for AppThreadUnsubscribeResponse with fn from_json(
  value,
  path,
) {
  guard value is { "status": status, .. } else {
    raise JsonDecodeError((path, "expected thread/unsubscribe response"))
  }
  { status: @json.from_json(status, path=path.add_key("status")) }
}

///|
pub(all) enum AppThreadUnsubscribeStatus {
  AppThreadNotLoaded
  AppThreadNotSubscribed
  AppThreadUnsubscribed
} derive(Debug)

///|
pub impl FromJson for AppThreadUnsubscribeStatus with fn from_json(value, path) {
  match value {
    String("notLoaded") => AppThreadNotLoaded
    String("notSubscribed") => AppThreadNotSubscribed
    String("unsubscribed") => AppThreadUnsubscribed
    _ => raise JsonDecodeError((path, "expected thread unsubscribe status"))
  }
}

///|
pub struct AppTurnSteerParams {
  thread_id : String
  input : Array[AppUserInput]
  expected_turn_id : String
} derive(Debug)

///|
pub fn AppTurnSteerParams::new(
  thread_id : String,
  input : Array[AppUserInput],
  expected_turn_id : String,
) -> AppTurnSteerParams {
  { thread_id, input, expected_turn_id }
}

///|
pub impl ToJson for AppTurnSteerParams with fn to_json(params) {
  {
    "threadId": params.thread_id,
    "input": params.input,
    "expectedTurnId": params.expected_turn_id,
  }
}

///|
pub struct AppTurnSteerResponse {
  turn_id : String
} derive(Debug)

///|
pub impl FromJson for AppTurnSteerResponse with fn from_json(value, path) {
  guard value is { "turnId": String(turn_id), .. } else {
    raise JsonDecodeError((path, "expected turn/steer response"))
  }
  { turn_id, }
}

///|
pub struct AppSkillsListParams {
  cwds : Array[String]?
  force_reload : Bool?
} derive(Debug)

///|
pub fn AppSkillsListParams::new(
  cwds? : Array[String],
  force_reload? : Bool,
) -> AppSkillsListParams {
  { cwds, force_reload }
}

///|
pub impl ToJson for AppSkillsListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cwds is Some(cwds) {
    obj.set("cwds", cwds.to_json())
  }
  app_put_true(obj, "forceReload", params.force_reload)
  Json::object(obj)
}

///|
pub struct AppSkillMetadata {
  name : String
  description : String
  short_description : String?
  interface : AppSkillInterface?
  dependencies : AppSkillDependencies?
  path : String
  scope : AppSkillScope
  enabled : Bool
} derive(Debug)

///|
pub impl FromJson for AppSkillMetadata with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "description": String(description),
      "shortDescription"? : short_description,
      "interface"? : skill_interface,
      "dependencies"? : dependencies,
      "path": String(skill_path),
      "scope": scope,
      "enabled": enabled,
      ..
    } else {
    raise JsonDecodeError((path, "expected skill metadata"))
  }
  {
    name,
    description,
    short_description: app_optional_string(
      short_description,
      path.add_key("shortDescription"),
    ),
    interface: match skill_interface {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("interface")))
    },
    dependencies: match dependencies {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("dependencies")))
    },
    path: skill_path,
    scope: @json.from_json(scope, path=path.add_key("scope")),
    enabled: app_bool(enabled, path.add_key("enabled")),
  }
}

///|
pub enum AppSkillScope {
  AppSkillScopeUser
  AppSkillScopeRepo
  AppSkillScopeSystem
  AppSkillScopeAdmin
} derive(Debug)

///|
pub impl FromJson for AppSkillScope with fn from_json(value, path) {
  match value {
    String("user") => AppSkillScopeUser
    String("repo") => AppSkillScopeRepo
    String("system") => AppSkillScopeSystem
    String("admin") => AppSkillScopeAdmin
    _ => raise JsonDecodeError((path, "expected skill scope"))
  }
}

///|
pub struct AppSkillDependencies {
  tools : ArrayView[AppSkillToolDependency]
} derive(Debug)

///|
pub impl FromJson for AppSkillDependencies with fn from_json(value, path) {
  guard value is { "tools": tools, .. } else {
    raise JsonDecodeError((path, "expected skill dependencies"))
  }
  { tools: @json.from_json(tools, path=path.add_key("tools")) }
}

///|
pub struct AppSkillToolDependency {
  dep_type : String
  value : String
  description : String?
  transport : String?
  command : String?
  url : String?
} derive(Debug)

///|
pub impl FromJson for AppSkillToolDependency with fn from_json(value, path) {
  guard value
    is {
      "type": String(dep_type),
      "value": String(dep_value),
      "description"? : description,
      "transport"? : transport,
      "command"? : command,
      "url"? : url,
      ..
    } else {
    raise JsonDecodeError((path, "expected skill tool dependency"))
  }
  {
    dep_type,
    value: dep_value,
    description: app_optional_string(description, path.add_key("description")),
    transport: app_optional_string(transport, path.add_key("transport")),
    command: app_optional_string(command, path.add_key("command")),
    url: app_optional_string(url, path.add_key("url")),
  }
}

///|
pub struct AppSkillErrorInfo {
  path : String
  message : String
} derive(Debug)

///|
pub impl FromJson for AppSkillErrorInfo with fn from_json(value, path) {
  guard value is { "path": String(skill_path), "message": String(message), .. } else {
    raise JsonDecodeError((path, "expected skill error info"))
  }
  { path: skill_path, message }
}

///|
pub struct AppSkillsListEntry {
  cwd : String
  skills : ArrayView[AppSkillMetadata]
  errors : ArrayView[AppSkillErrorInfo]
} derive(Debug)

///|
pub impl FromJson for AppSkillsListEntry with fn from_json(value, path) {
  guard value is { "cwd": String(cwd), "skills": skills, "errors": errors, .. } else {
    raise JsonDecodeError((path, "expected skills/list entry"))
  }
  {
    cwd,
    skills: @json.from_json(skills, path=path.add_key("skills")),
    errors: @json.from_json(errors, path=path.add_key("errors")),
  }
}

///|
pub struct AppSkillsListResponse {
  data : ArrayView[AppSkillsListEntry]
} derive(Debug)

///|
pub impl FromJson for AppSkillsListResponse with fn from_json(value, path) {
  guard value is { "data": data, .. } else {
    raise JsonDecodeError((path, "expected skills/list response"))
  }
  { data: @json.from_json(data, path=path.add_key("data")) }
}

///|
pub struct AppListParams {
  cursor : String?
  limit : UInt?
  thread_id : String?
  force_refetch : Bool?
} derive(Debug)

///|
pub fn AppListParams::new(
  cursor? : String,
  limit? : UInt,
  thread_id? : String,
  force_refetch? : Bool,
) -> AppListParams {
  { cursor, limit, thread_id, force_refetch }
}

///|
pub impl ToJson for AppListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cursor is Some(cursor) {
    obj.set("cursor", cursor.to_json())
  }
  if params.limit is Some(limit) {
    obj.set("limit", limit.to_json())
  }
  if params.thread_id is Some(thread_id) {
    obj.set("threadId", thread_id.to_json())
  }
  app_put_true(obj, "forceRefetch", params.force_refetch)
  Json::object(obj)
}

///|
pub struct AppListResponse {
  data : ArrayView[AppInfo]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppListResponse with fn from_json(value, path) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected app/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub struct AppInfo {
  id : String
  name : String
  description : String?
  is_accessible : Bool
  is_enabled : Bool
  plugin_display_names : ArrayView[String]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppInfo with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "description"? : description,
      "isAccessible"? : is_accessible,
      "isEnabled"? : is_enabled,
      "pluginDisplayNames"? : plugin_display_names,
      ..
    } else {
    raise JsonDecodeError((path, "expected app info"))
  }
  {
    id,
    name,
    description: app_optional_string(description, path.add_key("description")),
    is_accessible: match is_accessible {
      Some(value) => app_bool(value, path.add_key("isAccessible"))
      None => false
    },
    is_enabled: match is_enabled {
      Some(value) => app_bool(value, path.add_key("isEnabled"))
      None => true
    },
    plugin_display_names: match plugin_display_names {
      Some(value) =>
        @json.from_json(value, path=path.add_key("pluginDisplayNames"))
      None =>
        @json.from_json(
          Json::array([]),
          path=path.add_key("pluginDisplayNames"),
        )
    },
    raw: value,
  }
}

///|
pub struct AppConfigReadParams {
  include_layers : Bool
  cwd : String?
} derive(Debug)

///|
pub fn AppConfigReadParams::new(
  include_layers : Bool,
  cwd? : String,
) -> AppConfigReadParams {
  { include_layers, cwd }
}

///|
pub impl ToJson for AppConfigReadParams with fn to_json(params) {
  let obj : Map[String, Json] = { "includeLayers": params.include_layers }
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppConfigSnapshot {
  model : String?
  review_model : String?
  model_context_window : Int64?
  model_auto_compact_token_limit : Int64?
  model_provider : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox_mode : SandboxMode?
  sandbox_workspace_write : AppSandboxWorkspaceWrite?
  forced_chatgpt_workspace_id : String?
  forced_login_method : AppForcedLoginMethod?
  web_search : AppWebSearchMode?
  tools : AppConfigToolsV2?
  profile : String?
  profiles : Map[String, AppProfileV2]
  instructions : String?
  developer_instructions : String?
  compact_prompt : String?
  model_reasoning_effort : AppReasoningEffort?
  model_reasoning_summary : AppReasoningSummary?
  model_verbosity : AppModelVerbosity?
  service_tier : String?
  analytics : AppAnalyticsConfig?
  apps : AppAppsConfig?
  additional : Map[String, Json]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppConfigSnapshot with fn from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected config snapshot"))
  }
  let additional : Map[String, Json] = {}
  obj.each((key, value) => {
    if !app_config_known_key(key) {
      additional.set(key, value)
    }
  })
  guard value
    is {
      "model"? : model,
      "review_model"? : review_model,
      "model_context_window"? : model_context_window,
      "model_auto_compact_token_limit"? : model_auto_compact_token_limit,
      "model_provider"? : model_provider,
      "approval_policy"? : approval_policy,
      "approvals_reviewer"? : approvals_reviewer,
      "sandbox_mode"? : sandbox_mode,
      "sandbox_workspace_write"? : sandbox_workspace_write,
      "forced_chatgpt_workspace_id"? : forced_chatgpt_workspace_id,
      "forced_login_method"? : forced_login_method,
      "web_search"? : web_search,
      "tools"? : tools,
      "profile"? : profile,
      "profiles"? : profiles,
      "instructions"? : instructions,
      "developer_instructions"? : developer_instructions,
      "compact_prompt"? : compact_prompt,
      "model_reasoning_effort"? : model_reasoning_effort,
      "model_reasoning_summary"? : model_reasoning_summary,
      "model_verbosity"? : model_verbosity,
      "service_tier"? : service_tier,
      "analytics"? : analytics,
      "apps"? : apps,
      ..
    } else {
    raise JsonDecodeError((path, "expected config snapshot"))
  }
  {
    model: app_optional_string(model, path.add_key("model")),
    review_model: app_optional_string(
      review_model,
      path.add_key("review_model"),
    ),
    model_context_window: app_optional_int64(
      model_context_window,
      path.add_key("model_context_window"),
    ),
    model_auto_compact_token_limit: app_optional_int64(
      model_auto_compact_token_limit,
      path.add_key("model_auto_compact_token_limit"),
    ),
    model_provider: app_optional_string(
      model_provider,
      path.add_key("model_provider"),
    ),
    approval_policy: match approval_policy {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("approval_policy")))
    },
    approvals_reviewer: match approvals_reviewer {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("approvals_reviewer")))
    },
    sandbox_mode: match sandbox_mode {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("sandbox_mode")))
    },
    sandbox_workspace_write: match sandbox_workspace_write {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("sandbox_workspace_write")),
        )
    },
    forced_chatgpt_workspace_id: app_optional_string(
      forced_chatgpt_workspace_id,
      path.add_key("forced_chatgpt_workspace_id"),
    ),
    forced_login_method: match forced_login_method {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("forced_login_method")))
    },
    web_search: match web_search {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("web_search")))
    },
    tools: match tools {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("tools")))
    },
    profile: app_optional_string(profile, path.add_key("profile")),
    profiles: match profiles {
      Some(value) => @json.from_json(value, path=path.add_key("profiles"))
      None => {}
    },
    instructions: app_optional_string(
      instructions,
      path.add_key("instructions"),
    ),
    developer_instructions: app_optional_string(
      developer_instructions,
      path.add_key("developer_instructions"),
    ),
    compact_prompt: app_optional_string(
      compact_prompt,
      path.add_key("compact_prompt"),
    ),
    model_reasoning_effort: match model_reasoning_effort {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("model_reasoning_effort")),
        )
    },
    model_reasoning_summary: match model_reasoning_summary {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("model_reasoning_summary")),
        )
    },
    model_verbosity: match model_verbosity {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("model_verbosity")))
    },
    service_tier: app_optional_string(
      service_tier,
      path.add_key("service_tier"),
    ),
    analytics: match analytics {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("analytics")))
    },
    apps: match apps {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("apps")))
    },
    additional,
    raw: value,
  }
}

///|
pub impl ToJson for AppConfigSnapshot with fn to_json(snapshot) {
  snapshot.raw
}

///|
pub struct AppSandboxWorkspaceWrite {
  writable_roots : ArrayView[String]
  network_access : Bool
  exclude_tmpdir_env_var : Bool
  exclude_slash_tmp : Bool
} derive(Debug)

///|
pub impl FromJson for AppSandboxWorkspaceWrite with fn from_json(value, path) {
  guard value
    is {
      "writable_roots": writable_roots,
      "network_access": network_access,
      "exclude_tmpdir_env_var": exclude_tmpdir_env_var,
      "exclude_slash_tmp": exclude_slash_tmp,
      ..
    } else {
    raise JsonDecodeError((path, "expected sandbox workspace-write config"))
  }
  {
    writable_roots: @json.from_json(
      writable_roots,
      path=path.add_key("writable_roots"),
    ),
    network_access: app_bool(network_access, path.add_key("network_access")),
    exclude_tmpdir_env_var: app_bool(
      exclude_tmpdir_env_var,
      path.add_key("exclude_tmpdir_env_var"),
    ),
    exclude_slash_tmp: app_bool(
      exclude_slash_tmp,
      path.add_key("exclude_slash_tmp"),
    ),
  }
}

///|
pub enum AppForcedLoginMethod {
  AppForcedLoginChatGPT
  AppForcedLoginApi
} derive(Debug)

///|
pub impl FromJson for AppForcedLoginMethod with fn from_json(value, path) {
  match value {
    String("chatgpt") => AppForcedLoginChatGPT
    String("api") => AppForcedLoginApi
    _ => raise JsonDecodeError((path, "expected forced login method"))
  }
}

///|
pub enum AppModelVerbosity {
  AppVerbosityLow
  AppVerbosityMedium
  AppVerbosityHigh
} derive(Debug)

///|
pub impl FromJson for AppModelVerbosity with fn from_json(value, path) {
  match value {
    String("low") => AppVerbosityLow
    String("medium") => AppVerbosityMedium
    String("high") => AppVerbosityHigh
    _ => raise JsonDecodeError((path, "expected model verbosity"))
  }
}

///|
pub struct AppConfigToolsV2 {
  web_search : AppWebSearchToolConfig?
  view_image : Bool?
} derive(Debug)

///|
pub impl FromJson for AppConfigToolsV2 with fn from_json(value, path) {
  guard value is { "web_search"? : web_search, "view_image"? : view_image, .. } else {
    raise JsonDecodeError((path, "expected config tools"))
  }
  {
    web_search: match web_search {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("web_search")))
    },
    view_image: app_optional_bool(view_image, path.add_key("view_image")),
  }
}

///|
pub enum AppWebSearchContextSize {
  AppWebSearchContextLow
  AppWebSearchContextMedium
  AppWebSearchContextHigh
} derive(Debug)

///|
pub impl FromJson for AppWebSearchContextSize with fn from_json(value, path) {
  match value {
    String("low") => AppWebSearchContextLow
    String("medium") => AppWebSearchContextMedium
    String("high") => AppWebSearchContextHigh
    _ => raise JsonDecodeError((path, "expected web search context size"))
  }
}

///|
pub struct AppWebSearchLocation {
  country : String?
  region : String?
  city : String?
  timezone : String?
} derive(Debug)

///|
pub impl FromJson for AppWebSearchLocation with fn from_json(value, path) {
  guard value
    is {
      "country"? : country,
      "region"? : region,
      "city"? : city,
      "timezone"? : timezone,
      ..
    } else {
    raise JsonDecodeError((path, "expected web search location"))
  }
  {
    country: app_optional_string(country, path.add_key("country")),
    region: app_optional_string(region, path.add_key("region")),
    city: app_optional_string(city, path.add_key("city")),
    timezone: app_optional_string(timezone, path.add_key("timezone")),
  }
}

///|
pub struct AppWebSearchToolConfig {
  context_size : AppWebSearchContextSize?
  allowed_domains : ArrayView[String]?
  location : AppWebSearchLocation?
} derive(Debug)

///|
pub impl FromJson for AppWebSearchToolConfig with fn from_json(value, path) {
  guard value
    is {
      "context_size"? : context_size,
      "allowed_domains"? : allowed_domains,
      "location"? : location,
      ..
    } else {
    raise JsonDecodeError((path, "expected web search tool config"))
  }
  {
    context_size: match context_size {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("context_size")))
    },
    allowed_domains: match allowed_domains {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("allowed_domains")))
    },
    location: match location {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("location")))
    },
  }
}

///|
pub struct AppProfileV2 {
  model : String?
  model_provider : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  service_tier : String?
  model_reasoning_effort : AppReasoningEffort?
  model_reasoning_summary : AppReasoningSummary?
  model_verbosity : AppModelVerbosity?
  web_search : AppWebSearchMode?
  tools : AppConfigToolsV2?
  chatgpt_base_url : String?
  additional : Map[String, Json]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppProfileV2 with fn from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected config profile"))
  }
  let additional : Map[String, Json] = {}
  obj.each((key, value) => {
    if !app_profile_known_key(key) {
      additional.set(key, value)
    }
  })
  guard value
    is {
      "model"? : model,
      "model_provider"? : model_provider,
      "approval_policy"? : approval_policy,
      "approvals_reviewer"? : approvals_reviewer,
      "service_tier"? : service_tier,
      "model_reasoning_effort"? : model_reasoning_effort,
      "model_reasoning_summary"? : model_reasoning_summary,
      "model_verbosity"? : model_verbosity,
      "web_search"? : web_search,
      "tools"? : tools,
      "chatgpt_base_url"? : chatgpt_base_url,
      ..
    } else {
    raise JsonDecodeError((path, "expected config profile"))
  }
  {
    model: app_optional_string(model, path.add_key("model")),
    model_provider: app_optional_string(
      model_provider,
      path.add_key("model_provider"),
    ),
    approval_policy: match approval_policy {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("approval_policy")))
    },
    approvals_reviewer: match approvals_reviewer {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("approvals_reviewer")))
    },
    service_tier: app_optional_string(
      service_tier,
      path.add_key("service_tier"),
    ),
    model_reasoning_effort: match model_reasoning_effort {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("model_reasoning_effort")),
        )
    },
    model_reasoning_summary: match model_reasoning_summary {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("model_reasoning_summary")),
        )
    },
    model_verbosity: match model_verbosity {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("model_verbosity")))
    },
    web_search: match web_search {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("web_search")))
    },
    tools: match tools {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("tools")))
    },
    chatgpt_base_url: app_optional_string(
      chatgpt_base_url,
      path.add_key("chatgpt_base_url"),
    ),
    additional,
    raw: value,
  }
}

///|
pub struct AppAnalyticsConfig {
  enabled : Bool?
  additional : Map[String, Json]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppAnalyticsConfig with fn from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected analytics config"))
  }
  let additional : Map[String, Json] = {}
  obj.each((key, value) => if key != "enabled" { additional.set(key, value) })
  guard value is { "enabled"? : enabled, .. } else {
    raise JsonDecodeError((path, "expected analytics config"))
  }
  {
    enabled: app_optional_bool(enabled, path.add_key("enabled")),
    additional,
    raw: value,
  }
}

///|
pub enum AppToolApproval {
  AppToolApprovalAuto
  AppToolApprovalPrompt
  AppToolApprovalApprove
} derive(Debug)

///|
pub impl FromJson for AppToolApproval with fn from_json(value, path) {
  match value {
    String("auto") => AppToolApprovalAuto
    String("prompt") => AppToolApprovalPrompt
    String("approve") => AppToolApprovalApprove
    _ => raise JsonDecodeError((path, "expected app tool approval"))
  }
}

///|
pub struct AppToolConfig {
  enabled : Bool?
  approval_mode : AppToolApproval?
} derive(Debug)

///|
pub impl FromJson for AppToolConfig with fn from_json(value, path) {
  guard value is { "enabled"? : enabled, "approval_mode"? : approval_mode, .. } else {
    raise JsonDecodeError((path, "expected app tool config"))
  }
  {
    enabled: app_optional_bool(enabled, path.add_key("enabled")),
    approval_mode: match approval_mode {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("approval_mode")))
    },
  }
}

///|
pub struct AppToolsConfig {
  tools : Map[String, AppToolConfig]
} derive(Debug)

///|
pub impl FromJson for AppToolsConfig with fn from_json(value, path) {
  guard value is Object(_) else {
    raise JsonDecodeError((path, "expected app tools config"))
  }
  { tools: @json.from_json(value, path~) }
}

///|
pub struct AppConnectorConfig {
  enabled : Bool
  destructive_enabled : Bool?
  open_world_enabled : Bool?
  default_tools_approval_mode : AppToolApproval?
  default_tools_enabled : Bool?
  tools : AppToolsConfig?
} derive(Debug)

///|
pub impl FromJson for AppConnectorConfig with fn from_json(value, path) {
  guard value
    is {
      "enabled": enabled,
      "destructive_enabled"? : destructive_enabled,
      "open_world_enabled"? : open_world_enabled,
      "default_tools_approval_mode"? : default_tools_approval_mode,
      "default_tools_enabled"? : default_tools_enabled,
      "tools"? : tools,
      ..
    } else {
    raise JsonDecodeError((path, "expected app connector config"))
  }
  {
    enabled: app_bool(enabled, path.add_key("enabled")),
    destructive_enabled: app_optional_bool(
      destructive_enabled,
      path.add_key("destructive_enabled"),
    ),
    open_world_enabled: app_optional_bool(
      open_world_enabled,
      path.add_key("open_world_enabled"),
    ),
    default_tools_approval_mode: match default_tools_approval_mode {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(
            value,
            path=path.add_key("default_tools_approval_mode"),
          ),
        )
    },
    default_tools_enabled: app_optional_bool(
      default_tools_enabled,
      path.add_key("default_tools_enabled"),
    ),
    tools: match tools {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("tools")))
    },
  }
}

///|
pub struct AppAppsDefaultConfig {
  enabled : Bool
  destructive_enabled : Bool
  open_world_enabled : Bool
} derive(Debug)

///|
pub impl FromJson for AppAppsDefaultConfig with fn from_json(value, path) {
  guard value
    is {
      "enabled": enabled,
      "destructive_enabled": destructive_enabled,
      "open_world_enabled": open_world_enabled,
      ..
    } else {
    raise JsonDecodeError((path, "expected default apps config"))
  }
  {
    enabled: app_bool(enabled, path.add_key("enabled")),
    destructive_enabled: app_bool(
      destructive_enabled,
      path.add_key("destructive_enabled"),
    ),
    open_world_enabled: app_bool(
      open_world_enabled,
      path.add_key("open_world_enabled"),
    ),
  }
}

///|
pub struct AppAppsConfig {
  default_config : AppAppsDefaultConfig?
  apps : Map[String, AppConnectorConfig]
} derive(Debug)

///|
pub impl FromJson for AppAppsConfig with fn from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected apps config"))
  }
  let apps : Map[String, AppConnectorConfig] = {}
  obj.each((key, app) => {
    if key != "_default" {
      apps.set(key, @json.from_json(app, path=path.add_key(key)))
    }
  })
  guard value is { "_default"? : default_config, .. } else {
    raise JsonDecodeError((path, "expected apps config"))
  }
  {
    default_config: match default_config {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("_default")))
    },
    apps,
  }
}

///|
pub struct AppConfigLayer {
  name : AppConfigLayerSource
  version : String
  config : Json
  disabled_reason : String?
} derive(Debug)

///|
pub impl FromJson for AppConfigLayer with fn from_json(value, path) {
  guard value
    is {
      "name": name,
      "version": String(version),
      "config": config,
      "disabledReason"? : disabled_reason,
      ..
    } else {
    raise JsonDecodeError((path, "expected config layer"))
  }
  {
    name: @json.from_json(name, path=path.add_key("name")),
    version,
    config,
    disabled_reason: app_optional_string(
      disabled_reason,
      path.add_key("disabledReason"),
    ),
  }
}

///|
fn app_config_known_key(key : String) -> Bool {
  match key {
    "model"
    | "review_model"
    | "model_context_window"
    | "model_auto_compact_token_limit"
    | "model_provider"
    | "approval_policy"
    | "approvals_reviewer"
    | "sandbox_mode"
    | "sandbox_workspace_write"
    | "forced_chatgpt_workspace_id"
    | "forced_login_method"
    | "web_search"
    | "tools"
    | "profile"
    | "profiles"
    | "instructions"
    | "developer_instructions"
    | "compact_prompt"
    | "model_reasoning_effort"
    | "model_reasoning_summary"
    | "model_verbosity"
    | "service_tier"
    | "analytics"
    | "apps" => true
    _ => false
  }
}

///|
fn app_profile_known_key(key : String) -> Bool {
  match key {
    "model"
    | "model_provider"
    | "approval_policy"
    | "approvals_reviewer"
    | "service_tier"
    | "model_reasoning_effort"
    | "model_reasoning_summary"
    | "model_verbosity"
    | "web_search"
    | "tools"
    | "chatgpt_base_url" => true
    _ => false
  }
}

///|
pub struct AppConfigReadResponse {
  config : AppConfigSnapshot
  origins : Map[String, AppConfigLayerMetadata]
  layers : ArrayView[AppConfigLayer]?
} derive(Debug)

///|
pub impl FromJson for AppConfigReadResponse with fn from_json(value, path) {
  guard value
    is { "config": config, "origins": origins, "layers"? : layers, .. } else {
    raise JsonDecodeError((path, "expected config/read response"))
  }
  {
    config: @json.from_json(config, path=path.add_key("config")),
    origins: @json.from_json(origins, path=path.add_key("origins")),
    layers: match layers {
      Some(Null) | None => None
      Some(layers) => Some(@json.from_json(layers, path=path.add_key("layers")))
    },
  }
}

///|
pub struct AppModelProviderCapabilitiesReadResponse {
  namespace_tools : Bool
  image_generation : Bool
  web_search : Bool
} derive(Debug)

///|
pub impl FromJson for AppModelProviderCapabilitiesReadResponse with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "namespaceTools": namespace_tools,
      "imageGeneration": image_generation,
      "webSearch": web_search,
      ..
    } else {
    raise JsonDecodeError(
      (path, "expected modelProvider/capabilities/read response"),
    )
  }
  {
    namespace_tools: app_bool(namespace_tools, path.add_key("namespaceTools")),
    image_generation: app_bool(
      image_generation,
      path.add_key("imageGeneration"),
    ),
    web_search: app_bool(web_search, path.add_key("webSearch")),
  }
}

///|
/// Parameters for the app-server `thread/list` request.
pub struct AppThreadListParams {
  cursor : String?
  limit : UInt?
  sort_key : AppThreadSortKey?
  sort_direction : AppSortDirection?
  model_providers : Array[String]?
  source_kinds : Array[AppThreadSourceKind]?
  archived : Bool?
  cwd : AppThreadListCwd?
  use_state_db_only : Bool?
  search_term : String?
} derive(Debug)

///|
pub fn AppThreadListParams::new(
  cursor? : String,
  limit? : UInt,
  sort_key? : AppThreadSortKey,
  sort_direction? : AppSortDirection,
  model_providers? : Array[String],
  source_kinds? : Array[AppThreadSourceKind],
  archived? : Bool,
  cwd? : AppThreadListCwd,
  use_state_db_only? : Bool,
  search_term? : String,
) -> AppThreadListParams {
  {
    cursor,
    limit,
    sort_key,
    sort_direction,
    model_providers,
    source_kinds,
    archived,
    cwd,
    use_state_db_only,
    search_term,
  }
}

///|
pub impl ToJson for AppThreadListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cursor is Some(cursor) {
    obj.set("cursor", cursor.to_json())
  }
  if params.limit is Some(limit) {
    obj.set("limit", limit.to_json())
  }
  if params.sort_key is Some(sort_key) {
    obj.set("sortKey", sort_key.to_json())
  }
  if params.sort_direction is Some(sort_direction) {
    obj.set("sortDirection", sort_direction.to_json())
  }
  if params.model_providers is Some(model_providers) {
    obj.set("modelProviders", model_providers.to_json())
  }
  if params.source_kinds is Some(source_kinds) {
    obj.set("sourceKinds", source_kinds.to_json())
  }
  if params.archived is Some(archived) {
    obj.set("archived", archived.to_json())
  }
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  app_put_true(obj, "useStateDbOnly", params.use_state_db_only)
  if params.search_term is Some(search_term) {
    obj.set("searchTerm", search_term.to_json())
  }
  Json::object(obj)
}

///|
pub(all) enum AppThreadListCwd {
  OneCwd(String)
  ManyCwds(Array[String])
} derive(Debug)

///|
pub impl ToJson for AppThreadListCwd with fn to_json(cwd) {
  match cwd {
    OneCwd(value) => value.to_json()
    ManyCwds(values) => values.to_json()
  }
}

///|
pub(all) enum AppThreadSortKey {
  ThreadCreatedAt
  ThreadUpdatedAt
} derive(Debug)

///|
pub impl ToJson for AppThreadSortKey with fn to_json(key) {
  match key {
    ThreadCreatedAt => "created_at".to_json()
    ThreadUpdatedAt => "updated_at".to_json()
  }
}

///|
pub(all) enum AppSortDirection {
  SortAsc
  SortDesc
} derive(Debug)

///|
pub impl ToJson for AppSortDirection with fn to_json(direction) {
  match direction {
    SortAsc => "asc".to_json()
    SortDesc => "desc".to_json()
  }
}

///|
pub(all) enum AppThreadSourceKind {
  SourceCli
  SourceVscode
  SourceExec
  SourceAppServer
  SourceSubAgent
  SourceSubAgentReview
  SourceSubAgentCompact
  SourceSubAgentThreadSpawn
  SourceSubAgentOther
  SourceUnknown
} derive(Debug)

///|
pub impl ToJson for AppThreadSourceKind with fn to_json(kind) {
  match kind {
    SourceCli => "cli".to_json()
    SourceVscode => "vscode".to_json()
    SourceExec => "exec".to_json()
    SourceAppServer => "appServer".to_json()
    SourceSubAgent => "subAgent".to_json()
    SourceSubAgentReview => "subAgentReview".to_json()
    SourceSubAgentCompact => "subAgentCompact".to_json()
    SourceSubAgentThreadSpawn => "subAgentThreadSpawn".to_json()
    SourceSubAgentOther => "subAgentOther".to_json()
    SourceUnknown => "unknown".to_json()
  }
}

///|
/// Parameters for the app-server `thread/start` request.
pub struct AppThreadStartParams {
  model : String?
  model_provider : String?
  service_tier : AppNullableString?
  cwd : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox : SandboxMode?
  config : Map[String, Json]?
  service_name : String?
  base_instructions : String?
  developer_instructions : String?
  personality : AppPersonality?
  ephemeral : Bool?
  session_start_source : AppThreadStartSource?
} derive(Debug)

///|
pub fn AppThreadStartParams::new(
  model? : String,
  model_provider? : String,
  service_tier? : AppNullableString,
  cwd? : String,
  approval_policy? : AppApprovalPolicy,
  approvals_reviewer? : AppApprovalsReviewer,
  sandbox? : SandboxMode,
  config? : Map[String, Json],
  service_name? : String,
  base_instructions? : String,
  developer_instructions? : String,
  personality? : AppPersonality,
  ephemeral? : Bool,
  session_start_source? : AppThreadStartSource,
) -> AppThreadStartParams {
  {
    model,
    model_provider,
    service_tier,
    cwd,
    approval_policy,
    approvals_reviewer,
    sandbox,
    config,
    service_name,
    base_instructions,
    developer_instructions,
    personality,
    ephemeral,
    session_start_source,
  }
}

///|
pub impl ToJson for AppThreadStartParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.model is Some(model) {
    obj.set("model", model.to_json())
  }
  if params.model_provider is Some(model_provider) {
    obj.set("modelProvider", model_provider.to_json())
  }
  app_put_nullable_string(obj, "serviceTier", params.service_tier)
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  if params.approval_policy is Some(approval_policy) {
    obj.set("approvalPolicy", approval_policy.to_json())
  }
  if params.approvals_reviewer is Some(approvals_reviewer) {
    obj.set("approvalsReviewer", approvals_reviewer.to_json())
  }
  if params.sandbox is Some(sandbox) {
    obj.set("sandbox", sandbox.to_json())
  }
  if params.config is Some(config) {
    obj.set("config", config.to_json())
  }
  if params.service_name is Some(service_name) {
    obj.set("serviceName", service_name.to_json())
  }
  if params.base_instructions is Some(base_instructions) {
    obj.set("baseInstructions", base_instructions.to_json())
  }
  if params.developer_instructions is Some(developer_instructions) {
    obj.set("developerInstructions", developer_instructions.to_json())
  }
  if params.personality is Some(personality) {
    obj.set("personality", personality.to_json())
  }
  if params.ephemeral is Some(ephemeral) {
    obj.set("ephemeral", ephemeral.to_json())
  }
  if params.session_start_source is Some(session_start_source) {
    obj.set("sessionStartSource", session_start_source.to_json())
  }
  Json::object(obj)
}

///|
pub(all) enum AppApprovalPolicy {
  AppApprovalUntrusted
  AppApprovalOnFailure
  AppApprovalOnRequest
  AppApprovalNever
  AppApprovalGranular(
    sandbox_approval~ : Bool,
    rules~ : Bool,
    skill_approval~ : Bool,
    request_permissions~ : Bool,
    mcp_elicitations~ : Bool
  )
} derive(Debug)

///|
pub impl ToJson for AppApprovalPolicy with fn to_json(policy) {
  match policy {
    AppApprovalUntrusted => "untrusted".to_json()
    AppApprovalOnFailure => "on-failure".to_json()
    AppApprovalOnRequest => "on-request".to_json()
    AppApprovalNever => "never".to_json()
    AppApprovalGranular(
      sandbox_approval~,
      rules~,
      skill_approval~,
      request_permissions~,
      mcp_elicitations~
    ) =>
      {
        "granular": {
          "sandbox_approval": sandbox_approval,
          "rules": rules,
          "skill_approval": skill_approval,
          "request_permissions": request_permissions,
          "mcp_elicitations": mcp_elicitations,
        },
      }
  }
}

///|
pub impl FromJson for AppApprovalPolicy with fn from_json(value, path) {
  match value {
    String("untrusted") => AppApprovalUntrusted
    String("on-failure") => AppApprovalOnFailure
    String("on-request") => AppApprovalOnRequest
    String("never") => AppApprovalNever
    {
      "granular": {
        "sandbox_approval": sandbox_approval,
        "rules": rules,
        "skill_approval": skill_approval,
        "request_permissions": request_permissions,
        "mcp_elicitations": mcp_elicitations,
        ..
      },
      ..
    } =>
      AppApprovalGranular(
        sandbox_approval=app_bool(
          sandbox_approval,
          path.add_key("granular").add_key("sandbox_approval"),
        ),
        rules=app_bool(rules, path.add_key("granular").add_key("rules")),
        skill_approval=app_bool(
          skill_approval,
          path.add_key("granular").add_key("skill_approval"),
        ),
        request_permissions=app_bool(
          request_permissions,
          path.add_key("granular").add_key("request_permissions"),
        ),
        mcp_elicitations=app_bool(
          mcp_elicitations,
          path.add_key("granular").add_key("mcp_elicitations"),
        ),
      )
    _ => raise JsonDecodeError((path, "expected approval policy"))
  }
}

///|
pub(all) enum AppApprovalsReviewer {
  AppReviewerUser
  AppReviewerAutoReview
  AppReviewerGuardianSubagent
} derive(Debug)

///|
pub impl ToJson for AppApprovalsReviewer with fn to_json(reviewer) {
  match reviewer {
    AppReviewerUser => "user".to_json()
    AppReviewerAutoReview => "auto_review".to_json()
    AppReviewerGuardianSubagent => "guardian_subagent".to_json()
  }
}

///|
pub impl FromJson for AppApprovalsReviewer with fn from_json(value, path) {
  match value {
    String("user") => AppReviewerUser
    String("auto_review") => AppReviewerAutoReview
    String("guardian_subagent") => AppReviewerGuardianSubagent
    _ => raise JsonDecodeError((path, "expected approvals reviewer"))
  }
}

///|
pub(all) enum AppPersonality {
  AppNoPersonality
  AppFriendlyPersonality
  AppPragmaticPersonality
} derive(Debug)

///|
pub impl ToJson for AppPersonality with fn to_json(personality) {
  match personality {
    AppNoPersonality => "none".to_json()
    AppFriendlyPersonality => "friendly".to_json()
    AppPragmaticPersonality => "pragmatic".to_json()
  }
}

///|
pub(all) enum AppThreadStartSource {
  AppThreadStartup
  AppThreadClear
} derive(Debug)

///|
pub impl ToJson for AppThreadStartSource with fn to_json(source) {
  match source {
    AppThreadStartup => "startup".to_json()
    AppThreadClear => "clear".to_json()
  }
}

///|
pub impl ToJson for SandboxMode with fn to_json(mode) {
  match mode {
    ReadOnly => "read-only".to_json()
    WorkspaceWrite => "workspace-write".to_json()
    DangerFullAccess => "danger-full-access".to_json()
  }
}

///|
pub impl FromJson for SandboxMode with fn from_json(value, path) {
  match value {
    String("read-only") => ReadOnly
    String("workspace-write") => WorkspaceWrite
    String("danger-full-access") => DangerFullAccess
    _ => raise JsonDecodeError((path, "expected sandbox mode"))
  }
}

///|
/// Parameters for the app-server `thread/read` request.
pub struct AppThreadReadParams {
  thread_id : String
  include_turns : Bool
} derive(Debug)

///|
pub fn AppThreadReadParams::new(
  thread_id : String,
  include_turns : Bool,
) -> AppThreadReadParams {
  { thread_id, include_turns }
}

///|
pub impl ToJson for AppThreadReadParams with fn to_json(params) {
  { "threadId": params.thread_id, "includeTurns": params.include_turns }
}

///|
/// Parameters for the app-server `turn/start` request.
pub struct AppTurnStartParams {
  thread_id : String
  input : Array[AppUserInput]
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
} derive(Debug)

///|
pub fn AppTurnStartParams::new(
  thread_id : String,
  input : Array[AppUserInput],
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
) -> AppTurnStartParams {
  {
    thread_id,
    input,
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
pub impl ToJson for AppTurnStartParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "input": params.input,
  }
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  if params.approval_policy is Some(approval_policy) {
    obj.set("approvalPolicy", approval_policy.to_json())
  }
  if params.approvals_reviewer is Some(approvals_reviewer) {
    obj.set("approvalsReviewer", approvals_reviewer.to_json())
  }
  if params.sandbox_policy is Some(sandbox_policy) {
    obj.set("sandboxPolicy", sandbox_policy.to_json())
  }
  if params.model is Some(model) {
    obj.set("model", model.to_json())
  }
  app_put_nullable_string(obj, "serviceTier", params.service_tier)
  if params.effort is Some(effort) {
    obj.set("effort", effort.to_json())
  }
  if params.summary is Some(summary) {
    obj.set("summary", summary.to_json())
  }
  if params.personality is Some(personality) {
    obj.set("personality", personality.to_json())
  }
  if params.output_schema is Some(output_schema) {
    obj.set("outputSchema", output_schema)
  }
  Json::object(obj)
}

///|
pub(all) enum AppUserInput {
  AppInputText(text~ : String)
  AppInputImage(url~ : String)
  AppInputLocalImage(path~ : String)
  AppInputSkill(name~ : String, path~ : String)
  AppInputMention(name~ : String, path~ : String)
} derive(Debug)

///|
pub impl ToJson for AppUserInput with fn to_json(input) {
  match input {
    AppInputText(text~) => { "type": "text", "text": text, "text_elements": [] }
    AppInputImage(url~) => { "type": "image", "url": url }
    AppInputLocalImage(path~) => { "type": "localImage", "path": path }
    AppInputSkill(name~, path~) =>
      { "type": "skill", "name": name, "path": path }
    AppInputMention(name~, path~) =>
      { "type": "mention", "name": name, "path": path }
  }
}

///|
pub(all) enum AppNetworkAccess {
  AppNetworkRestricted
  AppNetworkEnabled
} derive(Debug)

///|
pub impl ToJson for AppNetworkAccess with fn to_json(access) {
  match access {
    AppNetworkRestricted => "restricted".to_json()
    AppNetworkEnabled => "enabled".to_json()
  }
}

///|
pub impl FromJson for AppNetworkAccess with fn from_json(value, path) {
  match value {
    String("restricted") => AppNetworkRestricted
    String("enabled") => AppNetworkEnabled
    _ => raise JsonDecodeError((path, "expected network access"))
  }
}

///|
pub(all) enum AppSandboxPolicy {
  AppDangerFullAccess
  AppReadOnly(network_access~ : Bool)
  AppExternalSandbox(network_access~ : AppNetworkAccess)
  AppWorkspaceWrite(
    writable_roots~ : Array[String],
    network_access~ : Bool,
    exclude_tmpdir_env_var~ : Bool,
    exclude_slash_tmp~ : Bool
  )
} derive(Debug)

///|
pub impl ToJson for AppSandboxPolicy with fn to_json(policy) {
  match policy {
    AppDangerFullAccess => { "type": "dangerFullAccess" }
    AppReadOnly(network_access~) =>
      { "type": "readOnly", "networkAccess": network_access }
    AppExternalSandbox(network_access~) =>
      { "type": "externalSandbox", "networkAccess": network_access }
    AppWorkspaceWrite(
      writable_roots~,
      network_access~,
      exclude_tmpdir_env_var~,
      exclude_slash_tmp~
    ) =>
      {
        "type": "workspaceWrite",
        "writableRoots": writable_roots,
        "networkAccess": network_access,
        "excludeTmpdirEnvVar": exclude_tmpdir_env_var,
        "excludeSlashTmp": exclude_slash_tmp,
      }
  }
}

///|
pub impl FromJson for AppSandboxPolicy with fn from_json(value, path) {
  match value {
    { "type": String("dangerFullAccess"), .. } => AppDangerFullAccess
    { "type": String("readOnly"), "networkAccess": network_access, .. } =>
      AppReadOnly(
        network_access=app_bool(network_access, path.add_key("networkAccess")),
      )
    { "type": String("externalSandbox"), "networkAccess": network_access, .. } =>
      AppExternalSandbox(
        network_access=@json.from_json(
          network_access,
          path=path.add_key("networkAccess"),
        ),
      )
    {
      "type": String("workspaceWrite"),
      "writableRoots": writable_roots,
      "networkAccess": network_access,
      "excludeTmpdirEnvVar": exclude_tmpdir_env_var,
      "excludeSlashTmp": exclude_slash_tmp,
      ..
    } =>
      AppWorkspaceWrite(
        writable_roots=@json.from_json(
          writable_roots,
          path=path.add_key("writableRoots"),
        ),
        network_access=app_bool(network_access, path.add_key("networkAccess")),
        exclude_tmpdir_env_var=app_bool(
          exclude_tmpdir_env_var,
          path.add_key("excludeTmpdirEnvVar"),
        ),
        exclude_slash_tmp=app_bool(
          exclude_slash_tmp,
          path.add_key("excludeSlashTmp"),
        ),
      )
    _ => raise JsonDecodeError((path, "expected sandbox policy"))
  }
}

///|
pub(all) enum AppReasoningEffort {
  AppEffortNone
  AppEffortMinimal
  AppEffortLow
  AppEffortMedium
  AppEffortHigh
  AppEffortXhigh
} derive(Debug)

///|
pub impl ToJson for AppReasoningEffort with fn to_json(effort) {
  match effort {
    AppEffortNone => "none".to_json()
    AppEffortMinimal => "minimal".to_json()
    AppEffortLow => "low".to_json()
    AppEffortMedium => "medium".to_json()
    AppEffortHigh => "high".to_json()
    AppEffortXhigh => "xhigh".to_json()
  }
}

///|
pub impl FromJson for AppReasoningEffort with fn from_json(value, path) {
  match value {
    String("none") => AppEffortNone
    String("minimal") => AppEffortMinimal
    String("low") => AppEffortLow
    String("medium") => AppEffortMedium
    String("high") => AppEffortHigh
    String("xhigh") => AppEffortXhigh
    _ => raise JsonDecodeError((path, "expected reasoning effort"))
  }
}

///|
pub(all) enum AppReasoningSummary {
  AppSummaryAuto
  AppSummaryConcise
  AppSummaryDetailed
  AppSummaryNone
} derive(Debug)

///|
pub impl ToJson for AppReasoningSummary with fn to_json(summary) {
  match summary {
    AppSummaryAuto => "auto".to_json()
    AppSummaryConcise => "concise".to_json()
    AppSummaryDetailed => "detailed".to_json()
    AppSummaryNone => "none".to_json()
  }
}

///|
pub impl FromJson for AppReasoningSummary with fn from_json(value, path) {
  match value {
    String("auto") => AppSummaryAuto
    String("concise") => AppSummaryConcise
    String("detailed") => AppSummaryDetailed
    String("none") => AppSummaryNone
    _ => raise JsonDecodeError((path, "expected reasoning summary"))
  }
}

///|
/// Parameters for the app-server `turn/interrupt` request.
pub struct AppTurnInterruptParams {
  thread_id : String
  turn_id : String
} derive(Debug)

///|
pub fn AppTurnInterruptParams::new(
  thread_id : String,
  turn_id : String,
) -> AppTurnInterruptParams {
  { thread_id, turn_id }
}

///|
pub impl ToJson for AppTurnInterruptParams with fn to_json(params) {
  { "threadId": params.thread_id, "turnId": params.turn_id }
}

///|
/// Call `model/list`.
pub async fn CodexAppConnection::model_list(
  self : CodexAppConnection,
  params? : AppModelListParams,
) -> AppModelListResponse {
  let params = match params {
    Some(params) => params
    None => AppModelListParams::new()
  }
  @json.from_json(self.call_raw("model/list", params=params.to_json()))
}

///|
pub struct AppModelListResponse {
  data : ArrayView[AppModel]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppModelListResponse with fn from_json(value, path) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected model/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub struct AppModel {
  id : String
  model : String
  upgrade : String?
  upgrade_info : AppModelUpgradeInfo?
  availability_nux : AppModelAvailabilityNux?
  display_name : String
  description : String
  hidden : Bool
  supported_reasoning_efforts : ArrayView[AppReasoningEffortOption]
  default_reasoning_effort : AppReasoningEffort
  input_modalities : ArrayView[AppInputModality]
  supports_personality : Bool
  additional_speed_tiers : ArrayView[String]
  service_tiers : ArrayView[AppModelServiceTier]
  is_default : Bool
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppModel with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "model": String(model),
      "upgrade"? : upgrade,
      "upgradeInfo"? : upgrade_info,
      "availabilityNux"? : availability_nux,
      "displayName": String(display_name),
      "description": String(description),
      "hidden": hidden,
      "supportedReasoningEfforts": supported_reasoning_efforts,
      "defaultReasoningEffort": default_reasoning_effort,
      "inputModalities"? : input_modalities,
      "supportsPersonality"? : supports_personality,
      "additionalSpeedTiers"? : additional_speed_tiers,
      "serviceTiers"? : service_tiers,
      "isDefault": is_default,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server Model"))
  }
  {
    id,
    model,
    upgrade: app_optional_string(upgrade, path.add_key("upgrade")),
    upgrade_info: match upgrade_info {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("upgradeInfo")))
    },
    availability_nux: match availability_nux {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("availabilityNux")))
    },
    display_name,
    description,
    hidden: app_bool(hidden, path.add_key("hidden")),
    supported_reasoning_efforts: @json.from_json(
      supported_reasoning_efforts,
      path=path.add_key("supportedReasoningEfforts"),
    ),
    default_reasoning_effort: @json.from_json(
      default_reasoning_effort,
      path=path.add_key("defaultReasoningEffort"),
    ),
    input_modalities: match input_modalities {
      Some(value) =>
        @json.from_json(value, path=path.add_key("inputModalities"))
      None =>
        @json.from_json(
          Json::array([Json::string("text"), Json::string("image")]),
          path=path.add_key("inputModalities"),
        )
    },
    supports_personality: match supports_personality {
      Some(value) => app_bool(value, path.add_key("supportsPersonality"))
      None => false
    },
    additional_speed_tiers: match additional_speed_tiers {
      Some(value) =>
        @json.from_json(value, path=path.add_key("additionalSpeedTiers"))
      None =>
        @json.from_json(
          Json::array([]),
          path=path.add_key("additionalSpeedTiers"),
        )
    },
    service_tiers: match service_tiers {
      Some(value) => @json.from_json(value, path=path.add_key("serviceTiers"))
      None =>
        @json.from_json(Json::array([]), path=path.add_key("serviceTiers"))
    },
    is_default: app_bool(is_default, path.add_key("isDefault")),
    raw: value,
  }
}

///|
pub struct AppModelUpgradeInfo {
  model : String
  upgrade_copy : String?
  model_link : String?
  migration_markdown : String?
} derive(Debug)

///|
pub impl FromJson for AppModelUpgradeInfo with fn from_json(value, path) {
  guard value
    is {
      "model": String(model),
      "upgradeCopy"? : upgrade_copy,
      "modelLink"? : model_link,
      "migrationMarkdown"? : migration_markdown,
      ..
    } else {
    raise JsonDecodeError((path, "expected model upgrade info"))
  }
  {
    model,
    upgrade_copy: app_optional_string(upgrade_copy, path.add_key("upgradeCopy")),
    model_link: app_optional_string(model_link, path.add_key("modelLink")),
    migration_markdown: app_optional_string(
      migration_markdown,
      path.add_key("migrationMarkdown"),
    ),
  }
}

///|
pub struct AppModelAvailabilityNux {
  message : String
} derive(Debug)

///|
pub impl FromJson for AppModelAvailabilityNux with fn from_json(value, path) {
  guard value is { "message": String(message), .. } else {
    raise JsonDecodeError((path, "expected model availability nux"))
  }
  { message, }
}

///|
pub struct AppModelServiceTier {
  id : String
  name : String
  description : String
} derive(Debug)

///|
pub impl FromJson for AppModelServiceTier with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "description": String(description),
      ..
    } else {
    raise JsonDecodeError((path, "expected model service tier"))
  }
  { id, name, description }
}

///|
pub struct AppReasoningEffortOption {
  reasoning_effort : AppReasoningEffort
  description : String
} derive(Debug)

///|
pub impl FromJson for AppReasoningEffortOption with fn from_json(value, path) {
  guard value
    is {
      "reasoningEffort": reasoning_effort,
      "description": String(description),
      ..
    } else {
    raise JsonDecodeError((path, "expected reasoning effort option"))
  }
  {
    reasoning_effort: @json.from_json(
      reasoning_effort,
      path=path.add_key("reasoningEffort"),
    ),
    description,
  }
}

///|
pub(all) enum AppInputModality {
  AppTextModality
  AppImageModality
} derive(Debug)

///|
pub impl FromJson for AppInputModality with fn from_json(value, path) {
  match value {
    String("text") => AppTextModality
    String("image") => AppImageModality
    _ => raise JsonDecodeError((path, "expected input modality"))
  }
}

///|
/// Parameters for the app-server `model/list` request.
pub struct AppModelListParams {
  /// Opaque pagination cursor returned by a previous call.
  cursor : String?
  /// Optional page size; defaults to a server-side value.
  limit : UInt?
  /// Include models hidden from the default picker list.
  include_hidden : Bool?
} derive(Debug)

///|
pub fn AppModelListParams::new(
  cursor? : String,
  limit? : UInt,
  include_hidden? : Bool,
) -> AppModelListParams {
  { cursor, limit, include_hidden }
}

///|
pub impl ToJson for AppModelListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cursor is Some(cursor) {
    obj.set("cursor", cursor.to_json())
  }
  if params.limit is Some(limit) {
    obj.set("limit", limit.to_json())
  }
  if params.include_hidden is Some(include_hidden) {
    obj.set("includeHidden", include_hidden.to_json())
  }
  Json::object(obj)
}

///|
/// Send one app-server JSON-RPC notification.
async fn CodexAppConnection::notify(
  self : CodexAppConnection,
  rpc_method : String,
  params? : Json,
) -> Unit {
  self.send(AppClientMessage::ClientNotification(rpc_method~, params~))
}

///|
/// Handle the next server-initiated JSON-RPC request.
///
/// If the handler returns normally, the SDK sends the JSON-RPC response. If the
/// handler raises, the SDK catches the error and sends a JSON-RPC error response.
async fn CodexAppConnection::handle_next_request(
  self : CodexAppConnection,
  handler : async (AppServerRequest) -> AppServerResponse,
) -> Bool {
  match self.next_request() {
    Some(request) => {
      self.handle_request(request, handler)
      true
    }
    None => false
  }
}

///|
async fn CodexAppConnection::handle_request(
  self : CodexAppConnection,
  request : AppServerRequest,
  handler : async (AppServerRequest) -> AppServerResponse,
) -> Unit {
  let id = request.id
  let result = handler(request) catch {
    e => {
      self.respond_error(id, {
        code: -32603,
        message: "App-server request handler failed: \{e}",
        data: None,
      })
      return
    }
  }
  self.respond(id, result.to_json())
}

///|
/// Serve server-initiated app-server requests until the connection closes.
///
/// This is intended for long-running app-server sessions that also consume
/// notifications through `next_event`. The handler may raise; raised errors are
/// caught by `handle_request` and sent back as JSON-RPC error responses.
async fn CodexAppConnection::serve_requests(
  self : CodexAppConnection,
  handler : async (AppServerRequest) -> AppServerResponse,
) -> Unit {
  while self.handle_next_request(handler) {
    ()
  }
}

///|
/// Server-initiated app-server request.
pub struct AppServerRequest {
  priv id : AppRequestId
  details : AppServerRequestDetails
} derive(Debug)

///|
pub enum AppServerRequestDetails {
  AppCommandExecutionApprovalRequest(AppCommandExecutionApprovalRequest)
  AppFileChangeApprovalRequest(AppFileChangeApprovalRequest)
  AppToolRequestUserInputRequest(AppToolRequestUserInputRequest)
  AppDynamicToolCallRequest(AppDynamicToolCallRequest)
  AppPermissionsRequestApprovalRequest(AppPermissionsRequestApprovalRequest)
  AppChatgptAuthTokensRefreshRequest(AppChatgptAuthTokensRefreshRequest)
  AppMcpServerElicitationRequest(AppMcpServerElicitationRequest)
} derive(Debug)

///|
pub(all) enum AppServerResponse {
  AppCommandExecutionApprovalResponse(
    decision~ : AppCommandExecutionApprovalDecision
  )
  AppFileChangeApprovalResponse(decision~ : AppFileChangeApprovalDecision)
  AppToolRequestUserInputResponse(
    answers~ : Map[String, AppToolRequestUserInputAnswer]
  )
  AppDynamicToolCallResponse(
    content_items~ : ArrayView[AppDynamicToolCallOutputContentItem],
    success~ : Bool
  )
  AppPermissionsRequestApprovalResponse(
    permissions~ : AppGrantedPermissionProfile,
    scope~ : AppPermissionGrantScope,
    strict_auto_review~ : Bool?
  )
  AppChatgptAuthTokensRefreshResponse(
    access_token~ : String,
    chatgpt_account_id~ : String,
    chatgpt_plan_type~ : String?
  )
  AppMcpServerElicitationResponse(
    action~ : AppMcpServerElicitationAction,
    content~ : Json?,
    meta~ : Json?
  )
} derive(Debug)

///|
pub impl ToJson for AppServerResponse with fn to_json(response) {
  match response {
    AppCommandExecutionApprovalResponse(decision~) => { "decision": decision }
    AppFileChangeApprovalResponse(decision~) => { "decision": decision }
    AppToolRequestUserInputResponse(answers~) => { "answers": answers }
    AppDynamicToolCallResponse(content_items~, success~) =>
      { "contentItems": content_items, "success": success }
    AppPermissionsRequestApprovalResponse(
      permissions~,
      scope~,
      strict_auto_review~
    ) => {
      let obj : Map[String, Json] = {
        "permissions": permissions.to_json(),
        "scope": scope.to_json(),
      }
      app_put_bool(obj, "strictAutoReview", strict_auto_review)
      Json::object(obj)
    }
    AppChatgptAuthTokensRefreshResponse(
      access_token~,
      chatgpt_account_id~,
      chatgpt_plan_type~
    ) =>
      {
        "accessToken": access_token,
        "chatgptAccountId": chatgpt_account_id,
        "chatgptPlanType": match chatgpt_plan_type {
          Some(value) => value.to_json()
          None => Json::null()
        },
      }
    AppMcpServerElicitationResponse(action~, content~, meta~) =>
      {
        "action": action.to_json(),
        "content": match content {
          Some(value) => value
          None => Json::null()
        },
        "_meta": match meta {
          Some(value) => value
          None => Json::null()
        },
      }
  }
}

///|
pub(all) struct AppCommandExecutionApprovalRequest {
  thread_id : String
  turn_id : String
  item_id : String
  started_at_ms : Int64
  approval_id : String?
  reason : String?
  network_approval_context : AppNetworkApprovalContext?
  command : String?
  cwd : String?
  command_actions : ArrayView[AppCommandAction]?
  proposed_execpolicy_amendment : ArrayView[String]?
  proposed_network_policy_amendments : ArrayView[AppNetworkPolicyAmendment]?
  priv raw : Json
} derive(Debug)

///|
pub enum AppNetworkApprovalProtocol {
  AppNetworkApprovalHttp
  AppNetworkApprovalHttps
  AppNetworkApprovalSocks5Tcp
  AppNetworkApprovalSocks5Udp
} derive(Debug)

///|
pub impl FromJson for AppNetworkApprovalProtocol with fn from_json(value, path) {
  match value {
    String("http") => AppNetworkApprovalHttp
    String("https") => AppNetworkApprovalHttps
    String("socks5Tcp") => AppNetworkApprovalSocks5Tcp
    String("socks5Udp") => AppNetworkApprovalSocks5Udp
    _ => raise JsonDecodeError((path, "expected network approval protocol"))
  }
}

///|
pub struct AppNetworkApprovalContext {
  host : String
  protocol : AppNetworkApprovalProtocol
} derive(Debug)

///|
pub impl FromJson for AppNetworkApprovalContext with fn from_json(value, path) {
  guard value is { "host": String(host), "protocol": protocol, .. } else {
    raise JsonDecodeError((path, "expected network approval context"))
  }
  { host, protocol: @json.from_json(protocol, path=path.add_key("protocol")) }
}

///|
pub enum AppCommandAction {
  AppCommandReadAction(command~ : String, name~ : String, path~ : String)
  AppCommandListFilesAction(command~ : String, path~ : String?)
  AppCommandSearchAction(command~ : String, query~ : String?, path~ : String?)
  AppCommandUnknownAction(command~ : String)
} derive(Debug)

///|
pub impl FromJson for AppCommandAction with fn from_json(value, path) {
  guard value is { "type": String(action_type), "command": String(command), .. } else {
    raise JsonDecodeError((path, "expected command action"))
  }
  match action_type {
    "read" => {
      guard value is { "name": String(name), "path": String(action_path), .. } else {
        raise JsonDecodeError((path, "expected read command action"))
      }
      AppCommandReadAction(command~, name~, path=action_path)
    }
    "listFiles" => {
      guard value is { "path"? : action_path, .. } else {
        raise JsonDecodeError((path, "expected listFiles command action"))
      }
      AppCommandListFilesAction(
        command~,
        path=app_optional_string(action_path, path.add_key("path")),
      )
    }
    "search" => {
      guard value is { "query"? : query, "path"? : action_path, .. } else {
        raise JsonDecodeError((path, "expected search command action"))
      }
      AppCommandSearchAction(
        command~,
        query=app_optional_string(query, path.add_key("query")),
        path=app_optional_string(action_path, path.add_key("path")),
      )
    }
    "unknown" => AppCommandUnknownAction(command~)
    _ => raise JsonDecodeError((path, "expected command action type"))
  }
}

///|
pub impl FromJson for AppCommandExecutionApprovalRequest with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId": String(turn_id),
      "itemId": String(item_id),
      "startedAtMs": Number(started_at_ms, ..),
      "approvalId"? : approval_id,
      "reason"? : reason,
      "networkApprovalContext"? : network_approval_context,
      "command"? : command,
      "cwd"? : cwd,
      "commandActions"? : command_actions,
      "proposedExecpolicyAmendment"? : proposed_execpolicy_amendment,
      "proposedNetworkPolicyAmendments"? : proposed_network_policy_amendments,
      ..
    } else {
    raise JsonDecodeError((path, "expected command execution approval request"))
  }
  {
    thread_id,
    turn_id,
    item_id,
    started_at_ms: started_at_ms.to_int64(),
    approval_id: app_optional_string(approval_id, path.add_key("approvalId")),
    reason: app_optional_string(reason, path.add_key("reason")),
    network_approval_context: match network_approval_context {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("networkApprovalContext")),
        )
    },
    command: app_optional_string(command, path.add_key("command")),
    cwd: app_optional_string(cwd, path.add_key("cwd")),
    command_actions: match command_actions {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("commandActions")))
    },
    proposed_execpolicy_amendment: match proposed_execpolicy_amendment {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(
            value,
            path=path.add_key("proposedExecpolicyAmendment"),
          ),
        )
    },
    proposed_network_policy_amendments: match
      proposed_network_policy_amendments {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(
            value,
            path=path.add_key("proposedNetworkPolicyAmendments"),
          ),
        )
    },
    raw: value,
  }
}

///|
pub(all) enum AppCommandExecutionApprovalDecision {
  AppCommandAccept
  AppCommandAcceptForSession
  AppCommandDecline
  AppCommandCancel
  AppCommandAcceptWithExecpolicyAmendment(ArrayView[String])
  AppCommandApplyNetworkPolicyAmendment(AppNetworkPolicyAmendment)
} derive(Debug)

///|
pub(all) enum AppNetworkPolicyRuleAction {
  AppNetworkPolicyAllow
  AppNetworkPolicyDeny
} derive(Debug)

///|
pub impl ToJson for AppNetworkPolicyRuleAction with fn to_json(action) {
  match action {
    AppNetworkPolicyAllow => "allow".to_json()
    AppNetworkPolicyDeny => "deny".to_json()
  }
}

///|
pub impl FromJson for AppNetworkPolicyRuleAction with fn from_json(value, path) {
  match value {
    String("allow") => AppNetworkPolicyAllow
    String("deny") => AppNetworkPolicyDeny
    _ => raise JsonDecodeError((path, "expected network policy rule action"))
  }
}

///|
pub(all) struct AppNetworkPolicyAmendment {
  host : String
  action : AppNetworkPolicyRuleAction
} derive(Debug)

///|
pub impl ToJson for AppNetworkPolicyAmendment with fn to_json(amendment) {
  { "host": amendment.host, "action": amendment.action }
}

///|
pub impl FromJson for AppNetworkPolicyAmendment with fn from_json(value, path) {
  guard value is { "host": String(host), "action": action, .. } else {
    raise JsonDecodeError((path, "expected network policy amendment"))
  }
  { host, action: @json.from_json(action, path=path.add_key("action")) }
}

///|
pub impl ToJson for AppCommandExecutionApprovalDecision with fn to_json(
  decision,
) {
  match decision {
    AppCommandAccept => "accept".to_json()
    AppCommandAcceptForSession => "acceptForSession".to_json()
    AppCommandDecline => "decline".to_json()
    AppCommandCancel => "cancel".to_json()
    AppCommandAcceptWithExecpolicyAmendment(amendment) =>
      { "acceptWithExecpolicyAmendment": { "execpolicy_amendment": amendment } }
    AppCommandApplyNetworkPolicyAmendment(amendment) =>
      {
        "applyNetworkPolicyAmendment": { "network_policy_amendment": amendment },
      }
  }
}

///|
pub(all) struct AppFileChangeApprovalRequest {
  thread_id : String
  turn_id : String
  item_id : String
  started_at_ms : Int64
  reason : String?
  grant_root : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppFileChangeApprovalRequest with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId": String(turn_id),
      "itemId": String(item_id),
      "startedAtMs": Number(started_at_ms, ..),
      "reason"? : reason,
      "grantRoot"? : grant_root,
      ..
    } else {
    raise JsonDecodeError((path, "expected file change approval request"))
  }
  {
    thread_id,
    turn_id,
    item_id,
    started_at_ms: started_at_ms.to_int64(),
    reason: app_optional_string(reason, path.add_key("reason")),
    grant_root: app_optional_string(grant_root, path.add_key("grantRoot")),
    raw: value,
  }
}

///|
pub(all) enum AppFileChangeApprovalDecision {
  AppFileChangeAccept
  AppFileChangeAcceptForSession
  AppFileChangeDecline
  AppFileChangeCancel
} derive(Debug)

///|
pub impl ToJson for AppFileChangeApprovalDecision with fn to_json(decision) {
  match decision {
    AppFileChangeAccept => "accept".to_json()
    AppFileChangeAcceptForSession => "acceptForSession".to_json()
    AppFileChangeDecline => "decline".to_json()
    AppFileChangeCancel => "cancel".to_json()
  }
}

///|
pub(all) struct AppToolRequestUserInputRequest {
  thread_id : String
  turn_id : String
  item_id : String
  questions : ArrayView[AppToolRequestUserInputQuestion]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppToolRequestUserInputRequest with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId": String(turn_id),
      "itemId": String(item_id),
      "questions": questions,
      ..
    } else {
    raise JsonDecodeError((path, "expected tool user-input request"))
  }
  {
    thread_id,
    turn_id,
    item_id,
    questions: @json.from_json(questions, path=path.add_key("questions")),
    raw: value,
  }
}

///|
pub(all) struct AppDynamicToolCallRequest {
  thread_id : String
  turn_id : String
  call_id : String
  tool_namespace : String?
  tool : String
  arguments : Json
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppDynamicToolCallRequest with fn from_json(value, path) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId": String(turn_id),
      "callId": String(call_id),
      "namespace"? : tool_namespace,
      "tool": String(tool),
      "arguments": arguments,
      ..
    } else {
    raise JsonDecodeError((path, "expected dynamic tool call request"))
  }
  {
    thread_id,
    turn_id,
    call_id,
    tool_namespace: app_optional_string(
      tool_namespace,
      path.add_key("namespace"),
    ),
    tool,
    arguments,
    raw: value,
  }
}

///|
pub(all) struct AppToolRequestUserInputQuestion {
  id : String
  header : String
  question : String
  is_other : Bool
  is_secret : Bool
  options : ArrayView[AppToolRequestUserInputOption]?
} derive(Debug)

///|
pub impl FromJson for AppToolRequestUserInputQuestion with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "id": String(id),
      "header": String(header),
      "question": String(question),
      "isOther": is_other,
      "isSecret": is_secret,
      "options"? : options,
      ..
    } else {
    raise JsonDecodeError((path, "expected tool user-input question"))
  }
  {
    id,
    header,
    question,
    is_other: app_bool(is_other, path.add_key("isOther")),
    is_secret: app_bool(is_secret, path.add_key("isSecret")),
    options: match options {
      Some(Null) | None => None
      Some(options) =>
        Some(@json.from_json(options, path=path.add_key("options")))
    },
  }
}

///|
pub(all) struct AppToolRequestUserInputOption {
  label : String
  description : String
} derive(Debug, FromJson)

///|
pub(all) struct AppToolRequestUserInputAnswer {
  answers : ArrayView[String]
} derive(Debug, ToJson)

///|
/// Respond to a server-initiated JSON-RPC request.
async fn CodexAppConnection::respond(
  self : CodexAppConnection,
  id : AppRequestId,
  result : Json,
) -> Unit {
  self.send(AppClientMessage::ClientResponse(id~, result~))
}

///|
/// Send an error response to a server-initiated JSON-RPC request.
async fn CodexAppConnection::respond_error(
  self : CodexAppConnection,
  id : AppRequestId,
  error : AppRpcError,
) -> Unit {
  self.send(AppClientMessage::ClientErrorResponse(id~, error~))
}

///|
/// Send one client JSON-RPC frame to the app server.
async fn CodexAppConnection::send(
  self : CodexAppConnection,
  message : AppClientMessage,
) -> Unit {
  self.outgoing.put(message.to_json())
}

///|
/// Receive the next server notification from the app server.
pub async fn CodexAppConnection::next_event(
  self : CodexAppConnection,
) -> AppServerEvent? {
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
    AppQueuedEvent(event) => Some(event)
    AppQueuedClosed => {
      self.events_closed = true
      None
    }
  }
}

///|
async fn CodexAppConnection::next_request(
  self : CodexAppConnection,
) -> AppServerRequest? {
  let request = self.requests.get() catch { _ => return None }
  Some(request)
}

///|
/// Close the send channel. The app-server process exits after stdin closes.
fn CodexAppConnection::close(self : CodexAppConnection) -> Unit {
  self.outgoing.close(clear=true)
  self.close_pending_requests()
}

///|
/// JSON-RPC request id used by the Codex app server protocol.
pub enum AppRequestId {
  StringId(String)
  IntId(Int64)
} derive(Debug, Eq)

///|
pub impl ToJson for AppRequestId with fn to_json(id) {
  match id {
    StringId(value) => value.to_json()
    IntId(value) => Json::number(value.to_double())
  }
}

///|
pub impl FromJson for AppRequestId with fn from_json(value, path) {
  match value {
    String(value) => StringId(value)
    Number(value, ..) => IntId(value.to_int64())
    _ =>
      raise JsonDecodeError(
        (
          path, "expected string or integer request id, got \\{value.stringify()}",
        ),
      )
  }
}

///|
priv struct AppRpcError {
  code : Int64
  message : String
  data : Json?
}

///|
impl ToJson for AppRpcError with fn to_json(error) {
  let obj : Map[String, Json] = {
    "code": Json::number(error.code.to_double()),
    "message": error.message,
  }
  if error.data is Some(data) {
    obj.set("data", data)
  }
  Json::object(obj)
}

///|
impl FromJson for AppRpcError with fn from_json(value, path) {
  guard value
    is {
      "code": Number(code, ..),
      "message": String(message),
      "data"? : data,
      ..
    } else {
    raise JsonDecodeError((path, "expected JSON-RPC error object"))
  }
  { code: code.to_int64(), message, data }
}

///|
fn format_app_rpc_error(error : AppRpcError) -> String {
  match error.data {
    Some(data) =>
      "Codex app server error \{error.code}: \{error.message}; data=\{data.stringify()}"
    None => "Codex app server error \{error.code}: \{error.message}"
  }
}

///|
fn app_put_string(
  obj : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
pub(all) enum AppNullableString {
  AppNullableStringNull
  AppNullableStringValue(String)
} derive(Debug)

///|
pub impl ToJson for AppNullableString with fn to_json(value) {
  match value {
    AppNullableStringNull => Json::null()
    AppNullableStringValue(value) => value.to_json()
  }
}

///|
fn app_put_nullable_string(
  obj : Map[String, Json],
  key : String,
  value : AppNullableString?,
) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
fn app_env_to_json(env : Map[String, String?]) -> Json {
  let obj : Map[String, Json] = {}
  for key, value in env {
    match value {
      Some(value) => obj.set(key, value.to_json())
      None => obj.set(key, Json::null())
    }
  }
  Json::object(obj)
}

///|
fn app_put_bool(obj : Map[String, Json], key : String, value : Bool?) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
fn app_put_true(obj : Map[String, Json], key : String, value : Bool?) -> Unit {
  if value is Some(true) {
    obj.set(key, true.to_json())
  }
}

///|
fn app_put_uint(obj : Map[String, Json], key : String, value : UInt?) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
fn app_put_int64(obj : Map[String, Json], key : String, value : Int64?) -> Unit {
  if value is Some(value) {
    obj.set(key, Json::number(value.to_double()))
  }
}

///|
fn app_put_uint64(
  obj : Map[String, Json],
  key : String,
  value : UInt64?,
) -> Unit {
  if value is Some(value) {
    obj.set(key, Json::number(value.to_double()))
  }
}

///|
fn app_put_json(obj : Map[String, Json], key : String, value : Json?) -> Unit {
  if value is Some(value) {
    obj.set(key, value)
  }
}

///|
fn app_put_strings(
  obj : Map[String, Json],
  key : String,
  value : Array[String]?,
) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
pub(all) struct AppClientInfo {
  name : String
  title : String?
  version : String
} derive(Debug)

///|
pub impl ToJson for AppClientInfo with fn to_json(info) {
  let obj : Map[String, Json] = { "name": info.name, "version": info.version }
  app_put_string(obj, "title", info.title)
  Json::object(obj)
}

///|
pub(all) struct AppInitializeCapabilities {
  experimental_api : Bool
  opt_out_notification_methods : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppInitializeCapabilities with fn to_json(capabilities) {
  let obj : Map[String, Json] = {
    "experimentalApi": capabilities.experimental_api,
  }
  app_put_strings(
    obj,
    "optOutNotificationMethods",
    capabilities.opt_out_notification_methods,
  )
  Json::object(obj)
}

///|
pub(all) struct AppInitializeParams {
  client_info : AppClientInfo
  capabilities : AppInitializeCapabilities?
} derive(Debug)

///|
pub impl ToJson for AppInitializeParams with fn to_json(params) {
  let obj : Map[String, Json] = { "clientInfo": params.client_info }
  match params.capabilities {
    Some(capabilities) => obj.set("capabilities", capabilities.to_json())
    None => obj.set("capabilities", Json::null())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadForkParams {
  thread_id : String
  model : String?
  model_provider : String?
  service_tier : AppNullableString?
  cwd : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox : SandboxMode?
  config : Map[String, Json]?
  base_instructions : String?
  developer_instructions : String?
  ephemeral : Bool?
} derive(Debug)

///|
pub impl ToJson for AppThreadForkParams with fn to_json(params) {
  let obj : Map[String, Json] = { "threadId": params.thread_id }
  app_put_string(obj, "model", params.model)
  app_put_string(obj, "modelProvider", params.model_provider)
  app_put_nullable_string(obj, "serviceTier", params.service_tier)
  app_put_string(obj, "cwd", params.cwd)
  if params.approval_policy is Some(value) {
    obj.set("approvalPolicy", value.to_json())
  }
  if params.approvals_reviewer is Some(value) {
    obj.set("approvalsReviewer", value.to_json())
  }
  if params.sandbox is Some(value) {
    obj.set("sandbox", value.to_json())
  }
  if params.config is Some(value) {
    obj.set("config", value.to_json())
  }
  app_put_string(obj, "baseInstructions", params.base_instructions)
  app_put_string(obj, "developerInstructions", params.developer_instructions)
  app_put_true(obj, "ephemeral", params.ephemeral)
  Json::object(obj)
}

///|
pub(all) struct AppThreadMetadataGitInfoUpdateParams {
  sha : AppNullableString?
  branch : AppNullableString?
  origin_url : AppNullableString?
} derive(Debug)

///|
pub impl ToJson for AppThreadMetadataGitInfoUpdateParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_nullable_string(obj, "sha", params.sha)
  app_put_nullable_string(obj, "branch", params.branch)
  app_put_nullable_string(obj, "originUrl", params.origin_url)
  Json::object(obj)
}

///|
pub(all) struct AppThreadMetadataUpdateParams {
  thread_id : String
  git_info : AppThreadMetadataGitInfoUpdateParams?
} derive(Debug)

///|
pub impl ToJson for AppThreadMetadataUpdateParams with fn to_json(params) {
  let obj : Map[String, Json] = { "threadId": params.thread_id }
  if params.git_info is Some(value) {
    obj.set("gitInfo", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadShellCommandParams {
  thread_id : String
  command : String
} derive(Debug)

///|
pub impl ToJson for AppThreadShellCommandParams with fn to_json(params) {
  { "threadId": params.thread_id, "command": params.command }
}

///|
pub(all) struct AppThreadApproveGuardianDeniedActionParams {
  thread_id : String
  event : Json
} derive(Debug)

///|
pub impl ToJson for AppThreadApproveGuardianDeniedActionParams with fn to_json(
  params,
) {
  { "threadId": params.thread_id, "event": params.event }
}

///|
pub(all) struct AppThreadRollbackParams {
  thread_id : String
  num_turns : UInt
} derive(Debug)

///|
pub impl ToJson for AppThreadRollbackParams with fn to_json(params) {
  { "threadId": params.thread_id, "numTurns": params.num_turns }
}

///|
pub(all) struct AppThreadInjectItemsParams {
  thread_id : String
  items : Array[Json]
} derive(Debug)

///|
pub impl ToJson for AppThreadInjectItemsParams with fn to_json(params) {
  { "threadId": params.thread_id, "items": params.items }
}

///|
pub(all) struct AppHooksListParams {
  cwds : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppHooksListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_strings(obj, "cwds", params.cwds)
  Json::object(obj)
}

///|
pub(all) struct AppMarketplaceAddParams {
  source : String
  ref_name : String?
  sparse_paths : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppMarketplaceAddParams with fn to_json(params) {
  let obj : Map[String, Json] = { "source": params.source }
  app_put_string(obj, "refName", params.ref_name)
  app_put_strings(obj, "sparsePaths", params.sparse_paths)
  Json::object(obj)
}

///|
pub(all) struct AppMarketplaceRemoveParams {
  marketplace_name : String
} derive(Debug)

///|
pub impl ToJson for AppMarketplaceRemoveParams with fn to_json(params) {
  { "marketplaceName": params.marketplace_name }
}

///|
pub(all) struct AppMarketplaceUpgradeParams {
  marketplace_name : String?
} derive(Debug)

///|
pub impl ToJson for AppMarketplaceUpgradeParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "marketplaceName", params.marketplace_name)
  Json::object(obj)
}

///|
pub(all) enum AppPluginListMarketplaceKind {
  AppPluginMarketplaceLocal
  AppPluginMarketplaceWorkspaceDirectory
  AppPluginMarketplaceSharedWithMe
} derive(Debug)

///|
pub impl ToJson for AppPluginListMarketplaceKind with fn to_json(kind) {
  match kind {
    AppPluginMarketplaceLocal => "local".to_json()
    AppPluginMarketplaceWorkspaceDirectory => "workspace-directory".to_json()
    AppPluginMarketplaceSharedWithMe => "shared-with-me".to_json()
  }
}

///|
pub(all) struct AppPluginListParams {
  cwds : Array[String]?
  marketplace_kinds : Array[AppPluginListMarketplaceKind]?
} derive(Debug)

///|
pub impl ToJson for AppPluginListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_strings(obj, "cwds", params.cwds)
  if params.marketplace_kinds is Some(value) {
    obj.set("marketplaceKinds", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppPluginReadParams {
  marketplace_path : String?
  remote_marketplace_name : String?
  plugin_name : String
} derive(Debug)

///|
pub impl ToJson for AppPluginReadParams with fn to_json(params) {
  let obj : Map[String, Json] = { "pluginName": params.plugin_name }
  app_put_string(obj, "marketplacePath", params.marketplace_path)
  app_put_string(obj, "remoteMarketplaceName", params.remote_marketplace_name)
  Json::object(obj)
}

///|
pub(all) struct AppFsPathParams {
  path : String
} derive(Debug)

///|
pub impl ToJson for AppFsPathParams with fn to_json(params) {
  { "path": params.path }
}

///|
pub(all) struct AppFsWriteFileParams {
  path : String
  data_base64 : String
} derive(Debug)

///|
pub impl ToJson for AppFsWriteFileParams with fn to_json(params) {
  { "path": params.path, "dataBase64": params.data_base64 }
}

///|
pub(all) struct AppFsCreateDirectoryParams {
  path : String
  recursive : Bool?
} derive(Debug)

///|
pub impl ToJson for AppFsCreateDirectoryParams with fn to_json(params) {
  let obj : Map[String, Json] = { "path": params.path }
  app_put_bool(obj, "recursive", params.recursive)
  Json::object(obj)
}

///|
pub(all) struct AppFsRemoveParams {
  path : String
  recursive : Bool?
  force : Bool?
} derive(Debug)

///|
pub impl ToJson for AppFsRemoveParams with fn to_json(params) {
  let obj : Map[String, Json] = { "path": params.path }
  app_put_bool(obj, "recursive", params.recursive)
  app_put_bool(obj, "force", params.force)
  Json::object(obj)
}

///|
pub(all) struct AppFsCopyParams {
  source_path : String
  destination_path : String
  recursive : Bool?
} derive(Debug)

///|
pub impl ToJson for AppFsCopyParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "sourcePath": params.source_path,
    "destinationPath": params.destination_path,
  }
  app_put_true(obj, "recursive", params.recursive)
  Json::object(obj)
}

///|
pub(all) struct AppFsWatchParams {
  watch_id : String
  path : String
} derive(Debug)

///|
pub impl ToJson for AppFsWatchParams with fn to_json(params) {
  { "watchId": params.watch_id, "path": params.path }
}

///|
pub(all) struct AppFsUnwatchParams {
  watch_id : String
} derive(Debug)

///|
pub impl ToJson for AppFsUnwatchParams with fn to_json(params) {
  { "watchId": params.watch_id }
}

///|
pub(all) struct AppSkillsConfigWriteParams {
  path : String?
  name : String?
  enabled : Bool
} derive(Debug)

///|
pub impl ToJson for AppSkillsConfigWriteParams with fn to_json(params) {
  let obj : Map[String, Json] = { "enabled": params.enabled }
  app_put_string(obj, "path", params.path)
  app_put_string(obj, "name", params.name)
  Json::object(obj)
}

///|
pub(all) struct AppPluginInstallParams {
  marketplace_path : String?
  remote_marketplace_name : String?
  plugin_name : String
} derive(Debug)

///|
pub impl ToJson for AppPluginInstallParams with fn to_json(params) {
  let obj : Map[String, Json] = { "pluginName": params.plugin_name }
  app_put_string(obj, "marketplacePath", params.marketplace_path)
  app_put_string(obj, "remoteMarketplaceName", params.remote_marketplace_name)
  Json::object(obj)
}

///|
pub(all) struct AppPluginUninstallParams {
  plugin_id : String
} derive(Debug)

///|
pub impl ToJson for AppPluginUninstallParams with fn to_json(params) {
  { "pluginId": params.plugin_id }
}

///|
pub(all) enum AppReviewTarget {
  AppReviewUncommittedChanges
  AppReviewBaseBranch(branch~ : String)
  AppReviewCommit(sha~ : String, title~ : String?)
  AppReviewCustom(instructions~ : String)
} derive(Debug)

///|
pub impl ToJson for AppReviewTarget with fn to_json(target) {
  match target {
    AppReviewUncommittedChanges => { "type": "uncommittedChanges" }
    AppReviewBaseBranch(branch~) => { "type": "baseBranch", "branch": branch }
    AppReviewCommit(sha~, title~) => {
      let obj : Map[String, Json] = { "type": "commit", "sha": sha }
      match title {
        Some(title) => obj.set("title", title.to_json())
        None => obj.set("title", Json::null())
      }
      Json::object(obj)
    }
    AppReviewCustom(instructions~) =>
      { "type": "custom", "instructions": instructions }
  }
}

///|
pub(all) enum AppReviewDelivery {
  AppReviewInline
  AppReviewDetached
} derive(Debug)

///|
pub impl ToJson for AppReviewDelivery with fn to_json(delivery) {
  match delivery {
    AppReviewInline => "inline".to_json()
    AppReviewDetached => "detached".to_json()
  }
}

///|
pub(all) struct AppReviewStartParams {
  thread_id : String
  target : AppReviewTarget
  delivery : AppReviewDelivery?
} derive(Debug)

///|
pub impl ToJson for AppReviewStartParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "target": params.target,
  }
  if params.delivery is Some(value) {
    obj.set("delivery", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppCursorLimitParams {
  cursor : String?
  limit : UInt?
} derive(Debug)

///|
pub impl ToJson for AppCursorLimitParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "cursor", params.cursor)
  app_put_uint(obj, "limit", params.limit)
  Json::object(obj)
}

///|
pub(all) struct AppExperimentalFeatureEnablementSetParams {
  enablement : Map[String, Bool]
} derive(Debug)

///|
pub impl ToJson for AppExperimentalFeatureEnablementSetParams with fn to_json(
  params,
) {
  { "enablement": params.enablement }
}

///|
pub(all) struct AppMcpServerOauthLoginParams {
  name : String
  scopes : Array[String]?
  timeout_secs : Int64?
} derive(Debug)

///|
pub impl ToJson for AppMcpServerOauthLoginParams with fn to_json(params) {
  let obj : Map[String, Json] = { "name": params.name }
  app_put_strings(obj, "scopes", params.scopes)
  app_put_int64(obj, "timeoutSecs", params.timeout_secs)
  Json::object(obj)
}

///|
pub(all) enum AppMcpServerStatusDetail {
  AppMcpServerStatusFull
  AppMcpServerStatusToolsAndAuthOnly
} derive(Debug)

///|
pub impl ToJson for AppMcpServerStatusDetail with fn to_json(detail) {
  match detail {
    AppMcpServerStatusFull => "full".to_json()
    AppMcpServerStatusToolsAndAuthOnly => "toolsAndAuthOnly".to_json()
  }
}

///|
pub(all) struct AppMcpServerStatusListParams {
  cursor : String?
  limit : UInt?
  detail : AppMcpServerStatusDetail?
} derive(Debug)

///|
pub impl ToJson for AppMcpServerStatusListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "cursor", params.cursor)
  app_put_uint(obj, "limit", params.limit)
  if params.detail is Some(value) {
    obj.set("detail", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppMcpResourceReadParams {
  thread_id : String?
  server : String
  uri : String
} derive(Debug)

///|
pub impl ToJson for AppMcpResourceReadParams with fn to_json(params) {
  let obj : Map[String, Json] = { "server": params.server, "uri": params.uri }
  app_put_string(obj, "threadId", params.thread_id)
  Json::object(obj)
}

///|
pub(all) struct AppMcpServerToolCallParams {
  thread_id : String
  server : String
  tool : String
  arguments : Json?
  meta : Json?
} derive(Debug)

///|
pub impl ToJson for AppMcpServerToolCallParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "server": params.server,
    "tool": params.tool,
  }
  app_put_json(obj, "arguments", params.arguments)
  app_put_json(obj, "_meta", params.meta)
  Json::object(obj)
}

///|
pub(all) enum AppWindowsSandboxSetupMode {
  AppWindowsSandboxElevated
  AppWindowsSandboxUnelevated
} derive(Debug)

///|
pub impl ToJson for AppWindowsSandboxSetupMode with fn to_json(mode) {
  match mode {
    AppWindowsSandboxElevated => "elevated".to_json()
    AppWindowsSandboxUnelevated => "unelevated".to_json()
  }
}

///|
pub impl FromJson for AppWindowsSandboxSetupMode with fn from_json(value, path) {
  match value {
    String("elevated") => AppWindowsSandboxElevated
    String("unelevated") => AppWindowsSandboxUnelevated
    _ => raise JsonDecodeError((path, "expected Windows sandbox setup mode"))
  }
}

///|
pub(all) struct AppWindowsSandboxSetupStartParams {
  mode : AppWindowsSandboxSetupMode
  cwd : String?
} derive(Debug)

///|
pub impl ToJson for AppWindowsSandboxSetupStartParams with fn to_json(params) {
  let obj : Map[String, Json] = { "mode": params.mode }
  app_put_string(obj, "cwd", params.cwd)
  Json::object(obj)
}

///|
pub(all) enum AppLoginAccountParams {
  AppLoginApiKey(api_key~ : String)
  AppLoginChatGPT(codex_streamlined_login~ : Bool?)
  AppLoginChatGPTDeviceCode
  AppLoginChatGPTAuthTokens(
    access_token~ : String,
    chatgpt_account_id~ : String,
    chatgpt_plan_type~ : String?
  )
} derive(Debug)

///|
pub impl ToJson for AppLoginAccountParams with fn to_json(params) {
  match params {
    AppLoginApiKey(api_key~) => { "type": "apiKey", "apiKey": api_key }
    AppLoginChatGPT(codex_streamlined_login~) => {
      let obj : Map[String, Json] = { "type": "chatgpt" }
      app_put_bool(obj, "codexStreamlinedLogin", codex_streamlined_login)
      Json::object(obj)
    }
    AppLoginChatGPTDeviceCode => { "type": "chatgptDeviceCode" }
    AppLoginChatGPTAuthTokens(
      access_token~,
      chatgpt_account_id~,
      chatgpt_plan_type~
    ) => {
      let obj : Map[String, Json] = {
        "type": "chatgptAuthTokens",
        "accessToken": access_token,
        "chatgptAccountId": chatgpt_account_id,
      }
      app_put_string(obj, "chatgptPlanType", chatgpt_plan_type)
      Json::object(obj)
    }
  }
}

///|
pub(all) struct AppCancelLoginAccountParams {
  login_id : String
} derive(Debug)

///|
pub impl ToJson for AppCancelLoginAccountParams with fn to_json(params) {
  { "loginId": params.login_id }
}

///|
pub(all) enum AppAddCreditsNudgeKind {
  AppNudgeCredits
  AppNudgeUsageLimit
} derive(Debug)

///|
pub impl ToJson for AppAddCreditsNudgeKind with fn to_json(kind) {
  match kind {
    AppNudgeCredits => "credits".to_json()
    AppNudgeUsageLimit => "usage_limit".to_json()
  }
}

///|
pub(all) struct AppSendAddCreditsNudgeEmailParams {
  kind : AppAddCreditsNudgeKind
} derive(Debug)

///|
pub impl ToJson for AppSendAddCreditsNudgeEmailParams with fn to_json(params) {
  { "creditType": params.kind }
}

///|
pub(all) struct AppFeedbackUploadParams {
  classification : String
  reason : String?
  thread_id : String?
  include_logs : Bool
  extra_log_files : Array[String]?
  tags : Map[String, String]?
} derive(Debug)

///|
pub impl ToJson for AppFeedbackUploadParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "classification": params.classification,
    "includeLogs": params.include_logs,
  }
  app_put_string(obj, "reason", params.reason)
  app_put_string(obj, "threadId", params.thread_id)
  app_put_strings(obj, "extraLogFiles", params.extra_log_files)
  if params.tags is Some(value) {
    obj.set("tags", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppCommandExecTerminalSize {
  rows : UInt16
  cols : UInt16
} derive(Debug)

///|
pub impl ToJson for AppCommandExecTerminalSize with fn to_json(size) {
  { "rows": size.rows, "cols": size.cols }
}

///|
pub(all) struct AppCommandExecParams {
  command : Array[String]
  process_id : String?
  tty : Bool?
  stream_stdin : Bool?
  stream_stdout_stderr : Bool?
  output_bytes_cap : UInt64?
  disable_output_cap : Bool?
  disable_timeout : Bool?
  timeout_ms : Int64?
  cwd : String?
  env : Map[String, String?]?
  size : AppCommandExecTerminalSize?
  sandbox_policy : AppSandboxPolicy?
} derive(Debug)

///|
pub impl ToJson for AppCommandExecParams with fn to_json(params) {
  let obj : Map[String, Json] = { "command": params.command }
  app_put_string(obj, "processId", params.process_id)
  app_put_true(obj, "tty", params.tty)
  app_put_true(obj, "streamStdin", params.stream_stdin)
  app_put_true(obj, "streamStdoutStderr", params.stream_stdout_stderr)
  app_put_uint64(obj, "outputBytesCap", params.output_bytes_cap)
  app_put_true(obj, "disableOutputCap", params.disable_output_cap)
  app_put_true(obj, "disableTimeout", params.disable_timeout)
  app_put_int64(obj, "timeoutMs", params.timeout_ms)
  app_put_string(obj, "cwd", params.cwd)
  if params.env is Some(value) {
    obj.set("env", app_env_to_json(value))
  }
  if params.size is Some(value) {
    obj.set("size", value.to_json())
  }
  if params.sandbox_policy is Some(value) {
    obj.set("sandboxPolicy", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppCommandExecWriteParams {
  process_id : String
  delta_base64 : String?
  close_stdin : Bool?
} derive(Debug)

///|
pub impl ToJson for AppCommandExecWriteParams with fn to_json(params) {
  let obj : Map[String, Json] = { "processId": params.process_id }
  app_put_string(obj, "deltaBase64", params.delta_base64)
  app_put_true(obj, "closeStdin", params.close_stdin)
  Json::object(obj)
}

///|
pub(all) struct AppCommandExecProcessParams {
  process_id : String
} derive(Debug)

///|
pub impl ToJson for AppCommandExecProcessParams with fn to_json(params) {
  { "processId": params.process_id }
}

///|
pub(all) struct AppCommandExecResizeParams {
  process_id : String
  size : AppCommandExecTerminalSize
} derive(Debug)

///|
pub impl ToJson for AppCommandExecResizeParams with fn to_json(params) {
  { "processId": params.process_id, "size": params.size }
}

///|
pub(all) struct AppExternalAgentConfigDetectParams {
  include_home : Bool?
  cwds : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigDetectParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_true(obj, "includeHome", params.include_home)
  app_put_strings(obj, "cwds", params.cwds)
  Json::object(obj)
}

///|
pub(all) struct AppExternalAgentConfigMigrationItem {
  item_type : AppExternalAgentConfigMigrationItemType
  description : String
  cwd : String?
  details : AppMigrationDetails?
} derive(Debug)

///|
pub(all) enum AppExternalAgentConfigMigrationItemType {
  AppMigrationAgentsMd
  AppMigrationConfig
  AppMigrationSkills
  AppMigrationPlugins
  AppMigrationMcpServerConfig
  AppMigrationSubagents
  AppMigrationHooks
  AppMigrationCommands
  AppMigrationSessions
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigMigrationItemType with fn to_json(
  item_type,
) {
  match item_type {
    AppMigrationAgentsMd => "AGENTS_MD".to_json()
    AppMigrationConfig => "CONFIG".to_json()
    AppMigrationSkills => "SKILLS".to_json()
    AppMigrationPlugins => "PLUGINS".to_json()
    AppMigrationMcpServerConfig => "MCP_SERVER_CONFIG".to_json()
    AppMigrationSubagents => "SUBAGENTS".to_json()
    AppMigrationHooks => "HOOKS".to_json()
    AppMigrationCommands => "COMMANDS".to_json()
    AppMigrationSessions => "SESSIONS".to_json()
  }
}

///|
pub impl FromJson for AppExternalAgentConfigMigrationItemType with fn from_json(
  value,
  path,
) {
  match value {
    String("AGENTS_MD") => AppMigrationAgentsMd
    String("CONFIG") => AppMigrationConfig
    String("SKILLS") => AppMigrationSkills
    String("PLUGINS") => AppMigrationPlugins
    String("MCP_SERVER_CONFIG") => AppMigrationMcpServerConfig
    String("SUBAGENTS") => AppMigrationSubagents
    String("HOOKS") => AppMigrationHooks
    String("COMMANDS") => AppMigrationCommands
    String("SESSIONS") => AppMigrationSessions
    _ =>
      raise JsonDecodeError(
        (path, "expected external agent config migration item type"),
      )
  }
}

///|
pub(all) struct AppMigrationDetails {
  plugins : ArrayView[AppPluginsMigration]
  sessions : ArrayView[AppSessionMigration]
  mcp_servers : ArrayView[AppNamedMigration]
  hooks : ArrayView[AppNamedMigration]
  subagents : ArrayView[AppNamedMigration]
  commands : ArrayView[AppNamedMigration]
} derive(Debug)

///|
pub impl ToJson for AppMigrationDetails with fn to_json(details) {
  {
    "plugins": details.plugins,
    "sessions": details.sessions,
    "mcpServers": details.mcp_servers,
    "hooks": details.hooks,
    "subagents": details.subagents,
    "commands": details.commands,
  }
}

///|
pub impl FromJson for AppMigrationDetails with fn from_json(value, path) {
  guard value
    is {
      "plugins"? : plugins,
      "sessions"? : sessions,
      "mcpServers"? : mcp_servers,
      "hooks"? : hooks,
      "subagents"? : subagents,
      "commands"? : commands,
      ..
    } else {
    raise JsonDecodeError((path, "expected migration details"))
  }
  {
    plugins: match plugins {
      Some(value) => @json.from_json(value, path=path.add_key("plugins"))
      None => @json.from_json(Json::array([]), path=path.add_key("plugins"))
    },
    sessions: match sessions {
      Some(value) => @json.from_json(value, path=path.add_key("sessions"))
      None => @json.from_json(Json::array([]), path=path.add_key("sessions"))
    },
    mcp_servers: match mcp_servers {
      Some(value) => @json.from_json(value, path=path.add_key("mcpServers"))
      None => @json.from_json(Json::array([]), path=path.add_key("mcpServers"))
    },
    hooks: match hooks {
      Some(value) => @json.from_json(value, path=path.add_key("hooks"))
      None => @json.from_json(Json::array([]), path=path.add_key("hooks"))
    },
    subagents: match subagents {
      Some(value) => @json.from_json(value, path=path.add_key("subagents"))
      None => @json.from_json(Json::array([]), path=path.add_key("subagents"))
    },
    commands: match commands {
      Some(value) => @json.from_json(value, path=path.add_key("commands"))
      None => @json.from_json(Json::array([]), path=path.add_key("commands"))
    },
  }
}

///|
pub(all) struct AppPluginsMigration {
  marketplace_name : String
  plugin_names : ArrayView[String]
} derive(Debug)

///|
pub impl ToJson for AppPluginsMigration with fn to_json(migration) {
  {
    "marketplaceName": migration.marketplace_name,
    "pluginNames": migration.plugin_names,
  }
}

///|
pub impl FromJson for AppPluginsMigration with fn from_json(value, path) {
  guard value
    is {
      "marketplaceName": String(marketplace_name),
      "pluginNames": plugin_names,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugins migration"))
  }
  {
    marketplace_name,
    plugin_names: @json.from_json(
      plugin_names,
      path=path.add_key("pluginNames"),
    ),
  }
}

///|
pub(all) struct AppSessionMigration {
  path : String
  cwd : String
  title : String?
} derive(Debug)

///|
pub impl ToJson for AppSessionMigration with fn to_json(migration) {
  let obj : Map[String, Json] = { "path": migration.path, "cwd": migration.cwd }
  match migration.title {
    Some(title) => obj.set("title", title.to_json())
    None => obj.set("title", Json::null())
  }
  Json::object(obj)
}

///|
pub impl FromJson for AppSessionMigration with fn from_json(value, path) {
  guard value
    is {
      "path": String(session_path),
      "cwd": String(cwd),
      "title"? : title,
      ..
    } else {
    raise JsonDecodeError((path, "expected session migration"))
  }
  {
    path: session_path,
    cwd,
    title: app_optional_string(title, path.add_key("title")),
  }
}

///|
pub(all) struct AppNamedMigration {
  name : String
} derive(Debug)

///|
pub impl ToJson for AppNamedMigration with fn to_json(migration) {
  { "name": migration.name }
}

///|
pub impl FromJson for AppNamedMigration with fn from_json(value, path) {
  guard value is { "name": String(name), .. } else {
    raise JsonDecodeError((path, "expected named migration"))
  }
  { name, }
}

///|
pub impl ToJson for AppExternalAgentConfigMigrationItem with fn to_json(item) {
  let obj : Map[String, Json] = {
    "itemType": item.item_type,
    "description": item.description,
  }
  app_put_string(obj, "cwd", item.cwd)
  match item.details {
    Some(value) => obj.set("details", value.to_json())
    None => obj.set("details", Json::null())
  }
  Json::object(obj)
}

///|
pub(all) struct AppExternalAgentConfigImportParams {
  migration_items : Array[AppExternalAgentConfigMigrationItem]
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigImportParams with fn to_json(params) {
  { "migrationItems": params.migration_items }
}

///|
pub(all) enum AppMergeStrategy {
  AppMergeReplace
  AppMergeUpsert
} derive(Debug)

///|
pub impl ToJson for AppMergeStrategy with fn to_json(strategy) {
  match strategy {
    AppMergeReplace => "replace".to_json()
    AppMergeUpsert => "upsert".to_json()
  }
}

///|
pub(all) struct AppConfigEdit {
  key_path : String
  value : Json
  merge_strategy : AppMergeStrategy
} derive(Debug)

///|
pub impl ToJson for AppConfigEdit with fn to_json(edit) {
  {
    "keyPath": edit.key_path,
    "value": edit.value,
    "mergeStrategy": edit.merge_strategy,
  }
}

///|
pub(all) struct AppConfigValueWriteParams {
  key_path : String
  value : Json
  merge_strategy : AppMergeStrategy
  file_path : String?
  expected_version : String?
} derive(Debug)

///|
pub impl ToJson for AppConfigValueWriteParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "keyPath": params.key_path,
    "value": params.value,
    "mergeStrategy": params.merge_strategy,
  }
  app_put_string(obj, "filePath", params.file_path)
  app_put_string(obj, "expectedVersion", params.expected_version)
  Json::object(obj)
}

///|
pub(all) struct AppConfigBatchWriteParams {
  edits : Array[AppConfigEdit]
  file_path : String?
  expected_version : String?
  reload_user_config : Bool?
} derive(Debug)

///|
pub impl ToJson for AppConfigBatchWriteParams with fn to_json(params) {
  let obj : Map[String, Json] = { "edits": params.edits }
  app_put_string(obj, "filePath", params.file_path)
  app_put_string(obj, "expectedVersion", params.expected_version)
  app_put_true(obj, "reloadUserConfig", params.reload_user_config)
  Json::object(obj)
}

///|
pub(all) struct AppAccountReadParams {
  refresh_token : Bool
} derive(Debug)

///|
pub impl ToJson for AppAccountReadParams with fn to_json(params) {
  { "refreshToken": params.refresh_token }
}

///|
pub(all) struct AppFuzzyFileSearchParams {
  query : String
  roots : Array[String]
  cancellation_token : String?
} derive(Debug)

///|
pub impl ToJson for AppFuzzyFileSearchParams with fn to_json(params) {
  let obj : Map[String, Json] = { "query": params.query, "roots": params.roots }
  match params.cancellation_token {
    Some(value) => obj.set("cancellationToken", value.to_json())
    None => obj.set("cancellationToken", Json::null())
  }
  Json::object(obj)
}

///|
async fn CodexAppConnection::call_raw(
  self : CodexAppConnection,
  rpc_method : String,
  params? : Json,
) -> Json {
  self.call(rpc_method, params?)
}

///|
async fn CodexAppConnection::call_empty(
  self : CodexAppConnection,
  rpc_method : String,
  params? : Json,
) -> Unit {
  let _ = self.call(rpc_method, params?)
}

///|
pub struct AppInitializeResponse {
  user_agent : String
  codex_home : String
  platform_family : String
  platform_os : String
} derive(Debug)

///|
pub impl FromJson for AppInitializeResponse with fn from_json(value, path) {
  guard value
    is {
      "userAgent": String(user_agent),
      "codexHome": String(codex_home),
      "platformFamily": String(platform_family),
      "platformOs": String(platform_os),
      ..
    } else {
    raise JsonDecodeError((path, "expected initialize response"))
  }
  { user_agent, codex_home, platform_family, platform_os }
}

///|
pub struct AppThreadForkResponse {
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
} derive(Debug)

///|
pub impl FromJson for AppThreadForkResponse with fn from_json(value, path) {
  let response = app_thread_session_response(
    value, path, "expected thread/fork response",
  )
  {
    thread: response.thread,
    model: response.model,
    model_provider: response.model_provider,
    service_tier: response.service_tier,
    cwd: response.cwd,
    instruction_sources: response.instruction_sources,
    approval_policy: response.approval_policy,
    approvals_reviewer: response.approvals_reviewer,
    sandbox: response.sandbox,
    reasoning_effort: response.reasoning_effort,
  }
}

///|
pub struct AppThreadMetadataUpdateResponse {
  thread : AppThread
} derive(Debug)

///|
pub impl FromJson for AppThreadMetadataUpdateResponse with fn from_json(
  value,
  path,
) {
  guard value is { "thread": thread, .. } else {
    raise JsonDecodeError((path, "expected thread/metadata/update response"))
  }
  { thread: @json.from_json(thread, path=path.add_key("thread")) }
}

///|
pub struct AppThreadRollbackResponse {
  thread : AppThread
} derive(Debug)

///|
pub impl FromJson for AppThreadRollbackResponse with fn from_json(value, path) {
  guard value is { "thread": thread, .. } else {
    raise JsonDecodeError((path, "expected thread/rollback response"))
  }
  { thread: @json.from_json(thread, path=path.add_key("thread")) }
}

///|
pub struct AppHookErrorInfo {
  path : String
  message : String
} derive(Debug)

///|
pub impl FromJson for AppHookErrorInfo with fn from_json(value, path) {
  guard value is { "path": String(hook_path), "message": String(message), .. } else {
    raise JsonDecodeError((path, "expected hook error info"))
  }
  { path: hook_path, message }
}

///|
pub struct AppHookMetadata {
  key : String
  event_name : AppHookEventName
  handler_type : AppHookHandlerType
  matcher : String?
  command : String?
  timeout_sec : UInt64
  status_message : String?
  source_path : String
  source : AppHookSource
  plugin_id : String?
  display_order : Int64
  enabled : Bool
  is_managed : Bool
  current_hash : String
  trust_status : AppHookTrustStatus
  priv raw : Json
} derive(Debug)

///|
pub enum AppHookEventName {
  AppHookPreToolUse
  AppHookPermissionRequest
  AppHookPostToolUse
  AppHookPreCompact
  AppHookPostCompact
  AppHookSessionStart
  AppHookUserPromptSubmit
  AppHookStop
} derive(Debug)

///|
pub impl FromJson for AppHookEventName with fn from_json(value, path) {
  match value {
    String("preToolUse") => AppHookPreToolUse
    String("permissionRequest") => AppHookPermissionRequest
    String("postToolUse") => AppHookPostToolUse
    String("preCompact") => AppHookPreCompact
    String("postCompact") => AppHookPostCompact
    String("sessionStart") => AppHookSessionStart
    String("userPromptSubmit") => AppHookUserPromptSubmit
    String("stop") => AppHookStop
    _ => raise JsonDecodeError((path, "expected hook event name"))
  }
}

///|
pub enum AppHookHandlerType {
  AppHookCommandHandler
  AppHookPromptHandler
  AppHookAgentHandler
} derive(Debug)

///|
pub impl FromJson for AppHookHandlerType with fn from_json(value, path) {
  match value {
    String("command") => AppHookCommandHandler
    String("prompt") => AppHookPromptHandler
    String("agent") => AppHookAgentHandler
    _ => raise JsonDecodeError((path, "expected hook handler type"))
  }
}

///|
pub enum AppHookSource {
  AppHookSystemSource
  AppHookUserSource
  AppHookProjectSource
  AppHookMdmSource
  AppHookSessionFlagsSource
  AppHookPluginSource
  AppHookCloudRequirementsSource
  AppHookLegacyManagedConfigFileSource
  AppHookLegacyManagedConfigMdmSource
  AppHookUnknownSource
} derive(Debug)

///|
pub impl FromJson for AppHookSource with fn from_json(value, path) {
  match value {
    String("system") => AppHookSystemSource
    String("user") => AppHookUserSource
    String("project") => AppHookProjectSource
    String("mdm") => AppHookMdmSource
    String("sessionFlags") => AppHookSessionFlagsSource
    String("plugin") => AppHookPluginSource
    String("cloudRequirements") => AppHookCloudRequirementsSource
    String("legacyManagedConfigFile") => AppHookLegacyManagedConfigFileSource
    String("legacyManagedConfigMdm") => AppHookLegacyManagedConfigMdmSource
    String("unknown") => AppHookUnknownSource
    _ => raise JsonDecodeError((path, "expected hook source"))
  }
}

///|
pub enum AppHookTrustStatus {
  AppHookManagedTrust
  AppHookUntrusted
  AppHookTrusted
  AppHookModified
} derive(Debug)

///|
pub impl FromJson for AppHookTrustStatus with fn from_json(value, path) {
  match value {
    String("managed") => AppHookManagedTrust
    String("untrusted") => AppHookUntrusted
    String("trusted") => AppHookTrusted
    String("modified") => AppHookModified
    _ => raise JsonDecodeError((path, "expected hook trust status"))
  }
}

///|
pub impl FromJson for AppHookMetadata with fn from_json(value, path) {
  guard value
    is {
      "key": String(key),
      "eventName": event_name,
      "handlerType": handler_type,
      "matcher"? : matcher,
      "command"? : command,
      "timeoutSec": Number(timeout_sec, ..),
      "statusMessage"? : status_message,
      "sourcePath": String(source_path),
      "source": source,
      "pluginId"? : plugin_id,
      "displayOrder": Number(display_order, ..),
      "enabled": enabled,
      "isManaged": is_managed,
      "currentHash": String(current_hash),
      "trustStatus": trust_status,
      ..
    } else {
    raise JsonDecodeError((path, "expected hook metadata"))
  }
  {
    key,
    event_name: @json.from_json(event_name, path=path.add_key("eventName")),
    handler_type: @json.from_json(
      handler_type,
      path=path.add_key("handlerType"),
    ),
    matcher: app_optional_string(matcher, path.add_key("matcher")),
    command: app_optional_string(command, path.add_key("command")),
    timeout_sec: timeout_sec.to_uint64(),
    status_message: app_optional_string(
      status_message,
      path.add_key("statusMessage"),
    ),
    source_path,
    source: @json.from_json(source, path=path.add_key("source")),
    plugin_id: app_optional_string(plugin_id, path.add_key("pluginId")),
    display_order: display_order.to_int64(),
    enabled: app_bool(enabled, path.add_key("enabled")),
    is_managed: app_bool(is_managed, path.add_key("isManaged")),
    current_hash,
    trust_status: @json.from_json(
      trust_status,
      path=path.add_key("trustStatus"),
    ),
    raw: value,
  }
}

///|
pub struct AppHooksListEntry {
  cwd : String
  hooks : ArrayView[AppHookMetadata]
  warnings : ArrayView[String]
  errors : ArrayView[AppHookErrorInfo]
} derive(Debug)

///|
pub impl FromJson for AppHooksListEntry with fn from_json(value, path) {
  guard value
    is {
      "cwd": String(cwd),
      "hooks": hooks,
      "warnings": warnings,
      "errors": errors,
      ..
    } else {
    raise JsonDecodeError((path, "expected hooks/list entry"))
  }
  {
    cwd,
    hooks: @json.from_json(hooks, path=path.add_key("hooks")),
    warnings: @json.from_json(warnings, path=path.add_key("warnings")),
    errors: @json.from_json(errors, path=path.add_key("errors")),
  }
}

///|
pub struct AppHooksListResponse {
  data : ArrayView[AppHooksListEntry]
} derive(Debug)

///|
pub impl FromJson for AppHooksListResponse with fn from_json(value, path) {
  guard value is { "data": data, .. } else {
    raise JsonDecodeError((path, "expected hooks/list response"))
  }
  { data: @json.from_json(data, path=path.add_key("data")) }
}

///|
pub struct AppMarketplaceAddResponse {
  marketplace_name : String
  installed_root : String
  already_added : Bool
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceAddResponse with fn from_json(value, path) {
  guard value
    is {
      "marketplaceName": String(marketplace_name),
      "installedRoot": String(installed_root),
      "alreadyAdded": already_added,
      ..
    } else {
    raise JsonDecodeError((path, "expected marketplace/add response"))
  }
  {
    marketplace_name,
    installed_root,
    already_added: app_bool(already_added, path.add_key("alreadyAdded")),
  }
}

///|
pub struct AppMarketplaceRemoveResponse {
  marketplace_name : String
  installed_root : String?
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceRemoveResponse with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "marketplaceName": String(marketplace_name),
      "installedRoot"? : installed_root,
      ..
    } else {
    raise JsonDecodeError((path, "expected marketplace/remove response"))
  }
  {
    marketplace_name,
    installed_root: app_optional_string(
      installed_root,
      path.add_key("installedRoot"),
    ),
  }
}

///|
pub struct AppMarketplaceUpgradeErrorInfo {
  marketplace_name : String
  message : String
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceUpgradeErrorInfo with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "marketplaceName": String(marketplace_name),
      "message": String(message),
      ..
    } else {
    raise JsonDecodeError((path, "expected marketplace upgrade error info"))
  }
  { marketplace_name, message }
}

///|
pub struct AppMarketplaceUpgradeResponse {
  selected_marketplaces : ArrayView[String]
  upgraded_roots : ArrayView[String]
  errors : ArrayView[AppMarketplaceUpgradeErrorInfo]
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceUpgradeResponse with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "selectedMarketplaces": selected_marketplaces,
      "upgradedRoots": upgraded_roots,
      "errors": errors,
      ..
    } else {
    raise JsonDecodeError((path, "expected marketplace/upgrade response"))
  }
  {
    selected_marketplaces: @json.from_json(
      selected_marketplaces,
      path=path.add_key("selectedMarketplaces"),
    ),
    upgraded_roots: @json.from_json(
      upgraded_roots,
      path=path.add_key("upgradedRoots"),
    ),
    errors: @json.from_json(errors, path=path.add_key("errors")),
  }
}

///|
pub struct AppMarketplaceInterface {
  display_name : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceInterface with fn from_json(value, path) {
  guard value is { "displayName"? : display_name, .. } else {
    raise JsonDecodeError((path, "expected marketplace interface"))
  }
  {
    display_name: app_optional_string(display_name, path.add_key("displayName")),
    raw: value,
  }
}

///|
pub enum AppPluginAuthPolicy {
  AppPluginAuthOnInstall
  AppPluginAuthOnUse
} derive(Debug)

///|
pub impl FromJson for AppPluginAuthPolicy with fn from_json(value, path) {
  match value {
    String("ON_INSTALL") => AppPluginAuthOnInstall
    String("ON_USE") => AppPluginAuthOnUse
    _ => raise JsonDecodeError((path, "expected plugin auth policy"))
  }
}

///|
pub enum AppPluginInstallPolicy {
  AppPluginInstallNotAvailable
  AppPluginInstallAvailable
  AppPluginInstallInstalledByDefault
} derive(Debug)

///|
pub impl FromJson for AppPluginInstallPolicy with fn from_json(value, path) {
  match value {
    String("NOT_AVAILABLE") => AppPluginInstallNotAvailable
    String("AVAILABLE") => AppPluginInstallAvailable
    String("INSTALLED_BY_DEFAULT") => AppPluginInstallInstalledByDefault
    _ => raise JsonDecodeError((path, "expected plugin install policy"))
  }
}

///|
pub enum AppPluginSource {
  AppPluginSourceLocal(path~ : String)
  AppPluginSourceGit(
    url~ : String,
    path~ : String?,
    ref_name~ : String?,
    sha~ : String?
  )
  AppPluginSourceRemote
} derive(Debug)

///|
pub impl FromJson for AppPluginSource with fn from_json(value, path) {
  guard value is { "type": String(source_type), .. } else {
    raise JsonDecodeError((path, "expected plugin source"))
  }
  match source_type {
    "local" => {
      guard value is { "path": String(local_path), .. } else {
        raise JsonDecodeError((path, "expected local plugin source"))
      }
      AppPluginSourceLocal(path=local_path)
    }
    "git" => {
      guard value
        is {
          "url": String(url),
          "path"? : source_path,
          "refName"? : ref_name,
          "sha"? : sha,
          ..
        } else {
        raise JsonDecodeError((path, "expected git plugin source"))
      }
      AppPluginSourceGit(
        url~,
        path=app_optional_string(source_path, path.add_key("path")),
        ref_name=app_optional_string(ref_name, path.add_key("refName")),
        sha=app_optional_string(sha, path.add_key("sha")),
      )
    }
    "remote" => AppPluginSourceRemote
    _ => raise JsonDecodeError((path, "expected plugin source type"))
  }
}

///|
pub struct AppPluginInterface {
  display_name : String?
  short_description : String?
  long_description : String?
  developer_name : String?
  category : String?
  capabilities : ArrayView[String]
  website_url : String?
  privacy_policy_url : String?
  terms_of_service_url : String?
  default_prompt : ArrayView[String]?
  brand_color : String?
  composer_icon : String?
  composer_icon_url : String?
  logo : String?
  logo_url : String?
  screenshots : ArrayView[String]
  screenshot_urls : ArrayView[String]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppPluginInterface with fn from_json(value, path) {
  guard value
    is {
      "displayName"? : display_name,
      "shortDescription"? : short_description,
      "longDescription"? : long_description,
      "developerName"? : developer_name,
      "category"? : category,
      "capabilities": capabilities,
      "websiteUrl"? : website_url,
      "privacyPolicyUrl"? : privacy_policy_url,
      "termsOfServiceUrl"? : terms_of_service_url,
      "defaultPrompt"? : default_prompt,
      "brandColor"? : brand_color,
      "composerIcon"? : composer_icon,
      "composerIconUrl"? : composer_icon_url,
      "logo"? : logo,
      "logoUrl"? : logo_url,
      "screenshots": screenshots,
      "screenshotUrls": screenshot_urls,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugin interface"))
  }
  {
    display_name: app_optional_string(display_name, path.add_key("displayName")),
    short_description: app_optional_string(
      short_description,
      path.add_key("shortDescription"),
    ),
    long_description: app_optional_string(
      long_description,
      path.add_key("longDescription"),
    ),
    developer_name: app_optional_string(
      developer_name,
      path.add_key("developerName"),
    ),
    category: app_optional_string(category, path.add_key("category")),
    capabilities: @json.from_json(
      capabilities,
      path=path.add_key("capabilities"),
    ),
    website_url: app_optional_string(website_url, path.add_key("websiteUrl")),
    privacy_policy_url: app_optional_string(
      privacy_policy_url,
      path.add_key("privacyPolicyUrl"),
    ),
    terms_of_service_url: app_optional_string(
      terms_of_service_url,
      path.add_key("termsOfServiceUrl"),
    ),
    default_prompt: match default_prompt {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("defaultPrompt")))
    },
    brand_color: app_optional_string(brand_color, path.add_key("brandColor")),
    composer_icon: app_optional_string(
      composer_icon,
      path.add_key("composerIcon"),
    ),
    composer_icon_url: app_optional_string(
      composer_icon_url,
      path.add_key("composerIconUrl"),
    ),
    logo: app_optional_string(logo, path.add_key("logo")),
    logo_url: app_optional_string(logo_url, path.add_key("logoUrl")),
    screenshots: @json.from_json(screenshots, path=path.add_key("screenshots")),
    screenshot_urls: @json.from_json(
      screenshot_urls,
      path=path.add_key("screenshotUrls"),
    ),
    raw: value,
  }
}

///|
pub struct AppPluginSummary {
  id : String
  name : String
  source : AppPluginSource
  installed : Bool
  enabled : Bool
  install_policy : AppPluginInstallPolicy
  auth_policy : AppPluginAuthPolicy
  interface : AppPluginInterface?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppPluginSummary with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "source": source,
      "installed": installed,
      "enabled": enabled,
      "installPolicy": install_policy,
      "authPolicy": auth_policy,
      "interface"? : interface,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugin summary"))
  }
  {
    id,
    name,
    source: @json.from_json(source, path=path.add_key("source")),
    installed: app_bool(installed, path.add_key("installed")),
    enabled: app_bool(enabled, path.add_key("enabled")),
    install_policy: @json.from_json(
      install_policy,
      path=path.add_key("installPolicy"),
    ),
    auth_policy: @json.from_json(auth_policy, path=path.add_key("authPolicy")),
    interface: match interface {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("interface")))
    },
    raw: value,
  }
}

///|
pub struct AppPluginMarketplaceEntry {
  name : String
  path : String?
  interface : AppMarketplaceInterface?
  plugins : ArrayView[AppPluginSummary]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppPluginMarketplaceEntry with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "path"? : marketplace_path,
      "interface"? : interface,
      "plugins": plugins,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugin marketplace entry"))
  }
  {
    name,
    path: app_optional_string(marketplace_path, path.add_key("path")),
    interface: match interface {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("interface")))
    },
    plugins: @json.from_json(plugins, path=path.add_key("plugins")),
    raw: value,
  }
}

///|
pub struct AppMarketplaceLoadErrorInfo {
  marketplace_path : String
  message : String
} derive(Debug)

///|
pub impl FromJson for AppMarketplaceLoadErrorInfo with fn from_json(value, path) {
  guard value
    is {
      "marketplacePath": String(marketplace_path),
      "message": String(message),
      ..
    } else {
    raise JsonDecodeError((path, "expected marketplace load error info"))
  }
  { marketplace_path, message }
}

///|
pub struct AppPluginListResponse {
  marketplaces : ArrayView[AppPluginMarketplaceEntry]
  marketplace_load_errors : ArrayView[AppMarketplaceLoadErrorInfo]
  featured_plugin_ids : ArrayView[String]
} derive(Debug)

///|
pub impl FromJson for AppPluginListResponse with fn from_json(value, path) {
  guard value
    is {
      "marketplaces": marketplaces,
      "marketplaceLoadErrors"? : marketplace_load_errors,
      "featuredPluginIds"? : featured_plugin_ids,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugin/list response"))
  }
  {
    marketplaces: @json.from_json(
      marketplaces,
      path=path.add_key("marketplaces"),
    ),
    marketplace_load_errors: match marketplace_load_errors {
      Some(value) =>
        @json.from_json(value, path=path.add_key("marketplaceLoadErrors"))
      None => []
    },
    featured_plugin_ids: match featured_plugin_ids {
      Some(value) =>
        @json.from_json(value, path=path.add_key("featuredPluginIds"))
      None => []
    },
  }
}

///|
pub struct AppSummary {
  id : String
  name : String
  description : String?
  install_url : String?
  needs_auth : Bool
} derive(Debug)

///|
pub impl FromJson for AppSummary with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "description"? : description,
      "installUrl"? : install_url,
      "needsAuth": needs_auth,
      ..
    } else {
    raise JsonDecodeError((path, "expected app summary"))
  }
  {
    id,
    name,
    description: app_optional_string(description, path.add_key("description")),
    install_url: app_optional_string(install_url, path.add_key("installUrl")),
    needs_auth: app_bool(needs_auth, path.add_key("needsAuth")),
  }
}

///|
pub struct AppPluginDetail {
  marketplace_name : String
  marketplace_path : String?
  summary : AppPluginSummary
  description : String?
  skills : ArrayView[AppSkillSummary]
  apps : ArrayView[AppSummary]
  mcp_servers : ArrayView[String]
  priv raw : Json
} derive(Debug)

///|
pub struct AppSkillSummary {
  name : String
  description : String
  short_description : String?
  interface : AppSkillInterface?
  path : String?
  enabled : Bool
} derive(Debug)

///|
pub impl FromJson for AppSkillSummary with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "description": String(description),
      "shortDescription"? : short_description,
      "interface"? : skill_interface,
      "path"? : skill_path,
      "enabled": enabled,
      ..
    } else {
    raise JsonDecodeError((path, "expected skill summary"))
  }
  {
    name,
    description,
    short_description: app_optional_string(
      short_description,
      path.add_key("shortDescription"),
    ),
    interface: match skill_interface {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("interface")))
    },
    path: app_optional_string(skill_path, path.add_key("path")),
    enabled: app_bool(enabled, path.add_key("enabled")),
  }
}

///|
pub struct AppSkillInterface {
  display_name : String?
  short_description : String?
  icon_small : String?
  icon_large : String?
  brand_color : String?
  default_prompt : String?
} derive(Debug)

///|
pub impl FromJson for AppSkillInterface with fn from_json(value, path) {
  guard value
    is {
      "displayName"? : display_name,
      "shortDescription"? : short_description,
      "iconSmall"? : icon_small,
      "iconLarge"? : icon_large,
      "brandColor"? : brand_color,
      "defaultPrompt"? : default_prompt,
      ..
    } else {
    raise JsonDecodeError((path, "expected skill interface"))
  }
  {
    display_name: app_optional_string(display_name, path.add_key("displayName")),
    short_description: app_optional_string(
      short_description,
      path.add_key("shortDescription"),
    ),
    icon_small: app_optional_string(icon_small, path.add_key("iconSmall")),
    icon_large: app_optional_string(icon_large, path.add_key("iconLarge")),
    brand_color: app_optional_string(brand_color, path.add_key("brandColor")),
    default_prompt: app_optional_string(
      default_prompt,
      path.add_key("defaultPrompt"),
    ),
  }
}

///|
pub impl FromJson for AppPluginDetail with fn from_json(value, path) {
  guard value
    is {
      "marketplaceName": String(marketplace_name),
      "marketplacePath"? : marketplace_path,
      "summary": summary,
      "description"? : description,
      "skills": skills,
      "apps": apps,
      "mcpServers": mcp_servers,
      ..
    } else {
    raise JsonDecodeError((path, "expected plugin detail"))
  }
  {
    marketplace_name,
    marketplace_path: app_optional_string(
      marketplace_path,
      path.add_key("marketplacePath"),
    ),
    summary: @json.from_json(summary, path=path.add_key("summary")),
    description: app_optional_string(description, path.add_key("description")),
    skills: @json.from_json(skills, path=path.add_key("skills")),
    apps: @json.from_json(apps, path=path.add_key("apps")),
    mcp_servers: @json.from_json(mcp_servers, path=path.add_key("mcpServers")),
    raw: value,
  }
}

///|
pub struct AppPluginReadResponse {
  plugin : AppPluginDetail
} derive(Debug)

///|
pub impl FromJson for AppPluginReadResponse with fn from_json(value, path) {
  guard value is { "plugin": plugin, .. } else {
    raise JsonDecodeError((path, "expected plugin/read response"))
  }
  { plugin: @json.from_json(plugin, path=path.add_key("plugin")) }
}

///|
pub struct AppFsReadFileResponse {
  data_base64 : String
} derive(Debug)

///|
pub impl FromJson for AppFsReadFileResponse with fn from_json(value, path) {
  guard value is { "dataBase64": String(data_base64), .. } else {
    raise JsonDecodeError((path, "expected fs/readFile response"))
  }
  { data_base64, }
}

///|
pub struct AppFsGetMetadataResponse {
  is_directory : Bool
  is_file : Bool
  is_symlink : Bool
  created_at_ms : Int64
  modified_at_ms : Int64
} derive(Debug)

///|
pub impl FromJson for AppFsGetMetadataResponse with fn from_json(value, path) {
  guard value
    is {
      "isDirectory": is_directory,
      "isFile": is_file,
      "isSymlink": is_symlink,
      "createdAtMs": Number(created_at_ms, ..),
      "modifiedAtMs": Number(modified_at_ms, ..),
      ..
    } else {
    raise JsonDecodeError((path, "expected fs/getMetadata response"))
  }
  {
    is_directory: app_bool(is_directory, path.add_key("isDirectory")),
    is_file: app_bool(is_file, path.add_key("isFile")),
    is_symlink: app_bool(is_symlink, path.add_key("isSymlink")),
    created_at_ms: created_at_ms.to_int64(),
    modified_at_ms: modified_at_ms.to_int64(),
  }
}

///|
pub struct AppFsReadDirectoryEntry {
  file_name : String
  is_directory : Bool
  is_file : Bool
} derive(Debug)

///|
pub impl FromJson for AppFsReadDirectoryEntry with fn from_json(value, path) {
  guard value
    is {
      "fileName": String(file_name),
      "isDirectory": is_directory,
      "isFile": is_file,
      ..
    } else {
    raise JsonDecodeError((path, "expected fs/readDirectory entry"))
  }
  {
    file_name,
    is_directory: app_bool(is_directory, path.add_key("isDirectory")),
    is_file: app_bool(is_file, path.add_key("isFile")),
  }
}

///|
pub struct AppFsReadDirectoryResponse {
  entries : ArrayView[AppFsReadDirectoryEntry]
} derive(Debug)

///|
pub impl FromJson for AppFsReadDirectoryResponse with fn from_json(value, path) {
  guard value is { "entries": entries, .. } else {
    raise JsonDecodeError((path, "expected fs/readDirectory response"))
  }
  { entries: @json.from_json(entries, path=path.add_key("entries")) }
}

///|
pub struct AppFsWatchResponse {
  path : String
} derive(Debug)

///|
pub impl FromJson for AppFsWatchResponse with fn from_json(value, path) {
  guard value is { "path": String(watch_path), .. } else {
    raise JsonDecodeError((path, "expected fs/watch response"))
  }
  { path: watch_path }
}

///|
pub struct AppSkillsConfigWriteResponse {
  effective_enabled : Bool
} derive(Debug)

///|
pub impl FromJson for AppSkillsConfigWriteResponse with fn from_json(
  value,
  path,
) {
  guard value is { "effectiveEnabled": effective_enabled, .. } else {
    raise JsonDecodeError((path, "expected skills/config/write response"))
  }
  {
    effective_enabled: app_bool(
      effective_enabled,
      path.add_key("effectiveEnabled"),
    ),
  }
}

///|
pub struct AppPluginInstallResponse {
  auth_policy : AppPluginAuthPolicy
  apps_needing_auth : ArrayView[AppSummary]
} derive(Debug)

///|
pub impl FromJson for AppPluginInstallResponse with fn from_json(value, path) {
  guard value
    is { "authPolicy": auth_policy, "appsNeedingAuth": apps_needing_auth, .. } else {
    raise JsonDecodeError((path, "expected plugin/install response"))
  }
  {
    auth_policy: @json.from_json(auth_policy, path=path.add_key("authPolicy")),
    apps_needing_auth: @json.from_json(
      apps_needing_auth,
      path=path.add_key("appsNeedingAuth"),
    ),
  }
}

///|
pub struct AppReviewStartResponse {
  turn : AppTurn
  review_thread_id : String
} derive(Debug)

///|
pub impl FromJson for AppReviewStartResponse with fn from_json(value, path) {
  guard value
    is { "turn": turn, "reviewThreadId": String(review_thread_id), .. } else {
    raise JsonDecodeError((path, "expected review/start response"))
  }
  { turn: @json.from_json(turn, path=path.add_key("turn")), review_thread_id }
}

///|
pub enum AppExperimentalFeatureStage {
  AppFeatureBeta
  AppFeatureUnderDevelopment
  AppFeatureStable
  AppFeatureDeprecated
  AppFeatureRemoved
} derive(Debug)

///|
pub impl FromJson for AppExperimentalFeatureStage with fn from_json(value, path) {
  match value {
    String("beta") => AppFeatureBeta
    String("underDevelopment") => AppFeatureUnderDevelopment
    String("stable") => AppFeatureStable
    String("deprecated") => AppFeatureDeprecated
    String("removed") => AppFeatureRemoved
    _ => raise JsonDecodeError((path, "expected experimental feature stage"))
  }
}

///|
pub struct AppExperimentalFeature {
  name : String
  stage : AppExperimentalFeatureStage
  display_name : String?
  description : String?
  announcement : String?
  enabled : Bool
  default_enabled : Bool
} derive(Debug)

///|
pub impl FromJson for AppExperimentalFeature with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "stage": stage,
      "displayName"? : display_name,
      "description"? : description,
      "announcement"? : announcement,
      "enabled": enabled,
      "defaultEnabled": default_enabled,
      ..
    } else {
    raise JsonDecodeError((path, "expected experimental feature"))
  }
  {
    name,
    stage: @json.from_json(stage, path=path.add_key("stage")),
    display_name: app_optional_string(display_name, path.add_key("displayName")),
    description: app_optional_string(description, path.add_key("description")),
    announcement: app_optional_string(
      announcement,
      path.add_key("announcement"),
    ),
    enabled: app_bool(enabled, path.add_key("enabled")),
    default_enabled: app_bool(default_enabled, path.add_key("defaultEnabled")),
  }
}

///|
pub struct AppExperimentalFeatureListResponse {
  data : ArrayView[AppExperimentalFeature]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppExperimentalFeatureListResponse with fn from_json(
  value,
  path,
) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected experimentalFeature/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub struct AppExperimentalFeatureEnablementSetResponse {
  enablement : Map[String, Bool]
} derive(Debug)

///|
pub impl FromJson for AppExperimentalFeatureEnablementSetResponse with fn from_json(
  value,
  path,
) {
  guard value is { "enablement": enablement, .. } else {
    raise JsonDecodeError(
      (path, "expected experimentalFeature/enablement/set response"),
    )
  }
  { enablement: @json.from_json(enablement, path=path.add_key("enablement")) }
}

///|
pub struct AppMcpServerOauthLoginResponse {
  authorization_url : String
} derive(Debug)

///|
pub impl FromJson for AppMcpServerOauthLoginResponse with fn from_json(
  value,
  path,
) {
  guard value is { "authorizationUrl": String(authorization_url), .. } else {
    raise JsonDecodeError((path, "expected mcp/server/oauth/login response"))
  }
  { authorization_url, }
}

///|
pub enum AppMcpAuthStatus {
  AppMcpUnsupported
  AppMcpNotLoggedIn
  AppMcpBearerToken
  AppMcpOAuth
} derive(Debug)

///|
pub impl FromJson for AppMcpAuthStatus with fn from_json(value, path) {
  match value {
    String("unsupported") => AppMcpUnsupported
    String("notLoggedIn") => AppMcpNotLoggedIn
    String("bearerToken") => AppMcpBearerToken
    String("oAuth") => AppMcpOAuth
    _ => raise JsonDecodeError((path, "expected MCP auth status"))
  }
}

///|
pub struct AppMcpServerStatus {
  name : String
  tools : Map[String, AppMcpTool]
  resources : ArrayView[AppMcpResource]
  resource_templates : ArrayView[AppMcpResourceTemplate]
  auth_status : AppMcpAuthStatus
} derive(Debug)

///|
pub struct AppMcpTool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : Json?
  icons : ArrayView[Json]?
  meta : Json?
} derive(Debug)

///|
pub impl FromJson for AppMcpTool with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "title"? : title,
      "description"? : description,
      "inputSchema": input_schema,
      "outputSchema"? : output_schema,
      "annotations"? : annotations,
      "icons"? : icons,
      "_meta"? : meta,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP tool"))
  }
  {
    name,
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    input_schema,
    output_schema: app_optional_json(output_schema),
    annotations: app_optional_json(annotations),
    icons: match icons {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("icons")))
    },
    meta: app_optional_json(meta),
  }
}

///|
pub struct AppMcpResource {
  annotations : Json?
  description : String?
  mime_type : String?
  name : String
  size : Int64?
  title : String?
  uri : String
  icons : ArrayView[Json]?
  meta : Json?
} derive(Debug)

///|
pub impl FromJson for AppMcpResource with fn from_json(value, path) {
  guard value
    is {
      "annotations"? : annotations,
      "description"? : description,
      "mimeType"? : mime_type,
      "name": String(name),
      "size"? : size,
      "title"? : title,
      "uri": String(uri),
      "icons"? : icons,
      "_meta"? : meta,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP resource"))
  }
  {
    annotations: app_optional_json(annotations),
    description: app_optional_string(description, path.add_key("description")),
    mime_type: app_optional_string(mime_type, path.add_key("mimeType")),
    name,
    size: app_optional_int64(size, path.add_key("size")),
    title: app_optional_string(title, path.add_key("title")),
    uri,
    icons: match icons {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("icons")))
    },
    meta: app_optional_json(meta),
  }
}

///|
pub struct AppMcpResourceTemplate {
  annotations : Json?
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
} derive(Debug)

///|
pub impl FromJson for AppMcpResourceTemplate with fn from_json(value, path) {
  guard value
    is {
      "annotations"? : annotations,
      "uriTemplate": String(uri_template),
      "name": String(name),
      "title"? : title,
      "description"? : description,
      "mimeType"? : mime_type,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP resource template"))
  }
  {
    annotations: app_optional_json(annotations),
    uri_template,
    name,
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    mime_type: app_optional_string(mime_type, path.add_key("mimeType")),
  }
}

///|
pub impl FromJson for AppMcpServerStatus with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "tools": tools,
      "resources": resources,
      "resourceTemplates": resource_templates,
      "authStatus": auth_status,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP server status"))
  }
  {
    name,
    tools: @json.from_json(tools, path=path.add_key("tools")),
    resources: @json.from_json(resources, path=path.add_key("resources")),
    resource_templates: @json.from_json(
      resource_templates,
      path=path.add_key("resourceTemplates"),
    ),
    auth_status: @json.from_json(auth_status, path=path.add_key("authStatus")),
  }
}

///|
pub struct AppMcpServerStatusListResponse {
  data : ArrayView[AppMcpServerStatus]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppMcpServerStatusListResponse with fn from_json(
  value,
  path,
) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected mcp/server/status/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub struct AppMcpServerResourceReadResponse {
  contents : ArrayView[AppMcpResourceContent]
} derive(Debug)

///|
pub enum AppMcpResourceContent {
  AppMcpTextResourceContent(
    uri~ : String,
    mime_type~ : String?,
    text~ : String,
    meta~ : Json?
  )
  AppMcpBlobResourceContent(
    uri~ : String,
    mime_type~ : String?,
    blob~ : String,
    meta~ : Json?
  )
} derive(Debug)

///|
pub impl FromJson for AppMcpResourceContent with fn from_json(value, path) {
  match value {
    {
      "uri": String(uri),
      "mimeType"? : mime_type,
      "text": String(text),
      "_meta"? : meta,
      ..
    } =>
      AppMcpTextResourceContent(
        uri~,
        mime_type=app_optional_string(mime_type, path.add_key("mimeType")),
        text~,
        meta=app_optional_json(meta),
      )
    {
      "uri": String(uri),
      "mimeType"? : mime_type,
      "blob": String(blob),
      "_meta"? : meta,
      ..
    } =>
      AppMcpBlobResourceContent(
        uri~,
        mime_type=app_optional_string(mime_type, path.add_key("mimeType")),
        blob~,
        meta=app_optional_json(meta),
      )
    _ => raise JsonDecodeError((path, "expected MCP resource content"))
  }
}

///|
pub impl FromJson for AppMcpServerResourceReadResponse with fn from_json(
  value,
  path,
) {
  guard value is { "contents": contents, .. } else {
    raise JsonDecodeError((path, "expected mcp/resource/read response"))
  }
  { contents: @json.from_json(contents, path=path.add_key("contents")) }
}

///|
pub struct AppMcpServerToolCallResponse {
  content : ArrayView[Json]
  structured_content : Json?
  is_error : Bool?
  meta : Json?
} derive(Debug)

///|
pub impl FromJson for AppMcpServerToolCallResponse with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "content": content,
      "structuredContent"? : structured_content,
      "isError"? : is_error,
      "_meta"? : meta,
      ..
    } else {
    raise JsonDecodeError((path, "expected mcp/server/tool/call response"))
  }
  {
    content: @json.from_json(content, path=path.add_key("content")),
    structured_content: app_optional_json(structured_content),
    is_error: app_optional_bool(is_error, path.add_key("isError")),
    meta: app_optional_json(meta),
  }
}

///|
pub struct AppWindowsSandboxSetupStartResponse {
  started : Bool
} derive(Debug)

///|
pub impl FromJson for AppWindowsSandboxSetupStartResponse with fn from_json(
  value,
  path,
) {
  guard value is { "started": started, .. } else {
    raise JsonDecodeError(
      (path, "expected windowsSandbox/setup/start response"),
    )
  }
  { started: app_bool(started, path.add_key("started")) }
}

///|
pub enum AppAccountLoginStartResponse {
  AppAccountLoginApiKey
  AppAccountLoginChatGPT(login_id~ : String, auth_url~ : String)
  AppAccountLoginChatGPTDeviceCode(
    login_id~ : String,
    verification_url~ : String,
    user_code~ : String
  )
  AppAccountLoginChatGPTAuthTokens
} derive(Debug)

///|
pub impl FromJson for AppAccountLoginStartResponse with fn from_json(
  value,
  path,
) {
  match value {
    { "type": String("apiKey"), .. } => AppAccountLoginApiKey
    {
      "type": String("chatgpt"),
      "loginId": String(login_id),
      "authUrl": String(auth_url),
      ..
    } => AppAccountLoginChatGPT(login_id~, auth_url~)
    {
      "type": String("chatgptDeviceCode"),
      "loginId": String(login_id),
      "verificationUrl": String(verification_url),
      "userCode": String(user_code),
      ..
    } =>
      AppAccountLoginChatGPTDeviceCode(login_id~, verification_url~, user_code~)
    { "type": String("chatgptAuthTokens"), .. } =>
      AppAccountLoginChatGPTAuthTokens
    _ => raise JsonDecodeError((path, "expected account/login/start response"))
  }
}

///|
pub enum AppCancelLoginAccountStatus {
  AppCancelLoginCanceled
  AppCancelLoginNotFound
} derive(Debug)

///|
pub impl FromJson for AppCancelLoginAccountStatus with fn from_json(value, path) {
  match value {
    String("canceled") => AppCancelLoginCanceled
    String("notFound") => AppCancelLoginNotFound
    _ => raise JsonDecodeError((path, "expected cancel login account status"))
  }
}

///|
pub struct AppAccountLoginCancelResponse {
  status : AppCancelLoginAccountStatus
} derive(Debug)

///|
pub impl FromJson for AppAccountLoginCancelResponse with fn from_json(
  value,
  path,
) {
  guard value is { "status": status, .. } else {
    raise JsonDecodeError((path, "expected account/login/cancel response"))
  }
  { status: @json.from_json(status, path=path.add_key("status")) }
}

///|
pub struct AppRateLimitSnapshot {
  limit_id : String?
  limit_name : String?
  primary : AppRateLimitWindow?
  secondary : AppRateLimitWindow?
  credits : AppCreditsSnapshot?
  plan_type : AppPlanType?
  rate_limit_reached_type : AppRateLimitReachedType?
  priv raw : Json
} derive(Debug)

///|
pub struct AppRateLimitWindow {
  used_percent : Int
  window_duration_mins : Int64?
  resets_at : Int64?
} derive(Debug)

///|
pub impl FromJson for AppRateLimitWindow with fn from_json(value, path) {
  guard value
    is {
      "usedPercent": Number(used_percent, ..),
      "windowDurationMins"? : window_duration_mins,
      "resetsAt"? : resets_at,
      ..
    } else {
    raise JsonDecodeError((path, "expected rate limit window"))
  }
  {
    used_percent: used_percent.to_int(),
    window_duration_mins: app_optional_int64(
      window_duration_mins,
      path.add_key("windowDurationMins"),
    ),
    resets_at: app_optional_int64(resets_at, path.add_key("resetsAt")),
  }
}

///|
pub struct AppCreditsSnapshot {
  has_credits : Bool
  unlimited : Bool
  balance : String?
} derive(Debug)

///|
pub impl FromJson for AppCreditsSnapshot with fn from_json(value, path) {
  guard value
    is {
      "hasCredits": has_credits,
      "unlimited": unlimited,
      "balance"? : balance,
      ..
    } else {
    raise JsonDecodeError((path, "expected credits snapshot"))
  }
  {
    has_credits: app_bool(has_credits, path.add_key("hasCredits")),
    unlimited: app_bool(unlimited, path.add_key("unlimited")),
    balance: app_optional_string(balance, path.add_key("balance")),
  }
}

///|
pub enum AppPlanType {
  AppPlanFree
  AppPlanGo
  AppPlanPlus
  AppPlanPro
  AppPlanProlite
  AppPlanTeam
  AppPlanSelfServeBusinessUsageBased
  AppPlanBusiness
  AppPlanEnterpriseCbpUsageBased
  AppPlanEnterprise
  AppPlanEdu
  AppPlanUnknown
} derive(Debug)

///|
pub impl FromJson for AppPlanType with fn from_json(value, path) {
  match value {
    String("free") => AppPlanFree
    String("go") => AppPlanGo
    String("plus") => AppPlanPlus
    String("pro") => AppPlanPro
    String("prolite") => AppPlanProlite
    String("team") => AppPlanTeam
    String("self_serve_business_usage_based") =>
      AppPlanSelfServeBusinessUsageBased
    String("business") => AppPlanBusiness
    String("enterprise_cbp_usage_based") => AppPlanEnterpriseCbpUsageBased
    String("enterprise") => AppPlanEnterprise
    String("edu") => AppPlanEdu
    String("unknown") => AppPlanUnknown
    _ => raise JsonDecodeError((path, "expected plan type"))
  }
}

///|
pub enum AppRateLimitReachedType {
  AppRateLimitReached
  AppWorkspaceOwnerCreditsDepleted
  AppWorkspaceMemberCreditsDepleted
  AppWorkspaceOwnerUsageLimitReached
  AppWorkspaceMemberUsageLimitReached
} derive(Debug)

///|
pub impl FromJson for AppRateLimitReachedType with fn from_json(value, path) {
  match value {
    String("rate_limit_reached") => AppRateLimitReached
    String("workspace_owner_credits_depleted") =>
      AppWorkspaceOwnerCreditsDepleted
    String("workspace_member_credits_depleted") =>
      AppWorkspaceMemberCreditsDepleted
    String("workspace_owner_usage_limit_reached") =>
      AppWorkspaceOwnerUsageLimitReached
    String("workspace_member_usage_limit_reached") =>
      AppWorkspaceMemberUsageLimitReached
    _ => raise JsonDecodeError((path, "expected rate limit reached type"))
  }
}

///|
pub impl FromJson for AppRateLimitSnapshot with fn from_json(value, path) {
  guard value
    is {
      "limitId"? : limit_id,
      "limitName"? : limit_name,
      "primary"? : primary,
      "secondary"? : secondary,
      "credits"? : credits,
      "planType"? : plan_type,
      "rateLimitReachedType"? : rate_limit_reached_type,
      ..
    } else {
    raise JsonDecodeError((path, "expected rate limit snapshot"))
  }
  {
    limit_id: app_optional_string(limit_id, path.add_key("limitId")),
    limit_name: app_optional_string(limit_name, path.add_key("limitName")),
    primary: match primary {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("primary")))
    },
    secondary: match secondary {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("secondary")))
    },
    credits: match credits {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("credits")))
    },
    plan_type: match plan_type {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("planType")))
    },
    rate_limit_reached_type: match rate_limit_reached_type {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("rateLimitReachedType")))
    },
    raw: value,
  }
}

///|
pub struct AppAccountRateLimitsReadResponse {
  rate_limits : AppRateLimitSnapshot
  rate_limits_by_limit_id : Map[String, AppRateLimitSnapshot]?
} derive(Debug)

///|
pub impl FromJson for AppAccountRateLimitsReadResponse with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "rateLimits": rate_limits,
      "rateLimitsByLimitId"? : rate_limits_by_limit_id,
      ..
    } else {
    raise JsonDecodeError((path, "expected account/rateLimits/read response"))
  }
  {
    rate_limits: @json.from_json(rate_limits, path=path.add_key("rateLimits")),
    rate_limits_by_limit_id: match rate_limits_by_limit_id {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("rateLimitsByLimitId")))
    },
  }
}

///|
pub enum AppAddCreditsNudgeEmailStatus {
  AppAddCreditsNudgeSent
  AppAddCreditsNudgeCooldownActive
} derive(Debug)

///|
pub impl FromJson for AppAddCreditsNudgeEmailStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("sent") => AppAddCreditsNudgeSent
    String("cooldown_active") => AppAddCreditsNudgeCooldownActive
    _ => raise JsonDecodeError((path, "expected add-credits nudge status"))
  }
}

///|
pub struct AppAccountSendAddCreditsNudgeEmailResponse {
  status : AppAddCreditsNudgeEmailStatus
} derive(Debug)

///|
pub impl FromJson for AppAccountSendAddCreditsNudgeEmailResponse with fn from_json(
  value,
  path,
) {
  guard value is { "status": status, .. } else {
    raise JsonDecodeError(
      (path, "expected account/sendAddCreditsNudgeEmail response"),
    )
  }
  { status: @json.from_json(status, path=path.add_key("status")) }
}

///|
pub struct AppFeedbackUploadResponse {
  thread_id : String
} derive(Debug)

///|
pub impl FromJson for AppFeedbackUploadResponse with fn from_json(value, path) {
  guard value is { "threadId": String(thread_id), .. } else {
    raise JsonDecodeError((path, "expected feedback/upload response"))
  }
  { thread_id, }
}

///|
pub struct AppCommandExecResponse {
  exit_code : Int
  stdout : String
  stderr : String
} derive(Debug)

///|
pub impl FromJson for AppCommandExecResponse with fn from_json(value, path) {
  guard value
    is {
      "exitCode": Number(exit_code, ..),
      "stdout": String(stdout),
      "stderr": String(stderr),
      ..
    } else {
    raise JsonDecodeError((path, "expected command/exec response"))
  }
  { exit_code: exit_code.to_int(), stdout, stderr }
}

///|
pub struct AppExternalAgentConfigDetectResponse {
  items : ArrayView[AppExternalAgentConfigMigrationItem]
} derive(Debug)

///|
pub impl FromJson for AppExternalAgentConfigMigrationItem with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "itemType": item_type,
      "description": String(description),
      "cwd"? : cwd,
      "details"? : details,
      ..
    } else {
    raise JsonDecodeError(
      (path, "expected external agent config migration item"),
    )
  }
  {
    item_type: @json.from_json(item_type, path=path.add_key("itemType")),
    description,
    cwd: app_optional_string(cwd, path.add_key("cwd")),
    details: match details {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("details")))
    },
  }
}

///|
pub impl FromJson for AppExternalAgentConfigDetectResponse with fn from_json(
  value,
  path,
) {
  guard value is { "items": items, .. } else {
    raise JsonDecodeError(
      (path, "expected externalAgentConfig/detect response"),
    )
  }
  { items: @json.from_json(items, path=path.add_key("items")) }
}

///|
pub enum AppConfigWriteStatus {
  AppConfigWriteOk
  AppConfigWriteOkOverridden
} derive(Debug)

///|
pub impl FromJson for AppConfigWriteStatus with fn from_json(value, path) {
  match value {
    String("ok") => AppConfigWriteOk
    String("okOverridden") => AppConfigWriteOkOverridden
    _ => raise JsonDecodeError((path, "expected config write status"))
  }
}

///|
pub struct AppConfigOverriddenMetadata {
  message : String
  overriding_layer : AppConfigLayerMetadata
  effective_value : Json
} derive(Debug)

///|
pub struct AppConfigLayerMetadata {
  name : AppConfigLayerSource
  version : String
} derive(Debug)

///|
pub impl FromJson for AppConfigLayerMetadata with fn from_json(value, path) {
  guard value is { "name": name, "version": String(version), .. } else {
    raise JsonDecodeError((path, "expected config layer metadata"))
  }
  { name: @json.from_json(name, path=path.add_key("name")), version }
}

///|
pub enum AppConfigLayerSource {
  AppConfigLayerMdm(domain~ : String, key~ : String)
  AppConfigLayerSystem(file~ : String)
  AppConfigLayerUser(file~ : String)
  AppConfigLayerProject(dot_codex_folder~ : String)
  AppConfigLayerSessionFlags
  AppConfigLayerLegacyManagedConfigTomlFromFile(file~ : String)
  AppConfigLayerLegacyManagedConfigTomlFromMdm
} derive(Debug)

///|
pub impl FromJson for AppConfigLayerSource with fn from_json(value, path) {
  match value {
    { "type": String("mdm"), "domain": String(domain), "key": String(key), .. } =>
      AppConfigLayerMdm(domain~, key~)
    { "type": String("system"), "file": String(file), .. } =>
      AppConfigLayerSystem(file~)
    { "type": String("user"), "file": String(file), .. } =>
      AppConfigLayerUser(file~)
    {
      "type": String("project"),
      "dotCodexFolder": String(dot_codex_folder),
      ..
    } => AppConfigLayerProject(dot_codex_folder~)
    { "type": String("sessionFlags"), .. } => AppConfigLayerSessionFlags
    {
      "type": String("legacyManagedConfigTomlFromFile"),
      "file": String(file),
      ..
    } => AppConfigLayerLegacyManagedConfigTomlFromFile(file~)
    { "type": String("legacyManagedConfigTomlFromMdm"), .. } =>
      AppConfigLayerLegacyManagedConfigTomlFromMdm
    _ => raise JsonDecodeError((path, "expected config layer source"))
  }
}

///|
pub impl FromJson for AppConfigOverriddenMetadata with fn from_json(value, path) {
  guard value
    is {
      "message": String(message),
      "overridingLayer": overriding_layer,
      "effectiveValue": effective_value,
      ..
    } else {
    raise JsonDecodeError((path, "expected config overridden metadata"))
  }
  {
    message,
    overriding_layer: @json.from_json(
      overriding_layer,
      path=path.add_key("overridingLayer"),
    ),
    effective_value,
  }
}

///|
pub struct AppConfigValueWriteResponse {
  status : AppConfigWriteStatus
  version : String
  file_path : String
  overridden_metadata : AppConfigOverriddenMetadata?
} derive(Debug)

///|
pub impl FromJson for AppConfigValueWriteResponse with fn from_json(value, path) {
  guard value
    is {
      "status": status,
      "version": String(version),
      "filePath": String(file_path),
      "overriddenMetadata"? : overridden_metadata,
      ..
    } else {
    raise JsonDecodeError((path, "expected config/value/write response"))
  }
  {
    status: @json.from_json(status, path=path.add_key("status")),
    version,
    file_path,
    overridden_metadata: match overridden_metadata {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("overriddenMetadata")))
    },
  }
}

///|
pub struct AppConfigBatchWriteResponse {
  status : AppConfigWriteStatus
  version : String
  file_path : String
  overridden_metadata : AppConfigOverriddenMetadata?
} derive(Debug)

///|
pub impl FromJson for AppConfigBatchWriteResponse with fn from_json(value, path) {
  guard value
    is {
      "status": status,
      "version": String(version),
      "filePath": String(file_path),
      "overriddenMetadata"? : overridden_metadata,
      ..
    } else {
    raise JsonDecodeError((path, "expected config/batch/write response"))
  }
  {
    status: @json.from_json(status, path=path.add_key("status")),
    version,
    file_path,
    overridden_metadata: match overridden_metadata {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("overriddenMetadata")))
    },
  }
}

///|
pub struct AppConfigRequirementsReadResponse {
  requirements : AppConfigRequirements?
} derive(Debug)

///|
pub struct AppConfigRequirements {
  allowed_approval_policies : ArrayView[AppApprovalPolicy]?
  allowed_sandbox_modes : ArrayView[SandboxMode]?
  allowed_web_search_modes : ArrayView[AppWebSearchMode]?
  allow_managed_hooks_only : Bool?
  feature_requirements : Map[String, Bool]?
  enforce_residency : AppResidencyRequirement?
} derive(Debug)

///|
pub impl FromJson for AppConfigRequirements with fn from_json(value, path) {
  guard value
    is {
      "allowedApprovalPolicies"? : allowed_approval_policies,
      "allowedSandboxModes"? : allowed_sandbox_modes,
      "allowedWebSearchModes"? : allowed_web_search_modes,
      "allowManagedHooksOnly"? : allow_managed_hooks_only,
      "featureRequirements"? : feature_requirements,
      "enforceResidency"? : enforce_residency,
      ..
    } else {
    raise JsonDecodeError((path, "expected config requirements"))
  }
  {
    allowed_approval_policies: match allowed_approval_policies {
      Some(Null) | None => None
      Some(value) =>
        Some(
          @json.from_json(value, path=path.add_key("allowedApprovalPolicies")),
        )
    },
    allowed_sandbox_modes: match allowed_sandbox_modes {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("allowedSandboxModes")))
    },
    allowed_web_search_modes: match allowed_web_search_modes {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("allowedWebSearchModes")))
    },
    allow_managed_hooks_only: app_optional_bool(
      allow_managed_hooks_only,
      path.add_key("allowManagedHooksOnly"),
    ),
    feature_requirements: match feature_requirements {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("featureRequirements")))
    },
    enforce_residency: match enforce_residency {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("enforceResidency")))
    },
  }
}

///|
pub enum AppWebSearchMode {
  AppWebSearchDisabled
  AppWebSearchCached
  AppWebSearchLive
} derive(Debug)

///|
pub impl FromJson for AppWebSearchMode with fn from_json(value, path) {
  match value {
    String("disabled") => AppWebSearchDisabled
    String("cached") => AppWebSearchCached
    String("live") => AppWebSearchLive
    _ => raise JsonDecodeError((path, "expected web search mode"))
  }
}

///|
pub enum AppResidencyRequirement {
  AppResidencyUs
} derive(Debug)

///|
pub impl FromJson for AppResidencyRequirement with fn from_json(value, path) {
  match value {
    String("us") => AppResidencyUs
    _ => raise JsonDecodeError((path, "expected residency requirement"))
  }
}

///|
pub impl FromJson for AppConfigRequirementsReadResponse with fn from_json(
  value,
  path,
) {
  guard value is { "requirements"? : requirements, .. } else {
    raise JsonDecodeError((path, "expected configRequirements/read response"))
  }
  {
    requirements: match requirements {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("requirements")))
    },
  }
}

///|
pub enum AppAccount {
  AppAccountApiKey
  AppAccountChatGPT(email~ : String, plan_type~ : AppPlanType)
  AppAccountAmazonBedrock
} derive(Debug)

///|
pub impl FromJson for AppAccount with fn from_json(value, path) {
  match value {
    { "type": String("apiKey"), .. } => AppAccountApiKey
    {
      "type": String("chatgpt"),
      "email": String(email),
      "planType": plan_type,
      ..
    } =>
      AppAccountChatGPT(
        email~,
        plan_type=@json.from_json(plan_type, path=path.add_key("planType")),
      )
    { "type": String("amazonBedrock"), .. } => AppAccountAmazonBedrock
    _ => raise JsonDecodeError((path, "expected account"))
  }
}

///|
pub struct AppAccountReadResponse {
  account : AppAccount?
  requires_openai_auth : Bool
} derive(Debug)

///|
pub impl FromJson for AppAccountReadResponse with fn from_json(value, path) {
  guard value
    is { "account"? : account, "requiresOpenaiAuth": requires_openai_auth, .. } else {
    raise JsonDecodeError((path, "expected account/read response"))
  }
  {
    account: match account {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("account")))
    },
    requires_openai_auth: app_bool(
      requires_openai_auth,
      path.add_key("requiresOpenaiAuth"),
    ),
  }
}

///|
pub struct AppConversationGitInfo {
  sha : String?
  branch : String?
  origin_url : String?
} derive(Debug)

///|
pub impl FromJson for AppConversationGitInfo with fn from_json(value, path) {
  guard value
    is { "sha"? : sha, "branch"? : branch, "originUrl"? : origin_url, .. } else {
    raise JsonDecodeError((path, "expected conversation git info"))
  }
  {
    sha: app_optional_string(sha, path.add_key("sha")),
    branch: app_optional_string(branch, path.add_key("branch")),
    origin_url: app_optional_string(origin_url, path.add_key("originUrl")),
  }
}

///|
pub enum AppFuzzyFileSearchMatchType {
  AppFuzzyFile
  AppFuzzyDirectory
} derive(Debug)

///|
pub impl FromJson for AppFuzzyFileSearchMatchType with fn from_json(value, path) {
  match value {
    String("file") => AppFuzzyFile
    String("directory") => AppFuzzyDirectory
    _ => raise JsonDecodeError((path, "expected fuzzy file search match type"))
  }
}

///|
pub struct AppFuzzyFileSearchResult {
  root : String
  path : String
  match_type : AppFuzzyFileSearchMatchType
  file_name : String
  score : UInt
  indices : ArrayView[UInt]?
} derive(Debug)

///|
pub impl FromJson for AppFuzzyFileSearchResult with fn from_json(value, path) {
  guard value
    is {
      "root": String(root),
      "path": String(result_path),
      "score": Number(score, ..),
      "indices"? : indices,
      ..
    } else {
    raise JsonDecodeError((path, "expected fuzzy file search result"))
  }
  let match_type = match value {
    { "match_type": value, .. } => value
    { "matchType": value, .. } => value
    _ =>
      raise JsonDecodeError(
        (path.add_key("match_type"), "expected fuzzy file search match type"),
      )
  }
  let match_type_path = match value {
    { "match_type": _, .. } => path.add_key("match_type")
    { "matchType": _, .. } => path.add_key("matchType")
    _ => path.add_key("match_type")
  }
  let file_name = match value {
    { "file_name": String(file_name), .. } => file_name
    { "fileName": String(file_name), .. } => file_name
    _ =>
      raise JsonDecodeError(
        (path.add_key("file_name"), "expected fuzzy file search file name"),
      )
  }
  {
    root,
    path: result_path,
    match_type: @json.from_json(match_type, path=match_type_path),
    file_name,
    score: score.to_uint(),
    indices: match indices {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("indices")))
    },
  }
}

///|
pub struct AppFuzzyFileSearchResponse {
  files : ArrayView[AppFuzzyFileSearchResult]
} derive(Debug)

///|
pub impl FromJson for AppFuzzyFileSearchResponse with fn from_json(value, path) {
  guard value is { "files": files, .. } else {
    raise JsonDecodeError((path, "expected fuzzyFileSearch response"))
  }
  { files: @json.from_json(files, path=path.add_key("files")) }
}

///|
/// Call `initialize`.
async fn CodexAppConnection::initialize(
  self : CodexAppConnection,
  params : AppInitializeParams,
) -> AppInitializeResponse {
  @json.from_json(self.call_raw("initialize", params=params.to_json()))
}

///|
/// Call `thread/fork`.
pub async fn CodexAppConnection::thread_fork(
  self : CodexAppConnection,
  params : AppThreadForkParams,
) -> AppThreadForkResponse {
  @json.from_json(self.call_raw("thread/fork", params=params.to_json()))
}

///|
/// Call `thread/metadata/update`.
pub async fn CodexAppConnection::thread_metadata_update(
  self : CodexAppConnection,
  params : AppThreadMetadataUpdateParams,
) -> AppThreadMetadataUpdateResponse {
  @json.from_json(
    self.call_raw("thread/metadata/update", params=params.to_json()),
  )
}

///|
/// Call `thread/compact/start`.
pub async fn CodexAppConnection::thread_compact_start(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> Unit {
  self.call_empty("thread/compact/start", params=params.to_json())
}

///|
/// Call `thread/shellCommand`.
pub async fn CodexAppConnection::thread_shell_command(
  self : CodexAppConnection,
  params : AppThreadShellCommandParams,
) -> Unit {
  self.call_empty("thread/shellCommand", params=params.to_json())
}

///|
/// Call `thread/approveGuardianDeniedAction`.
pub async fn CodexAppConnection::thread_approve_guardian_denied_action(
  self : CodexAppConnection,
  params : AppThreadApproveGuardianDeniedActionParams,
) -> Unit {
  self.call_empty("thread/approveGuardianDeniedAction", params=params.to_json())
}

///|
/// Call `thread/rollback`.
pub async fn CodexAppConnection::thread_rollback(
  self : CodexAppConnection,
  params : AppThreadRollbackParams,
) -> AppThreadRollbackResponse {
  @json.from_json(self.call_raw("thread/rollback", params=params.to_json()))
}

///|
/// Call `thread/inject_items`.
pub async fn CodexAppConnection::thread_inject_items(
  self : CodexAppConnection,
  params : AppThreadInjectItemsParams,
) -> Unit {
  self.call_empty("thread/inject_items", params=params.to_json())
}

///|
/// Call `hooks/list`.
pub async fn CodexAppConnection::hooks_list(
  self : CodexAppConnection,
  params : AppHooksListParams,
) -> AppHooksListResponse {
  @json.from_json(self.call_raw("hooks/list", params=params.to_json()))
}

///|
/// Call `marketplace/add`.
pub async fn CodexAppConnection::marketplace_add(
  self : CodexAppConnection,
  params : AppMarketplaceAddParams,
) -> AppMarketplaceAddResponse {
  @json.from_json(self.call_raw("marketplace/add", params=params.to_json()))
}

///|
/// Call `marketplace/remove`.
pub async fn CodexAppConnection::marketplace_remove(
  self : CodexAppConnection,
  params : AppMarketplaceRemoveParams,
) -> AppMarketplaceRemoveResponse {
  @json.from_json(self.call_raw("marketplace/remove", params=params.to_json()))
}

///|
/// Call `marketplace/upgrade`.
pub async fn CodexAppConnection::marketplace_upgrade(
  self : CodexAppConnection,
  params : AppMarketplaceUpgradeParams,
) -> AppMarketplaceUpgradeResponse {
  @json.from_json(self.call_raw("marketplace/upgrade", params=params.to_json()))
}

///|
/// Call `plugin/list`.
pub async fn CodexAppConnection::plugin_list(
  self : CodexAppConnection,
  params : AppPluginListParams,
) -> AppPluginListResponse {
  @json.from_json(self.call_raw("plugin/list", params=params.to_json()))
}

///|
/// Call `plugin/read`.
pub async fn CodexAppConnection::plugin_read(
  self : CodexAppConnection,
  params : AppPluginReadParams,
) -> AppPluginReadResponse {
  @json.from_json(self.call_raw("plugin/read", params=params.to_json()))
}

///|
/// Call `fs/readFile`.
pub async fn CodexAppConnection::fs_read_file(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsReadFileResponse {
  @json.from_json(self.call_raw("fs/readFile", params=params.to_json()))
}

///|
/// Call `fs/writeFile`.
pub async fn CodexAppConnection::fs_write_file(
  self : CodexAppConnection,
  params : AppFsWriteFileParams,
) -> Unit {
  self.call_empty("fs/writeFile", params=params.to_json())
}

///|
/// Call `fs/createDirectory`.
pub async fn CodexAppConnection::fs_create_directory(
  self : CodexAppConnection,
  params : AppFsCreateDirectoryParams,
) -> Unit {
  self.call_empty("fs/createDirectory", params=params.to_json())
}

///|
/// Call `fs/getMetadata`.
pub async fn CodexAppConnection::fs_get_metadata(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsGetMetadataResponse {
  @json.from_json(self.call_raw("fs/getMetadata", params=params.to_json()))
}

///|
/// Call `fs/readDirectory`.
pub async fn CodexAppConnection::fs_read_directory(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsReadDirectoryResponse {
  @json.from_json(self.call_raw("fs/readDirectory", params=params.to_json()))
}

///|
/// Call `fs/remove`.
pub async fn CodexAppConnection::fs_remove(
  self : CodexAppConnection,
  params : AppFsRemoveParams,
) -> Unit {
  self.call_empty("fs/remove", params=params.to_json())
}

///|
/// Call `fs/copy`.
pub async fn CodexAppConnection::fs_copy(
  self : CodexAppConnection,
  params : AppFsCopyParams,
) -> Unit {
  self.call_empty("fs/copy", params=params.to_json())
}

///|
/// Call `fs/watch`.
pub async fn CodexAppConnection::fs_watch(
  self : CodexAppConnection,
  params : AppFsWatchParams,
) -> AppFsWatchResponse {
  @json.from_json(self.call_raw("fs/watch", params=params.to_json()))
}

///|
/// Call `fs/unwatch`.
pub async fn CodexAppConnection::fs_unwatch(
  self : CodexAppConnection,
  params : AppFsUnwatchParams,
) -> Unit {
  self.call_empty("fs/unwatch", params=params.to_json())
}

///|
/// Call `skills/config/write`.
pub async fn CodexAppConnection::skills_config_write(
  self : CodexAppConnection,
  params : AppSkillsConfigWriteParams,
) -> AppSkillsConfigWriteResponse {
  @json.from_json(self.call_raw("skills/config/write", params=params.to_json()))
}

///|
/// Call `plugin/install`.
pub async fn CodexAppConnection::plugin_install(
  self : CodexAppConnection,
  params : AppPluginInstallParams,
) -> AppPluginInstallResponse {
  @json.from_json(self.call_raw("plugin/install", params=params.to_json()))
}

///|
/// Call `plugin/uninstall`.
pub async fn CodexAppConnection::plugin_uninstall(
  self : CodexAppConnection,
  params : AppPluginUninstallParams,
) -> Unit {
  self.call_empty("plugin/uninstall", params=params.to_json())
}

///|
/// Call `review/start`.
pub async fn CodexAppConnection::review_start(
  self : CodexAppConnection,
  params : AppReviewStartParams,
) -> AppReviewStartResponse {
  @json.from_json(self.call_raw("review/start", params=params.to_json()))
}

///|
/// Call `experimentalFeature/list`.
pub async fn CodexAppConnection::experimental_feature_list(
  self : CodexAppConnection,
  params : AppCursorLimitParams,
) -> AppExperimentalFeatureListResponse {
  @json.from_json(
    self.call_raw("experimentalFeature/list", params=params.to_json()),
  )
}

///|
/// Call `experimentalFeature/enablement/set`.
pub async fn CodexAppConnection::experimental_feature_enablement_set(
  self : CodexAppConnection,
  params : AppExperimentalFeatureEnablementSetParams,
) -> AppExperimentalFeatureEnablementSetResponse {
  @json.from_json(
    self.call_raw("experimentalFeature/enablement/set", params=params.to_json()),
  )
}

///|
/// Call `mcpServer/oauth/login`.
pub async fn CodexAppConnection::mcp_server_oauth_login(
  self : CodexAppConnection,
  params : AppMcpServerOauthLoginParams,
) -> AppMcpServerOauthLoginResponse {
  @json.from_json(
    self.call_raw("mcpServer/oauth/login", params=params.to_json()),
  )
}

///|
/// Call `config/mcpServer/reload`.
pub async fn CodexAppConnection::config_mcp_server_reload(
  self : CodexAppConnection,
) -> Unit {
  self.call_empty("config/mcpServer/reload")
}

///|
/// Call `mcpServerStatus/list`.
pub async fn CodexAppConnection::mcp_server_status_list(
  self : CodexAppConnection,
  params : AppMcpServerStatusListParams,
) -> AppMcpServerStatusListResponse {
  @json.from_json(
    self.call_raw("mcpServerStatus/list", params=params.to_json()),
  )
}

///|
/// Call `mcpServer/resource/read`.
pub async fn CodexAppConnection::mcp_server_resource_read(
  self : CodexAppConnection,
  params : AppMcpResourceReadParams,
) -> AppMcpServerResourceReadResponse {
  @json.from_json(
    self.call_raw("mcpServer/resource/read", params=params.to_json()),
  )
}

///|
/// Call `mcpServer/tool/call`.
pub async fn CodexAppConnection::mcp_server_tool_call(
  self : CodexAppConnection,
  params : AppMcpServerToolCallParams,
) -> AppMcpServerToolCallResponse {
  @json.from_json(self.call_raw("mcpServer/tool/call", params=params.to_json()))
}

///|
/// Call `windowsSandbox/setupStart`.
pub async fn CodexAppConnection::windows_sandbox_setup_start(
  self : CodexAppConnection,
  params : AppWindowsSandboxSetupStartParams,
) -> AppWindowsSandboxSetupStartResponse {
  @json.from_json(
    self.call_raw("windowsSandbox/setupStart", params=params.to_json()),
  )
}

///|
/// Call `account/login/start`.
pub async fn CodexAppConnection::account_login_start(
  self : CodexAppConnection,
  params : AppLoginAccountParams,
) -> AppAccountLoginStartResponse {
  @json.from_json(self.call_raw("account/login/start", params=params.to_json()))
}

///|
/// Call `account/login/cancel`.
pub async fn CodexAppConnection::account_login_cancel(
  self : CodexAppConnection,
  params : AppCancelLoginAccountParams,
) -> AppAccountLoginCancelResponse {
  @json.from_json(
    self.call_raw("account/login/cancel", params=params.to_json()),
  )
}

///|
/// Call `account/logout`.
pub async fn CodexAppConnection::account_logout(
  self : CodexAppConnection,
) -> Unit {
  self.call_empty("account/logout")
}

///|
/// Call `account/rateLimits/read`.
pub async fn CodexAppConnection::account_rate_limits_read(
  self : CodexAppConnection,
) -> AppAccountRateLimitsReadResponse {
  @json.from_json(self.call_raw("account/rateLimits/read"))
}

///|
/// Call `account/sendAddCreditsNudgeEmail`.
pub async fn CodexAppConnection::account_send_add_credits_nudge_email(
  self : CodexAppConnection,
  params : AppSendAddCreditsNudgeEmailParams,
) -> AppAccountSendAddCreditsNudgeEmailResponse {
  @json.from_json(
    self.call_raw("account/sendAddCreditsNudgeEmail", params=params.to_json()),
  )
}

///|
/// Call `feedback/upload`.
pub async fn CodexAppConnection::feedback_upload(
  self : CodexAppConnection,
  params : AppFeedbackUploadParams,
) -> AppFeedbackUploadResponse {
  @json.from_json(self.call_raw("feedback/upload", params=params.to_json()))
}

///|
/// Call `command/exec`.
pub async fn CodexAppConnection::command_exec(
  self : CodexAppConnection,
  params : AppCommandExecParams,
) -> AppCommandExecResponse {
  @json.from_json(self.call_raw("command/exec", params=params.to_json()))
}

///|
/// Call `command/exec/write`.
pub async fn CodexAppConnection::command_exec_write(
  self : CodexAppConnection,
  params : AppCommandExecWriteParams,
) -> Unit {
  self.call_empty("command/exec/write", params=params.to_json())
}

///|
/// Call `command/exec/terminate`.
pub async fn CodexAppConnection::command_exec_terminate(
  self : CodexAppConnection,
  params : AppCommandExecProcessParams,
) -> Unit {
  self.call_empty("command/exec/terminate", params=params.to_json())
}

///|
/// Call `command/exec/resize`.
pub async fn CodexAppConnection::command_exec_resize(
  self : CodexAppConnection,
  params : AppCommandExecResizeParams,
) -> Unit {
  self.call_empty("command/exec/resize", params=params.to_json())
}

///|
/// Call `externalAgentConfig/detect`.
pub async fn CodexAppConnection::external_agent_config_detect(
  self : CodexAppConnection,
  params : AppExternalAgentConfigDetectParams,
) -> AppExternalAgentConfigDetectResponse {
  @json.from_json(
    self.call_raw("externalAgentConfig/detect", params=params.to_json()),
  )
}

///|
/// Call `externalAgentConfig/import`.
pub async fn CodexAppConnection::external_agent_config_import(
  self : CodexAppConnection,
  params : AppExternalAgentConfigImportParams,
) -> Unit {
  self.call_empty("externalAgentConfig/import", params=params.to_json())
}

///|
/// Call `config/value/write`.
pub async fn CodexAppConnection::config_value_write(
  self : CodexAppConnection,
  params : AppConfigValueWriteParams,
) -> AppConfigValueWriteResponse {
  @json.from_json(self.call_raw("config/value/write", params=params.to_json()))
}

///|
/// Call `config/batchWrite`.
pub async fn CodexAppConnection::config_batch_write(
  self : CodexAppConnection,
  params : AppConfigBatchWriteParams,
) -> AppConfigBatchWriteResponse {
  @json.from_json(self.call_raw("config/batchWrite", params=params.to_json()))
}

///|
/// Call `configRequirements/read`.
pub async fn CodexAppConnection::config_requirements_read(
  self : CodexAppConnection,
) -> AppConfigRequirementsReadResponse {
  @json.from_json(self.call_raw("configRequirements/read"))
}

///|
/// Call `account/read`.
pub async fn CodexAppConnection::account_read(
  self : CodexAppConnection,
  params : AppAccountReadParams,
) -> AppAccountReadResponse {
  @json.from_json(self.call_raw("account/read", params=params.to_json()))
}

///|
/// Call `fuzzyFileSearch`.
pub async fn CodexAppConnection::fuzzy_file_search(
  self : CodexAppConnection,
  params : AppFuzzyFileSearchParams,
) -> AppFuzzyFileSearchResponse {
  @json.from_json(self.call_raw("fuzzyFileSearch", params=params.to_json()))
}

///|
/// Raw JSON-RPC message received from a Codex app server.
priv enum AppServerMessage {
  Notification(AppServerEvent)
  IgnoredNotification
  Request(AppServerRequest)
  UnsupportedRequest(id~ : AppRequestId, rpc_method~ : String)
  Response(id~ : AppRequestId, result~ : Json)
  ErrorResponse(id~ : AppRequestId, error~ : AppRpcError)
}

///|
/// JSON-RPC frame sent from this SDK to the Codex app server.
priv enum AppClientMessage {
  ClientRequest(id~ : AppRequestId, rpc_method~ : String, params~ : Json?)
  ClientNotification(rpc_method~ : String, params~ : Json?)
  ClientResponse(id~ : AppRequestId, result~ : Json)
  ClientErrorResponse(id~ : AppRequestId, error~ : AppRpcError)
}

///|
impl ToJson for AppClientMessage with fn to_json(message) {
  match message {
    ClientRequest(id~, rpc_method~, params~) => {
      let obj : Map[String, Json] = { "id": id, "method": rpc_method }
      if params is Some(params) {
        obj.set("params", params)
      }
      Json::object(obj)
    }
    ClientNotification(rpc_method~, params~) => {
      let obj : Map[String, Json] = { "method": rpc_method }
      if params is Some(params) {
        obj.set("params", params)
      }
      Json::object(obj)
    }
    ClientResponse(id~, result~) => { "id": id, "result": result }
    ClientErrorResponse(id~, error~) => { "id": id, "error": error }
  }
}

///|
impl FromJson for AppServerMessage with fn from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected JSON-RPC object"))
  }
  match obj {
    { "method": String(rpc_method), "id": id_json, "params"? : params, .. } =>
      match
        app_server_request(
          @json.from_json(id_json, path=path.add_key("id")),
          rpc_method,
          params,
          path.add_key("params"),
        ) {
        Some(request) => Request(request)
        None =>
          UnsupportedRequest(
            id=@json.from_json(id_json, path=path.add_key("id")),
            rpc_method~,
          )
      }
    { "method": String(_), .. } =>
      Notification(@json.from_json(value, path~)) catch {
        _ => IgnoredNotification
      }
    { "id": id_json, "result": result, .. } =>
      Response(id=@json.from_json(id_json, path=path.add_key("id")), result~)
    { "id": id_json, "error": error_json, .. } =>
      ErrorResponse(
        id=@json.from_json(id_json, path=path.add_key("id")),
        error=@json.from_json(error_json, path=path.add_key("error")),
      )
    _ => raise JsonDecodeError((path, "expected JSON-RPC message"))
  }
}

///|
fn app_server_request(
  id : AppRequestId,
  rpc_method : String,
  params : Json?,
  path : @json.JsonPath,
) -> AppServerRequest? raise @json.JsonDecodeError {
  let details = match rpc_method {
    "item/commandExecution/requestApproval" =>
      match params {
        Some(params) =>
          Some(
            AppCommandExecutionApprovalRequest(@json.from_json(params, path~)),
          )
        None => None
      }
    "item/fileChange/requestApproval" =>
      match params {
        Some(params) =>
          Some(AppFileChangeApprovalRequest(@json.from_json(params, path~)))
        None => None
      }
    "item/tool/requestUserInput" =>
      match params {
        Some(params) =>
          Some(AppToolRequestUserInputRequest(@json.from_json(params, path~)))
        None => None
      }
    "item/tool/call" =>
      match params {
        Some(params) =>
          Some(AppDynamicToolCallRequest(@json.from_json(params, path~)))
        None => None
      }
    "item/permissions/requestApproval" =>
      match params {
        Some(params) =>
          Some(
            AppPermissionsRequestApprovalRequest(@json.from_json(params, path~)),
          )
        None => None
      }
    "account/chatgptAuthTokens/refresh" =>
      match params {
        Some(params) =>
          Some(
            AppChatgptAuthTokensRefreshRequest(@json.from_json(params, path~)),
          )
        None => None
      }
    "mcpServer/elicitation/request" =>
      match params {
        Some(params) =>
          Some(AppMcpServerElicitationRequest(@json.from_json(params, path~)))
        None => None
      }
    _ => None
  }
  match details {
    Some(details) => Some({ id, details })
    None => None
  }
}

///|
/// App-server event. This is intentionally broader than the existing exec `Event`.
pub enum AppServerEvent {
  AppThreadStarted(AppThread)
  AppThreadStatusChanged(thread_id~ : String, status~ : AppThreadStatus)
  AppThreadArchived(thread_id~ : String)
  AppThreadUnarchived(thread_id~ : String)
  AppThreadClosed(thread_id~ : String)
  AppSkillsChanged
  AppThreadNameUpdated(thread_id~ : String, thread_name~ : String?)
  AppThreadGoalUpdated(
    thread_id~ : String,
    turn_id~ : String?,
    goal~ : AppThreadGoal
  )
  AppThreadGoalCleared(thread_id~ : String)
  AppTurnStarted(thread_id~ : String, turn~ : AppTurn)
  AppHookStarted(
    thread_id~ : String,
    turn_id~ : String?,
    run~ : AppHookRunSummary
  )
  AppTurnCompleted(thread_id~ : String, turn~ : AppTurn)
  AppHookCompleted(
    thread_id~ : String,
    turn_id~ : String?,
    run~ : AppHookRunSummary
  )
  AppTurnDiffUpdated(thread_id~ : String, turn_id~ : String, diff~ : String)
  AppTurnPlanUpdated(
    thread_id~ : String,
    turn_id~ : String,
    explanation~ : String?,
    plan~ : ArrayView[AppTurnPlanStep]
  )
  AppTurnError(
    thread_id~ : String,
    turn_id~ : String,
    error~ : AppTurnError,
    will_retry~ : Bool
  )
  AppItemStarted(AppThreadItemEvent)
  AppItemGuardianApprovalReviewStarted(
    thread_id~ : String,
    turn_id~ : String,
    started_at_ms~ : Int64,
    review_id~ : String,
    target_item_id~ : String?,
    review~ : AppGuardianApprovalReview,
    action~ : AppGuardianApprovalReviewAction
  )
  AppItemGuardianApprovalReviewCompleted(
    thread_id~ : String,
    turn_id~ : String,
    started_at_ms~ : Int64,
    completed_at_ms~ : Int64,
    review_id~ : String,
    target_item_id~ : String?,
    decision_source~ : AppAutoReviewDecisionSource,
    review~ : AppGuardianApprovalReview,
    action~ : AppGuardianApprovalReviewAction
  )
  AppItemCompleted(AppThreadItemEvent)
  AppRawResponseItemCompleted(
    thread_id~ : String,
    turn_id~ : String,
    item~ : AppResponseItem
  )
  AppAgentMessageDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppPlanDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppCommandExecOutputDelta(
    process_id~ : String,
    stream~ : AppOutputStream,
    delta_base64~ : String,
    cap_reached~ : Bool
  )
  AppCommandExecutionOutputDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppTerminalInteraction(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    process_id~ : String,
    stdin~ : String
  )
  AppFileChangeOutputDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppFileChangePatchUpdated(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    changes~ : ArrayView[AppThreadFileUpdateChange]
  )
  AppServerRequestResolved(thread_id~ : String, request_id~ : AppRequestId)
  AppMcpToolCallProgress(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    message~ : String
  )
  AppMcpServerOauthLoginCompleted(
    name~ : String,
    success~ : Bool,
    error~ : String?
  )
  AppMcpServerStatusUpdated(
    name~ : String,
    status~ : AppMcpServerStartupState,
    error~ : String?
  )
  AppAccountUpdated(auth_mode~ : AppAuthMode?, plan_type~ : AppPlanType?)
  AppAccountRateLimitsUpdated(rate_limits~ : AppRateLimitSnapshot)
  AppAppListUpdated(data~ : ArrayView[AppInfo])
  AppRemoteControlStatusChanged(
    status~ : AppRemoteControlConnectionStatus,
    installation_id~ : String,
    environment_id~ : String?
  )
  AppExternalAgentConfigImportCompleted
  AppFsChanged(watch_id~ : String, changed_paths~ : ArrayView[String])
  AppContextCompacted(thread_id~ : String, turn_id~ : String)
  AppFuzzyFileSearchSessionUpdated(
    session_id~ : String,
    query~ : String,
    files~ : ArrayView[AppFuzzyFileSearchResult]
  )
  AppFuzzyFileSearchSessionCompleted(session_id~ : String)
  AppReasoningSummaryTextDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String,
    summary_index~ : Int64
  )
  AppReasoningSummaryPartAdded(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    summary_index~ : Int64
  )
  AppReasoningTextDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String,
    content_index~ : Int64
  )
  AppWindowsWorldWritableWarning(
    sample_paths~ : ArrayView[String],
    extra_count~ : UInt64,
    failed_scan~ : Bool
  )
  AppWindowsSandboxSetupCompleted(
    mode~ : AppWindowsSandboxSetupMode,
    success~ : Bool,
    error~ : String?
  )
  AppAccountLoginCompleted(
    login_id~ : String?,
    success~ : Bool,
    error~ : String?
  )
  AppModelRerouted(
    thread_id~ : String,
    turn_id~ : String,
    from_model~ : String,
    to_model~ : String,
    reason~ : AppModelRerouteReason
  )
  AppModelVerification(
    thread_id~ : String,
    turn_id~ : String,
    verifications~ : ArrayView[AppModelVerification]
  )
  AppWarning(thread_id~ : String?, message~ : String)
  AppGuardianWarning(thread_id~ : String, message~ : String)
  AppDeprecationNotice(summary~ : String, details~ : String?)
  AppConfigWarning(
    summary~ : String,
    details~ : String?,
    path~ : String?,
    range~ : AppTextRange?
  )
  AppThreadTokenUsageUpdated(
    thread_id~ : String,
    turn_id~ : String,
    token_usage~ : AppThreadTokenUsage
  )
  AppThreadRealtimeStarted(
    thread_id~ : String,
    realtime_session_id~ : String?,
    version~ : AppRealtimeConversationVersion
  )
  AppThreadRealtimeItemAdded(thread_id~ : String, item~ : Json)
  AppThreadRealtimeTranscriptDelta(
    thread_id~ : String,
    role~ : String,
    delta~ : String
  )
  AppThreadRealtimeTranscriptDone(
    thread_id~ : String,
    role~ : String,
    text~ : String
  )
  AppThreadRealtimeOutputAudioDelta(
    thread_id~ : String,
    audio~ : AppThreadRealtimeAudioChunk
  )
  AppThreadRealtimeSdp(thread_id~ : String, sdp~ : String)
  AppThreadRealtimeError(thread_id~ : String, message~ : String)
  AppThreadRealtimeClosed(thread_id~ : String, reason~ : String?)
} derive(Debug)

///|
pub enum AppOutputStream {
  AppStdout
  AppStderr
} derive(Debug)

///|
pub impl FromJson for AppOutputStream with fn from_json(value, path) {
  match value {
    String("stdout") => AppStdout
    String("stderr") => AppStderr
    _ => raise JsonDecodeError((path, "expected output stream"))
  }
}

///|
pub enum AppMcpServerStartupState {
  AppMcpServerStarting
  AppMcpServerReady
  AppMcpServerFailed
  AppMcpServerCancelled
} derive(Debug)

///|
pub impl FromJson for AppMcpServerStartupState with fn from_json(value, path) {
  match value {
    String("starting") => AppMcpServerStarting
    String("ready") => AppMcpServerReady
    String("failed") => AppMcpServerFailed
    String("cancelled") => AppMcpServerCancelled
    _ => raise JsonDecodeError((path, "expected MCP server startup state"))
  }
}

///|
pub enum AppAuthMode {
  AppAuthApiKey
  AppAuthChatGPT
  AppAuthChatGPTAuthTokens
  AppAuthAgentIdentity
} derive(Debug)

///|
pub impl FromJson for AppAuthMode with fn from_json(value, path) {
  match value {
    String("apikey") => AppAuthApiKey
    String("chatgpt") => AppAuthChatGPT
    String("chatgptAuthTokens") => AppAuthChatGPTAuthTokens
    String("agentIdentity") => AppAuthAgentIdentity
    _ => raise JsonDecodeError((path, "expected auth mode"))
  }
}

///|
pub impl FromJson for AppServerEvent with fn from_json(value, path) {
  guard value
    is Object({ "method": String(rpc_method), "params"? : params, .. }) else {
    raise JsonDecodeError((path, "expected app-server notification"))
  }
  match rpc_method {
    "thread/started" => {
      guard params is Some({ "thread": thread, .. }) else {
        raise JsonDecodeError((path, "expected thread/started params"))
      }
      AppThreadStarted(
        @json.from_json(thread, path=path.add_key("params").add_key("thread")),
      )
    }
    "thread/status/changed" => {
      guard params
        is Some({ "threadId": String(thread_id), "status": status, .. }) else {
        raise JsonDecodeError((path, "expected thread/status/changed params"))
      }
      AppThreadStatusChanged(
        thread_id~,
        status=@json.from_json(
          status,
          path=path.add_key("params").add_key("status"),
        ),
      )
    }
    "thread/archived" => {
      guard params is Some({ "threadId": String(thread_id), .. }) else {
        raise JsonDecodeError((path, "expected thread/archived params"))
      }
      AppThreadArchived(thread_id~)
    }
    "thread/unarchived" => {
      guard params is Some({ "threadId": String(thread_id), .. }) else {
        raise JsonDecodeError((path, "expected thread/unarchived params"))
      }
      AppThreadUnarchived(thread_id~)
    }
    "thread/closed" => {
      guard params is Some({ "threadId": String(thread_id), .. }) else {
        raise JsonDecodeError((path, "expected thread/closed params"))
      }
      AppThreadClosed(thread_id~)
    }
    "skills/changed" => AppSkillsChanged
    "thread/name/updated" => {
      guard params
        is Some({ "threadId": String(thread_id), "threadName"? : name, .. }) else {
        raise JsonDecodeError((path, "expected thread/name/updated params"))
      }
      AppThreadNameUpdated(
        thread_id~,
        thread_name=app_optional_string(
          name,
          path.add_key("params").add_key("threadName"),
        ),
      )
    }
    "thread/goal/updated" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId"? : turn_id,
            "goal": goal,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected thread/goal/updated params"))
      }
      AppThreadGoalUpdated(
        thread_id~,
        turn_id=app_optional_string(
          turn_id,
          path.add_key("params").add_key("turnId"),
        ),
        goal=@json.from_json(goal, path=path.add_key("params").add_key("goal")),
      )
    }
    "thread/goal/cleared" => {
      guard params is Some({ "threadId": String(thread_id), .. }) else {
        raise JsonDecodeError((path, "expected thread/goal/cleared params"))
      }
      AppThreadGoalCleared(thread_id~)
    }
    "turn/started" => {
      guard params is Some({ "threadId": String(thread_id), "turn": turn, .. }) else {
        raise JsonDecodeError((path, "expected turn/started params"))
      }
      AppTurnStarted(
        thread_id~,
        turn=@json.from_json(turn, path=path.add_key("params").add_key("turn")),
      )
    }
    "hook/started" => {
      guard params
        is Some(
          { "threadId": String(thread_id), "turnId"? : turn_id, "run": run, .. }
        ) else {
        raise JsonDecodeError((path, "expected hook/started params"))
      }
      AppHookStarted(
        thread_id~,
        turn_id=app_optional_string(
          turn_id,
          path.add_key("params").add_key("turnId"),
        ),
        run=@json.from_json(run, path=path.add_key("params").add_key("run")),
      )
    }
    "turn/completed" => {
      guard params is Some({ "threadId": String(thread_id), "turn": turn, .. }) else {
        raise JsonDecodeError((path, "expected turn/completed params"))
      }
      AppTurnCompleted(
        thread_id~,
        turn=@json.from_json(turn, path=path.add_key("params").add_key("turn")),
      )
    }
    "hook/completed" => {
      guard params
        is Some(
          { "threadId": String(thread_id), "turnId"? : turn_id, "run": run, .. }
        ) else {
        raise JsonDecodeError((path, "expected hook/completed params"))
      }
      AppHookCompleted(
        thread_id~,
        turn_id=app_optional_string(
          turn_id,
          path.add_key("params").add_key("turnId"),
        ),
        run=@json.from_json(run, path=path.add_key("params").add_key("run")),
      )
    }
    "turn/diff/updated" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "diff": String(diff),
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected turn/diff/updated params"))
      }
      AppTurnDiffUpdated(thread_id~, turn_id~, diff~)
    }
    "turn/plan/updated" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "explanation"? : explanation,
            "plan": plan,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected turn/plan/updated params"))
      }
      AppTurnPlanUpdated(
        thread_id~,
        turn_id~,
        explanation=app_optional_string(
          explanation,
          path.add_key("params").add_key("explanation"),
        ),
        plan=@json.from_json(plan, path=path.add_key("params").add_key("plan")),
      )
    }
    "error" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "error": error,
            "willRetry": will_retry,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected error params"))
      }
      AppTurnError(
        thread_id~,
        turn_id~,
        error=@json.from_json(
          error,
          path=path.add_key("params").add_key("error"),
        ),
        will_retry=app_bool(
          will_retry,
          path.add_key("params").add_key("willRetry"),
        ),
      )
    }
    "item/started" => AppItemStarted(@json.from_json(value, path~))
    "item/autoApprovalReview/started" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "startedAtMs": Number(started_at_ms, ..),
            "reviewId": String(review_id),
            "targetItemId"? : target_item_id,
            "review": review,
            "action": action,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/autoApprovalReview/started params"),
        )
      }
      AppItemGuardianApprovalReviewStarted(
        thread_id~,
        turn_id~,
        started_at_ms=started_at_ms.to_int64(),
        review_id~,
        target_item_id=app_optional_string(
          target_item_id,
          path.add_key("params").add_key("targetItemId"),
        ),
        review=@json.from_json(
          review,
          path=path.add_key("params").add_key("review"),
        ),
        action=@json.from_json(
          action,
          path=path.add_key("params").add_key("action"),
        ),
      )
    }
    "item/autoApprovalReview/completed" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "startedAtMs": Number(started_at_ms, ..),
            "completedAtMs": Number(completed_at_ms, ..),
            "reviewId": String(review_id),
            "targetItemId"? : target_item_id,
            "decisionSource": decision_source,
            "review": review,
            "action": action,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/autoApprovalReview/completed params"),
        )
      }
      AppItemGuardianApprovalReviewCompleted(
        thread_id~,
        turn_id~,
        started_at_ms=started_at_ms.to_int64(),
        completed_at_ms=completed_at_ms.to_int64(),
        review_id~,
        target_item_id=app_optional_string(
          target_item_id,
          path.add_key("params").add_key("targetItemId"),
        ),
        decision_source=@json.from_json(
          decision_source,
          path=path.add_key("params").add_key("decisionSource"),
        ),
        review=@json.from_json(
          review,
          path=path.add_key("params").add_key("review"),
        ),
        action=@json.from_json(
          action,
          path=path.add_key("params").add_key("action"),
        ),
      )
    }
    "item/completed" => AppItemCompleted(@json.from_json(value, path~))
    "rawResponseItem/completed" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "item": item,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected rawResponseItem/completed params"),
        )
      }
      AppRawResponseItemCompleted(
        thread_id~,
        turn_id~,
        item=@json.from_json(item, path=path.add_key("params").add_key("item")),
      )
    }
    "item/agentMessage/delta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected item/agentMessage/delta params"))
      }
      AppAgentMessageDelta(thread_id~, turn_id~, item_id~, delta~)
    }
    "item/plan/delta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected item/plan/delta params"))
      }
      AppPlanDelta(thread_id~, turn_id~, item_id~, delta~)
    }
    "command/exec/outputDelta" => {
      guard params
        is Some(
          {
            "processId": String(process_id),
            "stream": stream,
            "deltaBase64": String(delta_base64),
            "capReached": cap_reached,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected command/exec/outputDelta params"),
        )
      }
      AppCommandExecOutputDelta(
        process_id~,
        stream=@json.from_json(
          stream,
          path=path.add_key("params").add_key("stream"),
        ),
        delta_base64~,
        cap_reached=app_bool(
          cap_reached,
          path.add_key("params").add_key("capReached"),
        ),
      )
    }
    "item/commandExecution/outputDelta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/commandExecution/outputDelta params"),
        )
      }
      AppCommandExecutionOutputDelta(thread_id~, turn_id~, item_id~, delta~)
    }
    "item/commandExecution/terminalInteraction" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "processId": String(process_id),
            "stdin": String(stdin),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/commandExecution/terminalInteraction params"),
        )
      }
      AppTerminalInteraction(
        thread_id~,
        turn_id~,
        item_id~,
        process_id~,
        stdin~,
      )
    }
    "item/fileChange/outputDelta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/fileChange/outputDelta params"),
        )
      }
      AppFileChangeOutputDelta(thread_id~, turn_id~, item_id~, delta~)
    }
    "item/fileChange/patchUpdated" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "changes": changes,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/fileChange/patchUpdated params"),
        )
      }
      AppFileChangePatchUpdated(
        thread_id~,
        turn_id~,
        item_id~,
        changes=@json.from_json(
          changes,
          path=path.add_key("params").add_key("changes"),
        ),
      )
    }
    "serverRequest/resolved" => {
      guard params
        is Some({ "threadId": String(thread_id), "requestId": request_id, .. }) else {
        raise JsonDecodeError((path, "expected serverRequest/resolved params"))
      }
      AppServerRequestResolved(
        thread_id~,
        request_id=@json.from_json(
          request_id,
          path=path.add_key("params").add_key("requestId"),
        ),
      )
    }
    "item/mcpToolCall/progress" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "message": String(message),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/mcpToolCall/progress params"),
        )
      }
      AppMcpToolCallProgress(thread_id~, turn_id~, item_id~, message~)
    }
    "mcpServer/oauthLogin/completed" => {
      guard params
        is Some(
          { "name": String(name), "success": success, "error"? : error, .. }
        ) else {
        raise JsonDecodeError(
          (path, "expected mcpServer/oauthLogin/completed params"),
        )
      }
      AppMcpServerOauthLoginCompleted(
        name~,
        success=app_bool(success, path.add_key("params").add_key("success")),
        error=app_optional_string(
          error,
          path.add_key("params").add_key("error"),
        ),
      )
    }
    "mcpServer/startupStatus/updated" => {
      guard params
        is Some(
          { "name": String(name), "status": status, "error"? : error, .. }
        ) else {
        raise JsonDecodeError(
          (path, "expected mcpServer/startupStatus/updated params"),
        )
      }
      AppMcpServerStatusUpdated(
        name~,
        status=@json.from_json(
          status,
          path=path.add_key("params").add_key("status"),
        ),
        error=app_optional_string(
          error,
          path.add_key("params").add_key("error"),
        ),
      )
    }
    "account/updated" => {
      guard params
        is Some({ "authMode"? : auth_mode, "planType"? : plan_type, .. }) else {
        raise JsonDecodeError((path, "expected account/updated params"))
      }
      AppAccountUpdated(
        auth_mode=match auth_mode {
          Some(Null) | None => None
          Some(value) =>
            Some(
              @json.from_json(
                value,
                path=path.add_key("params").add_key("authMode"),
              ),
            )
        },
        plan_type=match plan_type {
          Some(Null) | None => None
          Some(value) =>
            Some(
              @json.from_json(
                value,
                path=path.add_key("params").add_key("planType"),
              ),
            )
        },
      )
    }
    "account/rateLimits/updated" => {
      guard params is Some({ "rateLimits": rate_limits, .. }) else {
        raise JsonDecodeError(
          (path, "expected account/rateLimits/updated params"),
        )
      }
      AppAccountRateLimitsUpdated(
        rate_limits=@json.from_json(
          rate_limits,
          path=path.add_key("params").add_key("rateLimits"),
        ),
      )
    }
    "app/list/updated" => {
      guard params is Some({ "data": data, .. }) else {
        raise JsonDecodeError((path, "expected app/list/updated params"))
      }
      AppAppListUpdated(
        data=@json.from_json(data, path=path.add_key("params").add_key("data")),
      )
    }
    "remoteControl/status/changed" => {
      guard params
        is Some(
          {
            "status": status,
            "installationId": String(installation_id),
            "environmentId"? : environment_id,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected remoteControl/status/changed params"),
        )
      }
      AppRemoteControlStatusChanged(
        status=@json.from_json(
          status,
          path=path.add_key("params").add_key("status"),
        ),
        installation_id~,
        environment_id=app_optional_string(
          environment_id,
          path.add_key("params").add_key("environmentId"),
        ),
      )
    }
    "externalAgentConfig/import/completed" =>
      AppExternalAgentConfigImportCompleted
    "fs/changed" => {
      guard params
        is Some(
          { "watchId": String(watch_id), "changedPaths": changed_paths, .. }
        ) else {
        raise JsonDecodeError((path, "expected fs/changed params"))
      }
      AppFsChanged(
        watch_id~,
        changed_paths=@json.from_json(
          changed_paths,
          path=path.add_key("params").add_key("changedPaths"),
        ),
      )
    }
    "thread/compacted" => {
      guard params
        is Some(
          { "threadId": String(thread_id), "turnId": String(turn_id), .. }
        ) else {
        raise JsonDecodeError((path, "expected thread/compacted params"))
      }
      AppContextCompacted(thread_id~, turn_id~)
    }
    "fuzzyFileSearch/sessionUpdated" => {
      guard params
        is Some(
          {
            "sessionId": String(session_id),
            "query": String(query),
            "files": files,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected fuzzyFileSearch/sessionUpdated params"),
        )
      }
      AppFuzzyFileSearchSessionUpdated(
        session_id~,
        query~,
        files=@json.from_json(
          files,
          path=path.add_key("params").add_key("files"),
        ),
      )
    }
    "fuzzyFileSearch/sessionCompleted" => {
      guard params is Some({ "sessionId": String(session_id), .. }) else {
        raise JsonDecodeError(
          (path, "expected fuzzyFileSearch/sessionCompleted params"),
        )
      }
      AppFuzzyFileSearchSessionCompleted(session_id~)
    }
    "item/reasoning/summaryTextDelta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            "summaryIndex": Number(summary_index, ..),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/reasoning/summaryTextDelta params"),
        )
      }
      AppReasoningSummaryTextDelta(
        thread_id~,
        turn_id~,
        item_id~,
        delta~,
        summary_index=summary_index.to_int64(),
      )
    }
    "item/reasoning/summaryPartAdded" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "summaryIndex": Number(summary_index, ..),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/reasoning/summaryPartAdded params"),
        )
      }
      AppReasoningSummaryPartAdded(
        thread_id~,
        turn_id~,
        item_id~,
        summary_index=summary_index.to_int64(),
      )
    }
    "item/reasoning/textDelta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "itemId": String(item_id),
            "delta": String(delta),
            "contentIndex": Number(content_index, ..),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected item/reasoning/textDelta params"),
        )
      }
      AppReasoningTextDelta(
        thread_id~,
        turn_id~,
        item_id~,
        delta~,
        content_index=content_index.to_int64(),
      )
    }
    "windows/worldWritableWarning" => {
      guard params
        is Some(
          {
            "samplePaths": sample_paths,
            "extraCount": Number(extra_count, ..),
            "failedScan": failed_scan,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected windows/worldWritableWarning params"),
        )
      }
      AppWindowsWorldWritableWarning(
        sample_paths=@json.from_json(
          sample_paths,
          path=path.add_key("params").add_key("samplePaths"),
        ),
        extra_count=extra_count.to_uint64(),
        failed_scan=app_bool(
          failed_scan,
          path.add_key("params").add_key("failedScan"),
        ),
      )
    }
    "windowsSandbox/setupCompleted" => {
      guard params
        is Some({ "mode": mode, "success": success, "error"? : error, .. }) else {
        raise JsonDecodeError(
          (path, "expected windowsSandbox/setupCompleted params"),
        )
      }
      AppWindowsSandboxSetupCompleted(
        mode=@json.from_json(mode, path=path.add_key("params").add_key("mode")),
        success=app_bool(success, path.add_key("params").add_key("success")),
        error=app_optional_string(
          error,
          path.add_key("params").add_key("error"),
        ),
      )
    }
    "account/login/completed" => {
      guard params
        is Some(
          { "loginId"? : login_id, "success": success, "error"? : error, .. }
        ) else {
        raise JsonDecodeError((path, "expected account/login/completed params"))
      }
      AppAccountLoginCompleted(
        login_id=app_optional_string(
          login_id,
          path.add_key("params").add_key("loginId"),
        ),
        success=app_bool(success, path.add_key("params").add_key("success")),
        error=app_optional_string(
          error,
          path.add_key("params").add_key("error"),
        ),
      )
    }
    "model/rerouted" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "fromModel": String(from_model),
            "toModel": String(to_model),
            "reason": reason,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected model/rerouted params"))
      }
      AppModelRerouted(
        thread_id~,
        turn_id~,
        from_model~,
        to_model~,
        reason=@json.from_json(
          reason,
          path=path.add_key("params").add_key("reason"),
        ),
      )
    }
    "model/verification" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "verifications": verifications,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected model/verification params"))
      }
      AppModelVerification(
        thread_id~,
        turn_id~,
        verifications=@json.from_json(
          verifications,
          path=path.add_key("params").add_key("verifications"),
        ),
      )
    }
    "warning" => {
      guard params
        is Some({ "threadId"? : thread_id, "message": String(message), .. }) else {
        raise JsonDecodeError((path, "expected warning params"))
      }
      AppWarning(
        thread_id=app_optional_string(
          thread_id,
          path.add_key("params").add_key("threadId"),
        ),
        message~,
      )
    }
    "guardianWarning" => {
      guard params
        is Some(
          { "threadId": String(thread_id), "message": String(message), .. }
        ) else {
        raise JsonDecodeError((path, "expected guardianWarning params"))
      }
      AppGuardianWarning(thread_id~, message~)
    }
    "deprecationNotice" => {
      guard params
        is Some({ "summary": String(summary), "details"? : details, .. }) else {
        raise JsonDecodeError((path, "expected deprecationNotice params"))
      }
      AppDeprecationNotice(
        summary~,
        details=app_optional_string(
          details,
          path.add_key("params").add_key("details"),
        ),
      )
    }
    "configWarning" => {
      guard params
        is Some(
          {
            "summary": String(summary),
            "details"? : details,
            "path"? : config_path,
            "range"? : range,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected configWarning params"))
      }
      AppConfigWarning(
        summary~,
        details=app_optional_string(
          details,
          path.add_key("params").add_key("details"),
        ),
        path=app_optional_string(
          config_path,
          path.add_key("params").add_key("path"),
        ),
        range=match range {
          Some(Null) | None => None
          Some(value) =>
            Some(
              @json.from_json(
                value,
                path=path.add_key("params").add_key("range"),
              ),
            )
        },
      )
    }
    "thread/tokenUsage/updated" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "turnId": String(turn_id),
            "tokenUsage": token_usage,
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected thread/tokenUsage/updated params"),
        )
      }
      AppThreadTokenUsageUpdated(
        thread_id~,
        turn_id~,
        token_usage=@json.from_json(
          token_usage,
          path=path.add_key("params").add_key("tokenUsage"),
        ),
      )
    }
    "thread/realtime/started" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "realtimeSessionId"? : realtime_session_id,
            "version": version,
            ..
          }
        ) else {
        raise JsonDecodeError((path, "expected thread/realtime/started params"))
      }
      AppThreadRealtimeStarted(
        thread_id~,
        realtime_session_id=app_optional_string(
          realtime_session_id,
          path.add_key("params").add_key("realtimeSessionId"),
        ),
        version=@json.from_json(
          version,
          path=path.add_key("params").add_key("version"),
        ),
      )
    }
    "thread/realtime/itemAdded" => {
      guard params is Some({ "threadId": String(thread_id), "item": item, .. }) else {
        raise JsonDecodeError(
          (path, "expected thread/realtime/itemAdded params"),
        )
      }
      AppThreadRealtimeItemAdded(thread_id~, item~)
    }
    "thread/realtime/transcript/delta" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "role": String(role),
            "delta": String(delta),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected thread/realtime/transcript/delta params"),
        )
      }
      AppThreadRealtimeTranscriptDelta(thread_id~, role~, delta~)
    }
    "thread/realtime/transcript/done" => {
      guard params
        is Some(
          {
            "threadId": String(thread_id),
            "role": String(role),
            "text": String(text),
            ..
          }
        ) else {
        raise JsonDecodeError(
          (path, "expected thread/realtime/transcript/done params"),
        )
      }
      AppThreadRealtimeTranscriptDone(thread_id~, role~, text~)
    }
    "thread/realtime/outputAudio/delta" => {
      guard params
        is Some({ "threadId": String(thread_id), "audio": audio, .. }) else {
        raise JsonDecodeError(
          (path, "expected thread/realtime/outputAudio/delta params"),
        )
      }
      AppThreadRealtimeOutputAudioDelta(
        thread_id~,
        audio=@json.from_json(
          audio,
          path=path.add_key("params").add_key("audio"),
        ),
      )
    }
    "thread/realtime/sdp" => {
      guard params
        is Some({ "threadId": String(thread_id), "sdp": String(sdp), .. }) else {
        raise JsonDecodeError((path, "expected thread/realtime/sdp params"))
      }
      AppThreadRealtimeSdp(thread_id~, sdp~)
    }
    "thread/realtime/error" => {
      guard params
        is Some(
          { "threadId": String(thread_id), "message": String(message), .. }
        ) else {
        raise JsonDecodeError((path, "expected thread/realtime/error params"))
      }
      AppThreadRealtimeError(thread_id~, message~)
    }
    "thread/realtime/closed" => {
      guard params
        is Some({ "threadId": String(thread_id), "reason"? : reason, .. }) else {
        raise JsonDecodeError((path, "expected thread/realtime/closed params"))
      }
      AppThreadRealtimeClosed(
        thread_id~,
        reason=app_optional_string(
          reason,
          path.add_key("params").add_key("reason"),
        ),
      )
    }
    _ =>
      raise JsonDecodeError((path, "expected app-server notification method"))
  }
}

///|
/// Convert app-server notifications that exactly match existing exec stream semantics.
pub fn AppServerEvent::thread_event(self : AppServerEvent) -> Event? {
  match self {
    AppThreadStarted(thread) => Some(Event::ThreadStarted(thread_id=thread.id))
    AppTurnStarted(..) => Some(Event::TurnStarted)
    AppTurnError(error~, ..) =>
      Some(Event::TurnFailed({ message: error.message }))
    AppItemStarted(event) =>
      match event.item {
        Some(item) => Some(Event::ItemStarted(item))
        None => None
      }
    AppItemCompleted(event) =>
      match event.item {
        Some(item) => Some(Event::ItemCompleted(item))
        None => None
      }
    _ => None
  }
}

///|
pub struct AppThread {
  id : String
  forked_from_id : String?
  preview : String
  ephemeral : Bool
  model_provider : String
  created_at : Int64
  updated_at : Int64
  status : AppThreadStatus
  path : String?
  cwd : String
  cli_version : String
  source : AppSessionSource
  agent_nickname : String?
  agent_role : String?
  git_info : AppConversationGitInfo?
  name : String?
  turns : ArrayView[AppTurn]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppThread with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "forkedFromId"? : forked_from_id,
      "preview": String(preview),
      "ephemeral": ephemeral,
      "modelProvider": String(model_provider),
      "createdAt": Number(created_at, ..),
      "updatedAt": Number(updated_at, ..),
      "status": status,
      "path"? : thread_path,
      "cwd": String(cwd),
      "cliVersion": String(cli_version),
      "source": source,
      "agentNickname"? : agent_nickname,
      "agentRole"? : agent_role,
      "gitInfo"? : git_info,
      "name"? : name,
      "turns": turns,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server Thread"))
  }
  {
    id,
    forked_from_id: app_optional_string(
      forked_from_id,
      path.add_key("forkedFromId"),
    ),
    preview,
    ephemeral: app_bool(ephemeral, path.add_key("ephemeral")),
    model_provider,
    created_at: created_at.to_int64(),
    updated_at: updated_at.to_int64(),
    status: @json.from_json(status, path=path.add_key("status")),
    path: app_optional_string(thread_path, path.add_key("path")),
    cwd,
    cli_version,
    source: @json.from_json(source, path=path.add_key("source")),
    agent_nickname: app_optional_string(
      agent_nickname,
      path.add_key("agentNickname"),
    ),
    agent_role: app_optional_string(agent_role, path.add_key("agentRole")),
    git_info: match git_info {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("gitInfo")))
    },
    name: app_optional_string(name, path.add_key("name")),
    turns: @json.from_json(turns, path=path.add_key("turns")),
    raw: value,
  }
}

///|
pub enum AppSessionSource {
  AppSessionCli
  AppSessionVsCode
  AppSessionExec
  AppSessionAppServer
  AppSessionCustom(String)
  AppSessionSubAgent(AppSubAgentSource)
  AppSessionUnknown
} derive(Debug)

///|
pub impl FromJson for AppSessionSource with fn from_json(value, path) {
  match value {
    String("cli") => AppSessionCli
    String("vscode") => AppSessionVsCode
    String("exec") => AppSessionExec
    String("appServer") => AppSessionAppServer
    String("mcp") => AppSessionAppServer
    { "custom": String(source), .. } => AppSessionCustom(source)
    { "subAgent": source, .. } =>
      AppSessionSubAgent(@json.from_json(source, path=path.add_key("subAgent")))
    String("unknown") => AppSessionUnknown
    _ => raise JsonDecodeError((path, "expected session source"))
  }
}

///|
pub enum AppSubAgentSource {
  AppSubAgentReview
  AppSubAgentCompact
  AppSubAgentThreadSpawn(
    parent_thread_id~ : String,
    depth~ : Int,
    agent_path~ : String?,
    agent_nickname~ : String?,
    agent_role~ : String?
  )
  AppSubAgentMemoryConsolidation
  AppSubAgentOther(String)
} derive(Debug)

///|
pub impl FromJson for AppSubAgentSource with fn from_json(value, path) {
  match value {
    String("review") => AppSubAgentReview
    String("compact") => AppSubAgentCompact
    {
      "thread_spawn": {
        "parent_thread_id": String(parent_thread_id),
        "depth": Number(depth, ..),
        "agent_path"? : agent_path,
        "agent_nickname"? : agent_nickname,
        "agent_role"? : agent_role,
        ..
      },
      ..
    } =>
      AppSubAgentThreadSpawn(
        parent_thread_id~,
        depth=depth.to_int(),
        agent_path=app_optional_string(
          agent_path,
          path.add_key("thread_spawn").add_key("agent_path"),
        ),
        agent_nickname=app_optional_string(
          agent_nickname,
          path.add_key("thread_spawn").add_key("agent_nickname"),
        ),
        agent_role=app_optional_string(
          agent_role,
          path.add_key("thread_spawn").add_key("agent_role"),
        ),
      )
    String("memory_consolidation") => AppSubAgentMemoryConsolidation
    { "other": String(other), .. } => AppSubAgentOther(other)
    _ => raise JsonDecodeError((path, "expected sub-agent source"))
  }
}

///|
pub enum AppThreadActiveFlag {
  AppThreadWaitingOnApproval
  AppThreadWaitingOnUserInput
} derive(Debug)

///|
pub impl FromJson for AppThreadActiveFlag with fn from_json(value, path) {
  match value {
    String("waitingOnApproval") => AppThreadWaitingOnApproval
    String("waitingOnUserInput") => AppThreadWaitingOnUserInput
    _ => raise JsonDecodeError((path, "expected thread active flag"))
  }
}

///|
pub enum AppThreadStatus {
  ThreadNotLoaded
  ThreadIdle
  ThreadSystemError
  ThreadActive(active_flags~ : ArrayView[AppThreadActiveFlag])
} derive(Debug)

///|
pub impl FromJson for AppThreadStatus with fn from_json(value, path) {
  match value {
    { "type": String("notLoaded"), .. } => ThreadNotLoaded
    { "type": String("idle"), .. } => ThreadIdle
    { "type": String("systemError"), .. } => ThreadSystemError
    { "type": String("active"), "activeFlags": active_flags, .. } =>
      ThreadActive(
        active_flags=@json.from_json(
          active_flags,
          path=path.add_key("activeFlags"),
        ),
      )
    _ => raise JsonDecodeError((path, "expected app-server ThreadStatus"))
  }
}

///|
pub struct AppTurn {
  id : String
  items : ArrayView[AppThreadItem]
  status : AppTurnStatus
  error : AppTurnError?
  started_at : Int64?
  completed_at : Int64?
  duration_ms : Int64?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppTurn with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "items": items,
      "status": status,
      "error"? : error,
      "startedAt"? : started_at,
      "completedAt"? : completed_at,
      "durationMs"? : duration_ms,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server Turn"))
  }
  let error = match error {
    Some(Null) | None => None
    Some(error) => Some(@json.from_json(error, path=path.add_key("error")))
  }
  {
    id,
    items: @json.from_json(items, path=path.add_key("items")),
    status: @json.from_json(status, path=path.add_key("status")),
    error,
    started_at: app_optional_int64(started_at, path.add_key("startedAt")),
    completed_at: app_optional_int64(completed_at, path.add_key("completedAt")),
    duration_ms: app_optional_int64(duration_ms, path.add_key("durationMs")),
    raw: value,
  }
}

///|
pub struct AppByteRange {
  start : UInt64
  end : UInt64
} derive(Debug)

///|
pub impl FromJson for AppByteRange with fn from_json(value, path) {
  guard value is { "start": Number(start, ..), "end": Number(end, ..), .. } else {
    raise JsonDecodeError((path, "expected byte range"))
  }
  { start: start.to_uint64(), end: end.to_uint64() }
}

///|
pub struct AppTextElement {
  byte_range : AppByteRange
  placeholder : String?
} derive(Debug)

///|
pub impl FromJson for AppTextElement with fn from_json(value, path) {
  guard value is { "byteRange": byte_range, "placeholder"? : placeholder, .. } else {
    raise JsonDecodeError((path, "expected text element"))
  }
  {
    byte_range: @json.from_json(byte_range, path=path.add_key("byteRange")),
    placeholder: app_optional_string(placeholder, path.add_key("placeholder")),
  }
}

///|
pub enum AppThreadUserInput {
  AppThreadInputText(text~ : String, text_elements~ : ArrayView[AppTextElement])
  AppThreadInputImage(url~ : String)
  AppThreadInputLocalImage(path~ : String)
  AppThreadInputSkill(name~ : String, path~ : String)
  AppThreadInputMention(name~ : String, path~ : String)
} derive(Debug)

///|
pub impl FromJson for AppThreadUserInput with fn from_json(value, path) {
  guard value is Object({ "type": String(input_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected user input"))
  }
  match input_type {
    "text" => {
      guard obj
        is { "text": String(text), "text_elements"? : text_elements, .. } else {
        raise JsonDecodeError((path, "expected text user input"))
      }
      AppThreadInputText(
        text~,
        text_elements=match text_elements {
          Some(value) =>
            @json.from_json(value, path=path.add_key("text_elements"))
          None => []
        },
      )
    }
    "image" => {
      guard obj is { "url": String(url), .. } else {
        raise JsonDecodeError((path, "expected image user input"))
      }
      AppThreadInputImage(url~)
    }
    "localImage" => {
      guard obj is { "path": String(image_path), .. } else {
        raise JsonDecodeError((path, "expected localImage user input"))
      }
      AppThreadInputLocalImage(path=image_path)
    }
    "skill" => {
      guard obj is { "name": String(name), "path": String(skill_path), .. } else {
        raise JsonDecodeError((path, "expected skill user input"))
      }
      AppThreadInputSkill(name~, path=skill_path)
    }
    "mention" => {
      guard obj is { "name": String(name), "path": String(mention_path), .. } else {
        raise JsonDecodeError((path, "expected mention user input"))
      }
      AppThreadInputMention(name~, path=mention_path)
    }
    _ => raise JsonDecodeError((path, "expected user input type"))
  }
}

///|
pub struct AppHookPromptFragment {
  text : String
  hook_run_id : String
} derive(Debug)

///|
pub impl FromJson for AppHookPromptFragment with fn from_json(value, path) {
  guard value is { "text": String(text), "hookRunId": String(hook_run_id), .. } else {
    raise JsonDecodeError((path, "expected hook prompt fragment"))
  }
  { text, hook_run_id }
}

///|
pub enum AppMessagePhase {
  AppMessageCommentary
  AppMessageFinalAnswer
} derive(Debug)

///|
pub impl FromJson for AppMessagePhase with fn from_json(value, path) {
  match value {
    String("commentary") => AppMessageCommentary
    String("final_answer") => AppMessageFinalAnswer
    _ => raise JsonDecodeError((path, "expected message phase"))
  }
}

///|
pub struct AppMemoryCitationEntry {
  path : String
  line_start : UInt
  line_end : UInt
  note : String
} derive(Debug)

///|
pub impl FromJson for AppMemoryCitationEntry with fn from_json(value, path) {
  guard value
    is {
      "path": String(entry_path),
      "lineStart": Number(line_start, ..),
      "lineEnd": Number(line_end, ..),
      "note": String(note),
      ..
    } else {
    raise JsonDecodeError((path, "expected memory citation entry"))
  }
  {
    path: entry_path,
    line_start: line_start.to_uint(),
    line_end: line_end.to_uint(),
    note,
  }
}

///|
pub struct AppMemoryCitation {
  entries : ArrayView[AppMemoryCitationEntry]
  thread_ids : ArrayView[String]
} derive(Debug)

///|
pub impl FromJson for AppMemoryCitation with fn from_json(value, path) {
  guard value is { "entries": entries, "threadIds": thread_ids, .. } else {
    raise JsonDecodeError((path, "expected memory citation"))
  }
  {
    entries: @json.from_json(entries, path=path.add_key("entries")),
    thread_ids: @json.from_json(thread_ids, path=path.add_key("threadIds")),
  }
}

///|
pub enum AppThreadCommandExecutionSource {
  AppThreadCommandSourceAgent
  AppThreadCommandSourceUserShell
  AppThreadCommandSourceUnifiedExecStartup
  AppThreadCommandSourceUnifiedExecInteraction
} derive(Debug)

///|
pub impl FromJson for AppThreadCommandExecutionSource with fn from_json(
  value,
  path,
) {
  match value {
    String("agent") => AppThreadCommandSourceAgent
    String("userShell") => AppThreadCommandSourceUserShell
    String("unifiedExecStartup") => AppThreadCommandSourceUnifiedExecStartup
    String("unifiedExecInteraction") =>
      AppThreadCommandSourceUnifiedExecInteraction
    _ => raise JsonDecodeError((path, "expected command execution source"))
  }
}

///|
pub enum AppThreadCommandExecutionStatus {
  AppThreadCommandInProgress
  AppThreadCommandCompleted
  AppThreadCommandFailed
  AppThreadCommandDeclined
} derive(Debug)

///|
pub impl FromJson for AppThreadCommandExecutionStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("inProgress") => AppThreadCommandInProgress
    String("completed") => AppThreadCommandCompleted
    String("failed") => AppThreadCommandFailed
    String("declined") => AppThreadCommandDeclined
    _ => raise JsonDecodeError((path, "expected command execution status"))
  }
}

///|
pub enum AppThreadPatchChangeKind {
  AppThreadPatchAdd
  AppThreadPatchDelete
  AppThreadPatchUpdate(move_path~ : String?)
} derive(Debug)

///|
pub impl FromJson for AppThreadPatchChangeKind with fn from_json(value, path) {
  match value {
    { "type": String("add"), .. } => AppThreadPatchAdd
    { "type": String("delete"), .. } => AppThreadPatchDelete
    { "type": String("update"), "move_path"? : move_path, .. } =>
      AppThreadPatchUpdate(
        move_path=app_optional_string(move_path, path.add_key("move_path")),
      )
    _ => raise JsonDecodeError((path, "expected patch change kind"))
  }
}

///|
pub struct AppThreadFileUpdateChange {
  path : String
  kind : AppThreadPatchChangeKind
  diff : String
} derive(Debug)

///|
pub impl FromJson for AppThreadFileUpdateChange with fn from_json(value, path) {
  guard value
    is { "path": String(file_path), "kind": kind, "diff": String(diff), .. } else {
    raise JsonDecodeError((path, "expected file update change"))
  }
  {
    path: file_path,
    kind: @json.from_json(kind, path=path.add_key("kind")),
    diff,
  }
}

///|
pub enum AppThreadPatchApplyStatus {
  AppThreadPatchInProgress
  AppThreadPatchCompleted
  AppThreadPatchFailed
  AppThreadPatchDeclined
} derive(Debug)

///|
pub impl FromJson for AppThreadPatchApplyStatus with fn from_json(value, path) {
  match value {
    String("inProgress") => AppThreadPatchInProgress
    String("completed") => AppThreadPatchCompleted
    String("failed") => AppThreadPatchFailed
    String("declined") => AppThreadPatchDeclined
    _ => raise JsonDecodeError((path, "expected patch apply status"))
  }
}

///|
pub enum AppThreadMcpToolCallStatus {
  AppThreadMcpInProgress
  AppThreadMcpCompleted
  AppThreadMcpFailed
} derive(Debug)

///|
pub impl FromJson for AppThreadMcpToolCallStatus with fn from_json(value, path) {
  match value {
    String("inProgress") => AppThreadMcpInProgress
    String("completed") => AppThreadMcpCompleted
    String("failed") => AppThreadMcpFailed
    _ => raise JsonDecodeError((path, "expected MCP tool call status"))
  }
}

///|
pub struct AppThreadMcpToolCallResult {
  content : ArrayView[Json]
  structured_content : Json?
  meta : Json?
} derive(Debug)

///|
pub impl FromJson for AppThreadMcpToolCallResult with fn from_json(value, path) {
  guard value
    is {
      "content": content,
      "structuredContent"? : structured_content,
      "_meta"? : meta,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP tool call result"))
  }
  {
    content: @json.from_json(content, path=path.add_key("content")),
    structured_content: app_optional_json(structured_content),
    meta: app_optional_json(meta),
  }
}

///|
pub struct AppThreadMcpToolCallError {
  message : String
} derive(Debug)

///|
pub impl FromJson for AppThreadMcpToolCallError with fn from_json(value, path) {
  guard value is { "message": String(message), .. } else {
    raise JsonDecodeError((path, "expected MCP tool call error"))
  }
  { message, }
}

///|
pub enum AppThreadDynamicToolCallStatus {
  AppThreadDynamicInProgress
  AppThreadDynamicCompleted
  AppThreadDynamicFailed
} derive(Debug)

///|
pub impl FromJson for AppThreadDynamicToolCallStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("inProgress") => AppThreadDynamicInProgress
    String("completed") => AppThreadDynamicCompleted
    String("failed") => AppThreadDynamicFailed
    _ => raise JsonDecodeError((path, "expected dynamic tool call status"))
  }
}

///|
pub(all) enum AppDynamicToolCallOutputContentItem {
  AppDynamicToolCallOutputText(text~ : String)
  AppDynamicToolCallOutputImage(image_url~ : String)
} derive(Debug)

///|
pub impl FromJson for AppDynamicToolCallOutputContentItem with fn from_json(
  value,
  path,
) {
  match value {
    { "type": String("inputText"), "text": String(text), .. } =>
      AppDynamicToolCallOutputText(text~)
    { "type": String("inputImage"), "imageUrl": String(image_url), .. } =>
      AppDynamicToolCallOutputImage(image_url~)
    _ => raise JsonDecodeError((path, "expected dynamic tool call output"))
  }
}

///|
pub impl ToJson for AppDynamicToolCallOutputContentItem with fn to_json(item) {
  match item {
    AppDynamicToolCallOutputText(text~) => { "type": "inputText", "text": text }
    AppDynamicToolCallOutputImage(image_url~) =>
      { "type": "inputImage", "imageUrl": image_url }
  }
}

///|
pub enum AppThreadCollabAgentTool {
  AppThreadCollabSpawnAgent
  AppThreadCollabSendInput
  AppThreadCollabResumeAgent
  AppThreadCollabWait
  AppThreadCollabCloseAgent
} derive(Debug)

///|
pub impl FromJson for AppThreadCollabAgentTool with fn from_json(value, path) {
  match value {
    String("spawnAgent") => AppThreadCollabSpawnAgent
    String("sendInput") => AppThreadCollabSendInput
    String("resumeAgent") => AppThreadCollabResumeAgent
    String("wait") => AppThreadCollabWait
    String("closeAgent") => AppThreadCollabCloseAgent
    _ => raise JsonDecodeError((path, "expected collab agent tool"))
  }
}

///|
pub enum AppThreadCollabAgentToolCallStatus {
  AppThreadCollabInProgress
  AppThreadCollabCompleted
  AppThreadCollabFailed
} derive(Debug)

///|
pub impl FromJson for AppThreadCollabAgentToolCallStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("inProgress") => AppThreadCollabInProgress
    String("completed") => AppThreadCollabCompleted
    String("failed") => AppThreadCollabFailed
    _ => raise JsonDecodeError((path, "expected collab agent tool call status"))
  }
}

///|
pub enum AppThreadCollabAgentStatus {
  AppThreadCollabAgentPendingInit
  AppThreadCollabAgentRunning
  AppThreadCollabAgentInterrupted
  AppThreadCollabAgentCompleted
  AppThreadCollabAgentErrored
  AppThreadCollabAgentShutdown
  AppThreadCollabAgentNotFound
} derive(Debug)

///|
pub impl FromJson for AppThreadCollabAgentStatus with fn from_json(value, path) {
  match value {
    String("pendingInit") => AppThreadCollabAgentPendingInit
    String("running") => AppThreadCollabAgentRunning
    String("interrupted") => AppThreadCollabAgentInterrupted
    String("completed") => AppThreadCollabAgentCompleted
    String("errored") => AppThreadCollabAgentErrored
    String("shutdown") => AppThreadCollabAgentShutdown
    String("notFound") => AppThreadCollabAgentNotFound
    _ => raise JsonDecodeError((path, "expected collab agent status"))
  }
}

///|
pub struct AppThreadCollabAgentState {
  status : AppThreadCollabAgentStatus
  message : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadCollabAgentState with fn from_json(value, path) {
  guard value is { "status": status, "message"? : message, .. } else {
    raise JsonDecodeError((path, "expected collab agent state"))
  }
  {
    status: @json.from_json(status, path=path.add_key("status")),
    message: app_optional_string(message, path.add_key("message")),
  }
}

///|
pub enum AppWebSearchAction {
  AppWebSearchActionSearch(query~ : String?, queries~ : ArrayView[String]?)
  AppWebSearchActionOpenPage(url~ : String?)
  AppWebSearchActionFindInPage(url~ : String?, pattern~ : String?)
  AppWebSearchActionOther
} derive(Debug)

///|
pub impl FromJson for AppWebSearchAction with fn from_json(value, path) {
  guard value is Object({ "type": String(action_type), .. } as obj) else {
    raise JsonDecodeError((path, "expected web search action"))
  }
  match action_type {
    "search" =>
      AppWebSearchActionSearch(
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
    "openPage" =>
      AppWebSearchActionOpenPage(
        url=match obj {
          { "url"? : url, .. } => app_optional_string(url, path.add_key("url"))
        },
      )
    "findInPage" =>
      AppWebSearchActionFindInPage(
        url=match obj {
          { "url"? : url, .. } => app_optional_string(url, path.add_key("url"))
        },
        pattern=match obj {
          { "pattern"? : pattern, .. } =>
            app_optional_string(pattern, path.add_key("pattern"))
        },
      )
    "other" => AppWebSearchActionOther
    _ => raise JsonDecodeError((path, "expected web search action type"))
  }
}

///|
pub enum AppThreadItem {
  AppThreadUserMessageItem(
    id~ : String,
    content~ : ArrayView[AppThreadUserInput]
  )
  AppThreadHookPromptItem(
    id~ : String,
    fragments~ : ArrayView[AppHookPromptFragment]
  )
  AppThreadAgentMessageItem(
    id~ : String,
    text~ : String,
    phase~ : AppMessagePhase?,
    memory_citation~ : AppMemoryCitation?
  )
  AppThreadPlanItem(id~ : String, text~ : String)
  AppThreadReasoningItem(
    id~ : String,
    summary~ : ArrayView[String],
    content~ : ArrayView[String]
  )
  AppThreadCommandExecutionItem(
    id~ : String,
    command~ : String,
    cwd~ : String,
    process_id~ : String?,
    source~ : AppThreadCommandExecutionSource,
    status~ : AppThreadCommandExecutionStatus,
    command_actions~ : ArrayView[AppCommandAction],
    aggregated_output~ : String?,
    exit_code~ : Int?,
    duration_ms~ : Int64?
  )
  AppThreadFileChangeItem(
    id~ : String,
    changes~ : ArrayView[AppThreadFileUpdateChange],
    status~ : AppThreadPatchApplyStatus
  )
  AppThreadMcpToolCallItem(
    id~ : String,
    server~ : String,
    tool~ : String,
    status~ : AppThreadMcpToolCallStatus,
    arguments~ : Json,
    mcp_app_resource_uri~ : String?,
    result~ : AppThreadMcpToolCallResult?,
    error~ : AppThreadMcpToolCallError?,
    duration_ms~ : Int64?
  )
  AppThreadDynamicToolCallItem(
    id~ : String,
    tool_namespace~ : String?,
    tool~ : String,
    arguments~ : Json,
    status~ : AppThreadDynamicToolCallStatus,
    content_items~ : ArrayView[AppDynamicToolCallOutputContentItem]?,
    success~ : Bool?,
    duration_ms~ : Int64?
  )
  AppThreadCollabAgentToolCallItem(
    id~ : String,
    tool~ : AppThreadCollabAgentTool,
    status~ : AppThreadCollabAgentToolCallStatus,
    sender_thread_id~ : String,
    receiver_thread_ids~ : ArrayView[String],
    prompt~ : String?,
    model~ : String?,
    reasoning_effort~ : AppReasoningEffort?,
    agents_states~ : Map[String, AppThreadCollabAgentState]
  )
  AppThreadWebSearchItem(
    id~ : String,
    query~ : String,
    action~ : AppWebSearchAction?
  )
  AppThreadImageViewItem(id~ : String, path~ : String)
  AppThreadImageGenerationItem(
    id~ : String,
    status~ : String,
    revised_prompt~ : String?,
    result~ : String,
    saved_path~ : String?
  )
  AppThreadEnteredReviewModeItem(id~ : String, review~ : String)
  AppThreadExitedReviewModeItem(id~ : String, review~ : String)
  AppThreadContextCompactionItem(id~ : String)
} derive(Debug)

///|
pub impl FromJson for AppThreadItem with fn from_json(value, path) {
  guard value
    is Object({ "type": String(item_type), "id": String(id), .. } as obj) else {
    raise JsonDecodeError((path, "expected app-server ThreadItem"))
  }
  match item_type {
    "userMessage" => {
      guard obj is { "content": content, .. } else {
        raise JsonDecodeError((path, "expected userMessage item"))
      }
      AppThreadUserMessageItem(
        id~,
        content=@json.from_json(content, path=path.add_key("content")),
      )
    }
    "hookPrompt" => {
      guard obj is { "fragments": fragments, .. } else {
        raise JsonDecodeError((path, "expected hookPrompt item"))
      }
      AppThreadHookPromptItem(
        id~,
        fragments=@json.from_json(fragments, path=path.add_key("fragments")),
      )
    }
    "agentMessage" => {
      guard obj
        is {
          "text": String(text),
          "phase"? : phase,
          "memoryCitation"? : memory_citation,
          ..
        } else {
        raise JsonDecodeError((path, "expected agentMessage item"))
      }
      AppThreadAgentMessageItem(
        id~,
        text~,
        phase=match phase {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("phase")))
        },
        memory_citation=match memory_citation {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("memoryCitation")))
        },
      )
    }
    "plan" => {
      guard obj is { "text": String(text), .. } else {
        raise JsonDecodeError((path, "expected plan item"))
      }
      AppThreadPlanItem(id~, text~)
    }
    "reasoning" => {
      guard obj is { "summary"? : summary, "content"? : content, .. } else {
        raise JsonDecodeError((path, "expected reasoning item"))
      }
      AppThreadReasoningItem(
        id~,
        summary=match summary {
          Some(value) => @json.from_json(value, path=path.add_key("summary"))
          None => []
        },
        content=match content {
          Some(value) => @json.from_json(value, path=path.add_key("content"))
          None => []
        },
      )
    }
    "commandExecution" => {
      guard obj
        is {
          "command": String(command),
          "cwd": String(cwd),
          "processId"? : process_id,
          "source"? : source,
          "status": status,
          "commandActions": command_actions,
          "aggregatedOutput"? : aggregated_output,
          "exitCode"? : exit_code,
          "durationMs"? : duration_ms,
          ..
        } else {
        raise JsonDecodeError((path, "expected commandExecution item"))
      }
      AppThreadCommandExecutionItem(
        id~,
        command~,
        cwd~,
        process_id=app_optional_string(process_id, path.add_key("processId")),
        source=match source {
          Some(value) => @json.from_json(value, path=path.add_key("source"))
          None => AppThreadCommandSourceAgent
        },
        status=@json.from_json(status, path=path.add_key("status")),
        command_actions=@json.from_json(
          command_actions,
          path=path.add_key("commandActions"),
        ),
        aggregated_output=app_optional_string(
          aggregated_output,
          path.add_key("aggregatedOutput"),
        ),
        exit_code=app_optional_int(exit_code, path.add_key("exitCode")),
        duration_ms=app_optional_int64(duration_ms, path.add_key("durationMs")),
      )
    }
    "fileChange" => {
      guard obj is { "changes": changes, "status": status, .. } else {
        raise JsonDecodeError((path, "expected fileChange item"))
      }
      AppThreadFileChangeItem(
        id~,
        changes=@json.from_json(changes, path=path.add_key("changes")),
        status=@json.from_json(status, path=path.add_key("status")),
      )
    }
    "mcpToolCall" => {
      guard obj
        is {
          "server": String(server),
          "tool": String(tool),
          "status": status,
          "arguments": arguments,
          "mcpAppResourceUri"? : mcp_app_resource_uri,
          "result"? : result,
          "error"? : error,
          "durationMs"? : duration_ms,
          ..
        } else {
        raise JsonDecodeError((path, "expected mcpToolCall item"))
      }
      AppThreadMcpToolCallItem(
        id~,
        server~,
        tool~,
        status=@json.from_json(status, path=path.add_key("status")),
        arguments~,
        mcp_app_resource_uri=app_optional_string(
          mcp_app_resource_uri,
          path.add_key("mcpAppResourceUri"),
        ),
        result=match result {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("result")))
        },
        error=match error {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("error")))
        },
        duration_ms=app_optional_int64(duration_ms, path.add_key("durationMs")),
      )
    }
    "dynamicToolCall" => {
      guard obj
        is {
          "namespace"? : tool_namespace,
          "tool": String(tool),
          "arguments": arguments,
          "status": status,
          "contentItems"? : content_items,
          "success"? : success,
          "durationMs"? : duration_ms,
          ..
        } else {
        raise JsonDecodeError((path, "expected dynamicToolCall item"))
      }
      AppThreadDynamicToolCallItem(
        id~,
        tool_namespace=app_optional_string(
          tool_namespace,
          path.add_key("namespace"),
        ),
        tool~,
        arguments~,
        status=@json.from_json(status, path=path.add_key("status")),
        content_items=match content_items {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("contentItems")))
        },
        success=app_optional_bool(success, path.add_key("success")),
        duration_ms=app_optional_int64(duration_ms, path.add_key("durationMs")),
      )
    }
    "collabAgentToolCall" => {
      guard obj
        is {
          "tool": tool,
          "status": status,
          "senderThreadId": String(sender_thread_id),
          "receiverThreadIds": receiver_thread_ids,
          "prompt"? : prompt,
          "model"? : model,
          "reasoningEffort"? : reasoning_effort,
          "agentsStates": agents_states,
          ..
        } else {
        raise JsonDecodeError((path, "expected collabAgentToolCall item"))
      }
      AppThreadCollabAgentToolCallItem(
        id~,
        tool=@json.from_json(tool, path=path.add_key("tool")),
        status=@json.from_json(status, path=path.add_key("status")),
        sender_thread_id~,
        receiver_thread_ids=@json.from_json(
          receiver_thread_ids,
          path=path.add_key("receiverThreadIds"),
        ),
        prompt=app_optional_string(prompt, path.add_key("prompt")),
        model=app_optional_string(model, path.add_key("model")),
        reasoning_effort=match reasoning_effort {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("reasoningEffort")))
        },
        agents_states=@json.from_json(
          agents_states,
          path=path.add_key("agentsStates"),
        ),
      )
    }
    "webSearch" => {
      guard obj is { "query": String(query), "action"? : action, .. } else {
        raise JsonDecodeError((path, "expected webSearch item"))
      }
      AppThreadWebSearchItem(
        id~,
        query~,
        action=match action {
          Some(Null) | None => None
          Some(value) =>
            Some(@json.from_json(value, path=path.add_key("action")))
        },
      )
    }
    "imageView" => {
      guard obj is { "path": String(image_path), .. } else {
        raise JsonDecodeError((path, "expected imageView item"))
      }
      AppThreadImageViewItem(id~, path=image_path)
    }
    "imageGeneration" => {
      guard obj
        is {
          "status": String(status),
          "revisedPrompt"? : revised_prompt,
          "result": String(result),
          "savedPath"? : saved_path,
          ..
        } else {
        raise JsonDecodeError((path, "expected imageGeneration item"))
      }
      AppThreadImageGenerationItem(
        id~,
        status~,
        revised_prompt=app_optional_string(
          revised_prompt,
          path.add_key("revisedPrompt"),
        ),
        result~,
        saved_path=app_optional_string(saved_path, path.add_key("savedPath")),
      )
    }
    "enteredReviewMode" => {
      guard obj is { "review": String(review), .. } else {
        raise JsonDecodeError((path, "expected enteredReviewMode item"))
      }
      AppThreadEnteredReviewModeItem(id~, review~)
    }
    "exitedReviewMode" => {
      guard obj is { "review": String(review), .. } else {
        raise JsonDecodeError((path, "expected exitedReviewMode item"))
      }
      AppThreadExitedReviewModeItem(id~, review~)
    }
    "contextCompaction" => AppThreadContextCompactionItem(id~)
    _ => raise JsonDecodeError((path, "expected app-server ThreadItem type"))
  }
}

///|
pub enum AppTurnStatus {
  AppTurnCompletedStatus
  AppTurnInterruptedStatus
  AppTurnFailedStatus
  AppTurnInProgressStatus
} derive(Debug, Eq)

///|
pub impl FromJson for AppTurnStatus with fn from_json(value, path) {
  match value {
    String("completed") => AppTurnCompletedStatus
    String("interrupted") => AppTurnInterruptedStatus
    String("failed") => AppTurnFailedStatus
    String("inProgress") => AppTurnInProgressStatus
    _ => raise JsonDecodeError((path, "expected app-server TurnStatus"))
  }
}

///|
pub struct AppTurnError {
  message : String
  codex_error_info : AppCodexErrorInfo?
  additional_details : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppTurnError with fn from_json(value, path) {
  guard value
    is {
      "message": String(message),
      "codexErrorInfo"? : codex_error_info,
      "additionalDetails"? : additional_details,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server TurnError"))
  }
  {
    message,
    codex_error_info: match codex_error_info {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("codexErrorInfo")))
    },
    additional_details: app_optional_string(
      additional_details,
      path.add_key("additionalDetails"),
    ),
    raw: value,
  }
}

///|
pub enum AppNonSteerableTurnKind {
  AppNonSteerableReview
  AppNonSteerableCompact
} derive(Debug)

///|
pub impl FromJson for AppNonSteerableTurnKind with fn from_json(value, path) {
  match value {
    String("review") => AppNonSteerableReview
    String("compact") => AppNonSteerableCompact
    _ => raise JsonDecodeError((path, "expected non-steerable turn kind"))
  }
}

///|
pub enum AppCodexErrorInfo {
  AppContextWindowExceeded
  AppUsageLimitExceeded
  AppServerOverloaded
  AppCyberPolicy
  AppHttpConnectionFailed(http_status_code~ : Int?)
  AppResponseStreamConnectionFailed(http_status_code~ : Int?)
  AppInternalServerError
  AppUnauthorized
  AppBadRequest
  AppThreadRollbackFailed
  AppSandboxError
  AppResponseStreamDisconnected(http_status_code~ : Int?)
  AppResponseTooManyFailedAttempts(http_status_code~ : Int?)
  AppActiveTurnNotSteerable(turn_kind~ : AppNonSteerableTurnKind)
  AppCodexOtherError
} derive(Debug)

///|
pub impl FromJson for AppCodexErrorInfo with fn from_json(value, path) {
  match value {
    String("contextWindowExceeded") => AppContextWindowExceeded
    String("usageLimitExceeded") => AppUsageLimitExceeded
    String("serverOverloaded") => AppServerOverloaded
    String("cyberPolicy") => AppCyberPolicy
    { "httpConnectionFailed": payload, .. } =>
      AppHttpConnectionFailed(
        http_status_code=app_codex_error_http_status_code(
          payload,
          path.add_key("httpConnectionFailed"),
        ),
      )
    { "responseStreamConnectionFailed": payload, .. } =>
      AppResponseStreamConnectionFailed(
        http_status_code=app_codex_error_http_status_code(
          payload,
          path.add_key("responseStreamConnectionFailed"),
        ),
      )
    String("internalServerError") => AppInternalServerError
    String("unauthorized") => AppUnauthorized
    String("badRequest") => AppBadRequest
    String("threadRollbackFailed") => AppThreadRollbackFailed
    String("sandboxError") => AppSandboxError
    { "responseStreamDisconnected": payload, .. } =>
      AppResponseStreamDisconnected(
        http_status_code=app_codex_error_http_status_code(
          payload,
          path.add_key("responseStreamDisconnected"),
        ),
      )
    { "responseTooManyFailedAttempts": payload, .. } =>
      AppResponseTooManyFailedAttempts(
        http_status_code=app_codex_error_http_status_code(
          payload,
          path.add_key("responseTooManyFailedAttempts"),
        ),
      )
    { "activeTurnNotSteerable": { "turnKind": turn_kind, .. }, .. } =>
      AppActiveTurnNotSteerable(
        turn_kind=@json.from_json(
          turn_kind,
          path=path.add_key("activeTurnNotSteerable").add_key("turnKind"),
        ),
      )
    String("other") => AppCodexOtherError
    String(_) => AppCodexOtherError
    _ => raise JsonDecodeError((path, "expected codex error info"))
  }
}

///|
pub struct AppThreadItemEvent {
  thread_id : String
  turn_id : String
  app_item : AppThreadItem
  item : ThreadItem?
  raw_item : Json
  timestamp_ms : Int64
} derive(Debug)

///|
pub impl FromJson for AppThreadItemEvent with fn from_json(value, path) {
  match value {
    {
      "method": String("item/started"),
      "params": {
        "threadId": String(thread_id),
        "turnId": String(turn_id),
        "item": raw_item,
        "startedAtMs": Number(timestamp_ms, ..),
        ..
      },
      ..
    } =>
      {
        thread_id,
        turn_id,
        app_item: @json.from_json(
          raw_item,
          path=path.add_key("params").add_key("item"),
        ),
        item: app_thread_item(raw_item, path.add_key("params").add_key("item")),
        raw_item,
        timestamp_ms: timestamp_ms.to_int64(),
      }
    {
      "method": String("item/completed"),
      "params": {
        "threadId": String(thread_id),
        "turnId": String(turn_id),
        "item": raw_item,
        "completedAtMs": Number(timestamp_ms, ..),
        ..
      },
      ..
    } =>
      {
        thread_id,
        turn_id,
        app_item: @json.from_json(
          raw_item,
          path=path.add_key("params").add_key("item"),
        ),
        item: app_thread_item(raw_item, path.add_key("params").add_key("item")),
        raw_item,
        timestamp_ms: timestamp_ms.to_int64(),
      }
    _ =>
      raise JsonDecodeError(
        (path, "expected app-server item lifecycle notification"),
      )
  }
}

///|
pub struct AppThreadTokenUsage {
  total : AppTokenUsageBreakdown
  last : AppTokenUsageBreakdown
  model_context_window : Int64?
} derive(Debug)

///|
pub impl FromJson for AppThreadTokenUsage with fn from_json(value, path) {
  guard value
    is {
      "total": total,
      "last": last,
      "modelContextWindow"? : model_context_window,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server ThreadTokenUsage"))
  }
  {
    total: app_usage(total, path.add_key("total")),
    last: app_usage(last, path.add_key("last")),
    model_context_window: app_optional_int64(
      model_context_window,
      path.add_key("modelContextWindow"),
    ),
  }
}

///|
pub struct AppTokenUsageBreakdown {
  total_tokens : Int64
  input_tokens : Int64
  cached_input_tokens : Int64
  output_tokens : Int64
  reasoning_output_tokens : Int64
} derive(Debug)

///|
pub impl FromJson for AppTokenUsageBreakdown with fn from_json(value, path) {
  app_usage(value, path)
}

///|
fn app_thread_item(
  value : Json,
  path : @json.JsonPath,
) -> ThreadItem? raise @json.JsonDecodeError {
  guard value is Object({ "type": String(ty), "id": String(id), .. } as obj) else {
    raise @json.JsonDecodeError((path, "expected app-server ThreadItem"))
  }
  match ty {
    "agentMessage" => {
      guard obj is { "text": String(text), .. } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server agentMessage item"),
        )
      }
      Some(AgentMessageItem(id~, text~))
    }
    "reasoning" => {
      let text = match obj {
        { "content": Array(content), .. } if content.length() > 0 =>
          app_string_array_join(content, path.add_key("content"), "\n")
        { "summary": Array(summary), .. } =>
          app_string_array_join(summary, path.add_key("summary"), "\n")
        _ => ""
      }
      Some(ReasoningItem(id~, text~))
    }
    "commandExecution" => {
      guard obj
        is {
          "command": String(command),
          "status": status,
          "aggregatedOutput"? : aggregated_output,
          "exitCode"? : exit_code,
          ..
        } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server commandExecution item"),
        )
      }
      let status = app_command_status(status, path.add_key("status"))
      let aggregated_output = match aggregated_output {
        Some(String(output)) => output
        Some(Null) | None => ""
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("aggregatedOutput"), "expected string or null"),
          )
      }
      Some(
        CommandExecutionItem(
          id~,
          command~,
          aggregated_output~,
          exit_code=app_optional_int(exit_code, path.add_key("exitCode")),
          status~,
        ),
      )
    }
    "fileChange" => {
      guard obj is { "changes": Array(changes), "status": status, .. } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server fileChange item"),
        )
      }
      let status = app_patch_status(status, path.add_key("status"))
      guard status is Some(status) else { return None }
      let converted_changes = []
      for change in changes {
        converted_changes.push(app_file_change(change, path.add_key("changes")))
      }
      Some(FileChangeItem(id~, changes=converted_changes, status~))
    }
    "mcpToolCall" => {
      guard obj
        is {
          "server": String(server),
          "tool": String(tool),
          "status": status,
          "arguments"? : arguments,
          "result"? : result,
          "error"? : error,
          ..
        } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server mcpToolCall item"),
        )
      }
      if error is Some(error) {
        guard error is Null || error is Object({ "message": String(_), .. }) else {
          raise @json.JsonDecodeError(
            (path.add_key("error"), "expected null or error object"),
          )
        }
      }
      Some(
        McpToolCallItem(
          id~,
          server~,
          tool~,
          status=app_mcp_status(status, path.add_key("status")),
          arguments=match arguments {
            Some(Null) | None => None
            Some(arguments) => Some(arguments)
          },
          result=if error is Some(Object({ "message": String(message), .. })) {
            Some(Err(message))
          } else if result is Some(Null) || result is None {
            None
          } else if result is Some(result) {
            Some(Ok(app_mcp_result(result, path.add_key("result"))))
          } else {
            None
          },
        ),
      )
    }
    "collabAgentToolCall" => {
      guard obj
        is {
          "tool": tool,
          "status": status,
          "senderThreadId": String(sender_thread_id),
          "receiverThreadIds": receiver_thread_ids,
          "prompt"? : prompt,
          "agentsStates": agents_states,
          ..
        } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server collabAgentToolCall item"),
        )
      }
      Some(
        CollabToolCallItem(
          id~,
          tool=app_collab_tool(tool, path.add_key("tool")),
          sender_thread_id~,
          receiver_thread_ids=@json.from_json(
            receiver_thread_ids,
            path=path.add_key("receiverThreadIds"),
          ),
          prompt=match prompt {
            Some(String(prompt)) => Some(prompt)
            Some(Null) | None => None
            _ =>
              raise @json.JsonDecodeError(
                (path.add_key("prompt"), "expected string or null"),
              )
          },
          agents_states=@json.from_json(
            agents_states,
            path=path.add_key("agentsStates"),
          ),
          status=app_collab_status(status, path.add_key("status")),
        ),
      )
    }
    "webSearch" => {
      guard obj is { "query": String(query), .. } else {
        raise @json.JsonDecodeError(
          (path, "expected app-server webSearch item"),
        )
      }
      Some(WebSearchItem(id~, query~))
    }
    _ => None
  }
}

///|
fn app_usage(
  value : Json,
  path : @json.JsonPath,
) -> AppTokenUsageBreakdown raise @json.JsonDecodeError {
  guard value
    is {
      "totalTokens": Number(total_tokens, ..),
      "inputTokens": Number(input_tokens, ..),
      "cachedInputTokens": Number(cached_input_tokens, ..),
      "outputTokens": Number(output_tokens, ..),
      "reasoningOutputTokens": Number(reasoning_output_tokens, ..),
      ..
    } else {
    raise @json.JsonDecodeError(
      (path, "expected app-server token usage breakdown"),
    )
  }
  {
    total_tokens: total_tokens.to_int64(),
    input_tokens: input_tokens.to_int64(),
    cached_input_tokens: cached_input_tokens.to_int64(),
    output_tokens: output_tokens.to_int64(),
    reasoning_output_tokens: reasoning_output_tokens.to_int64(),
  }
}

///|
fn app_file_change(
  value : Json,
  path : @json.JsonPath,
) -> FileUpdateChange raise @json.JsonDecodeError {
  guard value is { "path": String(file_path), "kind": kind, .. } else {
    raise @json.JsonDecodeError((path, "expected app-server FileUpdateChange"))
  }
  let kind = match kind {
    { "type": String("add"), .. } => PatchChangeKind::Add
    { "type": String("delete"), .. } => PatchChangeKind::Delete
    { "type": String("update"), .. } => PatchChangeKind::Update
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("kind"), "expected app-server PatchChangeKind"),
      )
  }
  { path: file_path, kind }
}

///|
fn app_mcp_result(
  value : Json,
  path : @json.JsonPath,
) -> McpToolCallResult raise @json.JsonDecodeError {
  guard value
    is {
      "content": Array(content),
      "structuredContent"? : structured_content,
      ..
    } else {
    raise @json.JsonDecodeError((path, "expected app-server McpToolCallResult"))
  }
  let structured_content = match structured_content {
    Some(value) => value
    None => Json::null()
  }
  { content, structured_content }
}

///|
fn app_string_array_join(
  values : Array[Json],
  path : @json.JsonPath,
  separator : String,
) -> String raise @json.JsonDecodeError {
  let parts = []
  for value in values {
    match value {
      String(text) => parts.push(text)
      _ => raise @json.JsonDecodeError((path, "expected string array"))
    }
  }
  parts.join(separator)
}

///|
fn app_command_status(
  value : Json,
  path : @json.JsonPath,
) -> CommandExecutionStatus raise @json.JsonDecodeError {
  match value {
    String("inProgress") => InProgress
    String("completed") => Completed
    String("failed") => Failed
    String("declined") => Declined
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected app-server CommandExecutionStatus"),
      )
  }
}

///|
fn app_patch_status(
  value : Json,
  path : @json.JsonPath,
) -> PatchApplyStatus? raise @json.JsonDecodeError {
  match value {
    String("inProgress") => Some(InProgress)
    String("completed") => Some(Completed)
    String("failed") => Some(Failed)
    String("declined") => None
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected app-server PatchApplyStatus"),
      )
  }
}

///|
fn app_mcp_status(
  value : Json,
  path : @json.JsonPath,
) -> McpToolCallStatus raise @json.JsonDecodeError {
  match value {
    String("inProgress") => InProgress
    String("completed") => Completed
    String("failed") => Failed
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected app-server McpToolCallStatus"),
      )
  }
}

///|
fn app_collab_status(
  value : Json,
  path : @json.JsonPath,
) -> CollabToolCallStatus raise @json.JsonDecodeError {
  match value {
    String("inProgress") => InProgress
    String("completed") => Completed
    String("failed") => Failed
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected app-server CollabAgentToolCallStatus"),
      )
  }
}

///|
fn app_collab_tool(
  value : Json,
  path : @json.JsonPath,
) -> CollabTool raise @json.JsonDecodeError {
  match value {
    String("spawnAgent") => SpawnAgent
    String("sendInput") => SendInput
    String("resumeAgent") => ResumeAgent
    String("wait") => Wait
    String("closeAgent") => CloseAgent
    _ =>
      raise @json.JsonDecodeError((path, "expected app-server CollabAgentTool"))
  }
}

///|
fn app_codex_error_http_status_code(
  value : Json,
  path : @json.JsonPath,
) -> Int? raise @json.JsonDecodeError {
  guard value is { "httpStatusCode"? : http_status_code, .. } else {
    raise @json.JsonDecodeError((path, "expected codex error info payload"))
  }
  app_optional_int(http_status_code, path.add_key("httpStatusCode"))
}

///|
fn app_bool(
  value : Json,
  path : @json.JsonPath,
) -> Bool raise @json.JsonDecodeError {
  match value {
    True => true
    False => false
    _ => raise @json.JsonDecodeError((path, "expected boolean"))
  }
}

///|
fn app_optional_string(
  value : Json?,
  path : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match value {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "expected string or null"))
  }
}

///|
fn app_optional_int(
  value : Json?,
  path : @json.JsonPath,
) -> Int? raise @json.JsonDecodeError {
  match value {
    Some(Number(value, ..)) => Some(value.to_int())
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "expected integer or null"))
  }
}

///|
fn app_optional_int64(
  value : Json?,
  path : @json.JsonPath,
) -> Int64? raise @json.JsonDecodeError {
  match value {
    Some(Number(value, ..)) => Some(value.to_int64())
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "expected integer or null"))
  }
}

///|
fn app_optional_uint(
  value : Json?,
  path : @json.JsonPath,
) -> UInt? raise @json.JsonDecodeError {
  match value {
    Some(Number(value, ..)) => Some(value.to_uint())
    Some(Null) | None => None
    _ =>
      raise @json.JsonDecodeError((path, "expected unsigned integer or null"))
  }
}

///|
fn app_optional_uint64(
  value : Json?,
  path : @json.JsonPath,
) -> UInt64? raise @json.JsonDecodeError {
  match value {
    Some(Number(value, ..)) => Some(value.to_uint64())
    Some(Null) | None => None
    _ =>
      raise @json.JsonDecodeError((path, "expected unsigned integer or null"))
  }
}

///|
fn app_optional_double(
  value : Json?,
  path : @json.JsonPath,
) -> Double? raise @json.JsonDecodeError {
  match value {
    Some(Number(value, ..)) => Some(value)
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "expected number or null"))
  }
}

///|
fn app_optional_bool(
  value : Json?,
  path : @json.JsonPath,
) -> Bool? raise @json.JsonDecodeError {
  match value {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "expected boolean or null"))
  }
}

///|
fn app_optional_json(value : Json?) -> Json? {
  match value {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}
