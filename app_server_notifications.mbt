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
pub(all) struct AppThreadGoal {
  thread_id : String
  objective : String
  status : AppThreadGoalStatus
  token_budget : Int64?
  tokens_used : Int64
  time_used_seconds : Int64
  created_at : Int64
  updated_at : Int64
} derive(Debug)

///|
pub impl FromJson for AppThreadGoal with fn from_json(value, path) {
  guard value
    is {
      "threadId": String(thread_id),
      "objective": String(objective),
      "status": status,
      "tokenBudget"? : token_budget,
      "tokensUsed": Number(tokens_used, ..),
      "timeUsedSeconds": Number(time_used_seconds, ..),
      "createdAt": Number(created_at, ..),
      "updatedAt": Number(updated_at, ..),
      ..
    } else {
    raise JsonDecodeError((path, "expected thread goal"))
  }
  {
    thread_id,
    objective,
    status: @json.from_json(status, path=path.add_key("status")),
    token_budget: app_optional_int64(token_budget, path.add_key("tokenBudget")),
    tokens_used: tokens_used.to_int64(),
    time_used_seconds: time_used_seconds.to_int64(),
    created_at: created_at.to_int64(),
    updated_at: updated_at.to_int64(),
  }
}

///|
pub(all) enum AppThreadGoalStatus {
  AppThreadGoalActive
  AppThreadGoalPaused
  AppThreadGoalBudgetLimited
  AppThreadGoalComplete
} derive(Debug)

///|
pub impl FromJson for AppThreadGoalStatus with fn from_json(value, path) {
  match value {
    String("active") => AppThreadGoalActive
    String("paused") => AppThreadGoalPaused
    String("budgetLimited") => AppThreadGoalBudgetLimited
    String("complete") => AppThreadGoalComplete
    _ => raise JsonDecodeError((path, "expected thread goal status"))
  }
}

///|
pub(all) struct AppTurnPlanStep {
  step : String
  status : AppTurnPlanStepStatus
} derive(Debug)

///|
pub impl FromJson for AppTurnPlanStep with fn from_json(value, path) {
  guard value is { "step": String(step), "status": status, .. } else {
    raise JsonDecodeError((path, "expected turn plan step"))
  }
  { step, status: @json.from_json(status, path=path.add_key("status")) }
}

///|
pub(all) enum AppTurnPlanStepStatus {
  AppTurnPlanPending
  AppTurnPlanInProgress
  AppTurnPlanCompleted
} derive(Debug)

///|
pub impl FromJson for AppTurnPlanStepStatus with fn from_json(value, path) {
  match value {
    String("pending") => AppTurnPlanPending
    String("inProgress") => AppTurnPlanInProgress
    String("completed") => AppTurnPlanCompleted
    _ => raise JsonDecodeError((path, "expected turn plan step status"))
  }
}

///|
pub(all) enum AppRemoteControlConnectionStatus {
  AppRemoteControlDisabled
  AppRemoteControlConnecting
  AppRemoteControlConnected
  AppRemoteControlErrored
} derive(Debug)

///|
pub impl FromJson for AppRemoteControlConnectionStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("disabled") => AppRemoteControlDisabled
    String("connecting") => AppRemoteControlConnecting
    String("connected") => AppRemoteControlConnected
    String("errored") => AppRemoteControlErrored
    _ => raise JsonDecodeError((path, "expected remote control status"))
  }
}

///|
pub(all) enum AppModelRerouteReason {
  AppModelRerouteHighRiskCyberActivity
} derive(Debug)

///|
pub impl FromJson for AppModelRerouteReason with fn from_json(value, path) {
  match value {
    String("highRiskCyberActivity") => AppModelRerouteHighRiskCyberActivity
    _ => raise JsonDecodeError((path, "expected model reroute reason"))
  }
}

///|
pub(all) enum AppModelVerification {
  AppModelVerificationTrustedAccessForCyber
} derive(Debug)

///|
pub impl FromJson for AppModelVerification with fn from_json(value, path) {
  match value {
    String("trustedAccessForCyber") => AppModelVerificationTrustedAccessForCyber
    _ => raise JsonDecodeError((path, "expected model verification"))
  }
}

///|
pub(all) struct AppTextPosition {
  line : UInt64
  column : UInt64
} derive(Debug)

///|
pub impl FromJson for AppTextPosition with fn from_json(value, path) {
  guard value is { "line": Number(line, ..), "column": Number(column, ..), .. } else {
    raise JsonDecodeError((path, "expected text position"))
  }
  { line: line.to_uint64(), column: column.to_uint64() }
}

///|
pub(all) struct AppTextRange {
  start : AppTextPosition
  end : AppTextPosition
} derive(Debug)

///|
pub impl FromJson for AppTextRange with fn from_json(value, path) {
  guard value is { "start": start, "end": end, .. } else {
    raise JsonDecodeError((path, "expected text range"))
  }
  {
    start: @json.from_json(start, path=path.add_key("start")),
    end: @json.from_json(end, path=path.add_key("end")),
  }
}

///|
pub(all) struct AppHookRunSummary {
  id : String
  event_name : AppHookEventName
  handler_type : AppHookHandlerType
  execution_mode : AppHookExecutionMode
  scope : AppHookScope
  source_path : String
  source : AppHookSource
  display_order : Int64
  status : AppHookRunStatus
  status_message : String?
  started_at : Int64
  completed_at : Int64?
  duration_ms : Int64?
  entries : ArrayView[AppHookOutputEntry]
} derive(Debug)

///|
pub impl FromJson for AppHookRunSummary with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "eventName": event_name,
      "handlerType": handler_type,
      "executionMode": execution_mode,
      "scope": scope,
      "sourcePath": String(source_path),
      "source"? : source,
      "displayOrder": Number(display_order, ..),
      "status": status,
      "statusMessage"? : status_message,
      "startedAt": Number(started_at, ..),
      "completedAt"? : completed_at,
      "durationMs"? : duration_ms,
      "entries": entries,
      ..
    } else {
    raise JsonDecodeError((path, "expected hook run summary"))
  }
  {
    id,
    event_name: @json.from_json(event_name, path=path.add_key("eventName")),
    handler_type: @json.from_json(
      handler_type,
      path=path.add_key("handlerType"),
    ),
    execution_mode: @json.from_json(
      execution_mode,
      path=path.add_key("executionMode"),
    ),
    scope: @json.from_json(scope, path=path.add_key("scope")),
    source_path,
    source: match source {
      Some(Null) | None => AppHookUnknownSource
      Some(value) => @json.from_json(value, path=path.add_key("source"))
    },
    display_order: display_order.to_int64(),
    status: @json.from_json(status, path=path.add_key("status")),
    status_message: app_optional_string(
      status_message,
      path.add_key("statusMessage"),
    ),
    started_at: started_at.to_int64(),
    completed_at: app_optional_int64(completed_at, path.add_key("completedAt")),
    duration_ms: app_optional_int64(duration_ms, path.add_key("durationMs")),
    entries: @json.from_json(entries, path=path.add_key("entries")),
  }
}

///|
pub(all) enum AppHookExecutionMode {
  AppHookSyncExecution
  AppHookAsyncExecution
} derive(Debug)

///|
pub impl FromJson for AppHookExecutionMode with fn from_json(value, path) {
  match value {
    String("sync") => AppHookSyncExecution
    String("async") => AppHookAsyncExecution
    _ => raise JsonDecodeError((path, "expected hook execution mode"))
  }
}

///|
pub(all) enum AppHookScope {
  AppHookThreadScope
  AppHookTurnScope
} derive(Debug)

///|
pub impl FromJson for AppHookScope with fn from_json(value, path) {
  match value {
    String("thread") => AppHookThreadScope
    String("turn") => AppHookTurnScope
    _ => raise JsonDecodeError((path, "expected hook scope"))
  }
}

///|
pub(all) enum AppHookRunStatus {
  AppHookRunning
  AppHookCompleted
  AppHookFailed
  AppHookBlocked
  AppHookStopped
} derive(Debug)

///|
pub impl FromJson for AppHookRunStatus with fn from_json(value, path) {
  match value {
    String("running") => AppHookRunning
    String("completed") => AppHookCompleted
    String("failed") => AppHookFailed
    String("blocked") => AppHookBlocked
    String("stopped") => AppHookStopped
    _ => raise JsonDecodeError((path, "expected hook run status"))
  }
}

///|
pub(all) struct AppHookOutputEntry {
  kind : AppHookOutputEntryKind
  text : String
} derive(Debug)

///|
pub impl FromJson for AppHookOutputEntry with fn from_json(value, path) {
  guard value is { "kind": kind, "text": String(text), .. } else {
    raise JsonDecodeError((path, "expected hook output entry"))
  }
  { kind: @json.from_json(kind, path=path.add_key("kind")), text }
}

///|
pub(all) enum AppHookOutputEntryKind {
  AppHookOutputWarning
  AppHookOutputStop
  AppHookOutputFeedback
  AppHookOutputContext
  AppHookOutputError
} derive(Debug)

///|
pub impl FromJson for AppHookOutputEntryKind with fn from_json(value, path) {
  match value {
    String("warning") => AppHookOutputWarning
    String("stop") => AppHookOutputStop
    String("feedback") => AppHookOutputFeedback
    String("context") => AppHookOutputContext
    String("error") => AppHookOutputError
    _ => raise JsonDecodeError((path, "expected hook output entry kind"))
  }
}

///|
pub(all) enum AppRealtimeConversationVersion {
  AppRealtimeConversationV1
  AppRealtimeConversationV2
} derive(Debug)

///|
pub impl FromJson for AppRealtimeConversationVersion with fn from_json(
  value,
  path,
) {
  match value {
    String("v1") => AppRealtimeConversationV1
    String("v2") => AppRealtimeConversationV2
    _ => raise JsonDecodeError((path, "expected realtime conversation version"))
  }
}

///|
pub(all) struct AppThreadRealtimeAudioChunk {
  data : String
  sample_rate : UInt
  num_channels : UInt
  samples_per_channel : UInt?
  item_id : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadRealtimeAudioChunk with fn from_json(value, path) {
  guard value
    is {
      "data": String(data),
      "sampleRate": Number(sample_rate, ..),
      "numChannels": Number(num_channels, ..),
      "samplesPerChannel"? : samples_per_channel,
      "itemId"? : item_id,
      ..
    } else {
    raise JsonDecodeError((path, "expected realtime audio chunk"))
  }
  {
    data,
    sample_rate: sample_rate.to_uint(),
    num_channels: num_channels.to_uint(),
    samples_per_channel: app_optional_uint(
      samples_per_channel,
      path.add_key("samplesPerChannel"),
    ),
    item_id: app_optional_string(item_id, path.add_key("itemId")),
  }
}

///|
pub(all) struct AppGuardianApprovalReview {
  status : AppGuardianApprovalReviewStatus
  risk_level : AppGuardianRiskLevel?
  user_authorization : AppGuardianUserAuthorization?
  rationale : String?
} derive(Debug)

///|
pub impl FromJson for AppGuardianApprovalReview with fn from_json(value, path) {
  guard value
    is {
      "status": status,
      "riskLevel"? : risk_level,
      "userAuthorization"? : user_authorization,
      "rationale"? : rationale,
      ..
    } else {
    raise JsonDecodeError((path, "expected guardian approval review"))
  }
  {
    status: @json.from_json(status, path=path.add_key("status")),
    risk_level: match risk_level {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("riskLevel")))
    },
    user_authorization: match user_authorization {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("userAuthorization")))
    },
    rationale: app_optional_string(rationale, path.add_key("rationale")),
  }
}

///|
pub(all) enum AppGuardianApprovalReviewStatus {
  AppGuardianReviewInProgress
  AppGuardianReviewApproved
  AppGuardianReviewDenied
  AppGuardianReviewTimedOut
  AppGuardianReviewAborted
} derive(Debug)

///|
pub impl FromJson for AppGuardianApprovalReviewStatus with fn from_json(
  value,
  path,
) {
  match value {
    String("inProgress") => AppGuardianReviewInProgress
    String("approved") => AppGuardianReviewApproved
    String("denied") => AppGuardianReviewDenied
    String("timedOut") => AppGuardianReviewTimedOut
    String("aborted") => AppGuardianReviewAborted
    _ => raise JsonDecodeError((path, "expected guardian review status"))
  }
}

///|
pub(all) enum AppAutoReviewDecisionSource {
  AppAutoReviewDecisionAgent
} derive(Debug)

///|
pub impl FromJson for AppAutoReviewDecisionSource with fn from_json(value, path) {
  match value {
    String("agent") => AppAutoReviewDecisionAgent
    _ => raise JsonDecodeError((path, "expected auto-review decision source"))
  }
}

///|
pub(all) enum AppGuardianRiskLevel {
  AppGuardianRiskLow
  AppGuardianRiskMedium
  AppGuardianRiskHigh
  AppGuardianRiskCritical
} derive(Debug)

///|
pub impl FromJson for AppGuardianRiskLevel with fn from_json(value, path) {
  match value {
    String("low") => AppGuardianRiskLow
    String("medium") => AppGuardianRiskMedium
    String("high") => AppGuardianRiskHigh
    String("critical") => AppGuardianRiskCritical
    _ => raise JsonDecodeError((path, "expected guardian risk level"))
  }
}

///|
pub(all) enum AppGuardianUserAuthorization {
  AppGuardianUserAuthorizationUnknown
  AppGuardianUserAuthorizationLow
  AppGuardianUserAuthorizationMedium
  AppGuardianUserAuthorizationHigh
} derive(Debug)

///|
pub impl FromJson for AppGuardianUserAuthorization with fn from_json(
  value,
  path,
) {
  match value {
    String("unknown") => AppGuardianUserAuthorizationUnknown
    String("low") => AppGuardianUserAuthorizationLow
    String("medium") => AppGuardianUserAuthorizationMedium
    String("high") => AppGuardianUserAuthorizationHigh
    _ => raise JsonDecodeError((path, "expected guardian user authorization"))
  }
}

///|
pub(all) enum AppGuardianCommandSource {
  AppGuardianCommandSourceShell
  AppGuardianCommandSourceUnifiedExec
} derive(Debug)

///|
pub impl FromJson for AppGuardianCommandSource with fn from_json(value, path) {
  match value {
    String("shell") => AppGuardianCommandSourceShell
    String("unifiedExec") => AppGuardianCommandSourceUnifiedExec
    _ => raise JsonDecodeError((path, "expected guardian command source"))
  }
}

///|
pub(all) enum AppGuardianApprovalReviewAction {
  AppGuardianCommandAction(
    source~ : AppGuardianCommandSource,
    command~ : String,
    cwd~ : String
  )
  AppGuardianExecveAction(
    source~ : AppGuardianCommandSource,
    program~ : String,
    argv~ : ArrayView[String],
    cwd~ : String
  )
  AppGuardianApplyPatchAction(cwd~ : String, files~ : ArrayView[String])
  AppGuardianNetworkAccessAction(
    target~ : String,
    host~ : String,
    protocol~ : AppNetworkApprovalProtocol,
    port~ : UInt
  )
  AppGuardianMcpToolCallAction(
    server~ : String,
    tool_name~ : String,
    connector_id~ : String?,
    connector_name~ : String?,
    tool_title~ : String?
  )
  AppGuardianRequestPermissionsAction(
    reason~ : String?,
    permissions~ : AppRequestPermissionProfile
  )
} derive(Debug)

///|
pub impl FromJson for AppGuardianApprovalReviewAction with fn from_json(
  value,
  path,
) {
  guard value is { "type": String(action_type), .. } else {
    raise JsonDecodeError((path, "expected guardian review action"))
  }
  match action_type {
    "command" => {
      guard value
        is {
          "source": source,
          "command": String(command),
          "cwd": String(cwd),
          ..
        } else {
        raise JsonDecodeError((path, "expected guardian command action"))
      }
      AppGuardianCommandAction(
        source=@json.from_json(source, path=path.add_key("source")),
        command~,
        cwd~,
      )
    }
    "execve" => {
      guard value
        is {
          "source": source,
          "program": String(program),
          "argv": argv,
          "cwd": String(cwd),
          ..
        } else {
        raise JsonDecodeError((path, "expected guardian execve action"))
      }
      AppGuardianExecveAction(
        source=@json.from_json(source, path=path.add_key("source")),
        program~,
        argv=@json.from_json(argv, path=path.add_key("argv")),
        cwd~,
      )
    }
    "applyPatch" => {
      guard value is { "cwd": String(cwd), "files": files, .. } else {
        raise JsonDecodeError((path, "expected guardian apply-patch action"))
      }
      AppGuardianApplyPatchAction(
        cwd~,
        files=@json.from_json(files, path=path.add_key("files")),
      )
    }
    "networkAccess" => {
      guard value
        is {
          "target": String(target),
          "host": String(host),
          "protocol": protocol,
          "port": Number(port, ..),
          ..
        } else {
        raise JsonDecodeError((path, "expected guardian network action"))
      }
      AppGuardianNetworkAccessAction(
        target~,
        host~,
        protocol=@json.from_json(protocol, path=path.add_key("protocol")),
        port=port.to_uint(),
      )
    }
    "mcpToolCall" => {
      guard value
        is {
          "server": String(server),
          "toolName": String(tool_name),
          "connectorId"? : connector_id,
          "connectorName"? : connector_name,
          "toolTitle"? : tool_title,
          ..
        } else {
        raise JsonDecodeError((path, "expected guardian MCP tool call action"))
      }
      AppGuardianMcpToolCallAction(
        server~,
        tool_name~,
        connector_id=app_optional_string(
          connector_id,
          path.add_key("connectorId"),
        ),
        connector_name=app_optional_string(
          connector_name,
          path.add_key("connectorName"),
        ),
        tool_title=app_optional_string(tool_title, path.add_key("toolTitle")),
      )
    }
    "requestPermissions" => {
      guard value is { "reason"? : reason, "permissions": permissions, .. } else {
        raise JsonDecodeError(
          (path, "expected guardian request-permissions action"),
        )
      }
      AppGuardianRequestPermissionsAction(
        reason=app_optional_string(reason, path.add_key("reason")),
        permissions=@json.from_json(
          permissions,
          path=path.add_key("permissions"),
        ),
      )
    }
    _ =>
      raise JsonDecodeError(
        (path.add_key("type"), "expected guardian action type"),
      )
  }
}
