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
/// Entry point for low-level Codex app-server protocol handling.
///
/// This does not replace `Codex::start_thread` or `codex exec --json`; it is a
/// separate surface for callers that already have app-server JSON-RPC messages.
pub struct CodexApp {
  options : CodexOptions
}

///|
pub struct AppServerOptions {
  /// Override the path to the codex-app-server executable.
  executable_path_override : String?
} derive(Default)

///|
pub fn AppServerOptions::new(
  executable_path_override? : String,
) -> AppServerOptions {
  { executable_path_override, }
}

///|
/// Create a low-level app-server protocol helper from the same Codex client
/// configuration used for exec-based threads.
pub fn Codex::app_server(self : Codex) -> CodexApp {
  { options: self.options }
}

///|
/// Start a Codex app-server process using stdio JSON-RPC transport.
///
/// The returned connection has two logical channels:
/// - `send` writes client JSON-RPC frames to app-server stdin.
/// - `next` reads server JSON-RPC frames from app-server stdout.
pub fn[G] CodexApp::connect(
  self : CodexApp,
  options? : AppServerOptions = AppServerOptions::default(),
  taskgroup : @async.TaskGroup[G],
) -> CodexAppConnection {
  let executable_path = options.executable_path_override.unwrap_or(
    "codex-app-server",
  )
  let outgoing : @async.Queue[Json] = @async.Queue::new(kind=Unbounded)
  let buffered : @async.Queue[AppServerMessage] = @async.Queue::new(
    kind=Unbounded,
  )
  let incoming = @generator.AsyncGenerator::new(
    async fn(yield_) {
      let stdin = @process.write_to_process() catch {
        e => raise @error.reraise(e)
      }
      let stdout = @process.read_from_process() catch {
        e => raise @error.reraise(e)
      }
      let extra_env = self.options.env.unwrap_or({})
      if self.options.base_url is Some(base_url) {
        extra_env.set("OPENAI_BASE_URL", base_url)
      }
      if self.options.api_key is Some(api_key) {
        extra_env.set("CODEX_API_KEY", api_key)
      }
      @async.with_task_group(taskgroup => {
        taskgroup.spawn_bg(() => {
          let (exit_code, stderr) = @process.collect_stderr(
            executable_path,
            ["--listen", "stdio://"],
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
        let reader = stdout.0
        defer reader.close()
        while reader.read_until("\n") is Some(text) {
          let message : AppServerMessage = @json.from_json(@json.parse(text))
          yield_(message) catch {
            @generator.Return => return
            e => raise @error.reraise(e)
          }
        }
      })
    },
    taskgroup,
  )
  { outgoing, incoming, buffered, next_request_id: 1 }
}

///|
struct CodexAppConnection {
  outgoing : @async.Queue[Json]
  incoming : @generator.AsyncGenerator[AppServerMessage]
  buffered : @async.Queue[AppServerMessage]
  mut next_request_id : Int
}

///|
/// Call one app-server JSON-RPC method and wait for its response.
///
/// This is the ergonomic request/response API for app-server operations. It
/// allocates an integer JSON-RPC id, sends a `ClientRequest`, and returns the
/// matching `Response` or `ErrorResponse`. Other server messages observed while
/// waiting are buffered and can still be read later with `next`.
///
/// `call` and `next` share the same receive stream. Do not consume the same
/// connection concurrently from multiple tasks unless you provide your own
/// external synchronization.
async fn CodexAppConnection::call(
  self : CodexAppConnection,
  rpc_method : String,
  params? : Json,
) -> Json {
  let id = AppRequestId::IntId(self.next_request_id)
  self.next_request_id += 1
  self.send(AppClientMessage::ClientRequest(id~, rpc_method~, params~))
  let pending : Array[AppServerMessage] = []
  try {
    while self.buffered.try_get() is Some(message) {
      match message {
        Response(id=response_id, result~) if response_id == id => {
          for pending_message in pending {
            self.buffered.put(pending_message)
          }
          return result
        }
        ErrorResponse(id=response_id, error~) if response_id == id => {
          for pending_message in pending {
            self.buffered.put(pending_message)
          }
          @error.fail(format_app_rpc_error(error))
        }
        _ => pending.push(message)
      }
    }
  } catch {
    _ => ()
  }
  for pending_message in pending {
    self.buffered.put(pending_message)
  }
  while self.incoming.next() is Some(message) {
    match message {
      Response(id=response_id, result~) if response_id == id => return result
      ErrorResponse(id=response_id, error~) if response_id == id =>
        @error.fail(format_app_rpc_error(error))
      _ => self.buffered.put(message)
    }
  }
  @error.fail("Codex app server closed before responding to \{rpc_method}")
}

///|
/// Call a request object that implements the internal app-server request trait.
async fn CodexAppConnection::call_app(
  self : CodexAppConnection,
  call : &@internal.AppCall,
) -> Json {
  self.call(call.rpc_method(), params?=call.params())
}

///|
/// Send the app-server `initialized` notification.
pub async fn CodexAppConnection::initialized(self : CodexAppConnection) -> Unit {
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/list", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/start", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/resume`.
pub async fn CodexAppConnection::thread_resume(
  self : CodexAppConnection,
  params : AppThreadResumeParams,
) -> AppThreadStartResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/resume", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/archive`.
pub async fn CodexAppConnection::thread_archive(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppEmptyResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/archive", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/unarchive`.
pub async fn CodexAppConnection::thread_unarchive(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadReadResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/unarchive", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/unsubscribe`.
pub async fn CodexAppConnection::thread_unsubscribe(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadUnsubscribeResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/unsubscribe", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/name/set`.
pub async fn CodexAppConnection::thread_set_name(
  self : CodexAppConnection,
  params : AppThreadSetNameParams,
) -> AppEmptyResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/name/set", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/loaded/list", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `thread/read`.
pub async fn CodexAppConnection::thread_read(
  self : CodexAppConnection,
  params : AppThreadReadParams,
) -> AppThreadReadResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("thread/read", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `turn/start`.
pub async fn CodexAppConnection::turn_start(
  self : CodexAppConnection,
  params : AppTurnStartParams,
) -> AppTurnStartResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("turn/start", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `turn/steer`.
pub async fn CodexAppConnection::turn_steer(
  self : CodexAppConnection,
  params : AppTurnSteerParams,
) -> AppTurnSteerResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("turn/steer", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `turn/interrupt`.
pub async fn CodexAppConnection::turn_interrupt(
  self : CodexAppConnection,
  params : AppTurnInterruptParams,
) -> AppEmptyResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("turn/interrupt", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("skills/list", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("app/list", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `config/read`.
pub async fn CodexAppConnection::config_read(
  self : CodexAppConnection,
  params : AppConfigReadParams,
) -> AppConfigReadResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("config/read", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
/// Call `modelProvider/capabilities/read`.
pub async fn CodexAppConnection::model_provider_capabilities_read(
  self : CodexAppConnection,
) -> AppModelProviderCapabilitiesReadResponse {
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("modelProvider/capabilities/read", params={})
      as &@internal.AppCall,
    ),
  )
}

///|
pub struct AppThreadListResponse {
  data : Array[AppThread]
  next_cursor : String?
  backwards_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadListResponse with from_json(value, path) {
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
  instruction_sources : Array[String]
  approval_policy : AppApprovalPolicy
  approvals_reviewer : AppApprovalsReviewer
  sandbox : AppSandboxPolicy
  reasoning_effort : AppReasoningEffort?
} derive(Debug)

///|
pub impl FromJson for AppThreadStartResponse with from_json(value, path) {
  guard value
    is {
      "thread": thread,
      "model": String(model),
      "modelProvider": String(model_provider),
      "serviceTier"? : service_tier,
      "cwd": String(cwd),
      "instructionSources": instruction_sources,
      "approvalPolicy": approval_policy,
      "approvalsReviewer": approvals_reviewer,
      "sandbox": sandbox,
      "reasoningEffort"? : reasoning_effort,
      ..
    } else {
    raise JsonDecodeError((path, "expected thread/start response"))
  }
  {
    thread: @json.from_json(thread, path=path.add_key("thread")),
    model,
    model_provider,
    service_tier: app_optional_string(service_tier, path.add_key("serviceTier")),
    cwd,
    instruction_sources: @json.from_json(
      instruction_sources,
      path=path.add_key("instructionSources"),
    ),
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
pub impl FromJson for AppThreadReadResponse with from_json(value, path) {
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
pub impl FromJson for AppTurnStartResponse with from_json(value, path) {
  guard value is { "turn": turn, .. } else {
    raise JsonDecodeError((path, "expected turn/start response"))
  }
  { turn: @json.from_json(turn, path=path.add_key("turn")) }
}

///|
pub struct AppTurnInterruptResponse {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppTurnInterruptResponse with from_json(value, path) {
  guard value is Object(_) else {
    raise JsonDecodeError((path, "expected turn/interrupt response"))
  }
  { raw: value }
}

///|
pub struct AppEmptyResponse {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppEmptyResponse with from_json(value, path) {
  guard value is Object(_) else {
    raise JsonDecodeError((path, "expected empty object response"))
  }
  { raw: value }
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
pub impl ToJson for AppThreadIdParams with to_json(params) {
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
pub impl ToJson for AppThreadSetNameParams with to_json(params) {
  { "threadId": params.thread_id, "name": params.name }
}

///|
pub struct AppThreadResumeParams {
  thread_id : String
  model : String?
  model_provider : String?
  service_tier : String?
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
  service_tier? : String,
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
pub impl ToJson for AppThreadResumeParams with to_json(params) {
  let obj : Map[String, Json] = { "threadId": params.thread_id }
  if params.model is Some(model) {
    obj.set("model", model.to_json())
  }
  if params.model_provider is Some(model_provider) {
    obj.set("modelProvider", model_provider.to_json())
  }
  if params.service_tier is Some(service_tier) {
    obj.set("serviceTier", service_tier.to_json())
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
  limit : Int?
} derive(Debug)

///|
pub fn AppThreadLoadedListParams::new(
  cursor? : String,
  limit? : Int,
) -> AppThreadLoadedListParams {
  { cursor, limit }
}

///|
pub impl ToJson for AppThreadLoadedListParams with to_json(params) {
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
  data : Array[String]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadLoadedListResponse with from_json(value, path) {
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
pub impl FromJson for AppThreadUnsubscribeResponse with from_json(value, path) {
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
pub impl FromJson for AppThreadUnsubscribeStatus with from_json(value, path) {
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
pub impl ToJson for AppTurnSteerParams with to_json(params) {
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
pub impl FromJson for AppTurnSteerResponse with from_json(value, path) {
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
pub impl ToJson for AppSkillsListParams with to_json(params) {
  let obj : Map[String, Json] = {}
  if params.cwds is Some(cwds) {
    obj.set("cwds", cwds.to_json())
  }
  if params.force_reload is Some(force_reload) {
    obj.set("forceReload", force_reload.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppSkillsListEntry {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppSkillsListEntry with from_json(value, _path) {
  { raw: value }
}

///|
pub struct AppSkillsListResponse {
  data : Array[AppSkillsListEntry]
} derive(Debug)

///|
pub impl FromJson for AppSkillsListResponse with from_json(value, path) {
  guard value is { "data": data, .. } else {
    raise JsonDecodeError((path, "expected skills/list response"))
  }
  { data: @json.from_json(data, path=path.add_key("data")) }
}

///|
pub struct AppListParams {
  cursor : String?
  limit : Int?
  thread_id : String?
  force_refetch : Bool?
} derive(Debug)

///|
pub fn AppListParams::new(
  cursor? : String,
  limit? : Int,
  thread_id? : String,
  force_refetch? : Bool,
) -> AppListParams {
  { cursor, limit, thread_id, force_refetch }
}

///|
pub impl ToJson for AppListParams with to_json(params) {
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
  if params.force_refetch is Some(force_refetch) {
    obj.set("forceRefetch", force_refetch.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppListResponse {
  data : Array[AppInfo]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppListResponse with from_json(value, path) {
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
  plugin_display_names : Array[String]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppInfo with from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "description"? : description,
      "isAccessible": is_accessible,
      "isEnabled": is_enabled,
      "pluginDisplayNames": plugin_display_names,
      ..
    } else {
    raise JsonDecodeError((path, "expected app info"))
  }
  {
    id,
    name,
    description: app_optional_string(description, path.add_key("description")),
    is_accessible: app_bool(is_accessible, path.add_key("isAccessible")),
    is_enabled: app_bool(is_enabled, path.add_key("isEnabled")),
    plugin_display_names: @json.from_json(
      plugin_display_names,
      path=path.add_key("pluginDisplayNames"),
    ),
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
pub impl ToJson for AppConfigReadParams with to_json(params) {
  let obj : Map[String, Json] = { "includeLayers": params.include_layers }
  if params.cwd is Some(cwd) {
    obj.set("cwd", cwd.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppConfigSnapshot {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppConfigSnapshot with from_json(value, _path) {
  { raw: value }
}

///|
pub struct AppConfigOrigins {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppConfigOrigins with from_json(value, _path) {
  { raw: value }
}

///|
pub struct AppConfigLayers {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppConfigLayers with from_json(value, _path) {
  { raw: value }
}

///|
pub struct AppConfigReadResponse {
  config : AppConfigSnapshot
  origins : AppConfigOrigins
  layers : AppConfigLayers?
} derive(Debug)

///|
pub impl FromJson for AppConfigReadResponse with from_json(value, path) {
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
pub impl FromJson for AppModelProviderCapabilitiesReadResponse with from_json(
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
  limit : Int?
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
  limit? : Int,
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
pub impl ToJson for AppThreadListParams with to_json(params) {
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
  if params.use_state_db_only is Some(use_state_db_only) {
    obj.set("useStateDbOnly", use_state_db_only.to_json())
  }
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
pub impl ToJson for AppThreadListCwd with to_json(cwd) {
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
pub impl ToJson for AppThreadSortKey with to_json(key) {
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
pub impl ToJson for AppSortDirection with to_json(direction) {
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
pub impl ToJson for AppThreadSourceKind with to_json(kind) {
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
  service_tier : String?
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
  thread_source : AppThreadSource?
} derive(Debug)

///|
pub fn AppThreadStartParams::new(
  model? : String,
  model_provider? : String,
  service_tier? : String,
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
  thread_source? : AppThreadSource,
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
    thread_source,
  }
}

///|
pub impl ToJson for AppThreadStartParams with to_json(params) {
  let obj : Map[String, Json] = {}
  if params.model is Some(model) {
    obj.set("model", model.to_json())
  }
  if params.model_provider is Some(model_provider) {
    obj.set("modelProvider", model_provider.to_json())
  }
  if params.service_tier is Some(service_tier) {
    obj.set("serviceTier", service_tier.to_json())
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
  if params.thread_source is Some(thread_source) {
    obj.set("threadSource", thread_source.to_json())
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
pub impl ToJson for AppApprovalPolicy with to_json(policy) {
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
pub impl FromJson for AppApprovalPolicy with from_json(value, path) {
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
pub impl ToJson for AppApprovalsReviewer with to_json(reviewer) {
  match reviewer {
    AppReviewerUser => "user".to_json()
    AppReviewerAutoReview => "auto_review".to_json()
    AppReviewerGuardianSubagent => "guardian_subagent".to_json()
  }
}

///|
pub impl FromJson for AppApprovalsReviewer with from_json(value, path) {
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
pub impl ToJson for AppPersonality with to_json(personality) {
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
pub impl ToJson for AppThreadStartSource with to_json(source) {
  match source {
    AppThreadStartup => "startup".to_json()
    AppThreadClear => "clear".to_json()
  }
}

///|
pub(all) enum AppThreadSource {
  AppThreadSourceUser
  AppThreadSourceSubagent
  AppThreadSourceMemoryConsolidation
} derive(Debug)

///|
pub impl ToJson for AppThreadSource with to_json(source) {
  match source {
    AppThreadSourceUser => "user".to_json()
    AppThreadSourceSubagent => "subagent".to_json()
    AppThreadSourceMemoryConsolidation => "memory_consolidation".to_json()
  }
}

///|
pub impl ToJson for SandboxMode with to_json(mode) {
  match mode {
    ReadOnly => "read-only".to_json()
    WorkspaceWrite => "workspace-write".to_json()
    DangerFullAccess => "danger-full-access".to_json()
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
pub impl ToJson for AppThreadReadParams with to_json(params) {
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
  service_tier : String?
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
  service_tier? : String,
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
pub impl ToJson for AppTurnStartParams with to_json(params) {
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
  if params.service_tier is Some(service_tier) {
    obj.set("serviceTier", service_tier.to_json())
  }
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
pub impl ToJson for AppUserInput with to_json(input) {
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
pub impl ToJson for AppNetworkAccess with to_json(access) {
  match access {
    AppNetworkRestricted => "restricted".to_json()
    AppNetworkEnabled => "enabled".to_json()
  }
}

///|
pub impl FromJson for AppNetworkAccess with from_json(value, path) {
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
pub impl ToJson for AppSandboxPolicy with to_json(policy) {
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
pub impl FromJson for AppSandboxPolicy with from_json(value, path) {
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
pub impl ToJson for AppReasoningEffort with to_json(effort) {
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
pub impl FromJson for AppReasoningEffort with from_json(value, path) {
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
pub impl ToJson for AppReasoningSummary with to_json(summary) {
  match summary {
    AppSummaryAuto => "auto".to_json()
    AppSummaryConcise => "concise".to_json()
    AppSummaryDetailed => "detailed".to_json()
    AppSummaryNone => "none".to_json()
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
pub impl ToJson for AppTurnInterruptParams with to_json(params) {
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
  @json.from_json(
    self.call_app(
      @internal.AppRawCall::new("model/list", params=params.to_json())
      as &@internal.AppCall,
    ),
  )
}

///|
pub struct AppModelListResponse {
  data : Array[AppModel]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppModelListResponse with from_json(value, path) {
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
  display_name : String
  description : String
  hidden : Bool
  default_reasoning_effort : AppReasoningEffort
  input_modalities : Array[AppInputModality]
  supports_personality : Bool
  is_default : Bool
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppModel with from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "model": String(model),
      "displayName": String(display_name),
      "description": String(description),
      "hidden": hidden,
      "defaultReasoningEffort": default_reasoning_effort,
      "inputModalities": input_modalities,
      "supportsPersonality": supports_personality,
      "isDefault": is_default,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server Model"))
  }
  {
    id,
    model,
    display_name,
    description,
    hidden: app_bool(hidden, path.add_key("hidden")),
    default_reasoning_effort: @json.from_json(
      default_reasoning_effort,
      path=path.add_key("defaultReasoningEffort"),
    ),
    input_modalities: @json.from_json(
      input_modalities,
      path=path.add_key("inputModalities"),
    ),
    supports_personality: app_bool(
      supports_personality,
      path.add_key("supportsPersonality"),
    ),
    is_default: app_bool(is_default, path.add_key("isDefault")),
    raw: value,
  }
}

///|
pub(all) enum AppInputModality {
  AppTextModality
  AppImageModality
} derive(Debug)

///|
pub impl FromJson for AppInputModality with from_json(value, path) {
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
  limit : Int?
  /// Include models hidden from the default picker list.
  include_hidden : Bool?
} derive(Debug)

///|
pub fn AppModelListParams::new(
  cursor? : String,
  limit? : Int,
  include_hidden? : Bool,
) -> AppModelListParams {
  { cursor, limit, include_hidden }
}

///|
pub impl ToJson for AppModelListParams with to_json(params) {
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
/// Non-request messages observed while waiting are buffered for `next`. If the
/// handler returns normally, the SDK sends the JSON-RPC response. If the handler
/// raises, the SDK catches the error and sends a JSON-RPC error response.
pub async fn CodexAppConnection::handle_next_request(
  self : CodexAppConnection,
  handler : (AppServerRequest) -> AppServerResponse raise,
) -> Bool {
  let skipped : Array[AppServerMessage] = []
  try {
    while self.buffered.try_get() is Some(message) {
      match message {
        Request(request) => {
          for skipped_message in skipped {
            self.buffered.put(skipped_message)
          }
          self.handle_request(request, handler)
          return true
        }
        _ => skipped.push(message)
      }
    }
  } catch {
    _ => ()
  }
  for skipped_message in skipped {
    self.buffered.put(skipped_message)
  }
  while self.incoming.next() is Some(message) {
    match message {
      Request(request) => {
        self.handle_request(request, handler)
        return true
      }
      _ => self.buffered.put(message)
    }
  }
  false
}

///|
pub async fn CodexAppConnection::handle_request(
  self : CodexAppConnection,
  request : AppServerRequest,
  handler : (AppServerRequest) -> AppServerResponse raise,
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
/// Server-initiated app-server request.
pub struct AppServerRequest {
  id : AppRequestId
  rpc_method : String
  params : Json?
  details : AppServerRequestDetails
} derive(Debug)

///|
pub enum AppServerRequestDetails {
  AppCommandExecutionApprovalRequest(AppCommandExecutionApprovalRequest)
  AppFileChangeApprovalRequest(AppFileChangeApprovalRequest)
  AppToolRequestUserInputRequest(AppToolRequestUserInputRequest)
  AppRawRequest
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
  AppRawResponse(Json)
} derive(Debug)

///|
pub impl ToJson for AppServerResponse with to_json(response) {
  match response {
    AppCommandExecutionApprovalResponse(decision~) => { "decision": decision }
    AppFileChangeApprovalResponse(decision~) => { "decision": decision }
    AppToolRequestUserInputResponse(answers~) => { "answers": answers }
    AppRawResponse(value) => value
  }
}

///|
pub(all) struct AppCommandExecutionApprovalRequest {
  thread_id : String
  turn_id : String
  item_id : String
  started_at_ms : Int
  approval_id : String?
  reason : String?
  command : String?
  cwd : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppCommandExecutionApprovalRequest with from_json(
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
      "command"? : command,
      "cwd"? : cwd,
      ..
    } else {
    raise JsonDecodeError((path, "expected command execution approval request"))
  }
  {
    thread_id,
    turn_id,
    item_id,
    started_at_ms: started_at_ms.to_int(),
    approval_id: app_optional_string(approval_id, path.add_key("approvalId")),
    reason: app_optional_string(reason, path.add_key("reason")),
    command: app_optional_string(command, path.add_key("command")),
    cwd: app_optional_string(cwd, path.add_key("cwd")),
    raw: value,
  }
}

///|
pub(all) enum AppCommandExecutionApprovalDecision {
  AppCommandAccept
  AppCommandAcceptForSession
  AppCommandDecline
  AppCommandCancel
  AppCommandAcceptWithExecpolicyAmendment(Json)
  AppCommandApplyNetworkPolicyAmendment(Json)
} derive(Debug)

///|
pub impl ToJson for AppCommandExecutionApprovalDecision with to_json(decision) {
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
  started_at_ms : Int
  reason : String?
  grant_root : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppFileChangeApprovalRequest with from_json(value, path) {
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
    started_at_ms: started_at_ms.to_int(),
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
pub impl ToJson for AppFileChangeApprovalDecision with to_json(decision) {
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
  questions : Array[AppToolRequestUserInputQuestion]
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppToolRequestUserInputRequest with from_json(value, path) {
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
pub(all) struct AppToolRequestUserInputQuestion {
  id : String
  header : String
  question : String
  is_other : Bool
  is_secret : Bool
  options : Array[AppToolRequestUserInputOption]?
} derive(Debug)

///|
pub impl FromJson for AppToolRequestUserInputQuestion with from_json(
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
  answers : Array[String]
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
/// Receive the next server JSON-RPC frame from the app server.
pub async fn CodexAppConnection::next(
  self : CodexAppConnection,
) -> AppServerMessage? {
  let buffered = self.buffered.try_get() catch { _ => None }
  match buffered {
    Some(message) => Some(message)
    None => self.incoming.next()
  }
}

///|
/// Close the send channel. The app-server process exits after stdin closes.
pub fn CodexAppConnection::close(self : CodexAppConnection) -> Unit {
  self.outgoing.close(clear=true)
  self.buffered.close(clear=true)
}

///|
/// JSON-RPC request id used by the Codex app server protocol.
pub(all) enum AppRequestId {
  StringId(String)
  IntId(Int)
} derive(Debug, Eq)

///|
pub impl ToJson for AppRequestId with to_json(id) {
  match id {
    StringId(value) => value.to_json()
    IntId(value) => value.to_json()
  }
}

///|
pub impl FromJson for AppRequestId with from_json(value, path) {
  match value {
    String(value) => StringId(value)
    Number(value, ..) => IntId(value.to_int())
    _ =>
      raise JsonDecodeError(
        (
          path, "expected string or integer request id, got \\{value.stringify()}",
        ),
      )
  }
}

///|
pub struct AppRpcError {
  code : Int
  message : String
  data : Json?
} derive(ToJson, Debug)

///|
pub impl FromJson for AppRpcError with from_json(value, path) {
  guard value
    is {
      "code": Number(code, ..),
      "message": String(message),
      "data"? : data,
      ..
    } else {
    raise JsonDecodeError((path, "expected JSON-RPC error object"))
  }
  { code: code.to_int(), message, data }
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
fn app_put_bool(obj : Map[String, Json], key : String, value : Bool?) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
  }
}

///|
fn app_put_int(obj : Map[String, Json], key : String, value : Int?) -> Unit {
  if value is Some(value) {
    obj.set(key, value.to_json())
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
pub impl ToJson for AppClientInfo with to_json(info) {
  let obj : Map[String, Json] = { "name": info.name, "version": info.version }
  app_put_string(obj, "title", info.title)
  Json::object(obj)
}

///|
pub(all) struct AppInitializeCapabilities {
  experimental_api : Bool
  request_attestation : Bool
  opt_out_notification_methods : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppInitializeCapabilities with to_json(capabilities) {
  let obj : Map[String, Json] = {
    "experimentalApi": capabilities.experimental_api,
    "requestAttestation": capabilities.request_attestation,
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
pub impl ToJson for AppInitializeParams with to_json(params) {
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
  service_tier : String?
  cwd : String?
  approval_policy : AppApprovalPolicy?
  approvals_reviewer : AppApprovalsReviewer?
  sandbox : SandboxMode?
  config : Map[String, Json]?
  base_instructions : String?
  developer_instructions : String?
  ephemeral : Bool?
  thread_source : AppThreadSource?
} derive(Debug)

///|
pub impl ToJson for AppThreadForkParams with to_json(params) {
  let obj : Map[String, Json] = { "threadId": params.thread_id }
  app_put_string(obj, "model", params.model)
  app_put_string(obj, "modelProvider", params.model_provider)
  app_put_string(obj, "serviceTier", params.service_tier)
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
  app_put_bool(obj, "ephemeral", params.ephemeral)
  if params.thread_source is Some(value) {
    obj.set("threadSource", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadMetadataGitInfoUpdateParams {
  sha : String?
  branch : String?
  origin_url : String?
} derive(Debug)

///|
pub impl ToJson for AppThreadMetadataGitInfoUpdateParams with to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "sha", params.sha)
  app_put_string(obj, "branch", params.branch)
  app_put_string(obj, "originUrl", params.origin_url)
  Json::object(obj)
}

///|
pub(all) struct AppThreadMetadataUpdateParams {
  thread_id : String
  git_info : AppThreadMetadataGitInfoUpdateParams?
} derive(Debug)

///|
pub impl ToJson for AppThreadMetadataUpdateParams with to_json(params) {
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
pub impl ToJson for AppThreadShellCommandParams with to_json(params) {
  { "threadId": params.thread_id, "command": params.command }
}

///|
pub(all) struct AppThreadApproveGuardianDeniedActionParams {
  thread_id : String
  event : Json
} derive(Debug)

///|
pub impl ToJson for AppThreadApproveGuardianDeniedActionParams with to_json(
  params,
) {
  { "threadId": params.thread_id, "event": params.event }
}

///|
pub(all) struct AppThreadRollbackParams {
  thread_id : String
  num_turns : Int
} derive(Debug)

///|
pub impl ToJson for AppThreadRollbackParams with to_json(params) {
  { "threadId": params.thread_id, "numTurns": params.num_turns }
}

///|
pub(all) struct AppThreadInjectItemsParams {
  thread_id : String
  items : Array[Json]
} derive(Debug)

///|
pub impl ToJson for AppThreadInjectItemsParams with to_json(params) {
  { "threadId": params.thread_id, "items": params.items }
}

///|
pub(all) struct AppHooksListParams {
  cwds : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppHooksListParams with to_json(params) {
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
pub impl ToJson for AppMarketplaceAddParams with to_json(params) {
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
pub impl ToJson for AppMarketplaceRemoveParams with to_json(params) {
  { "marketplaceName": params.marketplace_name }
}

///|
pub(all) struct AppMarketplaceUpgradeParams {
  marketplace_name : String?
} derive(Debug)

///|
pub impl ToJson for AppMarketplaceUpgradeParams with to_json(params) {
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
pub impl ToJson for AppPluginListMarketplaceKind with to_json(kind) {
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
pub impl ToJson for AppPluginListParams with to_json(params) {
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
pub impl ToJson for AppPluginReadParams with to_json(params) {
  let obj : Map[String, Json] = { "pluginName": params.plugin_name }
  app_put_string(obj, "marketplacePath", params.marketplace_path)
  app_put_string(obj, "remoteMarketplaceName", params.remote_marketplace_name)
  Json::object(obj)
}

///|
pub(all) struct AppPluginSkillReadParams {
  remote_marketplace_name : String
  remote_plugin_id : String
  skill_name : String
} derive(Debug)

///|
pub impl ToJson for AppPluginSkillReadParams with to_json(params) {
  {
    "remoteMarketplaceName": params.remote_marketplace_name,
    "remotePluginId": params.remote_plugin_id,
    "skillName": params.skill_name,
  }
}

///|
pub(all) enum AppPluginShareDiscoverability {
  AppPluginShareListed
  AppPluginShareUnlisted
  AppPluginSharePrivate
} derive(Debug)

///|
pub impl ToJson for AppPluginShareDiscoverability with to_json(value) {
  match value {
    AppPluginShareListed => "LISTED".to_json()
    AppPluginShareUnlisted => "UNLISTED".to_json()
    AppPluginSharePrivate => "PRIVATE".to_json()
  }
}

///|
pub(all) enum AppPluginShareUpdateDiscoverability {
  AppPluginShareUpdateUnlisted
  AppPluginShareUpdatePrivate
} derive(Debug)

///|
pub impl ToJson for AppPluginShareUpdateDiscoverability with to_json(value) {
  match value {
    AppPluginShareUpdateUnlisted => "UNLISTED".to_json()
    AppPluginShareUpdatePrivate => "PRIVATE".to_json()
  }
}

///|
pub(all) struct AppPluginShareTarget {
  principal_type : String
  principal_id : String
  role : String
} derive(Debug)

///|
pub impl ToJson for AppPluginShareTarget with to_json(target) {
  {
    "principalType": target.principal_type,
    "principalId": target.principal_id,
    "role": target.role,
  }
}

///|
pub(all) struct AppPluginShareSaveParams {
  plugin_path : String
  remote_plugin_id : String?
  discoverability : AppPluginShareDiscoverability?
  share_targets : Array[AppPluginShareTarget]?
} derive(Debug)

///|
pub impl ToJson for AppPluginShareSaveParams with to_json(params) {
  let obj : Map[String, Json] = { "pluginPath": params.plugin_path }
  app_put_string(obj, "remotePluginId", params.remote_plugin_id)
  if params.discoverability is Some(value) {
    obj.set("discoverability", value.to_json())
  }
  if params.share_targets is Some(value) {
    obj.set("shareTargets", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppPluginShareUpdateTargetsParams {
  remote_plugin_id : String
  discoverability : AppPluginShareUpdateDiscoverability
  share_targets : Array[AppPluginShareTarget]
} derive(Debug)

///|
pub impl ToJson for AppPluginShareUpdateTargetsParams with to_json(params) {
  {
    "remotePluginId": params.remote_plugin_id,
    "discoverability": params.discoverability,
    "shareTargets": params.share_targets,
  }
}

///|
pub(all) struct AppPluginRemoteIdParams {
  remote_plugin_id : String
} derive(Debug)

///|
pub impl ToJson for AppPluginRemoteIdParams with to_json(params) {
  { "remotePluginId": params.remote_plugin_id }
}

///|
pub(all) struct AppFsPathParams {
  path : String
} derive(Debug)

///|
pub impl ToJson for AppFsPathParams with to_json(params) {
  { "path": params.path }
}

///|
pub(all) struct AppFsWriteFileParams {
  path : String
  data_base64 : String
} derive(Debug)

///|
pub impl ToJson for AppFsWriteFileParams with to_json(params) {
  { "path": params.path, "dataBase64": params.data_base64 }
}

///|
pub(all) struct AppFsCreateDirectoryParams {
  path : String
  recursive : Bool?
} derive(Debug)

///|
pub impl ToJson for AppFsCreateDirectoryParams with to_json(params) {
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
pub impl ToJson for AppFsRemoveParams with to_json(params) {
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
pub impl ToJson for AppFsCopyParams with to_json(params) {
  let obj : Map[String, Json] = {
    "sourcePath": params.source_path,
    "destinationPath": params.destination_path,
  }
  app_put_bool(obj, "recursive", params.recursive)
  Json::object(obj)
}

///|
pub(all) struct AppFsWatchParams {
  watch_id : String
  path : String
} derive(Debug)

///|
pub impl ToJson for AppFsWatchParams with to_json(params) {
  { "watchId": params.watch_id, "path": params.path }
}

///|
pub(all) struct AppFsUnwatchParams {
  watch_id : String
} derive(Debug)

///|
pub impl ToJson for AppFsUnwatchParams with to_json(params) {
  { "watchId": params.watch_id }
}

///|
pub(all) struct AppSkillsConfigWriteParams {
  path : String?
  name : String?
  enabled : Bool
} derive(Debug)

///|
pub impl ToJson for AppSkillsConfigWriteParams with to_json(params) {
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
pub impl ToJson for AppPluginInstallParams with to_json(params) {
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
pub impl ToJson for AppPluginUninstallParams with to_json(params) {
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
pub impl ToJson for AppReviewTarget with to_json(target) {
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
pub impl ToJson for AppReviewDelivery with to_json(delivery) {
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
pub impl ToJson for AppReviewStartParams with to_json(params) {
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
  limit : Int?
} derive(Debug)

///|
pub impl ToJson for AppCursorLimitParams with to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "cursor", params.cursor)
  app_put_int(obj, "limit", params.limit)
  Json::object(obj)
}

///|
pub(all) struct AppExperimentalFeatureEnablementSetParams {
  enablement : Map[String, Bool]
} derive(Debug)

///|
pub impl ToJson for AppExperimentalFeatureEnablementSetParams with to_json(
  params,
) {
  { "enablement": params.enablement }
}

///|
pub(all) struct AppMcpServerOauthLoginParams {
  name : String
  scopes : Array[String]?
  timeout_secs : Int?
} derive(Debug)

///|
pub impl ToJson for AppMcpServerOauthLoginParams with to_json(params) {
  let obj : Map[String, Json] = { "name": params.name }
  app_put_strings(obj, "scopes", params.scopes)
  app_put_int(obj, "timeoutSecs", params.timeout_secs)
  Json::object(obj)
}

///|
pub(all) enum AppMcpServerStatusDetail {
  AppMcpServerStatusFull
  AppMcpServerStatusToolsAndAuthOnly
} derive(Debug)

///|
pub impl ToJson for AppMcpServerStatusDetail with to_json(detail) {
  match detail {
    AppMcpServerStatusFull => "full".to_json()
    AppMcpServerStatusToolsAndAuthOnly => "toolsAndAuthOnly".to_json()
  }
}

///|
pub(all) struct AppMcpServerStatusListParams {
  cursor : String?
  limit : Int?
  detail : AppMcpServerStatusDetail?
} derive(Debug)

///|
pub impl ToJson for AppMcpServerStatusListParams with to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "cursor", params.cursor)
  app_put_int(obj, "limit", params.limit)
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
pub impl ToJson for AppMcpResourceReadParams with to_json(params) {
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
pub impl ToJson for AppMcpServerToolCallParams with to_json(params) {
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
pub impl ToJson for AppWindowsSandboxSetupMode with to_json(mode) {
  match mode {
    AppWindowsSandboxElevated => "elevated".to_json()
    AppWindowsSandboxUnelevated => "unelevated".to_json()
  }
}

///|
pub(all) struct AppWindowsSandboxSetupStartParams {
  mode : AppWindowsSandboxSetupMode
  cwd : String?
} derive(Debug)

///|
pub impl ToJson for AppWindowsSandboxSetupStartParams with to_json(params) {
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
pub impl ToJson for AppLoginAccountParams with to_json(params) {
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
pub impl ToJson for AppCancelLoginAccountParams with to_json(params) {
  { "loginId": params.login_id }
}

///|
pub(all) enum AppAddCreditsNudgeCreditType {
  AppAddCreditsNudgeCredits
  AppAddCreditsNudgeUsageLimit
} derive(Debug)

///|
pub impl ToJson for AppAddCreditsNudgeCreditType with to_json(credit_type) {
  match credit_type {
    AppAddCreditsNudgeCredits => "credits".to_json()
    AppAddCreditsNudgeUsageLimit => "usage_limit".to_json()
  }
}

///|
pub(all) struct AppSendAddCreditsNudgeEmailParams {
  credit_type : AppAddCreditsNudgeCreditType
} derive(Debug)

///|
pub impl ToJson for AppSendAddCreditsNudgeEmailParams with to_json(params) {
  { "creditType": params.credit_type }
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
pub impl ToJson for AppFeedbackUploadParams with to_json(params) {
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
  rows : Int
  cols : Int
} derive(Debug)

///|
pub impl ToJson for AppCommandExecTerminalSize with to_json(size) {
  { "rows": size.rows, "cols": size.cols }
}

///|
pub(all) struct AppCommandExecParams {
  command : Array[String]
  process_id : String?
  tty : Bool?
  stream_stdin : Bool?
  stream_stdout_stderr : Bool?
  output_bytes_cap : Int?
  disable_output_cap : Bool?
  disable_timeout : Bool?
  timeout_ms : Int?
  cwd : String?
  env : Map[String, String]?
  size : AppCommandExecTerminalSize?
  sandbox_policy : AppSandboxPolicy?
} derive(Debug)

///|
pub impl ToJson for AppCommandExecParams with to_json(params) {
  let obj : Map[String, Json] = { "command": params.command }
  app_put_string(obj, "processId", params.process_id)
  app_put_bool(obj, "tty", params.tty)
  app_put_bool(obj, "streamStdin", params.stream_stdin)
  app_put_bool(obj, "streamStdoutStderr", params.stream_stdout_stderr)
  app_put_int(obj, "outputBytesCap", params.output_bytes_cap)
  app_put_bool(obj, "disableOutputCap", params.disable_output_cap)
  app_put_bool(obj, "disableTimeout", params.disable_timeout)
  app_put_int(obj, "timeoutMs", params.timeout_ms)
  app_put_string(obj, "cwd", params.cwd)
  if params.env is Some(value) {
    obj.set("env", value.to_json())
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
pub impl ToJson for AppCommandExecWriteParams with to_json(params) {
  let obj : Map[String, Json] = { "processId": params.process_id }
  app_put_string(obj, "deltaBase64", params.delta_base64)
  app_put_bool(obj, "closeStdin", params.close_stdin)
  Json::object(obj)
}

///|
pub(all) struct AppCommandExecProcessParams {
  process_id : String
} derive(Debug)

///|
pub impl ToJson for AppCommandExecProcessParams with to_json(params) {
  { "processId": params.process_id }
}

///|
pub(all) struct AppCommandExecResizeParams {
  process_id : String
  size : AppCommandExecTerminalSize
} derive(Debug)

///|
pub impl ToJson for AppCommandExecResizeParams with to_json(params) {
  { "processId": params.process_id, "size": params.size }
}

///|
pub(all) struct AppExternalAgentConfigDetectParams {
  include_home : Bool?
  cwds : Array[String]?
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigDetectParams with to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_bool(obj, "includeHome", params.include_home)
  app_put_strings(obj, "cwds", params.cwds)
  Json::object(obj)
}

///|
pub(all) struct AppExternalAgentConfigMigrationItem {
  item_type : String
  description : String
  cwd : String?
  details : Json?
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigMigrationItem with to_json(item) {
  let obj : Map[String, Json] = {
    "itemType": item.item_type,
    "description": item.description,
  }
  app_put_string(obj, "cwd", item.cwd)
  match item.details {
    Some(value) => obj.set("details", value)
    None => obj.set("details", Json::null())
  }
  Json::object(obj)
}

///|
pub(all) struct AppExternalAgentConfigImportParams {
  migration_items : Array[AppExternalAgentConfigMigrationItem]
} derive(Debug)

///|
pub impl ToJson for AppExternalAgentConfigImportParams with to_json(params) {
  { "migrationItems": params.migration_items }
}

///|
pub(all) enum AppMergeStrategy {
  AppMergeReplace
  AppMergeUpsert
} derive(Debug)

///|
pub impl ToJson for AppMergeStrategy with to_json(strategy) {
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
pub impl ToJson for AppConfigEdit with to_json(edit) {
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
pub impl ToJson for AppConfigValueWriteParams with to_json(params) {
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
pub impl ToJson for AppConfigBatchWriteParams with to_json(params) {
  let obj : Map[String, Json] = { "edits": params.edits }
  app_put_string(obj, "filePath", params.file_path)
  app_put_string(obj, "expectedVersion", params.expected_version)
  app_put_bool(obj, "reloadUserConfig", params.reload_user_config)
  Json::object(obj)
}

///|
pub(all) struct AppAccountReadParams {
  refresh_token : Bool
} derive(Debug)

///|
pub impl ToJson for AppAccountReadParams with to_json(params) {
  { "refreshToken": params.refresh_token }
}

///|
pub(all) enum AppConversationSummaryParams {
  AppConversationSummaryByRolloutPath(String)
  AppConversationSummaryByConversationId(String)
} derive(Debug)

///|
pub impl ToJson for AppConversationSummaryParams with to_json(params) {
  match params {
    AppConversationSummaryByRolloutPath(path) => { "rolloutPath": path }
    AppConversationSummaryByConversationId(id) => { "conversationId": id }
  }
}

///|
pub(all) struct AppCwdParams {
  cwd : String
} derive(Debug)

///|
pub impl ToJson for AppCwdParams with to_json(params) {
  { "cwd": params.cwd }
}

///|
pub(all) struct AppGetAuthStatusParams {
  include_token : Bool?
  refresh_token : Bool?
} derive(Debug)

///|
pub impl ToJson for AppGetAuthStatusParams with to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_bool(obj, "includeToken", params.include_token)
  app_put_bool(obj, "refreshToken", params.refresh_token)
  Json::object(obj)
}

///|
pub(all) struct AppFuzzyFileSearchParams {
  query : String
  roots : Array[String]
  cancellation_token : String?
} derive(Debug)

///|
pub impl ToJson for AppFuzzyFileSearchParams with to_json(params) {
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
pub struct AppInitializeResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadForkResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadMetadataUpdateResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadCompactStartResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadShellCommandResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadApproveGuardianDeniedActionResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadRollbackResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppThreadInjectItemsResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppHooksListResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMarketplaceAddResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMarketplaceRemoveResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMarketplaceUpgradeResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginListResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginSkillReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginShareSaveResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginShareUpdateTargetsResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginShareListResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginShareCheckoutResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginShareDeleteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsReadFileResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsWriteFileResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsCreateDirectoryResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsGetMetadataResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsReadDirectoryResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsRemoveResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsCopyResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsWatchResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFsUnwatchResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppSkillsConfigWriteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginInstallResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppPluginUninstallResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppReviewStartResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppExperimentalFeatureListResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppExperimentalFeatureEnablementSetResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMcpServerOauthLoginResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppConfigMcpServerReloadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMcpServerStatusListResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMcpServerResourceReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppMcpServerToolCallResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppWindowsSandboxSetupStartResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppWindowsSandboxReadinessResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountLoginStartResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountLoginCancelResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountLogoutResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountRateLimitsReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountSendAddCreditsNudgeEmailResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFeedbackUploadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppCommandExecResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppCommandExecWriteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppCommandExecTerminateResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppCommandExecResizeResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppExternalAgentConfigDetectResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppExternalAgentConfigImportResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppConfigValueWriteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppConfigBatchWriteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppConfigRequirementsReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppAccountReadResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppConversationSummaryResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppGitDiffToRemoteResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppGetAuthStatusResponse {
  priv raw : Json
} derive(Debug)

///|
pub struct AppFuzzyFileSearchResponse {
  priv raw : Json
} derive(Debug)

///|
/// Call `initialize`.
pub async fn CodexAppConnection::initialize(
  self : CodexAppConnection,
  params : AppInitializeParams,
) -> AppInitializeResponse {
  { raw: self.call_raw("initialize", params=params.to_json()) }
}

///|
/// Call `thread/fork`.
pub async fn CodexAppConnection::thread_fork(
  self : CodexAppConnection,
  params : AppThreadForkParams,
) -> AppThreadForkResponse {
  { raw: self.call_raw("thread/fork", params=params.to_json()) }
}

///|
/// Call `thread/metadata/update`.
pub async fn CodexAppConnection::thread_metadata_update(
  self : CodexAppConnection,
  params : AppThreadMetadataUpdateParams,
) -> AppThreadMetadataUpdateResponse {
  { raw: self.call_raw("thread/metadata/update", params=params.to_json()) }
}

///|
/// Call `thread/compact/start`.
pub async fn CodexAppConnection::thread_compact_start(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadCompactStartResponse {
  { raw: self.call_raw("thread/compact/start", params=params.to_json()) }
}

///|
/// Call `thread/shellCommand`.
pub async fn CodexAppConnection::thread_shell_command(
  self : CodexAppConnection,
  params : AppThreadShellCommandParams,
) -> AppThreadShellCommandResponse {
  { raw: self.call_raw("thread/shellCommand", params=params.to_json()) }
}

///|
/// Call `thread/approveGuardianDeniedAction`.
pub async fn CodexAppConnection::thread_approve_guardian_denied_action(
  self : CodexAppConnection,
  params : AppThreadApproveGuardianDeniedActionParams,
) -> AppThreadApproveGuardianDeniedActionResponse {
  {
    raw: self.call_raw(
      "thread/approveGuardianDeniedAction",
      params=params.to_json(),
    ),
  }
}

///|
/// Call `thread/rollback`.
pub async fn CodexAppConnection::thread_rollback(
  self : CodexAppConnection,
  params : AppThreadRollbackParams,
) -> AppThreadRollbackResponse {
  { raw: self.call_raw("thread/rollback", params=params.to_json()) }
}

///|
/// Call `thread/inject_items`.
pub async fn CodexAppConnection::thread_inject_items(
  self : CodexAppConnection,
  params : AppThreadInjectItemsParams,
) -> AppThreadInjectItemsResponse {
  { raw: self.call_raw("thread/inject_items", params=params.to_json()) }
}

///|
/// Call `hooks/list`.
pub async fn CodexAppConnection::hooks_list(
  self : CodexAppConnection,
  params : AppHooksListParams,
) -> AppHooksListResponse {
  { raw: self.call_raw("hooks/list", params=params.to_json()) }
}

///|
/// Call `marketplace/add`.
pub async fn CodexAppConnection::marketplace_add(
  self : CodexAppConnection,
  params : AppMarketplaceAddParams,
) -> AppMarketplaceAddResponse {
  { raw: self.call_raw("marketplace/add", params=params.to_json()) }
}

///|
/// Call `marketplace/remove`.
pub async fn CodexAppConnection::marketplace_remove(
  self : CodexAppConnection,
  params : AppMarketplaceRemoveParams,
) -> AppMarketplaceRemoveResponse {
  { raw: self.call_raw("marketplace/remove", params=params.to_json()) }
}

///|
/// Call `marketplace/upgrade`.
pub async fn CodexAppConnection::marketplace_upgrade(
  self : CodexAppConnection,
  params : AppMarketplaceUpgradeParams,
) -> AppMarketplaceUpgradeResponse {
  { raw: self.call_raw("marketplace/upgrade", params=params.to_json()) }
}

///|
/// Call `plugin/list`.
pub async fn CodexAppConnection::plugin_list(
  self : CodexAppConnection,
  params : AppPluginListParams,
) -> AppPluginListResponse {
  { raw: self.call_raw("plugin/list", params=params.to_json()) }
}

///|
/// Call `plugin/read`.
pub async fn CodexAppConnection::plugin_read(
  self : CodexAppConnection,
  params : AppPluginReadParams,
) -> AppPluginReadResponse {
  { raw: self.call_raw("plugin/read", params=params.to_json()) }
}

///|
/// Call `plugin/skill/read`.
pub async fn CodexAppConnection::plugin_skill_read(
  self : CodexAppConnection,
  params : AppPluginSkillReadParams,
) -> AppPluginSkillReadResponse {
  { raw: self.call_raw("plugin/skill/read", params=params.to_json()) }
}

///|
/// Call `plugin/share/save`.
pub async fn CodexAppConnection::plugin_share_save(
  self : CodexAppConnection,
  params : AppPluginShareSaveParams,
) -> AppPluginShareSaveResponse {
  { raw: self.call_raw("plugin/share/save", params=params.to_json()) }
}

///|
/// Call `plugin/share/updateTargets`.
pub async fn CodexAppConnection::plugin_share_update_targets(
  self : CodexAppConnection,
  params : AppPluginShareUpdateTargetsParams,
) -> AppPluginShareUpdateTargetsResponse {
  { raw: self.call_raw("plugin/share/updateTargets", params=params.to_json()) }
}

///|
/// Call `plugin/share/list`.
pub async fn CodexAppConnection::plugin_share_list(
  self : CodexAppConnection,
) -> AppPluginShareListResponse {
  { raw: self.call_raw("plugin/share/list", params={}) }
}

///|
/// Call `plugin/share/checkout`.
pub async fn CodexAppConnection::plugin_share_checkout(
  self : CodexAppConnection,
  params : AppPluginRemoteIdParams,
) -> AppPluginShareCheckoutResponse {
  { raw: self.call_raw("plugin/share/checkout", params=params.to_json()) }
}

///|
/// Call `plugin/share/delete`.
pub async fn CodexAppConnection::plugin_share_delete(
  self : CodexAppConnection,
  params : AppPluginRemoteIdParams,
) -> AppPluginShareDeleteResponse {
  { raw: self.call_raw("plugin/share/delete", params=params.to_json()) }
}

///|
/// Call `fs/readFile`.
pub async fn CodexAppConnection::fs_read_file(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsReadFileResponse {
  { raw: self.call_raw("fs/readFile", params=params.to_json()) }
}

///|
/// Call `fs/writeFile`.
pub async fn CodexAppConnection::fs_write_file(
  self : CodexAppConnection,
  params : AppFsWriteFileParams,
) -> AppFsWriteFileResponse {
  { raw: self.call_raw("fs/writeFile", params=params.to_json()) }
}

///|
/// Call `fs/createDirectory`.
pub async fn CodexAppConnection::fs_create_directory(
  self : CodexAppConnection,
  params : AppFsCreateDirectoryParams,
) -> AppFsCreateDirectoryResponse {
  { raw: self.call_raw("fs/createDirectory", params=params.to_json()) }
}

///|
/// Call `fs/getMetadata`.
pub async fn CodexAppConnection::fs_get_metadata(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsGetMetadataResponse {
  { raw: self.call_raw("fs/getMetadata", params=params.to_json()) }
}

///|
/// Call `fs/readDirectory`.
pub async fn CodexAppConnection::fs_read_directory(
  self : CodexAppConnection,
  params : AppFsPathParams,
) -> AppFsReadDirectoryResponse {
  { raw: self.call_raw("fs/readDirectory", params=params.to_json()) }
}

///|
/// Call `fs/remove`.
pub async fn CodexAppConnection::fs_remove(
  self : CodexAppConnection,
  params : AppFsRemoveParams,
) -> AppFsRemoveResponse {
  { raw: self.call_raw("fs/remove", params=params.to_json()) }
}

///|
/// Call `fs/copy`.
pub async fn CodexAppConnection::fs_copy(
  self : CodexAppConnection,
  params : AppFsCopyParams,
) -> AppFsCopyResponse {
  { raw: self.call_raw("fs/copy", params=params.to_json()) }
}

///|
/// Call `fs/watch`.
pub async fn CodexAppConnection::fs_watch(
  self : CodexAppConnection,
  params : AppFsWatchParams,
) -> AppFsWatchResponse {
  { raw: self.call_raw("fs/watch", params=params.to_json()) }
}

///|
/// Call `fs/unwatch`.
pub async fn CodexAppConnection::fs_unwatch(
  self : CodexAppConnection,
  params : AppFsUnwatchParams,
) -> AppFsUnwatchResponse {
  { raw: self.call_raw("fs/unwatch", params=params.to_json()) }
}

///|
/// Call `skills/config/write`.
pub async fn CodexAppConnection::skills_config_write(
  self : CodexAppConnection,
  params : AppSkillsConfigWriteParams,
) -> AppSkillsConfigWriteResponse {
  { raw: self.call_raw("skills/config/write", params=params.to_json()) }
}

///|
/// Call `plugin/install`.
pub async fn CodexAppConnection::plugin_install(
  self : CodexAppConnection,
  params : AppPluginInstallParams,
) -> AppPluginInstallResponse {
  { raw: self.call_raw("plugin/install", params=params.to_json()) }
}

///|
/// Call `plugin/uninstall`.
pub async fn CodexAppConnection::plugin_uninstall(
  self : CodexAppConnection,
  params : AppPluginUninstallParams,
) -> AppPluginUninstallResponse {
  { raw: self.call_raw("plugin/uninstall", params=params.to_json()) }
}

///|
/// Call `review/start`.
pub async fn CodexAppConnection::review_start(
  self : CodexAppConnection,
  params : AppReviewStartParams,
) -> AppReviewStartResponse {
  { raw: self.call_raw("review/start", params=params.to_json()) }
}

///|
/// Call `experimentalFeature/list`.
pub async fn CodexAppConnection::experimental_feature_list(
  self : CodexAppConnection,
  params : AppCursorLimitParams,
) -> AppExperimentalFeatureListResponse {
  { raw: self.call_raw("experimentalFeature/list", params=params.to_json()) }
}

///|
/// Call `experimentalFeature/enablement/set`.
pub async fn CodexAppConnection::experimental_feature_enablement_set(
  self : CodexAppConnection,
  params : AppExperimentalFeatureEnablementSetParams,
) -> AppExperimentalFeatureEnablementSetResponse {
  {
    raw: self.call_raw(
      "experimentalFeature/enablement/set",
      params=params.to_json(),
    ),
  }
}

///|
/// Call `mcpServer/oauth/login`.
pub async fn CodexAppConnection::mcp_server_oauth_login(
  self : CodexAppConnection,
  params : AppMcpServerOauthLoginParams,
) -> AppMcpServerOauthLoginResponse {
  { raw: self.call_raw("mcpServer/oauth/login", params=params.to_json()) }
}

///|
/// Call `config/mcpServer/reload`.
pub async fn CodexAppConnection::config_mcp_server_reload(
  self : CodexAppConnection,
) -> AppConfigMcpServerReloadResponse {
  { raw: self.call_raw("config/mcpServer/reload") }
}

///|
/// Call `mcpServerStatus/list`.
pub async fn CodexAppConnection::mcp_server_status_list(
  self : CodexAppConnection,
  params : AppMcpServerStatusListParams,
) -> AppMcpServerStatusListResponse {
  { raw: self.call_raw("mcpServerStatus/list", params=params.to_json()) }
}

///|
/// Call `mcpServer/resource/read`.
pub async fn CodexAppConnection::mcp_server_resource_read(
  self : CodexAppConnection,
  params : AppMcpResourceReadParams,
) -> AppMcpServerResourceReadResponse {
  { raw: self.call_raw("mcpServer/resource/read", params=params.to_json()) }
}

///|
/// Call `mcpServer/tool/call`.
pub async fn CodexAppConnection::mcp_server_tool_call(
  self : CodexAppConnection,
  params : AppMcpServerToolCallParams,
) -> AppMcpServerToolCallResponse {
  { raw: self.call_raw("mcpServer/tool/call", params=params.to_json()) }
}

///|
/// Call `windowsSandbox/setupStart`.
pub async fn CodexAppConnection::windows_sandbox_setup_start(
  self : CodexAppConnection,
  params : AppWindowsSandboxSetupStartParams,
) -> AppWindowsSandboxSetupStartResponse {
  { raw: self.call_raw("windowsSandbox/setupStart", params=params.to_json()) }
}

///|
/// Call `windowsSandbox/readiness`.
pub async fn CodexAppConnection::windows_sandbox_readiness(
  self : CodexAppConnection,
) -> AppWindowsSandboxReadinessResponse {
  { raw: self.call_raw("windowsSandbox/readiness") }
}

///|
/// Call `account/login/start`.
pub async fn CodexAppConnection::account_login_start(
  self : CodexAppConnection,
  params : AppLoginAccountParams,
) -> AppAccountLoginStartResponse {
  { raw: self.call_raw("account/login/start", params=params.to_json()) }
}

///|
/// Call `account/login/cancel`.
pub async fn CodexAppConnection::account_login_cancel(
  self : CodexAppConnection,
  params : AppCancelLoginAccountParams,
) -> AppAccountLoginCancelResponse {
  { raw: self.call_raw("account/login/cancel", params=params.to_json()) }
}

///|
/// Call `account/logout`.
pub async fn CodexAppConnection::account_logout(
  self : CodexAppConnection,
) -> AppAccountLogoutResponse {
  { raw: self.call_raw("account/logout") }
}

///|
/// Call `account/rateLimits/read`.
pub async fn CodexAppConnection::account_rate_limits_read(
  self : CodexAppConnection,
) -> AppAccountRateLimitsReadResponse {
  { raw: self.call_raw("account/rateLimits/read") }
}

///|
/// Call `account/sendAddCreditsNudgeEmail`.
pub async fn CodexAppConnection::account_send_add_credits_nudge_email(
  self : CodexAppConnection,
  params : AppSendAddCreditsNudgeEmailParams,
) -> AppAccountSendAddCreditsNudgeEmailResponse {
  {
    raw: self.call_raw(
      "account/sendAddCreditsNudgeEmail",
      params=params.to_json(),
    ),
  }
}

///|
/// Call `feedback/upload`.
pub async fn CodexAppConnection::feedback_upload(
  self : CodexAppConnection,
  params : AppFeedbackUploadParams,
) -> AppFeedbackUploadResponse {
  { raw: self.call_raw("feedback/upload", params=params.to_json()) }
}

///|
/// Call `command/exec`.
pub async fn CodexAppConnection::command_exec(
  self : CodexAppConnection,
  params : AppCommandExecParams,
) -> AppCommandExecResponse {
  { raw: self.call_raw("command/exec", params=params.to_json()) }
}

///|
/// Call `command/exec/write`.
pub async fn CodexAppConnection::command_exec_write(
  self : CodexAppConnection,
  params : AppCommandExecWriteParams,
) -> AppCommandExecWriteResponse {
  { raw: self.call_raw("command/exec/write", params=params.to_json()) }
}

///|
/// Call `command/exec/terminate`.
pub async fn CodexAppConnection::command_exec_terminate(
  self : CodexAppConnection,
  params : AppCommandExecProcessParams,
) -> AppCommandExecTerminateResponse {
  { raw: self.call_raw("command/exec/terminate", params=params.to_json()) }
}

///|
/// Call `command/exec/resize`.
pub async fn CodexAppConnection::command_exec_resize(
  self : CodexAppConnection,
  params : AppCommandExecResizeParams,
) -> AppCommandExecResizeResponse {
  { raw: self.call_raw("command/exec/resize", params=params.to_json()) }
}

///|
/// Call `externalAgentConfig/detect`.
pub async fn CodexAppConnection::external_agent_config_detect(
  self : CodexAppConnection,
  params : AppExternalAgentConfigDetectParams,
) -> AppExternalAgentConfigDetectResponse {
  { raw: self.call_raw("externalAgentConfig/detect", params=params.to_json()) }
}

///|
/// Call `externalAgentConfig/import`.
pub async fn CodexAppConnection::external_agent_config_import(
  self : CodexAppConnection,
  params : AppExternalAgentConfigImportParams,
) -> AppExternalAgentConfigImportResponse {
  { raw: self.call_raw("externalAgentConfig/import", params=params.to_json()) }
}

///|
/// Call `config/value/write`.
pub async fn CodexAppConnection::config_value_write(
  self : CodexAppConnection,
  params : AppConfigValueWriteParams,
) -> AppConfigValueWriteResponse {
  { raw: self.call_raw("config/value/write", params=params.to_json()) }
}

///|
/// Call `config/batchWrite`.
pub async fn CodexAppConnection::config_batch_write(
  self : CodexAppConnection,
  params : AppConfigBatchWriteParams,
) -> AppConfigBatchWriteResponse {
  { raw: self.call_raw("config/batchWrite", params=params.to_json()) }
}

///|
/// Call `configRequirements/read`.
pub async fn CodexAppConnection::config_requirements_read(
  self : CodexAppConnection,
) -> AppConfigRequirementsReadResponse {
  { raw: self.call_raw("configRequirements/read") }
}

///|
/// Call `account/read`.
pub async fn CodexAppConnection::account_read(
  self : CodexAppConnection,
  params : AppAccountReadParams,
) -> AppAccountReadResponse {
  { raw: self.call_raw("account/read", params=params.to_json()) }
}

///|
/// Call `getConversationSummary`.
pub async fn CodexAppConnection::get_conversation_summary(
  self : CodexAppConnection,
  params : AppConversationSummaryParams,
) -> AppConversationSummaryResponse {
  { raw: self.call_raw("getConversationSummary", params=params.to_json()) }
}

///|
/// Call `gitDiffToRemote`.
pub async fn CodexAppConnection::git_diff_to_remote(
  self : CodexAppConnection,
  params : AppCwdParams,
) -> AppGitDiffToRemoteResponse {
  { raw: self.call_raw("gitDiffToRemote", params=params.to_json()) }
}

///|
/// Call `getAuthStatus`.
pub async fn CodexAppConnection::get_auth_status(
  self : CodexAppConnection,
  params : AppGetAuthStatusParams,
) -> AppGetAuthStatusResponse {
  { raw: self.call_raw("getAuthStatus", params=params.to_json()) }
}

///|
/// Call `fuzzyFileSearch`.
pub async fn CodexAppConnection::fuzzy_file_search(
  self : CodexAppConnection,
  params : AppFuzzyFileSearchParams,
) -> AppFuzzyFileSearchResponse {
  { raw: self.call_raw("fuzzyFileSearch", params=params.to_json()) }
}

///|
/// Raw JSON-RPC message received from a Codex app server.
pub enum AppServerMessage {
  Notification(AppServerEvent)
  Request(AppServerRequest)
  Response(id~ : AppRequestId, result~ : Json)
  ErrorResponse(id~ : AppRequestId, error~ : AppRpcError)
} derive(Debug)

///|
/// JSON-RPC frame sent from this SDK to the Codex app server.
pub(all) enum AppClientMessage {
  ClientRequest(id~ : AppRequestId, rpc_method~ : String, params~ : Json?)
  ClientNotification(rpc_method~ : String, params~ : Json?)
  ClientResponse(id~ : AppRequestId, result~ : Json)
  ClientErrorResponse(id~ : AppRequestId, error~ : AppRpcError)
} derive(Debug)

///|
pub impl ToJson for AppClientMessage with to_json(message) {
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
pub impl FromJson for AppServerMessage with from_json(value, path) {
  guard value is Object(obj) else {
    raise JsonDecodeError((path, "expected JSON-RPC object"))
  }
  match obj {
    { "method": String(rpc_method), "id": id_json, "params"? : params, .. } =>
      Request(
        app_server_request(
          @json.from_json(id_json, path=path.add_key("id")),
          rpc_method,
          params,
          path.add_key("params"),
        ),
      )
    { "method": String(_), .. } => Notification(@json.from_json(value, path~))
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
) -> AppServerRequest raise @json.JsonDecodeError {
  let details = match rpc_method {
    "item/commandExecution/requestApproval" =>
      match params {
        Some(params) =>
          AppCommandExecutionApprovalRequest(@json.from_json(params, path~))
        None => AppRawRequest
      }
    "item/fileChange/requestApproval" =>
      match params {
        Some(params) =>
          AppFileChangeApprovalRequest(@json.from_json(params, path~))
        None => AppRawRequest
      }
    "item/tool/requestUserInput" =>
      match params {
        Some(params) =>
          AppToolRequestUserInputRequest(@json.from_json(params, path~))
        None => AppRawRequest
      }
    _ => AppRawRequest
  }
  { id, rpc_method, params, details }
}

///|
/// App-server event. This is intentionally broader than the existing exec `Event`.
pub enum AppServerEvent {
  AppThreadStarted(AppThread)
  AppThreadStatusChanged(thread_id~ : String, status~ : AppThreadStatus)
  AppTurnStarted(thread_id~ : String, turn~ : AppTurn)
  AppTurnCompleted(thread_id~ : String, turn~ : AppTurn)
  AppTurnError(
    thread_id~ : String,
    turn_id~ : String,
    error~ : AppTurnError,
    will_retry~ : Bool
  )
  AppItemStarted(AppThreadItemEvent)
  AppItemCompleted(AppThreadItemEvent)
  AppAgentMessageDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppCommandExecutionOutputDelta(
    thread_id~ : String,
    turn_id~ : String,
    item_id~ : String,
    delta~ : String
  )
  AppThreadTokenUsageUpdated(
    thread_id~ : String,
    turn_id~ : String,
    token_usage~ : AppThreadTokenUsage
  )
  AppRaw(rpc_method~ : String, params~ : Json?)
} derive(Debug)

///|
pub impl FromJson for AppServerEvent with from_json(value, path) {
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
    "turn/started" => {
      guard params is Some({ "threadId": String(thread_id), "turn": turn, .. }) else {
        raise JsonDecodeError((path, "expected turn/started params"))
      }
      AppTurnStarted(
        thread_id~,
        turn=@json.from_json(turn, path=path.add_key("params").add_key("turn")),
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
    "item/completed" => AppItemCompleted(@json.from_json(value, path~))
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
    _ => AppRaw(rpc_method~, params~)
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
  session_id : String
  status : AppThreadStatus
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppThread with from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "sessionId": String(session_id),
      "status": status,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server Thread"))
  }
  {
    id,
    session_id,
    status: @json.from_json(status, path=path.add_key("status")),
    raw: value,
  }
}

///|
pub struct AppThreadActiveFlag {
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppThreadActiveFlag with from_json(value, _path) {
  { raw: value }
}

///|
pub enum AppThreadStatus {
  ThreadNotLoaded
  ThreadIdle
  ThreadSystemError
  ThreadActive(active_flags~ : Array[AppThreadActiveFlag])
} derive(Debug)

///|
pub impl FromJson for AppThreadStatus with from_json(value, path) {
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
  status : AppTurnStatus
  error : AppTurnError?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppTurn with from_json(value, path) {
  guard value is { "id": String(id), "status": status, "error"? : error, .. } else {
    raise JsonDecodeError((path, "expected app-server Turn"))
  }
  let error = match error {
    Some(Null) | None => None
    Some(error) => Some(@json.from_json(error, path=path.add_key("error")))
  }
  {
    id,
    status: @json.from_json(status, path=path.add_key("status")),
    error,
    raw: value,
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
pub impl FromJson for AppTurnStatus with from_json(value, path) {
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
  additional_details : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppTurnError with from_json(value, path) {
  guard value
    is {
      "message": String(message),
      "additionalDetails"? : additional_details,
      ..
    } else {
    raise JsonDecodeError((path, "expected app-server TurnError"))
  }
  let additional_details = match additional_details {
    Some(String(details)) => Some(details)
    Some(Null) | None => None
    _ =>
      raise JsonDecodeError(
        (path.add_key("additionalDetails"), "expected string or null"),
      )
  }
  { message, additional_details, raw: value }
}

///|
pub struct AppThreadItemEvent {
  thread_id : String
  turn_id : String
  item : ThreadItem?
  raw_item : Json
  timestamp_ms : Int
} derive(Debug)

///|
pub impl FromJson for AppThreadItemEvent with from_json(value, path) {
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
        item: app_thread_item(raw_item, path.add_key("params").add_key("item")),
        raw_item,
        timestamp_ms: timestamp_ms.to_int(),
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
        item: app_thread_item(raw_item, path.add_key("params").add_key("item")),
        raw_item,
        timestamp_ms: timestamp_ms.to_int(),
      }
    _ =>
      raise JsonDecodeError(
        (path, "expected app-server item lifecycle notification"),
      )
  }
}

///|
pub struct AppThreadTokenUsage {
  total : Usage
  last : Usage
  model_context_window : Int?
} derive(Debug)

///|
pub impl FromJson for AppThreadTokenUsage with from_json(value, path) {
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
    model_context_window: app_optional_int(
      model_context_window,
      path.add_key("modelContextWindow"),
    ),
  }
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
) -> Usage raise @json.JsonDecodeError {
  guard value
    is {
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
    input_tokens: input_tokens.to_int(),
    cached_input_tokens: cached_input_tokens.to_int(),
    output_tokens: output_tokens.to_int(),
    reasoning_output_tokens: reasoning_output_tokens.to_int(),
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
