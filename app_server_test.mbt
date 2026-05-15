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
      "choice": AppToolRequestUserInputAnswer::{ answers: ["first"] },
    }).to_json(),
    content=(
      #|Object({ "answers": Object({ "choice": Object({ "answers": Array([String("first")]) }) }) })
    ),
  )
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
        #|    "startedAtMs": 123,
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
      debug_inspect(event.timestamp_ms, content="123")
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
test "parse app-server thread status notification" {
  let event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "thread/status/changed",
        #|  "params": {
        #|    "threadId": "thread-1",
        #|    "status": { "type": "active", "activeFlags": [] }
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
      guard status is ThreadActive(active_flags~) && active_flags.length() == 0 else {
        fail("expected active status")
      }
    }
    _ => fail("expected thread status notification")
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
        #|    "startedAtMs": 123
        #|  }
        #|}
      ),
    ),
  )
  match message {
    Request(request) => {
      debug_inspect(request.id, content="IntId(7)")
      debug_inspect(
        request.rpc_method,
        content=(
          #|"item/commandExecution/requestApproval"
        ),
      )
      guard request.params is Some(_) else { fail("expected raw params") }
      match request.details {
        AppCommandExecutionApprovalRequest(command_request) =>
          debug_inspect(
            command_request.item_id,
            content=(
              #|"cmd-1"
            ),
          )
        _ => fail("expected typed command approval request")
      }
    }
    _ => fail("expected app-server request")
  }
}

///|
test "parse app-server unknown notification as raw" {
  let event : AppServerEvent = @json.from_json(
    @json.parse(
      (
        #|{
        #|  "method": "future/event",
        #|  "params": { "value": 1 }
        #|}
      ),
    ),
  )
  match event {
    AppRaw(rpc_method~, params~) => {
      debug_inspect(
        rpc_method,
        content=(
          #|"future/event"
        ),
      )
      guard params is Some(_) else { fail("expected preserved params") }
    }
    _ => fail("expected raw event")
  }
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
        #|        "totalTokens": 20,
        #|        "inputTokens": 10,
        #|        "cachedInputTokens": 3,
        #|        "outputTokens": 7,
        #|        "reasoningOutputTokens": 5
        #|      },
        #|      "last": {
        #|        "totalTokens": 20,
        #|        "inputTokens": 10,
        #|        "cachedInputTokens": 3,
        #|        "outputTokens": 7,
        #|        "reasoningOutputTokens": 5
        #|      },
        #|      "modelContextWindow": null
        #|    }
        #|  }
        #|}
      ),
    ),
  )
  match event {
    AppThreadTokenUsageUpdated(token_usage~, ..) =>
      debug_inspect(
        token_usage.last,
        content=(
          #|{
          #|  input_tokens: 10,
          #|  cached_input_tokens: 3,
          #|  output_tokens: 7,
          #|  reasoning_output_tokens: 5,
          #|}
        ),
      )
    _ => fail("expected token usage notification")
  }
}
