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
pub(all) struct AppThreadSectionAppearance {
  icon : String?
  color : String?
} derive(Debug)

///|
pub impl ToJson for AppThreadSectionAppearance with fn to_json(appearance) {
  let obj : Map[String, Json] = { "icon": Json::null(), "color": Json::null() }
  if appearance.icon is Some(icon) {
    obj.set("icon", icon.to_json())
  }
  if appearance.color is Some(color) {
    obj.set("color", color.to_json())
  }
  Json::object(obj)
}

///|
pub impl FromJson for AppThreadSectionAppearance with fn from_json(value, path) {
  guard value is { "icon"? : icon, "color"? : color, .. } else {
    raise JsonDecodeError((path, "expected thread section appearance"))
  }
  {
    icon: app_optional_string(icon, path.add_key("icon")),
    color: app_optional_string(color, path.add_key("color")),
  }
}

///|
pub(all) struct AppThreadSection {
  id : String
  name : String
  appearance : AppThreadSectionAppearance?
} derive(Debug)

///|
pub impl FromJson for AppThreadSection with fn from_json(value, path) {
  guard value
    is {
      "id": String(id),
      "name": String(name),
      "appearance"? : appearance,
      ..
    } else {
    raise JsonDecodeError((path, "expected thread section"))
  }
  {
    id,
    name,
    appearance: match appearance {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("appearance")))
    },
  }
}

///|
pub(all) enum AppThreadSectionAppearanceUpdate {
  AppClearThreadSectionAppearance
  AppSetThreadSectionAppearance(AppThreadSectionAppearance)
} derive(Debug)

///|
pub impl ToJson for AppThreadSectionAppearanceUpdate with fn to_json(update) {
  match update {
    AppClearThreadSectionAppearance => Json::null()
    AppSetThreadSectionAppearance(appearance) => appearance.to_json()
  }
}

///|
pub(all) struct AppThreadSectionListParams {
  cursor : String?
  limit : UInt?
} derive(Debug, Default)

///|
pub fn AppThreadSectionListParams::new(
  cursor? : String,
  limit? : UInt,
) -> AppThreadSectionListParams {
  { cursor, limit, }
}

///|
pub impl ToJson for AppThreadSectionListParams with fn to_json(params) {
  let obj : Map[String, Json] = {}
  app_put_string(obj, "cursor", params.cursor)
  if params.limit is Some(limit) {
    obj.set("limit", limit.to_json())
  }
  Json::object(obj)
}

///|
pub struct AppThreadSectionListResponse {
  data : ArrayView[AppThreadSection]
  next_cursor : String?
} derive(Debug)

///|
pub impl FromJson for AppThreadSectionListResponse with fn from_json(
  value,
  path,
) {
  guard value is { "data": data, "nextCursor"? : next_cursor, .. } else {
    raise JsonDecodeError((path, "expected threadSection/list response"))
  }
  {
    data: @json.from_json(data, path=path.add_key("data")),
    next_cursor: app_optional_string(next_cursor, path.add_key("nextCursor")),
  }
}

///|
pub(all) struct AppThreadSectionCreateParams {
  name : String
  appearance : AppThreadSectionAppearanceUpdate?
} derive(Debug)

///|
pub fn AppThreadSectionCreateParams::new(
  name : String,
  appearance? : AppThreadSectionAppearanceUpdate,
) -> AppThreadSectionCreateParams {
  { name, appearance, }
}

///|
pub impl ToJson for AppThreadSectionCreateParams with fn to_json(params) {
  let obj : Map[String, Json] = { "name": params.name }
  if params.appearance is Some(appearance) {
    obj.set("appearance", appearance.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadSectionUpdateParams {
  section_id : String
  name : String
  appearance : AppThreadSectionAppearanceUpdate?
} derive(Debug)

///|
pub impl ToJson for AppThreadSectionUpdateParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "sectionId": params.section_id,
    "name": params.name,
  }
  if params.appearance is Some(appearance) {
    obj.set("appearance", appearance.to_json())
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadSectionResponse {
  section : AppThreadSection
} derive(Debug)

///|
pub impl FromJson for AppThreadSectionResponse with fn from_json(value, path) {
  guard value is { "section": section, .. } else {
    raise JsonDecodeError((path, "expected thread section response"))
  }
  { section: @json.from_json(section, path=path.add_key("section")), }
}

///|
pub(all) struct AppThreadSectionDeleteParams {
  section_id : String
} derive(Debug)

///|
pub impl ToJson for AppThreadSectionDeleteParams with fn to_json(params) {
  { "sectionId": params.section_id }
}

///|
pub(all) struct AppThreadSectionMoveParams {
  thread_id : String
  section_id : AppNullableString
  before_thread_id : AppNullableString?
} derive(Debug)

///|
pub impl ToJson for AppThreadSectionMoveParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "sectionId": params.section_id,
  }
  app_put_nullable_string(obj, "beforeThreadId", params.before_thread_id)
  Json::object(obj)
}

///|
pub async fn CodexAppConnection::thread_delete(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> Unit {
  self.call_empty("thread/delete", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_section_list(
  self : CodexAppConnection,
  params? : AppThreadSectionListParams,
) -> AppThreadSectionListResponse {
  let params = params.unwrap_or_default()
  @json.from_json(self.call_raw("threadSection/list", params=params.to_json()))
}

///|
pub async fn CodexAppConnection::thread_section_create(
  self : CodexAppConnection,
  params : AppThreadSectionCreateParams,
) -> AppThreadSectionResponse {
  @json.from_json(
    self.call_raw("threadSection/create", params=params.to_json()),
  )
}

///|
pub async fn CodexAppConnection::thread_section_update(
  self : CodexAppConnection,
  params : AppThreadSectionUpdateParams,
) -> AppThreadSectionResponse {
  @json.from_json(
    self.call_raw("threadSection/update", params=params.to_json()),
  )
}

///|
pub async fn CodexAppConnection::thread_section_delete(
  self : CodexAppConnection,
  params : AppThreadSectionDeleteParams,
) -> Unit {
  self.call_empty("threadSection/delete", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_section_move(
  self : CodexAppConnection,
  params : AppThreadSectionMoveParams,
) -> Unit {
  self.call_empty("thread/section/move", params=params.to_json())
}

///|
pub async fn CodexAppSession::thread_delete(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> Unit {
  self.connection.thread_delete(params)
}

///|
pub async fn CodexAppSession::thread_section_list(
  self : CodexAppSession,
  params? : AppThreadSectionListParams,
) -> AppThreadSectionListResponse {
  self.connection.thread_section_list(params?)
}

///|
pub async fn CodexAppSession::thread_section_create(
  self : CodexAppSession,
  params : AppThreadSectionCreateParams,
) -> AppThreadSectionResponse {
  self.connection.thread_section_create(params)
}

///|
pub async fn CodexAppSession::thread_section_update(
  self : CodexAppSession,
  params : AppThreadSectionUpdateParams,
) -> AppThreadSectionResponse {
  self.connection.thread_section_update(params)
}

///|
pub async fn CodexAppSession::thread_section_delete(
  self : CodexAppSession,
  params : AppThreadSectionDeleteParams,
) -> Unit {
  self.connection.thread_section_delete(params)
}

///|
pub async fn CodexAppSession::thread_section_move(
  self : CodexAppSession,
  params : AppThreadSectionMoveParams,
) -> Unit {
  self.connection.thread_section_move(params)
}
