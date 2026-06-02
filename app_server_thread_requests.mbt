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
pub(all) struct AppThreadElicitationCounterParams {
  thread_id : String
} derive(Debug)

///|
pub impl ToJson for AppThreadElicitationCounterParams with fn to_json(params) {
  { "threadId": params.thread_id }
}

///|
pub(all) struct AppThreadElicitationCounterResponse {
  count : UInt64
  paused : Bool
} derive(Debug)

///|
pub impl FromJson for AppThreadElicitationCounterResponse with fn from_json(
  value,
  path,
) {
  guard value is { "count": Number(count, ..), "paused": paused, .. } else {
    raise JsonDecodeError(
      (path, "expected thread elicitation counter response"),
    )
  }
  { count: count.to_uint64(), paused: app_bool(paused, path.add_key("paused")) }
}

///|
pub(all) enum AppNullableInt64 {
  AppNullableInt64Null
  AppNullableInt64Value(Int64)
} derive(Debug)

///|
pub impl ToJson for AppNullableInt64 with fn to_json(value) {
  match value {
    AppNullableInt64Null => Json::null()
    AppNullableInt64Value(value) => Json::number(value.to_double())
  }
}

///|
pub impl ToJson for AppThreadGoalStatus with fn to_json(status) {
  match status {
    AppThreadGoalActive => "active".to_json()
    AppThreadGoalPaused => "paused".to_json()
    AppThreadGoalBudgetLimited => "budgetLimited".to_json()
    AppThreadGoalComplete => "complete".to_json()
  }
}

///|
pub(all) struct AppThreadGoalSetParams {
  thread_id : String
  objective : String?
  status : AppThreadGoalStatus?
  token_budget : AppNullableInt64?
} derive(Debug)

///|
pub impl ToJson for AppThreadGoalSetParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "objective": match params.objective {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "status": match params.status {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  if params.token_budget is Some(value) {
    obj.set("tokenBudget", value.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadGoalSetResponse {
  goal : AppThreadGoal
} derive(Debug)

///|
pub impl FromJson for AppThreadGoalSetResponse with fn from_json(value, path) {
  guard value is { "goal": goal, .. } else {
    raise JsonDecodeError((path, "expected thread/goal/set response"))
  }
  { goal: @json.from_json(goal, path=path.add_key("goal")) }
}

///|
pub(all) struct AppThreadGoalGetResponse {
  goal : AppThreadGoal?
} derive(Debug)

///|
pub impl FromJson for AppThreadGoalGetResponse with fn from_json(value, path) {
  guard value is { "goal"? : goal, .. } else {
    raise JsonDecodeError((path, "expected thread/goal/get response"))
  }
  {
    goal: match goal {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("goal")))
    },
  }
}

///|
pub(all) struct AppThreadGoalClearResponse {
  cleared : Bool
} derive(Debug)

///|
pub impl FromJson for AppThreadGoalClearResponse with fn from_json(value, path) {
  guard value is { "cleared": cleared, .. } else {
    raise JsonDecodeError((path, "expected thread/goal/clear response"))
  }
  { cleared: app_bool(cleared, path.add_key("cleared")) }
}

///|
pub(all) enum AppThreadMemoryMode {
  AppThreadMemoryEnabled
  AppThreadMemoryDisabled
} derive(Debug)

///|
pub impl ToJson for AppThreadMemoryMode with fn to_json(mode) {
  match mode {
    AppThreadMemoryEnabled => "enabled".to_json()
    AppThreadMemoryDisabled => "disabled".to_json()
  }
}

///|
pub(all) struct AppThreadMemoryModeSetParams {
  thread_id : String
  mode : AppThreadMemoryMode
} derive(Debug)

///|
pub impl ToJson for AppThreadMemoryModeSetParams with fn to_json(params) {
  { "threadId": params.thread_id, "mode": params.mode }
}

///|
pub(all) struct AppThreadTurnsListParams {
  thread_id : String
  cursor : String?
  limit : UInt?
  sort_direction : AppSortDirection?
} derive(Debug)

///|
pub impl ToJson for AppThreadTurnsListParams with fn to_json(params) {
  {
    "threadId": params.thread_id,
    "cursor": match params.cursor {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "limit": match params.limit {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "sortDirection": match params.sort_direction {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
}

///|
pub(all) struct AppThreadTurnsListResponse {
  data : ArrayView[AppTurn]
  next_cursor : String?
  backwards_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadTurnsListResponse with fn from_json(value, path) {
  guard value
    is {
      "data": data,
      "nextCursor"? : next_cursor,
      "backwardsCursor"? : backwards_cursor,
      ..
    } else {
    raise JsonDecodeError((path, "expected thread/turns/list response"))
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
pub async fn CodexAppConnection::thread_increment_elicitation(
  self : CodexAppConnection,
  params : AppThreadElicitationCounterParams,
) -> AppThreadElicitationCounterResponse {
  @json.from_json(
    self.call_raw("thread/increment_elicitation", params=params.to_json()),
  )
}

///|
pub async fn CodexAppConnection::thread_decrement_elicitation(
  self : CodexAppConnection,
  params : AppThreadElicitationCounterParams,
) -> AppThreadElicitationCounterResponse {
  @json.from_json(
    self.call_raw("thread/decrement_elicitation", params=params.to_json()),
  )
}

///|
pub async fn CodexAppConnection::thread_goal_set(
  self : CodexAppConnection,
  params : AppThreadGoalSetParams,
) -> AppThreadGoalSetResponse {
  @json.from_json(self.call_raw("thread/goal/set", params=params.to_json()))
}

///|
pub async fn CodexAppConnection::thread_goal_get(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadGoalGetResponse {
  @json.from_json(self.call_raw("thread/goal/get", params=params.to_json()))
}

///|
pub async fn CodexAppConnection::thread_goal_clear(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> AppThreadGoalClearResponse {
  @json.from_json(self.call_raw("thread/goal/clear", params=params.to_json()))
}

///|
pub async fn CodexAppConnection::thread_memory_mode_set(
  self : CodexAppConnection,
  params : AppThreadMemoryModeSetParams,
) -> Unit {
  self.call_empty("thread/memoryMode/set", params=params.to_json())
}

///|
pub async fn CodexAppConnection::memory_reset(
  self : CodexAppConnection,
) -> Unit {
  self.call_empty("memory/reset")
}

///|
pub async fn CodexAppConnection::thread_background_terminals_clean(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> Unit {
  self.call_empty("thread/backgroundTerminals/clean", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_turns_list(
  self : CodexAppConnection,
  params : AppThreadTurnsListParams,
) -> AppThreadTurnsListResponse {
  @json.from_json(self.call_raw("thread/turns/list", params=params.to_json()))
}
