///|
test "serialize app-server client request" {
  let message = AppClientMessage::ClientRequest(
    id=AppRequestId::IntId(7),
    rpc_method="thread/list",
    params=Some({ "limit": 20 }),
  )
  debug_inspect(
    message.to_json(),
    content=(
      #|Object(
      #|  {
      #|    "id": Number(7),
      #|    "method": String("thread/list"),
      #|    "params": Object({ "limit": Number(20) }),
      #|  },
      #|)
    ),
  )
}

///|
test "serialize app-server initialize capabilities" {
  let params = AppInitializeParams::{
    client_info: AppClientInfo::{
      name: "moonbit-codex-sdk",
      title: None,
      version: "0.150.1",
    },
    capabilities: Some(
      AppInitializeCapabilities::new(
        experimental_api=true,
        request_attestation=true,
        mcp_server_openai_form_elicitation=true,
        opt_out_notification_methods=["thread/name/updated"],
        extensions={ "openai/form": {} },
      ),
    ),
  }
  guard params.to_json()
    is {
      "clientInfo": { "version": String("0.150.1"), .. },
      "capabilities": {
        "experimentalApi": True,
        "requestAttestation": True,
        "mcpServerOpenaiFormElicitation": True,
        "optOutNotificationMethods": Array([String("thread/name/updated")]),
        "extensions": Object({ "openai/form": Object({ }) }),
        ..
      },
      ..
    } else {
    fail("expected request attestation capability")
  }
}

///|
test "serialize v0.150 app-server user inputs" {
  let inputs = [
    AppUserInput::AppInputImageWithDetail(
      url="https://example.test/image.png",
      detail=AppImageOriginal,
    ),
    AppUserInput::AppInputAudio(url="https://example.test/audio.wav"),
    AppUserInput::AppInputLocalAudio(path="/tmp/audio.wav"),
  ]
  debug_inspect(
    inputs.to_json(),
    content=(
      #|Array(
      #|  [
      #|    Object(
      #|      {
      #|        "type": String("image"),
      #|        "url": String("https://example.test/image.png"),
      #|        "detail": String("original"),
      #|      },
      #|    ),
      #|    Object(
      #|      {
      #|        "type": String("audio"),
      #|        "url": String("https://example.test/audio.wav"),
      #|      },
      #|    ),
      #|    Object({ "type": String("localAudio"), "path": String("/tmp/audio.wav") }),
      #|  ],
      #|)
    ),
  )
}

///|
test "serialize model list params" {
  let params = AppModelListParams::new(
    cursor="next-page",
    limit=25,
    include_hidden=true,
  )
  debug_inspect(
    params.to_json(),
    content=(
      #|Object(
      #|  {
      #|    "cursor": String("next-page"),
      #|    "limit": Number(25),
      #|    "includeHidden": True,
      #|  },
      #|)
    ),
  )
}

///|
test "serialize app-server typed params" {
  let thread_list = AppThreadListParams::new(
    limit=10,
    sort_key=ThreadUpdatedAt,
    sort_direction=SortDesc,
    source_kinds=[SourceCli, SourceAppServer],
    cwd=OneCwd("/repo"),
    search_term="sdk",
  )
  debug_inspect(
    thread_list.to_json(),
    content=(
      #|Object(
      #|  {
      #|    "limit": Number(10),
      #|    "sortKey": String("updated_at"),
      #|    "sortDirection": String("desc"),
      #|    "sourceKinds": Array([String("cli"), String("appServer")]),
      #|    "cwd": String("/repo"),
      #|    "searchTerm": String("sdk"),
      #|  },
      #|)
    ),
  )
  let turn_start = AppTurnStartParams::new(
    "thread-1",
    [AppInputText(text="hello")],
    approval_policy=AppApprovalOnRequest,
    sandbox_policy=AppReadOnly(network_access=false),
    effort=AppEffortHigh,
    summary=AppSummaryConcise,
  )
  debug_inspect(
    turn_start.to_json(),
    content=(
      #|Object(
      #|  {
      #|    "threadId": String("thread-1"),
      #|    "input": Array(
      #|      [
      #|        Object(
      #|          {
      #|            "type": String("text"),
      #|            "text": String("hello"),
      #|            "text_elements": Array([]),
      #|          },
      #|        ),
      #|      ],
      #|    ),
      #|    "approvalPolicy": String("on-request"),
      #|    "sandboxPolicy": Object({ "type": String("readOnly"), "networkAccess": False }),
      #|    "effort": String("high"),
      #|    "summary": String("concise"),
      #|  },
      #|)
    ),
  )
  let mcp_oauth = AppMcpServerOauthLoginParams::{
    name: "github",
    scopes: None,
    timeout_secs: Some(3_000_000_000),
  }
  guard mcp_oauth.to_json() is { "timeoutSecs": Number(timeout_secs, ..), .. } else {
    fail("expected mcp oauth timeout seconds")
  }
  debug_inspect(timeout_secs.to_int64(), content="3000000000")
}

///|
test "serialize app-server nullable request fields" {
  let thread_start = AppThreadStartParams::new(
    service_tier=AppNullableStringNull,
  )
  guard thread_start.to_json() is { "serviceTier": Null, .. } else {
    fail("expected thread/start serviceTier null")
  }
  let thread_resume = AppThreadResumeParams::new(
    "thread-1",
    service_tier=AppNullableStringValue("flex"),
  )
  guard thread_resume.to_json() is { "serviceTier": String("flex"), .. } else {
    fail("expected thread/resume serviceTier string")
  }
  let thread_fork = AppThreadForkParams::{
    thread_id: "thread-1",
    last_turn_id: None,
    model: None,
    model_provider: None,
    service_tier: Some(AppNullableStringNull),
    cwd: None,
    approval_policy: None,
    approvals_reviewer: None,
    sandbox: None,
    config: None,
    base_instructions: None,
    developer_instructions: None,
    ephemeral: None,
    thread_source: None,
  }
  guard thread_fork.to_json() is { "serviceTier": Null, .. } else {
    fail("expected thread/fork serviceTier null")
  }
  let turn_start = AppTurnStartParams::new(
    "thread-1",
    [AppInputText(text="hello")],
    service_tier=AppNullableStringNull,
  )
  guard turn_start.to_json() is { "serviceTier": Null, .. } else {
    fail("expected turn/start serviceTier null")
  }
  let metadata = AppThreadMetadataGitInfoUpdateParams::{
    sha: Some(AppNullableStringNull),
    branch: Some(AppNullableStringValue("main")),
    origin_url: None,
  }
  guard metadata.to_json() is { "sha": Null, "branch": String("main"), .. } else {
    fail("expected git metadata nullable fields")
  }
}

///|
test "serialize app-server command env null overrides" {
  let env : Map[String, String?] = { "KEEP": Some("1"), "DROP": None }
  let params = AppCommandExecParams::{
    command: ["env"],
    process_id: None,
    tty: None,
    stream_stdin: None,
    stream_stdout_stderr: None,
    output_bytes_cap: Some(5_000_000_000),
    disable_output_cap: None,
    disable_timeout: None,
    timeout_ms: Some(3_000_000_000),
    cwd: None,
    env: Some(env),
    size: Some({ rows: 24, cols: 80, }),
    sandbox_policy: None,
  }
  guard params.to_json()
    is { "env": { "KEEP": String("1"), "DROP": Null, .. }, .. } else {
    fail("expected command env to preserve null values")
  }
  guard params.to_json()
    is {
      "outputBytesCap": Number(output_bytes_cap, ..),
      "timeoutMs": Number(timeout_ms, ..),
      ..
    } else {
    fail("expected 64-bit command limits")
  }
  debug_inspect(output_bytes_cap.to_int64(), content="5000000000")
  debug_inspect(timeout_ms.to_int64(), content="3000000000")
  guard params.to_json()
    is {
      "size": { "rows": Number(rows, ..), "cols": Number(cols, ..), .. },
      ..
    } else {
    fail("expected unsigned terminal size")
  }
  debug_inspect(rows.to_uint(), content="24")
  debug_inspect(cols.to_uint(), content="80")
  let defaults = AppCommandExecParams::{
    command: ["true"],
    process_id: Some("proc-1"),
    tty: Some(false),
    stream_stdin: Some(false),
    stream_stdout_stderr: Some(false),
    output_bytes_cap: None,
    disable_output_cap: Some(false),
    disable_timeout: Some(false),
    timeout_ms: None,
    cwd: None,
    env: None,
    size: None,
    sandbox_policy: None,
  }
  guard defaults.to_json()
    is {
      "tty"? : None,
      "streamStdin"? : None,
      "streamStdoutStderr"? : None,
      "disableOutputCap"? : None,
      "disableTimeout"? : None,
      ..
    } else {
    fail("expected command/exec false flags to be omitted")
  }
  let stdin = AppCommandExecWriteParams::{
    process_id: "proc-1",
    delta_base64: None,
    close_stdin: Some(false),
  }
  guard stdin.to_json() is { "closeStdin"? : None, "deltaBase64"? : None, .. } else {
    fail("expected command/exec/write false closeStdin to be omitted")
  }
}

///|
test "serialize app-server thread audit request params" {
  let goal = AppThreadGoalSetParams::{
    thread_id: "thr_123",
    objective: None,
    status: Some(AppThreadGoalBudgetLimited),
    token_budget: Some(AppNullableInt64Null),
  }
  guard goal.to_json()
    is {
      "threadId": String("thr_123"),
      "objective": Null,
      "status": String("budgetLimited"),
      "tokenBudget": Null,
      ..
    } else {
    fail("expected thread/goal/set nulls and protocol status spelling")
  }
  let turns = AppThreadTurnsListParams::{
    thread_id: "thr_123",
    cursor: None,
    limit: Some(25),
    sort_direction: Some(SortDesc),
  }
  guard turns.to_json()
    is {
      "threadId": String("thr_123"),
      "cursor": Null,
      "limit": Number(limit, ..),
      "sortDirection": String("desc"),
      "itemsView"? : None,
      ..
    } else {
    fail("expected thread/turns/list params")
  }
  debug_inspect(limit.to_uint(), content="25")
}

///|
test "serialize app-server realtime and experimental request params" {
  let realtime = AppThreadRealtimeStartParams::{
    thread_id: "thr_123",
    output_modality: AppRealtimeAudio,
    prompt: Some(AppNullableStringNull),
    realtime_session_id: None,
    transport: Some(AppThreadRealtimeWebrtc(sdp="v=0")),
    voice: Some(AppRealtimeVoiceMarin),
  }
  guard realtime.to_json()
    is {
      "threadId": String("thr_123"),
      "outputModality": String("audio"),
      "prompt": Null,
      "realtimeSessionId": Null,
      "transport": { "type": String("webrtc"), "sdp": String("v=0"), .. },
      "voice": String("marin"),
      ..
    } else {
    fail("expected thread/realtime/start params")
  }
  let realtime_default_prompt = AppThreadRealtimeStartParams::{
    thread_id: "thr_123",
    output_modality: AppRealtimeAudio,
    prompt: None,
    realtime_session_id: None,
    transport: None,
    voice: None,
  }
  guard realtime_default_prompt.to_json()
    is {
      "prompt"? : None,
      "realtimeSessionId": Null,
      "transport": Null,
      "voice": Null,
      ..
    } else {
    fail("expected omitted realtime prompt and explicit nullable fields")
  }
  let append_audio = AppThreadRealtimeAppendAudioParams::{
    thread_id: "thr_123",
    audio: AppThreadRealtimeAudioChunk::{
      data: "AQID",
      sample_rate: 24000,
      num_channels: 1,
      samples_per_channel: None,
      item_id: None,
    },
  }
  guard append_audio.to_json()
    is {
      "audio": {
        "data": String("AQID"),
        "sampleRate": Number(sample_rate, ..),
        "numChannels": Number(num_channels, ..),
        "samplesPerChannel": Null,
        "itemId": Null,
        ..
      },
      ..
    } else {
    fail("expected realtime audio chunk null fields")
  }
  debug_inspect(sample_rate.to_uint(), content="24000")
  debug_inspect(num_channels.to_uint(), content="1")
  guard AppMockExperimentalMethodParams::{ value: None, }.to_json()
    is { "value": Null, .. } else {
    fail("expected mock/experimentalMethod null value")
  }
  guard AppFuzzyFileSearchSessionStartParams::{
      session_id: "search-1",
      roots: ["/repo"],
    }.to_json()
    is {
      "sessionId": String("search-1"),
      "roots": Array([String("/repo")]),
      ..
    } else {
    fail("expected fuzzy search session start params")
  }
}

///|
test "serialize app-server typed request responses" {
  debug_inspect(
    AppServerResponse::AppCommandExecutionApprovalResponse(
      decision=AppCommandDecline,
    ).to_json(),
    content=(
      #|Object({ "decision": String("decline") })
    ),
  )
  debug_inspect(
    AppServerResponse::AppToolRequestUserInputResponse(answers={
      "choice": AppToolRequestUserInputAnswer::{ answers: ["first"], },
    }).to_json(),
    content=(
      #|Object({ "answers": Object({ "choice": Object({ "answers": Array([String("first")]) }) }) })
    ),
  )
  debug_inspect(
    AppServerResponse::AppDynamicToolCallResponse(
      content_items=[
        AppDynamicToolCallOutputText(text="done"),
        AppDynamicToolCallOutputImage(
          image_url="https://example.test/image.png",
        ),
      ],
      success=true,
    ).to_json(),
    content=(
      #|Object(
      #|  {
      #|    "contentItems": Array(
      #|      [
      #|        Object({ "type": String("inputText"), "text": String("done") }),
      #|        Object(
      #|          {
      #|            "type": String("inputImage"),
      #|            "imageUrl": String("https://example.test/image.png"),
      #|          },
      #|        ),
      #|      ],
      #|    ),
      #|    "success": True,
      #|  },
      #|)
    ),
  )
  debug_inspect(
    AppServerResponse::AppCommandExecutionApprovalResponse(
      decision=AppCommandAcceptWithExecpolicyAmendment(["git", "status"]),
    ).to_json(),
    content=(
      #|Object({ "decision": Object({ "acceptWithExecpolicyAmendment": Object({ "execpolicy_amendment": Array([String("git"), String("status")]) }) }) })
    ),
  )
  debug_inspect(
    AppServerResponse::AppCommandExecutionApprovalResponse(
      decision=AppCommandApplyNetworkPolicyAmendment(AppNetworkPolicyAmendment::{
        host: "example.test",
        action: AppNetworkPolicyAllow,
      }),
    ).to_json(),
    content=(
      #|Object({ "decision": Object({ "applyNetworkPolicyAmendment": Object({ "network_policy_amendment": Object({ "host": String("example.test"), "action": String("allow") }) }) }) })
    ),
  )
  let permissions_response = AppServerResponse::AppPermissionsRequestApprovalResponse(
    permissions=AppGrantedPermissionProfile::{
      network: Some(AppAdditionalNetworkPermissions::{ enabled: Some(true), }),
      file_system: Some(AppAdditionalFileSystemPermissions::{
        read: None,
        write: None,
        glob_scan_max_depth: Some(5000000000UL),
        entries: Some([
          AppFileSystemSandboxEntry::{
            path: AppFileSystemSpecialPath(
              value=AppFileSystemProjectRoots(subpath=Some("src")),
            ),
            access: AppFileSystemWriteAccess,
          },
        ]),
      }),
    },
    scope=AppPermissionGrantSession,
    strict_auto_review=Some(true),
  ).to_json()
  guard permissions_response
    is {
      "permissions": {
        "fileSystem": { "globScanMaxDepth": Number(depth, ..), .. },
        ..
      },
      "scope": String("session"),
      "strictAutoReview": True,
      ..
    } else {
    fail("expected typed permissions approval response")
  }
  debug_inspect(depth.to_int64(), content="5000000000")
  guard AppServerResponse::AppChatgptAuthTokensRefreshResponse(
      access_token="token-1",
      chatgpt_account_id="acct-1",
      chatgpt_plan_type=None,
    ).to_json()
    is {
      "accessToken": String("token-1"),
      "chatgptAccountId": String("acct-1"),
      "chatgptPlanType": Null,
      ..
    } else {
    fail("expected typed ChatGPT auth token refresh response")
  }
  guard AppServerResponse::AppAttestationGenerateResponse(token="jwt-1").to_json()
    is { "token": String("jwt-1"), .. } else {
    fail("expected typed attestation generation response")
  }
  guard AppServerResponse::AppMcpServerElicitationResponse(
      action=AppMcpElicitationDecline,
      content=None,
      meta=None,
    ).to_json()
    is { "action": String("decline"), "content": Null, "_meta": Null, .. } else {
    fail("expected typed MCP elicitation response")
  }
}

///|
test "parse app-server audit request responses" {
  let elicitation : AppThreadElicitationCounterResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "count": 5000000000,
        #|  "paused": true
        #|}
      ),
    ),
  )
  debug_inspect(elicitation.count.reinterpret_as_int64(), content="5000000000")
  debug_inspect(elicitation.paused, content="true")
  let goal_get : AppThreadGoalGetResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "goal": {
        #|    "threadId": "thr_123",
        #|    "objective": "ship it",
        #|    "status": "budgetLimited",
        #|    "tokenBudget": 10000,
        #|    "tokensUsed": 123,
        #|    "timeUsedSeconds": 45,
        #|    "createdAt": 1700000000,
        #|    "updatedAt": 1700000123
        #|  }
        #|}
      ),
    ),
  )
  match goal_get.goal {
    Some(goal) => {
      debug_inspect(goal.status, content="AppThreadGoalBudgetLimited")
      debug_inspect(goal.token_budget, content="Some(10000)")
    }
    None => fail("expected goal")
  }
  let voices : AppThreadRealtimeListVoicesResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "voices": {
        #|    "v1": ["alloy"],
        #|    "v2": ["marin", "cedar"],
        #|    "defaultV1": "alloy",
        #|    "defaultV2": "marin"
        #|  }
        #|}
      ),
    ),
  )
  debug_inspect(voices.voices.v2.length(), content="2")
  debug_inspect(voices.voices.default_v2, content="AppRealtimeVoiceMarin")
  let collaboration_modes : AppCollaborationModeListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "data": [
        #|    {
        #|      "name": "plan",
        #|      "mode": "plan",
        #|      "model": "gpt-5",
        #|      "reasoning_effort": "high"
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(collaboration_modes.data.length(), content="1")
  debug_inspect(
    collaboration_modes.data[0].mode,
    content="Some(AppCollaborationPlan)",
  )
  debug_inspect(
    collaboration_modes.data[0].reasoning_effort,
    content="Some(AppEffortHigh)",
  )
}

///|
test "parse typed config read payload" {
  let response : AppConfigReadResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "config": {
        #|    "model": "gpt-5",
        #|    "model_context_window": 200000000000,
        #|    "approval_policy": "on-request",
        #|    "approvals_reviewer": "auto_review",
        #|    "sandbox_mode": "workspace-write",
        #|    "sandbox_workspace_write": {
        #|      "writable_roots": ["/workspace"],
        #|      "network_access": true,
        #|      "exclude_tmpdir_env_var": false,
        #|      "exclude_slash_tmp": true
        #|    },
        #|    "forced_login_method": "chatgpt",
        #|    "web_search": "live",
        #|    "tools": {
        #|      "web_search": {
        #|        "context_size": "high",
        #|        "allowed_domains": ["example.test"],
        #|        "location": { "country": "US", "region": null, "city": null, "timezone": "America/Los_Angeles" }
        #|      },
        #|      "view_image": true
        #|    },
        #|    "profiles": {
        #|      "work": {
        #|        "model": "gpt-5-mini",
        #|        "model_reasoning_effort": "low",
        #|        "model_reasoning_summary": "concise",
        #|        "model_verbosity": "medium",
        #|        "chatgpt_base_url": "https://chatgpt.example.test",
        #|        "custom_profile_key": true
        #|      }
        #|    },
        #|    "analytics": { "enabled": false, "unknown": "kept" },
        #|    "apps": {
        #|      "_default": {
        #|        "enabled": true,
        #|        "destructive_enabled": false,
        #|        "open_world_enabled": false
        #|      },
        #|      "calendar": {
        #|        "enabled": true,
        #|        "destructive_enabled": null,
        #|        "open_world_enabled": false,
        #|        "default_tools_approval_mode": "prompt",
        #|        "default_tools_enabled": true,
        #|        "tools": {
        #|          "create": {
        #|            "enabled": true,
        #|            "approval_mode": "approve"
        #|          }
        #|        }
        #|      }
        #|    },
        #|    "extra_config_key": "kept"
        #|  },
        #|  "origins": {
        #|    "model": {
        #|      "name": { "type": "user", "file": "/home/user/.codex/config.toml" },
        #|      "version": "1"
        #|    }
        #|  },
        #|  "layers": [
        #|    {
        #|      "name": { "type": "project", "dotCodexFolder": "/workspace/.codex" },
        #|      "version": "2",
        #|      "config": { "model": "gpt-5" },
        #|      "disabledReason": null
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(response.config.model, content="Some(\"gpt-5\")")
  guard response.config.model_context_window is Some(window) else {
    fail("expected model context window")
  }
  debug_inspect(window.to_string(), content="\"200000000000\"")
  debug_inspect(
    response.config.approval_policy,
    content="Some(AppApprovalOnRequest)",
  )
  guard response.config.sandbox_workspace_write is Some(workspace_write) else {
    fail("expected sandbox workspace-write config")
  }
  debug_inspect(workspace_write.writable_roots[0], content="\"/workspace\"")
  guard response.config.tools is Some(tools) else {
    fail("expected tools config")
  }
  guard tools.web_search is Some(web_search) else {
    fail("expected web search tool config")
  }
  debug_inspect(
    web_search.context_size,
    content="Some(AppWebSearchContextHigh)",
  )
  match response.config.profiles.get("work") {
    Some(profile) => {
      debug_inspect(
        profile.model_reasoning_effort,
        content="Some(AppEffortLow)",
      )
      match profile.additional.get("custom_profile_key") {
        Some(True) => ()
        _ => fail("expected custom profile key")
      }
    }
    None => fail("expected work profile")
  }
  guard response.config.apps is Some(apps) else { fail("expected apps config") }
  match apps.apps.get("calendar") {
    Some(app) =>
      debug_inspect(
        app.default_tools_approval_mode,
        content="Some(AppToolApprovalPrompt)",
      )
    None => fail("expected calendar app config")
  }
  match response.config.additional.get("extra_config_key") {
    Some(String("kept")) => ()
    _ => fail("expected extra config key")
  }
  match response.origins.get("model") {
    Some(origin) =>
      debug_inspect(
        origin.name,
        content=(
          #|AppConfigLayerUser(file="/home/user/.codex/config.toml")
        ),
      )
    None => fail("expected model origin")
  }
  match response.layers {
    Some(layers) =>
      debug_inspect(
        layers[0].name,
        content=(
          #|AppConfigLayerProject(dot_codex_folder="/workspace/.codex")
        ),
      )
    None => fail("expected config layers")
  }
}

///|
test "parse app-server item started notification" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/started",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "startedAtMs": 1710000000123,
        #|    "item": {
        #|      "type": "commandExecution",
        #|      "id": "cmd-1",
        #|      "command": "pwd",
        #|      "cwd": "/tmp",
        #|      "processId": null,
        #|      "source": "agent",
        #|      "status": "inProgress",
        #|      "commandActions": [],
        #|      "aggregatedOutput": null,
        #|      "exitCode": null,
        #|      "durationMs": null
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Notification(AppItemStarted(event)) => {
      debug_inspect(
        event.thread_id,
        content=(
          #|"thread-1"
        ),
      )
      debug_inspect(event.timestamp_ms, content="1710000000123")
      match event.item {
        Some(CommandExecutionItem(command~, aggregated_output~, status~, ..)) => {
          debug_inspect(
            command,
            content=(
              #|"pwd"
            ),
          )
          debug_inspect(
            aggregated_output,
            content=(
              #|""
            ),
          )
          guard status is InProgress else { fail("expected in-progress item") }
        }
        _ => fail("expected command execution item")
      }
      match message {
        Notification(event) => {
          guard event.thread_event()
            is Some(ItemStarted(CommandExecutionItem(..))) else {
            fail("expected bridge to exec item started")
          }
        }
        _ => fail("expected notification")
      }
    }
    _ => fail("expected app-server item started notification")
  }
}

///|
test "parse app-server auto-review and raw response item notifications" {
  let started : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/autoApprovalReview/started",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "startedAtMs": 1710000000123,
        #|    "reviewId": "review-1",
        #|    "targetItemId": "cmd-1",
        #|    "review": {
        #|      "status": "inProgress",
        #|      "riskLevel": null,
        #|      "userAuthorization": null,
        #|      "rationale": null
        #|    },
        #|    "action": {
        #|      "type": "command",
        #|      "source": "unifiedExec",
        #|      "command": "git status",
        #|      "cwd": "/repo"
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match started {
    AppItemGuardianApprovalReviewStarted(
      started_at_ms~,
      target_item_id~,
      review~,
      action~,
      ..
    ) => {
      debug_inspect(started_at_ms, content="1710000000123")
      debug_inspect(target_item_id, content="Some(\"cmd-1\")")
      debug_inspect(review.status, content="AppGuardianReviewInProgress")
      match action {
        AppGuardianCommandAction(source~, command~, cwd~) => {
          debug_inspect(source, content="AppGuardianCommandSourceUnifiedExec")
          debug_inspect(command, content="\"git status\"")
          debug_inspect(cwd, content="\"/repo\"")
        }
        _ => fail("expected guardian command action")
      }
    }
    _ => fail("expected auto-review started notification")
  }
  let completed : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/autoApprovalReview/completed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "startedAtMs": 1710000000123,
        #|    "completedAtMs": 1710000000999,
        #|    "reviewId": "review-1",
        #|    "targetItemId": null,
        #|    "decisionSource": "agent",
        #|    "review": {
        #|      "status": "approved",
        #|      "riskLevel": "high",
        #|      "userAuthorization": "medium",
        #|      "rationale": "temporary access"
        #|    },
        #|    "action": {
        #|      "type": "requestPermissions",
        #|      "reason": "need repo",
        #|      "permissions": {
        #|        "network": { "enabled": false },
        #|        "fileSystem": null
        #|      }
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match completed {
    AppItemGuardianApprovalReviewCompleted(
      completed_at_ms~,
      target_item_id~,
      decision_source~,
      review~,
      action~,
      ..
    ) => {
      debug_inspect(completed_at_ms, content="1710000000999")
      debug_inspect(target_item_id, content="None")
      debug_inspect(decision_source, content="AppAutoReviewDecisionAgent")
      debug_inspect(review.risk_level, content="Some(AppGuardianRiskHigh)")
      debug_inspect(
        review.user_authorization,
        content="Some(AppGuardianUserAuthorizationMedium)",
      )
      match action {
        AppGuardianRequestPermissionsAction(reason~, permissions~) => {
          debug_inspect(reason, content="Some(\"need repo\")")
          guard permissions.network is Some(network) else {
            fail("expected requested network permissions")
          }
          debug_inspect(network.enabled, content="Some(false)")
        }
        _ => fail("expected guardian request-permissions action")
      }
    }
    _ => fail("expected auto-review completed notification")
  }
  let raw_item : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "rawResponseItem/completed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "item": {
        #|      "type": "message",
        #|      "role": "assistant",
        #|      "content": [
        #|        { "type": "output_text", "text": "done" }
        #|      ],
        #|      "phase": "final_answer"
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match raw_item {
    AppRawResponseItemCompleted(item~, ..) =>
      match item {
        AppResponseMessage(role~, content~, phase~) => {
          debug_inspect(role, content="\"assistant\"")
          debug_inspect(phase, content="Some(AppResponseFinalAnswer)")
          match content[0] {
            AppResponseOutputText(text~) =>
              debug_inspect(text, content="\"done\"")
            _ => fail("expected response output text content")
          }
        }
        _ => fail("expected typed response message item")
      }
    _ => fail("expected raw response item notification")
  }
}

///|
test "parse app-server thread status notification" {
  let event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/status/changed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "status": {
        #|      "type": "active",
        #|      "activeFlags": ["waitingOnApproval", "waitingOnUserInput"]
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match event {
    AppThreadStatusChanged(thread_id~, status~) => {
      debug_inspect(
        thread_id,
        content=(
          #|"thread-1"
        ),
      )
      guard status is ThreadActive(active_flags~) && active_flags.length() == 2 else {
        fail("expected active status")
      }
      debug_inspect(active_flags[0], content="AppThreadWaitingOnApproval")
      debug_inspect(active_flags[1], content="AppThreadWaitingOnUserInput")
    }
    _ => fail("expected thread status notification")
  }
}

///|
test "parse typed app-server skills list response" {
  let response : AppSkillsListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "data": [
        #|    {
        #|      "cwd": "/workspace",
        #|      "skills": [
        #|        {
        #|          "name": "review",
        #|          "description": "Review code",
        #|          "shortDescription": "Review",
        #|          "interface": {
        #|            "displayName": "Review",
        #|            "shortDescription": "Review",
        #|            "iconSmall": "/tmp/icon-small.png",
        #|            "iconLarge": "/tmp/icon-large.png",
        #|            "brandColor": "#123456",
        #|            "defaultPrompt": "Check this"
        #|          },
        #|          "dependencies": {
        #|            "tools": [
        #|              {
        #|                "type": "mcp",
        #|                "value": "github",
        #|                "description": "GitHub MCP",
        #|                "transport": "stdio",
        #|                "command": "github-mcp",
        #|                "url": null
        #|              }
        #|            ]
        #|          },
        #|          "path": "/skills/review/SKILL.md",
        #|          "scope": "repo",
        #|          "enabled": true
        #|        }
        #|      ],
        #|      "errors": [
        #|        { "path": "/bad/SKILL.md", "message": "invalid" }
        #|      ]
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(response.data[0].cwd, content="\"/workspace\"")
  debug_inspect(response.data[0].skills[0].scope, content="AppSkillScopeRepo")
  guard response.data[0].skills[0].dependencies is Some(deps) else {
    fail("expected skill dependencies")
  }
  debug_inspect(deps.tools[0].command, content="Some(\"github-mcp\")")
  debug_inspect(response.data[0].errors[0].message, content="\"invalid\"")
}

///|
test "parse typed app-server hooks list response with 64-bit metadata" {
  let response : AppHooksListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "data": [
        #|    {
        #|      "cwd": "/workspace",
        #|      "hooks": [
        #|        {
        #|          "key": "pre-tool",
        #|          "eventName": "preToolUse",
        #|          "handlerType": "command",
        #|          "matcher": null,
        #|          "command": "echo ok",
        #|          "timeoutSec": 3000000000,
        #|          "statusMessage": null,
        #|          "sourcePath": "/workspace/.codex/hooks.json",
        #|          "source": "project",
        #|          "pluginId": null,
        #|          "displayOrder": 4000000000,
        #|          "enabled": true,
        #|          "isManaged": false,
        #|          "currentHash": "abc",
        #|          "trustStatus": "trusted"
        #|        }
        #|      ],
        #|      "warnings": [],
        #|      "errors": []
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  let hook = response.data[0].hooks[0]
  debug_inspect(hook.timeout_sec, content="3000000000")
  debug_inspect(hook.display_order, content="4000000000")
  debug_inspect(hook.trust_status, content="AppHookTrusted")
}

///|
test "parse app-server turn lifecycle notifications" {
  let started : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "turn/started",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turn": {
        #|      "id": "turn-1",
        #|      "items": [],
        #|      "status": "inProgress",
        #|      "error": null,
        #|      "startedAt": 1710000000,
        #|      "completedAt": null,
        #|      "durationMs": null
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match started {
    AppTurnStarted(thread_id~, turn~) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(
        turn.id,
        content=(
          #|"turn-1"
        ),
      )
      debug_inspect(turn.status, content="AppTurnInProgressStatus")
    }
    _ => fail("expected turn started notification")
  }
  let completed : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "turn/completed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turn": {
        #|      "id": "turn-1",
        #|      "items": [],
        #|      "status": "completed",
        #|      "error": null,
        #|      "startedAt": 1710000000,
        #|      "completedAt": 1710000001,
        #|      "durationMs": 1000
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match completed {
    AppTurnCompleted(thread_id~, turn~) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(
        turn.id,
        content=(
          #|"turn-1"
        ),
      )
      debug_inspect(turn.status, content="AppTurnCompletedStatus")
    }
    _ => fail("expected turn completed notification")
  }
}

///|
test "parse app-server turn error notification with unknown codex error info" {
  let event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "error",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "error": {
        #|      "message": "model request failed",
        #|      "codexErrorInfo": "newProviderCode",
        #|      "additionalDetails": null
        #|    },
        #|    "willRetry": false
        #|  }
        #|}
      ),
    ),
  )
  match event {
    AppTurnError(thread_id~, turn_id~, error~, will_retry~) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn_id, content="\"turn-1\"")
      debug_inspect(error.message, content="\"model request failed\"")
      debug_inspect(error.codex_error_info, content="Some(AppCodexOtherError)")
      guard !will_retry else { fail("expected non-retryable turn error") }
    }
    _ => fail("expected turn error notification")
  }
}

///|
test "parse app-server hook lifecycle notifications" {
  let started : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "hook/started",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "run": {
        #|      "id": "hook-run-1",
        #|      "eventName": "preToolUse",
        #|      "handlerType": "command",
        #|      "executionMode": "sync",
        #|      "scope": "turn",
        #|      "sourcePath": "/repo/.codex/hooks.json",
        #|      "displayOrder": 5000000000,
        #|      "status": "running",
        #|      "statusMessage": null,
        #|      "startedAt": 1710000000,
        #|      "completedAt": null,
        #|      "durationMs": null,
        #|      "entries": []
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match started {
    AppHookStarted(turn_id~, run~, ..) => {
      debug_inspect(turn_id, content="Some(\"turn-1\")")
      debug_inspect(run.source, content="AppHookUnknownSource")
      debug_inspect(run.display_order, content="5000000000")
      debug_inspect(run.status, content="AppHookRunning")
    }
    _ => fail("expected hook started notification")
  }
  let completed : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "hook/completed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": null,
        #|    "run": {
        #|      "id": "hook-run-1",
        #|      "eventName": "postToolUse",
        #|      "handlerType": "agent",
        #|      "executionMode": "async",
        #|      "scope": "thread",
        #|      "sourcePath": "/repo/.codex/hooks.json",
        #|      "source": "project",
        #|      "displayOrder": 5000000000,
        #|      "status": "completed",
        #|      "statusMessage": "done",
        #|      "startedAt": 1710000000,
        #|      "completedAt": 1710000002,
        #|      "durationMs": 2000,
        #|      "entries": [
        #|        { "kind": "feedback", "text": "looks good" }
        #|      ]
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match completed {
    AppHookCompleted(turn_id~, run~, ..) => {
      debug_inspect(turn_id, content="None")
      debug_inspect(run.event_name, content="AppHookPostToolUse")
      debug_inspect(run.handler_type, content="AppHookAgentHandler")
      debug_inspect(run.execution_mode, content="AppHookAsyncExecution")
      debug_inspect(run.scope, content="AppHookThreadScope")
      debug_inspect(run.source, content="AppHookProjectSource")
      debug_inspect(run.completed_at, content="Some(1710000002)")
      debug_inspect(run.entries[0].kind, content="AppHookOutputFeedback")
    }
    _ => fail("expected hook completed notification")
  }
}

///|
test "parse app-server server request with raw params" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": 7,
        #|  "method": "item/commandExecution/requestApproval",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "itemId": "cmd-1",
        #|    "startedAtMs": 123,
        #|    "networkApprovalContext": {
        #|      "host": "example.test",
        #|      "protocol": "https"
        #|    },
        #|    "command": "curl https://example.test",
        #|    "commandActions": [
        #|      {
        #|        "type": "search",
        #|        "command": "rg todo src",
        #|        "query": "todo",
        #|        "path": "src"
        #|      }
        #|    ],
        #|    "proposedExecpolicyAmendment": ["curl", "https://example.test"],
        #|    "proposedNetworkPolicyAmendments": [
        #|      { "host": "example.test", "action": "allow" }
        #|    ]
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) => {
      debug_inspect(request.id, content="IntId(7)")
      match request.details {
        AppCommandExecutionApprovalRequest(command_request) => {
          debug_inspect(
            command_request.item_id,
            content=(
              #|"cmd-1"
            ),
          )
          debug_inspect(command_request.cwd, content="None")
          guard command_request.network_approval_context is Some(context) else {
            fail("expected network approval context")
          }
          debug_inspect(context.protocol, content="AppNetworkApprovalHttps")
          guard command_request.command_actions is Some(actions) else {
            fail("expected command actions")
          }
          debug_inspect(actions.length(), content="1")
          match actions[0] {
            AppCommandSearchAction(query~, ..) =>
              debug_inspect(query, content="Some(\"todo\")")
            _ => fail("expected search action")
          }
          guard command_request.proposed_execpolicy_amendment
            is Some(execpolicy) else {
            fail("expected execpolicy amendment")
          }
          debug_inspect(execpolicy[0], content="\"curl\"")
          guard command_request.proposed_network_policy_amendments
            is Some(network) else {
            fail("expected network policy amendment")
          }
          debug_inspect(network[0].action, content="AppNetworkPolicyAllow")
        }
        _ => fail("expected typed command approval request")
      }
    }
    _ => fail("expected app-server request")
  }
}

///|
test "parse app-server dynamic tool call request" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "tool-call-1",
        #|  "method": "item/tool/call",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "callId": "call-1",
        #|    "namespace": "browser",
        #|    "tool": "open",
        #|    "arguments": { "url": "https://example.test" }
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) => {
      debug_inspect(request.id, content="StringId(\"tool-call-1\")")
      match request.details {
        AppDynamicToolCallRequest(tool_request) => {
          debug_inspect(
            tool_request.tool_namespace,
            content="Some(\"browser\")",
          )
          debug_inspect(tool_request.tool, content="\"open\"")
          guard tool_request.arguments is { "url": String(url), .. } else {
            fail("expected dynamic tool args")
          }
          debug_inspect(url, content="\"https://example.test\"")
        }
        _ => fail("expected typed dynamic tool request")
      }
    }
    _ => fail("expected app-server request")
  }
}

///|
test "parse app-server permissions approval request" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "permissions-1",
        #|  "method": "item/permissions/requestApproval",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "itemId": "permissions-item-1",
        #|    "startedAtMs": 1710000000123,
        #|    "cwd": "/repo",
        #|    "reason": null,
        #|    "permissions": {
        #|      "network": { "enabled": true },
        #|      "fileSystem": {
        #|        "read": ["/repo"],
        #|        "write": null,
        #|        "globScanMaxDepth": 5000000000,
        #|        "entries": [
        #|          {
        #|            "path": {
        #|              "type": "special",
        #|              "value": {
        #|                "kind": "project_roots",
        #|                "subpath": "src"
        #|              }
        #|            },
        #|            "access": "write"
        #|          }
        #|        ]
        #|      }
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) =>
      match request.details {
        AppPermissionsRequestApprovalRequest(approval) => {
          debug_inspect(approval.started_at_ms, content="1710000000123")
          debug_inspect(approval.cwd, content="\"/repo\"")
          debug_inspect(approval.reason, content="None")
          guard approval.permissions.network is Some(network) else {
            fail("expected network permissions")
          }
          debug_inspect(network.enabled, content="Some(true)")
          guard approval.permissions.file_system is Some(file_system) else {
            fail("expected filesystem permissions")
          }
          guard file_system.glob_scan_max_depth is Some(max_depth) else {
            fail("expected glob scan max depth")
          }
          debug_inspect(max_depth.reinterpret_as_int64(), content="5000000000")
          guard file_system.read is Some(read) else {
            fail("expected read permissions")
          }
          debug_inspect(read[0], content="\"/repo\"")
          debug_inspect(file_system.write, content="None")
          guard file_system.entries is Some(entries) else {
            fail("expected filesystem entries")
          }
          debug_inspect(entries[0].access, content="AppFileSystemWriteAccess")
          match entries[0].path {
            AppFileSystemSpecialPath(value~) =>
              match value {
                AppFileSystemProjectRoots(subpath~) =>
                  debug_inspect(subpath, content="Some(\"src\")")
                _ => fail("expected project_roots special path")
              }
            _ => fail("expected special filesystem path")
          }
        }
        _ => fail("expected typed permissions approval request")
      }
    _ => fail("expected app-server request")
  }
}

///|
test "parse app-server ChatGPT auth token refresh request" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "chatgpt-refresh-1",
        #|  "method": "account/chatgptAuthTokens/refresh",
        #|  "params": {
        #|    "reason": "unauthorized",
        #|    "previousAccountId": "acct-1"
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) =>
      match request.details {
        AppChatgptAuthTokensRefreshRequest(refresh) => {
          debug_inspect(
            refresh.reason,
            content="AppChatgptAuthTokensUnauthorized",
          )
          debug_inspect(refresh.previous_account_id, content="Some(\"acct-1\")")
        }
        _ => fail("expected typed ChatGPT auth token refresh request")
      }
    _ => fail("expected app-server request")
  }
}

///|
test "parse app-server attestation generate request" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "attestation-1",
        #|  "method": "attestation/generate",
        #|  "params": {}
        #|}
      ),
    ),
  )
  match message {
    Request(request) =>
      match request.details {
        AppAttestationGenerateRequest(_) =>
          debug_inspect(request.id, content="StringId(\"attestation-1\")")
        _ => fail("expected typed attestation generation request")
      }
    _ => fail("expected app-server request")
  }
}

///|
test "preserve app-server requests without typed variants" {
  let methods = ["applyPatchApproval", "execCommandApproval"]
  for rpc_method in methods {
    let message : AppServerMessage = @json.from_json({
      "id": rpc_method,
      "method": rpc_method,
      "params": {},
    })
    match message {
      Request({ details: AppRawServerRequest(rpc_method=raw_method, ..), .. }) =>
        debug_inspect(raw_method, content="\"\{rpc_method}\"")
      _ => fail("expected raw app-server request")
    }
  }
}

///|
test "preserve newer payloads for known app-server requests" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": 18,
        #|  "method": "item/commandExecution/requestApproval",
        #|  "params": { "futureShape": true }
        #|}
      ),
    ),
  )
  match message {
    Request({ details: AppRawServerRequest(rpc_method~, params~), .. }) => {
      debug_inspect(
        rpc_method,
        content=(
          #|"item/commandExecution/requestApproval"
        ),
      )
      debug_inspect(params, content="Some(Object({ \"futureShape\": True }))")
    }
    _ => fail("expected raw request fallback")
  }
}

///|
test "serialize and parse v0.150 thread sections" {
  let create = AppThreadSectionCreateParams::new(
    "SDK",
    appearance=AppSetThreadSectionAppearance({
      icon: Some("code"),
      color: Some("blue"),
    }),
  )
  debug_inspect(
    create.to_json(),
    content=(
      #|Object(
      #|  {
      #|    "name": String("SDK"),
      #|    "appearance": Object({ "icon": String("code"), "color": String("blue") }),
      #|  },
      #|)
    ),
  )
  let response : AppThreadSectionListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "data": [
        #|    {
        #|      "id": "section-1",
        #|      "name": "SDK",
        #|      "appearance": { "icon": "code", "color": null }
        #|    }
        #|  ],
        #|  "nextCursor": null
        #|}
      ),
    ),
  )
  debug_inspect(response.data[0].id, content="\"section-1\"")
  guard response.data[0].appearance is Some(appearance) else {
    fail("expected section appearance")
  }
  debug_inspect(appearance.icon, content="Some(\"code\")")
}

///|
test "session turn options attach thread id" {
  let options = AppTurnStartOptions::new(model="gpt-5", effort=AppEffortHigh)
  let params = options.params("thread-1", [AppInputText(text="hello")])
  guard params.to_json()
    is {
      "threadId": String("thread-1"),
      "input": Array([{ "text": String("hello"), .. }]),
      "model": String("gpt-5"),
      "effort": String("high"),
      ..
    } else {
    fail("expected turn options to build thread-scoped params")
  }
}

///|
async test "connection drains queued events before eof" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnInProgressStatus,
    error: None,
    started_at: Some(10),
    completed_at: None,
    duration_ms: None,
    raw: {},
  }
  connection.events.put(
    AppQueuedEvent(AppTurnStarted(thread_id="thread-1", turn~)),
  )
  connection.events.put(AppQueuedClosed)
  match connection.next_event() {
    Some(AppTurnStarted(thread_id~, turn~)) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn.id, content="\"turn-1\"")
    }
    _ => fail("expected queued event before eof")
  }
  guard connection.next_event() is None else {
    fail("expected eof after queued event")
  }
  guard connection.next_event() is None else { fail("expected repeated eof") }
}

///|
async test "session routes early turn events to pending stream" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnInProgressStatus,
    error: None,
    started_at: Some(10),
    completed_at: None,
    duration_ms: None,
    raw: {},
  }
  guard session.dispatch_turn_event(AppTurnStarted(thread_id="thread-1", turn~)) else {
    fail("expected session to route pending turn event")
  }
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  match stream.next() {
    Some(AppTurnStarted(thread_id~, turn~)) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn.id, content="\"turn-1\"")
    }
    _ => fail("expected turn started event")
  }
}

///|
async test "session closes turn stream on terminal event" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnCompletedStatus,
    error: None,
    started_at: Some(10),
    completed_at: Some(20),
    duration_ms: Some(10),
    raw: {},
  }
  guard session.dispatch_turn_event(
    AppTurnCompleted(thread_id="thread-1", turn~),
  ) else {
    fail("expected session to route completed turn event")
  }
  match stream.next() {
    Some(AppTurnCompleted(thread_id~, turn~)) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn.status, content="AppTurnCompletedStatus")
    }
    _ => fail("expected turn completed event")
  }
  guard stream.next() is None else {
    fail("expected terminal event to close the stream")
  }
}

///|
async test "session closes turn stream on raw turn completion" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "turn/completed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turn": {
        #|      "id": "turn-1",
        #|      "futureShape": true
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  let event = match message {
    Notification(event) => event
    _ => fail("expected app-server notification")
  }
  guard session.dispatch_turn_event(event) else {
    fail("expected session to route raw turn completion")
  }
  match stream.next() {
    Some(AppRawNotification(rpc_method~, ..)) =>
      debug_inspect(rpc_method, content="\"turn/completed\"")
    _ => fail("expected raw turn completion event")
  }
  guard stream.next() is None else {
    fail("expected raw turn completion to close the stream")
  }
}

///|
async test "session closes turn stream on raw non-retryable error" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "error",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "error": { "futureShape": true },
        #|    "willRetry": false
        #|  }
        #|}
      ),
    ),
  )
  let event = match message {
    Notification(event) => event
    _ => fail("expected app-server notification")
  }
  guard event
    is AppRawNotification(
      rpc_method="error",
      params=Some({ "willRetry": False, .. })
    ) else {
    fail("expected raw non-retryable turn error")
  }
  guard session.dispatch_turn_event(event) else {
    fail("expected session to route raw turn error")
  }
  debug_inspect(session.turn_streams.length(), content="0")
  match stream.next() {
    Some(AppRawNotification(rpc_method~, ..)) =>
      debug_inspect(rpc_method, content="\"error\"")
    _ => fail("expected raw turn error event")
  }
  guard stream.next() is None else {
    fail("expected raw non-retryable error to close the stream")
  }
}

///|
async test "session keeps turn stream open on raw retryable error" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "error",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "error": { "futureShape": true },
        #|    "willRetry": true
        #|  }
        #|}
      ),
    ),
  )
  let event = match message {
    Notification(event) => event
    _ => fail("expected app-server notification")
  }
  guard event
    is AppRawNotification(
      rpc_method="error",
      params=Some({ "willRetry": True, .. })
    ) else {
    fail("expected raw retryable turn error")
  }
  guard session.dispatch_turn_event(event) else {
    fail("expected session to route raw retryable turn error")
  }
  debug_inspect(session.turn_streams.length(), content="1")
  match stream.next() {
    Some(AppRawNotification(rpc_method~, ..)) =>
      debug_inspect(rpc_method, content="\"error\"")
    _ => fail("expected raw retryable turn error event")
  }
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnCompletedStatus,
    error: None,
    started_at: Some(10),
    completed_at: Some(20),
    duration_ms: Some(10),
    raw: {},
  }
  guard session.dispatch_turn_event(
    AppTurnCompleted(thread_id="thread-1", turn~),
  ) else {
    fail("expected stream to remain open for turn completion")
  }
  guard stream.next() is Some(AppTurnCompleted(..)) else {
    fail("expected turn completion after retryable raw error")
  }
  guard stream.next() is None else {
    fail("expected turn completion to close the stream")
  }
}

///|
async test "session preserves pending stream when terminal event arrives before response" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnCompletedStatus,
    error: None,
    started_at: Some(10),
    completed_at: Some(20),
    duration_ms: Some(10),
    raw: {},
  }
  guard session.dispatch_turn_event(
    AppTurnCompleted(thread_id="thread-1", turn~),
  ) else {
    fail("expected session to route early terminal turn event")
  }
  session.bind_turn_stream(stream_id, "turn-1")
  debug_inspect(session.turn_streams.length(), content="1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  match stream.next() {
    Some(AppTurnCompleted(thread_id~, turn~)) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn.status, content="AppTurnCompletedStatus")
    }
    _ => fail("expected queued terminal turn event")
  }
  guard stream.next() is None else {
    fail("expected queued close after terminal turn event")
  }
  debug_inspect(session.turn_streams.length(), content="0")
}

///|
async test "session keeps turn stream open on retryable turn error" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream("thread-1", events, None)
  session.bind_turn_stream(stream_id, "turn-1")
  let stream : AppTurnStream = {
    thread_id: "thread-1",
    turn_id: "turn-1",
    session,
    stream_id,
    events,
    events_closed: false,
  }
  let error : AppTurnError = {
    message: "temporary failure",
    codex_error_info: None,
    additional_details: None,
    raw: {},
  }
  guard session.dispatch_turn_event(
    AppTurnError(
      thread_id="thread-1",
      turn_id="turn-1",
      error~,
      will_retry=true,
    ),
  ) else {
    fail("expected session to route retryable turn error")
  }
  let turn : AppTurn = {
    id: "turn-1",
    items: [],
    status: AppTurnCompletedStatus,
    error: None,
    started_at: Some(10),
    completed_at: Some(20),
    duration_ms: Some(10),
    raw: {},
  }
  guard session.dispatch_turn_event(
    AppTurnCompleted(thread_id="thread-1", turn~),
  ) else {
    fail("expected session to route completed turn event after retry")
  }
  match stream.next() {
    Some(AppTurnError(will_retry~, ..)) => {
      guard will_retry else { fail("expected retryable turn error") }
    }
    _ => fail("expected retryable turn error event")
  }
  match stream.next() {
    Some(AppTurnCompleted(thread_id~, turn~)) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(turn.status, content="AppTurnCompletedStatus")
    }
    _ => fail("expected turn completed event after retry")
  }
  guard stream.next() is None else {
    fail("expected final completion to close the stream")
  }
}

///|
async test "session binds pending stream on early turn request" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let _ = session.register_pending_turn_stream(
    "thread-1",
    events,
    Some(fn(_) {
      AppCommandExecutionApprovalResponse(decision=AppCommandDecline)
    }),
  )
  let request : AppServerRequest = {
    id: StringId("approval-1"),
    details: AppCommandExecutionApprovalRequest({
      kind: AppCommandApprovalCommand,
      thread_id: "thread-1",
      turn_id: "turn-1",
      item_id: "item-1",
      started_at_ms: 1,
      approval_id: None,
      environment_id: None,
      reason: None,
      network_approval_context: None,
      command: None,
      cwd: None,
      command_actions: None,
      proposed_execpolicy_amendment: None,
      proposed_network_policy_amendments: None,
      raw: {},
    }),
  }
  session.handle_session_request(request, None)
  let response = connection.outgoing.get()
  guard response
    is {
      "id": String("approval-1"),
      "result": { "decision": String("decline"), .. },
      ..
    } else {
    fail("expected declined approval response")
  }
  debug_inspect(session.turn_streams[0].turn_id, content="Some(\"turn-1\")")
}

///|
async test "session routes turn request to stream handler" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream(
    "thread-1",
    events,
    Some(fn(_) {
      AppCommandExecutionApprovalResponse(decision=AppCommandDecline)
    }),
  )
  session.bind_turn_stream(stream_id, "turn-1")
  let request : AppServerRequest = {
    id: StringId("approval-1"),
    details: AppCommandExecutionApprovalRequest({
      kind: AppCommandApprovalCommand,
      thread_id: "thread-1",
      turn_id: "turn-1",
      item_id: "item-1",
      started_at_ms: 1,
      approval_id: None,
      environment_id: None,
      reason: None,
      network_approval_context: None,
      command: None,
      cwd: None,
      command_actions: None,
      proposed_execpolicy_amendment: None,
      proposed_network_policy_amendments: None,
      raw: {},
    }),
  }
  session.handle_session_request(request, None)
  let response = connection.outgoing.get()
  guard response
    is {
      "id": String("approval-1"),
      "result": { "decision": String("decline"), .. },
      ..
    } else {
    fail("expected declined approval response")
  }
}

///|
async test "session routes thread request to thread handler" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  session.set_thread_request_handler(
    "thread-1",
    Some(fn(_) {
      AppCommandExecutionApprovalResponse(decision=AppCommandAccept)
    }),
  )
  let request : AppServerRequest = {
    id: StringId("approval-1"),
    details: AppCommandExecutionApprovalRequest({
      kind: AppCommandApprovalCommand,
      thread_id: "thread-1",
      turn_id: "turn-1",
      item_id: "item-1",
      started_at_ms: 1,
      approval_id: None,
      environment_id: None,
      reason: None,
      network_approval_context: None,
      command: None,
      cwd: None,
      command_actions: None,
      proposed_execpolicy_amendment: None,
      proposed_network_policy_amendments: None,
      raw: {},
    }),
  }
  session.handle_session_request(request, None)
  let response = connection.outgoing.get()
  guard response
    is {
      "id": String("approval-1"),
      "result": { "decision": String("accept"), .. },
      ..
    } else {
    fail("expected accepted approval response")
  }
}

///|
async test "session prefers turn request handler over thread handler" {
  let connection : CodexAppConnection = {
    outgoing: @async.Queue::Queue(kind=Unbounded),
    events: @async.Queue::Queue(kind=Unbounded),
    requests: @async.Queue::Queue(kind=Unbounded),
    pending: [],
    next_request_id: 1,
    events_closed: false,
  }
  let session = CodexAppSession::new(connection)
  session.set_thread_request_handler(
    "thread-1",
    Some(fn(_) {
      AppCommandExecutionApprovalResponse(decision=AppCommandAccept)
    }),
  )
  let events : @async.Queue[AppQueuedTurnEvent] = @async.Queue::Queue(
    kind=Unbounded,
  )
  let stream_id = session.register_pending_turn_stream(
    "thread-1",
    events,
    Some(fn(_) {
      AppCommandExecutionApprovalResponse(decision=AppCommandDecline)
    }),
  )
  session.bind_turn_stream(stream_id, "turn-1")
  let request : AppServerRequest = {
    id: StringId("approval-1"),
    details: AppCommandExecutionApprovalRequest({
      kind: AppCommandApprovalCommand,
      thread_id: "thread-1",
      turn_id: "turn-1",
      item_id: "item-1",
      started_at_ms: 1,
      approval_id: None,
      environment_id: None,
      reason: None,
      network_approval_context: None,
      command: None,
      cwd: None,
      command_actions: None,
      proposed_execpolicy_amendment: None,
      proposed_network_policy_amendments: None,
      raw: {},
    }),
  }
  session.handle_session_request(request, None)
  let response = connection.outgoing.get()
  guard response
    is {
      "id": String("approval-1"),
      "result": { "decision": String("decline"), .. },
      ..
    } else {
    fail("expected turn handler to decline approval response")
  }
}

///|
test "parse app-server MCP elicitation request" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "mcp-elicit-1",
        #|  "method": "mcpServer/elicitation/request",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": null,
        #|    "serverName": "local",
        #|    "mode": "form",
        #|    "_meta": { "source": "test" },
        #|    "message": "Configure access",
        #|    "requestedSchema": {
        #|      "$schema": "https://json-schema.org/draft/2020-12/schema",
        #|      "type": "object",
        #|      "properties": {
        #|        "email": {
        #|          "type": "string",
        #|          "format": "email",
        #|          "default": "dev@example.test"
        #|        },
        #|        "count": {
        #|          "type": "integer",
        #|          "minimum": 1,
        #|          "maximum": 5,
        #|          "default": 3
        #|        },
        #|        "confirmed": {
        #|          "type": "boolean",
        #|          "default": true
        #|        },
        #|        "choice": {
        #|          "type": "string",
        #|          "enum": ["allow", "deny"],
        #|          "enumNames": ["Allow", "Deny"],
        #|          "default": "allow"
        #|        },
        #|        "scopes": {
        #|          "type": "array",
        #|          "minItems": 1,
        #|          "maxItems": 2,
        #|          "items": {
        #|            "anyOf": [
        #|              { "const": "read", "title": "Read" },
        #|              { "const": "write", "title": "Write" }
        #|            ]
        #|          },
        #|          "default": ["read"]
        #|        }
        #|      },
        #|      "required": ["email", "confirmed"]
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) =>
      match request.details {
        AppMcpServerElicitationRequest(elicitation_request) => {
          debug_inspect(elicitation_request.turn_id, content="None")
          debug_inspect(elicitation_request.server_name, content="\"local\"")
          match elicitation_request.elicitation {
            AppMcpElicitationForm(meta~, message~, requested_schema~) => {
              guard meta is Some({ "source": String("test"), .. }) else {
                fail("expected MCP elicitation metadata")
              }
              debug_inspect(message, content="\"Configure access\"")
              debug_inspect(
                requested_schema.schema_uri,
                content=(
                  #|Some("https://json-schema.org/draft/2020-12/schema")
                ),
              )
              guard requested_schema.required is Some(required) else {
                fail("expected required fields")
              }
              debug_inspect(required.length(), content="2")
              match requested_schema.properties.get("email") {
                Some(AppMcpElicitationString(schema)) =>
                  debug_inspect(
                    schema.format,
                    content="Some(AppMcpElicitationEmailFormat)",
                  )
                _ => fail("expected string email schema")
              }
              match requested_schema.properties.get("count") {
                Some(AppMcpElicitationNumber(schema)) =>
                  debug_inspect(
                    schema.number_type,
                    content="AppMcpElicitationNumberTypeInteger",
                  )
                _ => fail("expected integer count schema")
              }
              match requested_schema.properties.get("confirmed") {
                Some(AppMcpElicitationBoolean(schema)) =>
                  debug_inspect(schema.default, content="Some(true)")
                _ => fail("expected boolean confirmed schema")
              }
              match requested_schema.properties.get("choice") {
                Some(AppMcpElicitationStringEnum(schema)) => {
                  guard schema.enum_names is Some(enum_names) else {
                    fail("expected enum names")
                  }
                  debug_inspect(enum_names[0], content="\"Allow\"")
                }
                _ => fail("expected string enum choice schema")
              }
              match requested_schema.properties.get("scopes") {
                Some(AppMcpElicitationTitledMultiSelect(schema)) => {
                  debug_inspect(schema.min_items, content="Some(1)")
                  debug_inspect(
                    schema.items.any_of[1].const_value,
                    content="\"write\"",
                  )
                }
                _ => fail("expected titled multi-select schema")
              }
            }
            _ => fail("expected MCP form elicitation")
          }
        }
        _ => fail("expected typed MCP elicitation request")
      }
    _ => fail("expected app-server request")
  }
}

///|
test "preserve unknown app-server notification" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "future/event",
        #|  "params": { "value": 1 }
        #|}
      ),
    ),
  )
  match message {
    Notification(AppRawNotification(rpc_method~, params~)) => {
      debug_inspect(rpc_method, content="\"future/event\"")
      debug_inspect(params, content="Some(Object({ \"value\": Number(1) }))")
    }
    _ => fail("expected raw notification")
  }
}

///|
test "preserve newer payloads for known app-server notifications" {
  let message : AppServerMessage = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "turn/started",
        #|  "params": { "futureShape": true }
        #|}
      ),
    ),
  )
  match message {
    Notification(AppRawNotification(rpc_method~, params~)) => {
      debug_inspect(rpc_method, content="\"turn/started\"")
      debug_inspect(params, content="Some(Object({ \"futureShape\": True }))")
    }
    _ => fail("expected raw notification fallback")
  }
}

///|
test "bound app-server overload retry backoff" {
  debug_inspect(
    [
      app_server_overload_retry_delay(0),
      app_server_overload_retry_delay(1),
      app_server_overload_retry_delay(2),
      app_server_overload_retry_delay(3),
      app_server_overload_retry_delay(4),
    ],
    content="[50, 100, 200, 400, 400]",
  )
}

///|
test "parse app-server token usage notification" {
  let event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/tokenUsage/updated",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "tokenUsage": {
        #|      "total": {
        #|        "totalTokens": 3000000000,
        #|        "inputTokens": 2999999990,
        #|        "cachedInputTokens": 3,
        #|        "outputTokens": 7,
        #|        "reasoningOutputTokens": 5
        #|      },
        #|      "last": {
        #|        "totalTokens": 3000000000,
        #|        "inputTokens": 2999999990,
        #|        "cachedInputTokens": 3,
        #|        "outputTokens": 7,
        #|        "reasoningOutputTokens": 5
        #|      },
        #|      "modelContextWindow": 4000000000
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match event {
    AppThreadTokenUsageUpdated(token_usage~, ..) => {
      debug_inspect(
        token_usage.last,
        content=(
          #|{
          #|  total_tokens: 3000000000,
          #|  input_tokens: 2999999990,
          #|  cached_input_tokens: 3,
          #|  output_tokens: 7,
          #|  reasoning_output_tokens: 5,
          #|}
        ),
      )
      debug_inspect(
        token_usage.model_context_window,
        content="Some(4000000000)",
      )
    }
    _ => fail("expected token usage notification")
  }
}

///|
test "parse app-server realtime notifications" {
  let started : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/started",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "realtimeSessionId": "rt-1",
        #|    "version": "v2"
        #|  }
        #|}
      ),
    ),
  )
  match started {
    AppThreadRealtimeStarted(realtime_session_id~, version~, ..) => {
      debug_inspect(realtime_session_id, content="Some(\"rt-1\")")
      debug_inspect(version, content="AppRealtimeConversationV2")
    }
    _ => fail("expected realtime started notification")
  }
  let item_added : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/itemAdded",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "item": { "type": "response.output_item.added" }
        #|  }
        #|}
      ),
    ),
  )
  match item_added {
    AppThreadRealtimeItemAdded(item~, ..) => {
      guard item is { "type": String("response.output_item.added"), .. } else {
        fail("expected realtime raw item")
      }
    }
    _ => fail("expected realtime item-added notification")
  }
  let transcript_delta : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/transcript/delta",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "role": "assistant",
        #|    "delta": "hel"
        #|  }
        #|}
      ),
    ),
  )
  match transcript_delta {
    AppThreadRealtimeTranscriptDelta(role~, delta~, ..) => {
      debug_inspect(role, content="\"assistant\"")
      debug_inspect(delta, content="\"hel\"")
    }
    _ => fail("expected realtime transcript delta")
  }
  let transcript_done : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/transcript/done",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "role": "assistant",
        #|    "text": "hello"
        #|  }
        #|}
      ),
    ),
  )
  match transcript_done {
    AppThreadRealtimeTranscriptDone(text~, ..) =>
      debug_inspect(text, content="\"hello\"")
    _ => fail("expected realtime transcript done")
  }
  let audio_delta : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/outputAudio/delta",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "audio": {
        #|      "data": "AAAA",
        #|      "sampleRate": 24000,
        #|      "numChannels": 1,
        #|      "samplesPerChannel": 480,
        #|      "itemId": "item-1"
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match audio_delta {
    AppThreadRealtimeOutputAudioDelta(audio~, ..) => {
      debug_inspect(audio.sample_rate, content="24000")
      debug_inspect(audio.num_channels, content="1")
      debug_inspect(audio.samples_per_channel, content="Some(480)")
      debug_inspect(audio.item_id, content="Some(\"item-1\")")
    }
    _ => fail("expected realtime audio delta")
  }
  let sdp_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/sdp",
        #|  "params": { "threadId": "thread-1", "sdp": "answer" }
        #|}
      ),
    ),
  )
  match sdp_event {
    AppThreadRealtimeSdp(sdp~, ..) => debug_inspect(sdp, content="\"answer\"")
    _ => fail("expected realtime SDP")
  }
  let error_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/error",
        #|  "params": { "threadId": "thread-1", "message": "bad audio" }
        #|}
      ),
    ),
  )
  match error_event {
    AppThreadRealtimeError(message~, ..) =>
      debug_inspect(message, content="\"bad audio\"")
    _ => fail("expected realtime error")
  }
  let closed : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/realtime/closed",
        #|  "params": { "threadId": "thread-1", "reason": null }
        #|}
      ),
    ),
  )
  match closed {
    AppThreadRealtimeClosed(reason~, ..) =>
      debug_inspect(reason, content="None")
    _ => fail("expected realtime closed notification")
  }
}

///|
test "parse additional typed app-server notifications" {
  let name_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/name/updated",
        #|  "params": { "threadId": "thread-1", "threadName": "Build fix" }
        #|}
      ),
    ),
  )
  match name_event {
    AppThreadNameUpdated(thread_id~, thread_name~) => {
      debug_inspect(thread_id, content="\"thread-1\"")
      debug_inspect(thread_name, content="Some(\"Build fix\")")
    }
    _ => fail("expected thread name update")
  }
  let goal_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/goal/updated",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": null,
        #|    "goal": {
        #|      "threadId": "thread-1",
        #|      "objective": "Fix protocol correctness",
        #|      "status": "budgetLimited",
        #|      "tokenBudget": 12345,
        #|      "tokensUsed": 5000000000,
        #|      "timeUsedSeconds": 30,
        #|      "createdAt": 1710000000,
        #|      "updatedAt": 1710000001
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match goal_event {
    AppThreadGoalUpdated(turn_id~, goal~, ..) => {
      debug_inspect(turn_id, content="None")
      debug_inspect(goal.status, content="AppThreadGoalBudgetLimited")
      debug_inspect(goal.tokens_used, content="5000000000")
    }
    _ => fail("expected thread goal update")
  }
  let goal_cleared_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/goal/cleared",
        #|  "params": { "threadId": "thread-1" }
        #|}
      ),
    ),
  )
  match goal_cleared_event {
    AppThreadGoalCleared(thread_id~) =>
      debug_inspect(thread_id, content="\"thread-1\"")
    _ => fail("expected thread goal clear")
  }
  let plan_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "turn/plan/updated",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "explanation": "regroup",
        #|    "plan": [
        #|      { "step": "Inspect", "status": "completed" },
        #|      { "step": "Patch", "status": "inProgress" }
        #|    ]
        #|  }
        #|}
      ),
    ),
  )
  match plan_event {
    AppTurnPlanUpdated(explanation~, plan~, ..) => {
      debug_inspect(explanation, content="Some(\"regroup\")")
      debug_inspect(plan[1].status, content="AppTurnPlanInProgress")
    }
    _ => fail("expected turn plan update")
  }
  let patch_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/fileChange/patchUpdated",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "itemId": "file-1",
        #|    "changes": [
        #|      {
        #|        "path": "new.txt",
        #|        "kind": { "type": "update", "move_path": "old.txt" },
        #|        "diff": "@@ -1 +1 @@"
        #|      }
        #|    ]
        #|  }
        #|}
      ),
    ),
  )
  match patch_event {
    AppFileChangePatchUpdated(changes~, ..) => {
      debug_inspect(changes.length(), content="1")
      debug_inspect(changes[0].path, content="\"new.txt\"")
    }
    _ => fail("expected file change patch update")
  }
  let request_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "serverRequest/resolved",
        #|  "params": { "threadId": "thread-1", "requestId": 5000000000 }
        #|}
      ),
    ),
  )
  match request_event {
    AppServerRequestResolved(request_id~, ..) =>
      debug_inspect(request_id, content="IntId(5000000000)")
    _ => fail("expected server request resolution")
  }
  let fuzzy_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "fuzzyFileSearch/sessionUpdated",
        #|  "params": {
        #|    "sessionId": "session-1",
        #|    "query": "main",
        #|    "files": [
        #|      {
        #|        "root": "/repo",
        #|        "path": "src/main.mbt",
        #|        "match_type": "file",
        #|        "file_name": "main.mbt",
        #|        "score": 3000000000,
        #|        "indices": [0, 3000000000]
        #|      }
        #|    ]
        #|  }
        #|}
      ),
    ),
  )
  match fuzzy_event {
    AppFuzzyFileSearchSessionUpdated(files~, ..) =>
      debug_inspect(files[0].score, content="3000000000")
    _ => fail("expected fuzzy file search update")
  }
  let windows_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "windows/worldWritableWarning",
        #|  "params": {
        #|    "samplePaths": ["C:\\tmp"],
        #|    "extraCount": 5000000000,
        #|    "failedScan": false
        #|  }
        #|}
      ),
    ),
  )
  match windows_event {
    AppWindowsWorldWritableWarning(extra_count~, failed_scan~, ..) => {
      debug_inspect(extra_count, content="5000000000")
      debug_inspect(failed_scan, content="false")
    }
    _ => fail("expected Windows world-writable warning")
  }
  let setup_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "windowsSandbox/setupCompleted",
        #|  "params": {
        #|    "mode": "unelevated",
        #|    "success": false,
        #|    "error": "missing feature"
        #|  }
        #|}
      ),
    ),
  )
  match setup_event {
    AppWindowsSandboxSetupCompleted(mode~, success~, error~) => {
      debug_inspect(mode, content="AppWindowsSandboxUnelevated")
      debug_inspect(success, content="false")
      debug_inspect(error, content="Some(\"missing feature\")")
    }
    _ => fail("expected Windows sandbox setup completion")
  }
  let reasoning_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/reasoning/textDelta",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "itemId": "reason-1",
        #|    "delta": "next",
        #|    "contentIndex": 3000000000
        #|  }
        #|}
      ),
    ),
  )
  match reasoning_event {
    AppReasoningTextDelta(delta~, content_index~, ..) => {
      debug_inspect(delta, content="\"next\"")
      debug_inspect(content_index, content="3000000000")
    }
    _ => fail("expected reasoning text delta")
  }
  let terminal_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "item/commandExecution/terminalInteraction",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "itemId": "cmd-1",
        #|    "processId": "proc-1",
        #|    "stdin": "q"
        #|  }
        #|}
      ),
    ),
  )
  match terminal_event {
    AppTerminalInteraction(process_id~, stdin~, ..) => {
      debug_inspect(process_id, content="\"proc-1\"")
      debug_inspect(stdin, content="\"q\"")
    }
    _ => fail("expected terminal interaction")
  }
  let command_exec_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "command/exec/outputDelta",
        #|  "params": {
        #|    "processId": "proc-1",
        #|    "stream": "stderr",
        #|    "deltaBase64": "ZXJy",
        #|    "capReached": true
        #|  }
        #|}
      ),
    ),
  )
  match command_exec_event {
    AppCommandExecOutputDelta(stream~, delta_base64~, cap_reached~, ..) => {
      debug_inspect(stream, content="AppStderr")
      debug_inspect(delta_base64, content="\"ZXJy\"")
      debug_inspect(cap_reached, content="true")
    }
    _ => fail("expected command exec output delta")
  }
  let mcp_status_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "mcpServer/startupStatus/updated",
        #|  "params": {
        #|    "name": "github",
        #|    "status": "failed",
        #|    "error": "missing token"
        #|  }
        #|}
      ),
    ),
  )
  match mcp_status_event {
    AppMcpServerStatusUpdated(status~, error~, ..) => {
      debug_inspect(status, content="AppMcpServerFailed")
      debug_inspect(error, content="Some(\"missing token\")")
    }
    _ => fail("expected MCP server status update")
  }
  let account_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "account/updated",
        #|  "params": {
        #|    "authMode": "chatgptAuthTokens",
        #|    "planType": "plus"
        #|  }
        #|}
      ),
    ),
  )
  match account_event {
    AppAccountUpdated(auth_mode~, plan_type~) => {
      debug_inspect(auth_mode, content="Some(AppAuthChatGPTAuthTokens)")
      debug_inspect(plan_type, content="Some(AppPlanPlus)")
    }
    _ => fail("expected account update")
  }
  let remote_control_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "remoteControl/status/changed",
        #|  "params": {
        #|    "status": "connected",
        #|    "installationId": "install-1",
        #|    "environmentId": null
        #|  }
        #|}
      ),
    ),
  )
  match remote_control_event {
    AppRemoteControlStatusChanged(status~, environment_id~, ..) => {
      debug_inspect(status, content="AppRemoteControlConnected")
      debug_inspect(environment_id, content="None")
    }
    _ => fail("expected remote control status")
  }
  let fs_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "fs/changed",
        #|  "params": {
        #|    "watchId": "watch-1",
        #|    "changedPaths": ["/tmp/a.txt"]
        #|  }
        #|}
      ),
    ),
  )
  match fs_event {
    AppFsChanged(changed_paths~, ..) =>
      debug_inspect(changed_paths[0], content="\"/tmp/a.txt\"")
    _ => fail("expected fs change")
  }
  let warning_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "warning",
        #|  "params": { "threadId": null, "message": "careful" }
        #|}
      ),
    ),
  )
  match warning_event {
    AppWarning(thread_id~, message~) => {
      debug_inspect(thread_id, content="None")
      debug_inspect(message, content="\"careful\"")
    }
    _ => fail("expected warning")
  }
  let model_rerouted_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "model/rerouted",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "fromModel": "gpt-5",
        #|    "toModel": "gpt-5-cyber",
        #|    "reason": "highRiskCyberActivity"
        #|  }
        #|}
      ),
    ),
  )
  match model_rerouted_event {
    AppModelRerouted(to_model~, reason~, ..) => {
      debug_inspect(to_model, content="\"gpt-5-cyber\"")
      debug_inspect(reason, content="AppModelRerouteHighRiskCyberActivity")
    }
    _ => fail("expected model rerouted notification")
  }
  let model_verification_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "model/verification",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "turnId": "turn-1",
        #|    "verifications": ["trustedAccessForCyber"]
        #|  }
        #|}
      ),
    ),
  )
  match model_verification_event {
    AppModelVerification(verifications~, ..) =>
      debug_inspect(
        verifications[0],
        content="AppModelVerificationTrustedAccessForCyber",
      )
    _ => fail("expected model verification notification")
  }
  let config_warning_event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "configWarning",
        #|  "params": {
        #|    "summary": "Invalid config",
        #|    "details": "bad value",
        #|    "path": "/repo/.codex/config.toml",
        #|    "range": {
        #|      "start": { "line": 2, "column": 3 },
        #|      "end": { "line": 2, "column": 8 }
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match config_warning_event {
    AppConfigWarning(details~, path~, range~, ..) => {
      debug_inspect(details, content="Some(\"bad value\")")
      debug_inspect(path, content="Some(\"/repo/.codex/config.toml\")")
      guard range is Some(range) else { fail("expected config warning range") }
      debug_inspect(range.start.line, content="2")
      debug_inspect(range.end.column, content="8")
    }
    _ => fail("expected config warning notification")
  }
}

///|
test "parse typed app-server thread resume response" {
  let response : AppThreadResumeResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "thread": {
        #|    "id": "thread-1",
        #|    "sessionId": "session-1",
        #|    "forkedFromId": null,
        #|    "parentThreadId": "thread-parent",
        #|    "preview": "hello",
        #|    "ephemeral": false,
        #|    "section": {
        #|      "id": "section-1",
        #|      "name": "SDK",
        #|      "appearance": { "icon": "code", "color": "blue" }
        #|    },
        #|    "sectionEnteredAt": 1710000000,
        #|    "projectId": "project-1",
        #|    "modelProvider": "openai",
        #|    "createdAt": 1710000000,
        #|    "updatedAt": 1710000001,
        #|    "recencyAt": 1710000002,
        #|    "status": { "type": "idle" },
        #|    "path": null,
        #|    "cwd": "/tmp/project",
        #|    "cliVersion": "0.0.0",
        #|    "source": "appServer",
        #|    "threadSource": "moonbit-sdk",
        #|    "agentNickname": null,
        #|    "agentRole": null,
        #|    "gitInfo": {
        #|      "sha": null,
        #|      "branch": "main",
        #|      "originUrl": null
        #|    },
        #|    "name": null,
        #|    "turns": [
        #|      {
        #|        "id": "turn-1",
        #|        "items": [
        #|          {
        #|            "type": "userMessage",
        #|            "id": "user-1",
        #|            "content": [
        #|              {
        #|                "type": "text",
        #|                "text": "hello",
        #|                "text_elements": [
        #|                  {
        #|                    "byteRange": { "start": 5000000000, "end": 5000000005 },
        #|                    "placeholder": null
        #|                  }
        #|                ]
        #|              }
        #|            ]
        #|          },
        #|          {
        #|            "type": "agentMessage",
        #|            "id": "agent-1",
        #|            "text": "done",
        #|            "phase": "final_answer",
        #|            "memoryCitation": {
        #|              "entries": [
        #|                {
        #|                  "path": "AGENTS.md",
        #|                  "lineStart": 3000000000,
        #|                  "lineEnd": 3000000001,
        #|                  "note": "repo guide"
        #|                }
        #|              ],
        #|              "threadIds": ["thread-0"]
        #|            }
        #|          },
        #|          {
        #|            "type": "commandExecution",
        #|            "id": "cmd-1",
        #|            "command": "pwd",
        #|            "cwd": "/tmp/project",
        #|            "processId": null,
        #|            "source": "agent",
        #|            "status": "completed",
        #|            "commandActions": [
        #|              {
        #|                "type": "read",
        #|                "command": "cat README.md",
        #|                "name": "README.md",
        #|                "path": "/tmp/project/README.md"
        #|              }
        #|            ],
        #|            "aggregatedOutput": "/tmp/project\n",
        #|            "exitCode": 0,
        #|            "durationMs": 12
        #|          }
        #|        ],
        #|        "status": "completed",
        #|        "error": null,
        #|        "startedAt": 1710000000,
        #|        "completedAt": 1710000001,
        #|        "durationMs": 1000
        #|      }
        #|    ]
        #|  },
        #|  "model": "gpt-5",
        #|  "modelProvider": "openai",
        #|  "serviceTier": null,
        #|  "cwd": "/tmp/project",
        #|  "instructionSources": ["/tmp/project/AGENTS.md"],
        #|  "approvalPolicy": "on-request",
        #|  "approvalsReviewer": "user",
        #|  "sandbox": { "type": "readOnly", "networkAccess": false },
        #|  "reasoningEffort": "medium"
        #|}
      ),
    ),
  )
  debug_inspect(
    response.thread.id,
    content=(
      #|"thread-1"
    ),
  )
  debug_inspect(response.thread.session_id, content="\"session-1\"")
  debug_inspect(
    response.thread.parent_thread_id,
    content="Some(\"thread-parent\")",
  )
  guard response.thread.section is Some(section) else {
    fail("expected thread section")
  }
  debug_inspect(section.name, content="\"SDK\"")
  debug_inspect(response.thread.project_id, content="Some(\"project-1\")")
  debug_inspect(response.thread.recency_at, content="Some(1710000002)")
  debug_inspect(response.thread.thread_source, content="Some(\"moonbit-sdk\")")
  debug_inspect(response.thread.turns[0].items.length(), content="3")
  match response.thread.turns[0].items[0] {
    AppThreadUserMessageItem(content~, ..) =>
      match content[0] {
        AppThreadInputText(text_elements~, ..) => {
          let byte_range = text_elements[0].byte_range
          debug_inspect(byte_range.start, content="5000000000")
          debug_inspect(byte_range.end, content="5000000005")
        }
        _ => fail("expected text input")
      }
    _ => fail("expected user message item")
  }
  match response.thread.turns[0].items[1] {
    AppThreadAgentMessageItem(phase~, memory_citation~, ..) => {
      debug_inspect(phase, content="Some(AppMessageFinalAnswer)")
      guard memory_citation is Some(citation) else {
        fail("expected memory citation")
      }
      debug_inspect(citation.entries[0].line_start, content="3000000000")
      debug_inspect(citation.entries[0].line_end, content="3000000001")
    }
    _ => fail("expected agent message item")
  }
  match response.thread.turns[0].items[2] {
    AppThreadCommandExecutionItem(status~, command_actions~, duration_ms~, ..) => {
      debug_inspect(status, content="AppThreadCommandCompleted")
      debug_inspect(command_actions.length(), content="1")
      debug_inspect(duration_ms, content="Some(12)")
    }
    _ => fail("expected command execution item")
  }
  debug_inspect(response.instruction_sources.length(), content="1")
  debug_inspect(response.reasoning_effort, content="Some(AppEffortMedium)")
}

///|
test "parse typed app-server thread item variants" {
  let items : ArrayView[AppThreadItem] = @json.from_json(
    @json.parse(
      (
        #|[
        #|  {
        #|    "type": "hookPrompt",
        #|    "id": "hook-1",
        #|    "fragments": [
        #|      { "text": "review this", "hookRunId": "run-1" }
        #|    ]
        #|  },
        #|  {
        #|    "type": "reasoning",
        #|    "id": "reason-1",
        #|    "summary": ["looked around"],
        #|    "content": ["full reasoning"]
        #|  },
        #|  {
        #|    "type": "fileChange",
        #|    "id": "file-1",
        #|    "changes": [
        #|      {
        #|        "path": "new.txt",
        #|        "kind": { "type": "update", "move_path": "old.txt" },
        #|        "diff": "@@ -1 +1 @@"
        #|      }
        #|    ],
        #|    "status": "declined"
        #|  },
        #|  {
        #|    "type": "mcpToolCall",
        #|    "id": "mcp-1",
        #|    "server": "github",
        #|    "tool": "search",
        #|    "status": "completed",
        #|    "arguments": { "q": "codex" },
        #|    "mcpAppResourceUri": "app://github",
        #|    "result": {
        #|      "content": [{ "type": "text", "text": "ok" }],
        #|      "structuredContent": null,
        #|      "_meta": null
        #|    },
        #|    "error": null,
        #|    "durationMs": 5
        #|  },
        #|  {
        #|    "type": "dynamicToolCall",
        #|    "id": "dyn-1",
        #|    "namespace": null,
        #|    "tool": "image",
        #|    "arguments": {},
        #|    "status": "completed",
        #|    "contentItems": [
        #|      { "type": "inputText", "text": "prompt" },
        #|      { "type": "inputImage", "imageUrl": "https://example.test/image.png" }
        #|    ],
        #|    "success": true,
        #|    "durationMs": 6
        #|  },
        #|  {
        #|    "type": "collabAgentToolCall",
        #|    "id": "collab-1",
        #|    "tool": "spawnAgent",
        #|    "status": "inProgress",
        #|    "senderThreadId": "parent",
        #|    "receiverThreadIds": ["child"],
        #|    "prompt": null,
        #|    "model": "gpt-5",
        #|    "reasoningEffort": "low",
        #|    "agentsStates": {
        #|      "child": { "status": "running", "message": null }
        #|    }
        #|  },
        #|  {
        #|    "type": "webSearch",
        #|    "id": "web-1",
        #|    "query": "moonbit",
        #|    "action": {
        #|      "type": "search",
        #|      "query": "moonbit",
        #|      "queries": ["moonbit"]
        #|    }
        #|  },
        #|  {
        #|    "type": "imageView",
        #|    "id": "image-1",
        #|    "path": "/tmp/image.png"
        #|  },
        #|  {
        #|    "type": "imageGeneration",
        #|    "id": "gen-1",
        #|    "status": "completed",
        #|    "revisedPrompt": null,
        #|    "result": "image-base64",
        #|    "savedPath": "/tmp/generated.png"
        #|  },
        #|  {
        #|    "type": "contextCompaction",
        #|    "id": "compact-1"
        #|  }
        #|]
      ),
    ),
  )
  debug_inspect(items.length(), content="10")
  match items[2] {
    AppThreadFileChangeItem(status~, changes~, ..) => {
      debug_inspect(status, content="AppThreadPatchDeclined")
      match changes[0].kind {
        AppThreadPatchUpdate(move_path~) =>
          debug_inspect(move_path, content="Some(\"old.txt\")")
        _ => fail("expected update patch kind")
      }
    }
    _ => fail("expected file change item")
  }
  match items[4] {
    AppThreadDynamicToolCallItem(content_items~, success~, ..) => {
      guard content_items is Some(content_items) else {
        fail("expected dynamic content items")
      }
      debug_inspect(content_items.length(), content="2")
      debug_inspect(success, content="Some(true)")
    }
    _ => fail("expected dynamic tool item")
  }
  match items[5] {
    AppThreadCollabAgentToolCallItem(reasoning_effort~, agents_states~, ..) => {
      debug_inspect(reasoning_effort, content="Some(AppEffortLow)")
      match agents_states.get("child") {
        Some(state) =>
          debug_inspect(state.status, content="AppThreadCollabAgentRunning")
        None => fail("expected child agent state")
      }
    }
    _ => fail("expected collab tool item")
  }
  match items[6] {
    AppThreadWebSearchItem(action~, ..) => {
      guard action is Some(AppWebSearchActionSearch(queries~, ..)) else {
        fail("expected web search action")
      }
      guard queries is Some(queries) else { fail("expected web queries") }
      debug_inspect(queries[0], content="\"moonbit\"")
    }
    _ => fail("expected web search item")
  }
}

///|
test "default missing app-server thread lifecycle instruction sources" {
  let value = @json.parse(
    (
      #|{
      #|  "thread": {
      #|    "id": "thread-1",
      #|    "forkedFromId": null,
      #|    "preview": "hello",
      #|    "ephemeral": false,
      #|    "modelProvider": "openai",
      #|    "createdAt": 1710000000,
      #|    "updatedAt": 1710000001,
      #|    "status": { "type": "idle" },
      #|    "path": null,
      #|    "cwd": "/tmp/project",
      #|    "cliVersion": "0.0.0",
      #|    "source": "appServer",
      #|    "agentNickname": null,
      #|    "agentRole": null,
      #|    "gitInfo": null,
      #|    "name": null,
      #|    "turns": []
      #|  },
      #|  "model": "gpt-5",
      #|  "modelProvider": "openai",
      #|  "serviceTier": null,
      #|  "cwd": "/tmp/project",
      #|  "approvalPolicy": "on-failure",
      #|  "approvalsReviewer": "user",
      #|  "sandbox": { "type": "dangerFullAccess" },
      #|  "reasoningEffort": null
      #|}
    ),
  )
  let start : AppThreadStartResponse = @json.from_json(value)
  let resumed : AppThreadResumeResponse = @json.from_json(value)
  let fork : AppThreadForkResponse = @json.from_json(value)
  debug_inspect(start.instruction_sources.length(), content="0")
  debug_inspect(resumed.instruction_sources.length(), content="0")
  debug_inspect(fork.instruction_sources.length(), content="0")
}

///|
test "parse app-server app info defaults" {
  let info : AppInfo = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "app-1",
        #|  "name": "App One"
        #|}
      ),
    ),
  )
  guard !info.is_accessible else { fail("expected inaccessible by default") }
  guard info.is_enabled else { fail("expected enabled by default") }
  debug_inspect(info.plugin_display_names.length(), content="0")
}

///|
test "parse app-server model fields and defaults" {
  let minimal : AppModel = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "gpt-5",
        #|  "model": "gpt-5",
        #|  "displayName": "GPT-5",
        #|  "description": "Frontier model",
        #|  "hidden": false,
        #|  "supportedReasoningEfforts": [
        #|    { "reasoningEffort": "medium", "description": "Balanced" }
        #|  ],
        #|  "defaultReasoningEffort": "medium",
        #|  "isDefault": true
        #|}
      ),
    ),
  )
  debug_inspect(minimal.input_modalities.length(), content="2")
  debug_inspect(minimal.input_modalities[0], content="AppTextModality")
  debug_inspect(minimal.input_modalities[1], content="AppImageModality")
  guard !minimal.supports_personality else {
    fail("expected supportsPersonality to default false")
  }
  debug_inspect(minimal.additional_speed_tiers.length(), content="0")
  debug_inspect(minimal.service_tiers.length(), content="0")
  let full : AppModel = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "id": "legacy-model",
        #|  "model": "legacy-model",
        #|  "upgrade": "gpt-5",
        #|  "upgradeInfo": {
        #|    "model": "gpt-5",
        #|    "upgradeCopy": "Use GPT-5",
        #|    "modelLink": "https://example.test/model",
        #|    "migrationMarkdown": "Move over"
        #|  },
        #|  "availabilityNux": { "message": "New model available" },
        #|  "displayName": "Legacy",
        #|  "description": "Legacy model",
        #|  "modelSpecialty": "coding",
        #|  "hidden": false,
        #|  "supportedReasoningEfforts": [
        #|    { "reasoningEffort": "low", "description": "Fast" }
        #|  ],
        #|  "defaultReasoningEffort": "low",
        #|  "inputModalities": ["text"],
        #|  "supportsPersonality": true,
        #|  "multiAgentVersion": "v2",
        #|  "additionalSpeedTiers": ["fast"],
        #|  "serviceTiers": [
        #|    { "id": "flex", "name": "Flex", "description": "Flexible" }
        #|  ],
        #|  "defaultServiceTier": "flex",
        #|  "isDefault": false
        #|}
      ),
    ),
  )
  debug_inspect(full.upgrade, content="Some(\"gpt-5\")")
  guard full.upgrade_info is Some(upgrade_info) else {
    fail("expected upgrade info")
  }
  debug_inspect(upgrade_info.model, content="\"gpt-5\"")
  guard full.availability_nux is Some(availability_nux) else {
    fail("expected availability nux")
  }
  debug_inspect(
    availability_nux.message,
    content=(
      #|"New model available"
    ),
  )
  debug_inspect(
    full.supported_reasoning_efforts[0].reasoning_effort,
    content="AppEffortLow",
  )
  guard full.supports_personality else { fail("expected personality support") }
  debug_inspect(full.additional_speed_tiers[0], content="\"fast\"")
  debug_inspect(full.service_tiers[0].id, content="\"flex\"")
  debug_inspect(full.model_specialty, content="Some(\"coding\")")
  debug_inspect(full.multi_agent_version, content="Some(AppMultiAgentV2)")
  debug_inspect(full.default_service_tier, content="Some(\"flex\")")
}

///|
test "parse app-server typed config metadata and requirements" {
  let write_response : AppConfigValueWriteResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "status": "okOverridden",
        #|  "version": "v1",
        #|  "filePath": "/tmp/config.toml",
        #|  "overriddenMetadata": {
        #|    "message": "Overridden",
        #|    "overridingLayer": {
        #|      "name": { "type": "user", "file": "/home/user/.codex/config.toml" },
        #|      "version": "user-v1"
        #|    },
        #|    "effectiveValue": false
        #|  }
        #|}
      ),
    ),
  )
  guard write_response.overridden_metadata is Some(metadata) else {
    fail("expected overridden metadata")
  }
  debug_inspect(
    metadata.overriding_layer.name,
    content="AppConfigLayerUser(file=\"/home/user/.codex/config.toml\")",
  )
  let requirements : AppConfigRequirementsReadResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "requirements": {
        #|    "allowedApprovalPolicies": ["never"],
        #|    "allowedSandboxModes": ["read-only"],
        #|    "allowedWebSearchModes": ["live"],
        #|    "allowManagedHooksOnly": true,
        #|    "featureRequirements": { "managed": false },
        #|    "enforceResidency": "us"
        #|  }
        #|}
      ),
    ),
  )
  guard requirements.requirements is Some(config_requirements) else {
    fail("expected config requirements")
  }
  guard config_requirements.allowed_approval_policies is Some(policies) else {
    fail("expected approval policies")
  }
  debug_inspect(policies[0], content="AppApprovalNever")
  guard config_requirements.allowed_sandbox_modes is Some(sandbox_modes) else {
    fail("expected sandbox modes")
  }
  debug_inspect(sandbox_modes[0], content="ReadOnly")
  guard config_requirements.allowed_web_search_modes is Some(web_search_modes) else {
    fail("expected web search modes")
  }
  debug_inspect(web_search_modes[0], content="AppWebSearchLive")
  debug_inspect(
    config_requirements.enforce_residency,
    content="Some(AppResidencyUs)",
  )
}

///|
test "parse typed app-server filesystem responses" {
  let file : AppFsReadFileResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "dataBase64": "aGVsbG8="
        #|}
      ),
    ),
  )
  debug_inspect(
    file.data_base64,
    content=(
      #|"aGVsbG8="
    ),
  )
  let metadata : AppFsGetMetadataResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "isDirectory": false,
        #|  "isFile": true,
        #|  "isSymlink": false,
        #|  "createdAtMs": 1710000000123,
        #|  "modifiedAtMs": 1710000000456
        #|}
      ),
    ),
  )
  guard metadata.is_file && !metadata.is_directory else {
    fail("expected file metadata")
  }
  debug_inspect(metadata.modified_at_ms, content="1710000000456")
  let directory : AppFsReadDirectoryResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "entries": [
        #|    { "fileName": "src", "isDirectory": true, "isFile": false }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(directory.entries.length(), content="1")
  debug_inspect(
    directory.entries[0].file_name,
    content=(
      #|"src"
    ),
  )
}

///|
test "parse typed app-server command response" {
  let response : AppCommandExecResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "exitCode": 7,
        #|  "stdout": "out",
        #|  "stderr": "err"
        #|}
      ),
    ),
  )
  debug_inspect(response.exit_code, content="7")
  debug_inspect(
    response.stdout,
    content=(
      #|"out"
    ),
  )
  debug_inspect(
    response.stderr,
    content=(
      #|"err"
    ),
  )
}

///|
test "parse app-server typed mcp resources" {
  let status : AppMcpServerStatusListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "data": [
        #|    {
        #|      "name": "local",
        #|      "tools": {
        #|        "read": {
        #|          "name": "read",
        #|          "title": "Read",
        #|          "description": "Read a resource",
        #|          "inputSchema": { "type": "object" },
        #|          "outputSchema": { "type": "object" },
        #|          "annotations": { "readOnlyHint": true },
        #|          "icons": [],
        #|          "_meta": { "source": "test" }
        #|        }
        #|      },
        #|      "resources": [
        #|        { "uri": "file:///tmp/a.txt", "name": "a.txt", "size": 5000000000 }
        #|      ],
        #|      "resourceTemplates": [
        #|        { "uriTemplate": "file:///{path}", "name": "files" }
        #|      ],
        #|      "authStatus": "notLoggedIn"
        #|    }
        #|  ],
        #|  "nextCursor": null
        #|}
      ),
    ),
  )
  match status.data[0].tools.get("read") {
    Some(tool) => debug_inspect(tool.title, content="Some(\"Read\")")
    None => fail("expected read tool")
  }
  debug_inspect(
    status.data[0].resources[0].uri,
    content="\"file:///tmp/a.txt\"",
  )
  debug_inspect(status.data[0].resources[0].size, content="Some(5000000000)")
  debug_inspect(
    status.data[0].resource_templates[0].uri_template,
    content="\"file:///{path}\"",
  )
  let contents : AppMcpServerResourceReadResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "contents": [
        #|    {
        #|      "uri": "file:///tmp/a.txt",
        #|      "mimeType": "text/plain",
        #|      "text": "hello",
        #|      "_meta": { "line": 1 }
        #|    },
        #|    {
        #|      "uri": "file:///tmp/b.bin",
        #|      "blob": "AA=="
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  match contents.contents[0] {
    AppMcpTextResourceContent(text~, ..) =>
      debug_inspect(text, content="\"hello\"")
    _ => fail("expected text content")
  }
  match contents.contents[1] {
    AppMcpBlobResourceContent(blob~, ..) =>
      debug_inspect(blob, content="\"AA==\"")
    _ => fail("expected blob content")
  }
}

///|
test "parse app-server typed plugin detail summaries" {
  let detail : AppPluginDetail = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "marketplaceName": "local",
        #|  "marketplacePath": "/tmp/marketplace.json",
        #|  "summary": {
        #|    "id": "plugin-1",
        #|    "name": "Plugin One",
        #|    "source": { "type": "remote" },
        #|    "installed": true,
        #|    "enabled": true,
        #|    "installPolicy": "AVAILABLE",
        #|    "authPolicy": "ON_USE",
        #|    "interface": {
        #|      "displayName": "Plugin One",
        #|      "shortDescription": "Short plugin",
        #|      "longDescription": null,
        #|      "developerName": null,
        #|      "category": "productivity",
        #|      "capabilities": ["search"],
        #|      "websiteUrl": null,
        #|      "privacyPolicyUrl": null,
        #|      "termsOfServiceUrl": null,
        #|      "defaultPrompt": ["Start"],
        #|      "brandColor": "#123456",
        #|      "composerIcon": null,
        #|      "composerIconUrl": null,
        #|      "logo": null,
        #|      "logoUrl": null,
        #|      "screenshots": [],
        #|      "screenshotUrls": []
        #|    }
        #|  },
        #|  "description": "Plugin details",
        #|  "skills": [
        #|    {
        #|      "name": "skill-1",
        #|      "description": "Skill one",
        #|      "shortDescription": "Short",
        #|      "interface": { "displayName": "Skill One" },
        #|      "path": "/tmp/skill",
        #|      "enabled": true
        #|    }
        #|  ],
        #|  "apps": [],
        #|  "mcpServers": ["local"]
        #|}
      ),
    ),
  )
  guard detail.skills[0].interface is Some(skill_interface) else {
    fail("expected skill interface")
  }
  debug_inspect(skill_interface.display_name, content="Some(\"Skill One\")")
  debug_inspect(detail.summary.source, content="AppPluginSourceRemote")
  debug_inspect(
    detail.summary.install_policy,
    content="AppPluginInstallAvailable",
  )
  guard detail.summary.interface is Some(plugin_interface) else {
    fail("expected plugin interface")
  }
  debug_inspect(plugin_interface.capabilities.length(), content="1")
}

///|
test "parse app-server fuzzy file search snake case fields" {
  let response : AppFuzzyFileSearchResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "files": [
        #|    {
        #|      "root": "/repo",
        #|      "path": "src/main.mbt",
        #|      "match_type": "file",
        #|      "file_name": "main.mbt",
        #|      "score": 3000000000,
        #|      "indices": [0, 3000000000]
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(response.files[0].match_type, content="AppFuzzyFile")
  debug_inspect(
    response.files[0].file_name,
    content=(
      #|"main.mbt"
    ),
  )
  debug_inspect(response.files[0].score, content="3000000000")
  guard response.files[0].indices is Some(indices) else {
    fail("expected fuzzy indices")
  }
  debug_inspect(indices[1], content="3000000000")
}

///|
test "parse typed app-server account responses" {
  let login : AppAccountLoginStartResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "type": "chatgpt",
        #|  "loginId": "login-1",
        #|  "authUrl": "https://example.test/auth"
        #|}
      ),
    ),
  )
  match login {
    AppAccountLoginChatGPT(login_id~, auth_url~) => {
      debug_inspect(
        login_id,
        content=(
          #|"login-1"
        ),
      )
      debug_inspect(
        auth_url,
        content=(
          #|"https://example.test/auth"
        ),
      )
    }
    _ => fail("expected chatgpt login response")
  }
  let account : AppAccountReadResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "account": {
        #|    "type": "chatgpt",
        #|    "email": "user@example.test",
        #|    "planType": "plus"
        #|  },
        #|  "requiresOpenaiAuth": false
        #|}
      ),
    ),
  )
  guard account.requires_openai_auth == false else {
    fail("expected no auth requirement")
  }
  match account.account {
    Some(AppAccountChatGPT(email~, plan_type~)) => {
      debug_inspect(
        email,
        content=(
          #|"user@example.test"
        ),
      )
      debug_inspect(
        plan_type,
        content=(
          #|AppPlanPlus
        ),
      )
    }
    _ => fail("expected chatgpt account")
  }
}

///|
test "parse app-server account rate limit details" {
  let response : AppAccountRateLimitsReadResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "rateLimits": {
        #|    "limitId": "codex",
        #|    "limitName": "Codex",
        #|    "primary": {
        #|      "usedPercent": 75,
        #|      "windowDurationMins": 3000000000,
        #|      "resetsAt": 1710000000
        #|    },
        #|    "secondary": null,
        #|    "credits": {
        #|      "hasCredits": true,
        #|      "unlimited": false,
        #|      "balance": "10"
        #|    },
        #|    "planType": "plus",
        #|    "rateLimitReachedType": "rate_limit_reached"
        #|  },
        #|  "rateLimitsByLimitId": null
        #|}
      ),
    ),
  )
  guard response.rate_limits.primary is Some(primary) else {
    fail("expected primary window")
  }
  debug_inspect(primary.used_percent, content="75")
  debug_inspect(primary.window_duration_mins, content="Some(3000000000)")
  debug_inspect(primary.resets_at, content="Some(1710000000)")
  guard response.rate_limits.credits is Some(credits) else {
    fail("expected credits")
  }
  guard credits.has_credits && !credits.unlimited else {
    fail("expected finite credits")
  }
  debug_inspect(response.rate_limits.plan_type, content="Some(AppPlanPlus)")
  debug_inspect(
    response.rate_limits.rate_limit_reached_type,
    content="Some(AppRateLimitReached)",
  )
}

///|
test "parse app-server external agent migration details" {
  let response : AppExternalAgentConfigDetectResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "items": [
        #|    {
        #|      "itemType": "PLUGINS",
        #|      "description": "Plugin migration",
        #|      "cwd": null,
        #|      "details": {
        #|        "plugins": [
        #|          {
        #|            "marketplaceName": "local",
        #|            "pluginNames": ["plugin-1"]
        #|          }
        #|        ],
        #|        "sessions": [
        #|          { "path": "/tmp/session.jsonl", "cwd": "/repo", "title": "Work" }
        #|        ],
        #|        "mcpServers": [{ "name": "mcp" }],
        #|        "hooks": [{ "name": "hook" }],
        #|        "subagents": [{ "name": "agent" }],
        #|        "commands": [{ "name": "cmd" }]
        #|      }
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  debug_inspect(response.items[0].item_type, content="AppMigrationPlugins")
  guard response.items[0].details is Some(details) else {
    fail("expected migration details")
  }
  debug_inspect(details.plugins[0].plugin_names[0], content="\"plugin-1\"")
  debug_inspect(details.sessions[0].title, content="Some(\"Work\")")
  debug_inspect(details.mcp_servers[0].name, content="\"mcp\"")
}

///|
test "parse app-server external agent migration detail defaults" {
  let response : AppExternalAgentConfigDetectResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "items": [
        #|    {
        #|      "itemType": "CONFIG",
        #|      "description": "Config migration",
        #|      "details": {}
        #|    }
        #|  ]
        #|}
      ),
    ),
  )
  guard response.items[0].details is Some(details) else {
    fail("expected migration details")
  }
  debug_inspect(details.plugins.length(), content="0")
  debug_inspect(details.sessions.length(), content="0")
  debug_inspect(details.mcp_servers.length(), content="0")
  debug_inspect(details.hooks.length(), content="0")
  debug_inspect(details.subagents.length(), content="0")
  debug_inspect(details.commands.length(), content="0")
}

///|
test "parse typed app-server marketplace and plugin responses" {
  let marketplace : AppMarketplaceAddResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "marketplaceName": "local",
        #|  "installedRoot": "/tmp/marketplace",
        #|  "alreadyAdded": true
        #|}
      ),
    ),
  )
  guard marketplace.already_added else { fail("expected already added") }
  debug_inspect(
    marketplace.marketplace_name,
    content=(
      #|"local"
    ),
  )
  let plugin_list : AppPluginListResponse = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "marketplaces": [
        #|    {
        #|      "name": "local",
        #|      "path": "/tmp/marketplace.json",
        #|      "interface": { "displayName": "Local" },
        #|      "plugins": [
        #|        {
        #|          "id": "plugin-1",
        #|          "name": "Plugin One",
        #|          "source": { "type": "local", "path": "/tmp/plugin-one" },
        #|          "installed": true,
        #|          "enabled": true,
        #|          "installPolicy": "AVAILABLE",
        #|          "authPolicy": "ON_USE"
        #|        }
        #|      ]
        #|    }
        #|  ],
        #|  "marketplaceLoadErrors": [],
        #|  "featuredPluginIds": ["plugin-1"]
        #|}
      ),
    ),
  )
  debug_inspect(plugin_list.marketplaces.length(), content="1")
  debug_inspect(
    plugin_list.marketplaces[0].plugins[0].name,
    content=(
      #|"Plugin One"
    ),
  )
}
