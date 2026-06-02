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
pub(all) struct AppPermissionsRequestApprovalRequest {
  thread_id : String
  turn_id : String
  item_id : String
  started_at_ms : Int64
  cwd : String
  reason : String?
  permissions : AppRequestPermissionProfile
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppPermissionsRequestApprovalRequest with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId": String(turn_id),
      "itemId": String(item_id),
      "startedAtMs": Number(started_at_ms, ..),
      "cwd": String(cwd),
      "reason"? : reason,
      "permissions": permissions,
      ..
    } else {
    raise JsonDecodeError((path, "expected permissions approval request"))
  }
  {
    thread_id,
    turn_id,
    item_id,
    started_at_ms: started_at_ms.to_int64(),
    cwd,
    reason: app_optional_string(reason, path.add_key("reason")),
    permissions: @json.from_json(permissions, path=path.add_key("permissions")),
    raw: value,
  }
}

///|
pub(all) struct AppRequestPermissionProfile {
  network : AppAdditionalNetworkPermissions?
  file_system : AppAdditionalFileSystemPermissions?
} derive(Debug)

///|
pub impl FromJson for AppRequestPermissionProfile with fn from_json(value, path) {
  guard value is { "network"? : network, "fileSystem"? : file_system, .. } else {
    raise JsonDecodeError((path, "expected request permission profile"))
  }
  {
    network: match network {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("network")))
    },
    file_system: match file_system {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("fileSystem")))
    },
  }
}

///|
pub(all) struct AppGrantedPermissionProfile {
  network : AppAdditionalNetworkPermissions?
  file_system : AppAdditionalFileSystemPermissions?
} derive(Debug)

///|
pub impl ToJson for AppGrantedPermissionProfile with fn to_json(profile) {
  let obj : Map[String, Json] = {}
  if profile.network is Some(network) {
    obj.set("network", network.to_json())
  }
  if profile.file_system is Some(file_system) {
    obj.set("fileSystem", file_system.to_json())
  }
  Json::object(obj)
}

///|
pub impl FromJson for AppGrantedPermissionProfile with fn from_json(value, path) {
  guard value is { "network"? : network, "fileSystem"? : file_system, .. } else {
    raise JsonDecodeError((path, "expected granted permission profile"))
  }
  {
    network: match network {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("network")))
    },
    file_system: match file_system {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("fileSystem")))
    },
  }
}

///|
pub(all) struct AppAdditionalNetworkPermissions {
  enabled : Bool?
} derive(Debug)

///|
pub impl ToJson for AppAdditionalNetworkPermissions with fn to_json(permissions) {
  {
    "enabled": match permissions.enabled {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
}

///|
pub impl FromJson for AppAdditionalNetworkPermissions with fn from_json(
  value,
  path,
) {
  guard value is { "enabled"? : enabled, .. } else {
    raise JsonDecodeError((path, "expected additional network permissions"))
  }
  { enabled: app_optional_bool(enabled, path.add_key("enabled")) }
}

///|
pub(all) struct AppAdditionalFileSystemPermissions {
  read : ArrayView[String]?
  write : ArrayView[String]?
  glob_scan_max_depth : UInt64?
  entries : ArrayView[AppFileSystemSandboxEntry]?
} derive(Debug)

///|
pub impl ToJson for AppAdditionalFileSystemPermissions with fn to_json(
  permissions,
) {
  let obj : Map[String, Json] = {
    "read": match permissions.read {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "write": match permissions.write {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  app_put_uint64(obj, "globScanMaxDepth", permissions.glob_scan_max_depth)
  if permissions.entries is Some(entries) {
    obj.set("entries", entries.to_json())
  }
  Json::object(obj)
}

///|
pub impl FromJson for AppAdditionalFileSystemPermissions with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "read"? : read,
      "write"? : write,
      "globScanMaxDepth"? : glob_scan_max_depth,
      "entries"? : entries,
      ..
    } else {
    raise JsonDecodeError((path, "expected additional filesystem permissions"))
  }
  {
    read: match read {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("read")))
    },
    write: match write {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("write")))
    },
    glob_scan_max_depth: app_optional_uint64(
      glob_scan_max_depth,
      path.add_key("globScanMaxDepth"),
    ),
    entries: match entries {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("entries")))
    },
  }
}

///|
pub(all) struct AppFileSystemSandboxEntry {
  path : AppFileSystemPath
  access : AppFileSystemAccessMode
} derive(Debug)

///|
pub impl ToJson for AppFileSystemSandboxEntry with fn to_json(entry) {
  { "path": entry.path, "access": entry.access }
}

///|
pub impl FromJson for AppFileSystemSandboxEntry with fn from_json(value, path) {
  guard value is { "path": entry_path, "access": access, .. } else {
    raise JsonDecodeError((path, "expected filesystem sandbox entry"))
  }
  {
    path: @json.from_json(entry_path, path=path.add_key("path")),
    access: @json.from_json(access, path=path.add_key("access")),
  }
}

///|
pub(all) enum AppFileSystemAccessMode {
  AppFileSystemReadAccess
  AppFileSystemWriteAccess
  AppFileSystemNoAccess
} derive(Debug)

///|
pub impl ToJson for AppFileSystemAccessMode with fn to_json(access) {
  match access {
    AppFileSystemReadAccess => "read".to_json()
    AppFileSystemWriteAccess => "write".to_json()
    AppFileSystemNoAccess => "none".to_json()
  }
}

///|
pub impl FromJson for AppFileSystemAccessMode with fn from_json(value, path) {
  match value {
    String("read") => AppFileSystemReadAccess
    String("write") => AppFileSystemWriteAccess
    String("none") => AppFileSystemNoAccess
    _ => raise JsonDecodeError((path, "expected filesystem access mode"))
  }
}

///|
pub(all) enum AppFileSystemPath {
  AppFileSystemAbsolutePath(path~ : String)
  AppFileSystemGlobPattern(pattern~ : String)
  AppFileSystemSpecialPath(value~ : AppFileSystemSpecialPath)
} derive(Debug)

///|
pub impl ToJson for AppFileSystemPath with fn to_json(path) {
  match path {
    AppFileSystemAbsolutePath(path~) => { "type": "path", "path": path }
    AppFileSystemGlobPattern(pattern~) =>
      { "type": "glob_pattern", "pattern": pattern }
    AppFileSystemSpecialPath(value~) =>
      { "type": "special", "value": value.to_json() }
  }
}

///|
pub impl FromJson for AppFileSystemPath with fn from_json(value, path) {
  guard value is { "type": String(path_type), .. } else {
    raise JsonDecodeError((path, "expected filesystem path"))
  }
  match path_type {
    "path" => {
      guard value is { "path": String(fs_path), .. } else {
        raise JsonDecodeError((path, "expected filesystem path value"))
      }
      AppFileSystemAbsolutePath(path=fs_path)
    }
    "glob_pattern" => {
      guard value is { "pattern": String(pattern), .. } else {
        raise JsonDecodeError((path, "expected filesystem glob pattern"))
      }
      AppFileSystemGlobPattern(pattern~)
    }
    "special" => {
      guard value is { "value": special, .. } else {
        raise JsonDecodeError((path, "expected filesystem special path"))
      }
      AppFileSystemSpecialPath(
        value=@json.from_json(special, path=path.add_key("value")),
      )
    }
    _ => raise JsonDecodeError((path, "expected filesystem path type"))
  }
}

///|
pub(all) enum AppFileSystemSpecialPath {
  AppFileSystemRoot
  AppFileSystemMinimal
  AppFileSystemProjectRoots(subpath~ : String?)
  AppFileSystemTmpdir
  AppFileSystemSlashTmp
  AppFileSystemUnknown(path~ : String, subpath~ : String?)
} derive(Debug)

///|
pub impl ToJson for AppFileSystemSpecialPath with fn to_json(special) {
  match special {
    AppFileSystemRoot => { "kind": "root" }
    AppFileSystemMinimal => { "kind": "minimal" }
    AppFileSystemProjectRoots(subpath~) =>
      {
        "kind": "project_roots",
        "subpath": match subpath {
          Some(value) => value.to_json()
          None => Json::null()
        },
      }
    AppFileSystemTmpdir => { "kind": "tmpdir" }
    AppFileSystemSlashTmp => { "kind": "slash_tmp" }
    AppFileSystemUnknown(path~, subpath~) =>
      {
        "kind": "unknown",
        "path": path,
        "subpath": match subpath {
          Some(value) => value.to_json()
          None => Json::null()
        },
      }
  }
}

///|
pub impl FromJson for AppFileSystemSpecialPath with fn from_json(value, path) {
  guard value is { "kind": String(kind), .. } else {
    raise JsonDecodeError((path, "expected filesystem special path"))
  }
  match kind {
    "root" => AppFileSystemRoot
    "minimal" => AppFileSystemMinimal
    "project_roots" | "current_working_directory" => {
      guard value is { "subpath"? : subpath, .. } else {
        raise JsonDecodeError((path, "expected project roots special path"))
      }
      AppFileSystemProjectRoots(
        subpath=app_optional_string(subpath, path.add_key("subpath")),
      )
    }
    "tmpdir" => AppFileSystemTmpdir
    "slash_tmp" => AppFileSystemSlashTmp
    "unknown" => {
      guard value is { "path": String(unknown_path), "subpath"? : subpath, .. } else {
        raise JsonDecodeError((path, "expected unknown special path"))
      }
      AppFileSystemUnknown(
        path=unknown_path,
        subpath=app_optional_string(subpath, path.add_key("subpath")),
      )
    }
    _ => raise JsonDecodeError((path, "expected filesystem special path kind"))
  }
}

///|
pub(all) enum AppPermissionGrantScope {
  AppPermissionGrantTurn
  AppPermissionGrantSession
} derive(Debug)

///|
pub impl ToJson for AppPermissionGrantScope with fn to_json(scope) {
  match scope {
    AppPermissionGrantTurn => "turn".to_json()
    AppPermissionGrantSession => "session".to_json()
  }
}

///|
pub impl FromJson for AppPermissionGrantScope with fn from_json(value, path) {
  match value {
    String("turn") => AppPermissionGrantTurn
    String("session") => AppPermissionGrantSession
    _ => raise JsonDecodeError((path, "expected permission grant scope"))
  }
}

///|
pub(all) struct AppChatgptAuthTokensRefreshRequest {
  reason : AppChatgptAuthTokensRefreshReason
  previous_account_id : String?
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppChatgptAuthTokensRefreshRequest with fn from_json(
  value,
  path,
) {
  guard value is { "reason": reason, "previousAccountId"? : previous, .. } else {
    raise JsonDecodeError(
      (path, "expected ChatGPT auth tokens refresh request"),
    )
  }
  {
    reason: @json.from_json(reason, path=path.add_key("reason")),
    previous_account_id: app_optional_string(
      previous,
      path.add_key("previousAccountId"),
    ),
    raw: value,
  }
}

///|
pub(all) enum AppChatgptAuthTokensRefreshReason {
  AppChatgptAuthTokensUnauthorized
} derive(Debug)

///|
pub impl FromJson for AppChatgptAuthTokensRefreshReason with fn from_json(
  value,
  path,
) {
  match value {
    String("unauthorized") => AppChatgptAuthTokensUnauthorized
    _ =>
      raise JsonDecodeError(
        (path, "expected ChatGPT auth tokens refresh reason"),
      )
  }
}

///|
pub(all) struct AppMcpServerElicitationRequest {
  thread_id : String
  turn_id : String?
  server_name : String
  elicitation : AppMcpServerElicitationContent
  priv raw : Json
} derive(Debug)

///|
pub impl FromJson for AppMcpServerElicitationRequest with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "threadId": String(thread_id),
      "turnId"? : turn_id,
      "serverName": String(server_name),
      "mode": String(mode),
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP server elicitation request"))
  }
  {
    thread_id,
    turn_id: app_optional_string(turn_id, path.add_key("turnId")),
    server_name,
    elicitation: match mode {
      "form" => @json.from_json(value, path~)
      "url" => @json.from_json(value, path~)
      _ =>
        raise JsonDecodeError(
          (path.add_key("mode"), "expected MCP elicitation mode"),
        )
    },
    raw: value,
  }
}

///|
pub(all) enum AppMcpServerElicitationContent {
  AppMcpElicitationForm(
    meta~ : Json?,
    message~ : String,
    requested_schema~ : AppMcpElicitationSchema
  )
  AppMcpElicitationUrl(
    meta~ : Json?,
    message~ : String,
    url~ : String,
    elicitation_id~ : String
  )
} derive(Debug)

///|
pub impl FromJson for AppMcpServerElicitationContent with fn from_json(
  value,
  path,
) {
  guard value
    is { "mode": String(mode), "_meta"? : meta, "message": String(message), .. } else {
    raise JsonDecodeError((path, "expected MCP elicitation content"))
  }
  match mode {
    "form" => {
      guard value is { "requestedSchema": requested_schema, .. } else {
        raise JsonDecodeError((path, "expected MCP form elicitation content"))
      }
      AppMcpElicitationForm(
        meta=app_optional_json(meta),
        message~,
        requested_schema=@json.from_json(
          requested_schema,
          path=path.add_key("requestedSchema"),
        ),
      )
    }
    "url" => {
      guard value
        is { "url": String(url), "elicitationId": String(elicitation_id), .. } else {
        raise JsonDecodeError((path, "expected MCP URL elicitation content"))
      }
      AppMcpElicitationUrl(
        meta=app_optional_json(meta),
        message~,
        url~,
        elicitation_id~,
      )
    }
    _ =>
      raise JsonDecodeError(
        (path.add_key("mode"), "expected MCP elicitation mode"),
      )
  }
}

///|
pub(all) enum AppMcpServerElicitationAction {
  AppMcpElicitationAccept
  AppMcpElicitationDecline
  AppMcpElicitationCancel
} derive(Debug)

///|
pub impl ToJson for AppMcpServerElicitationAction with fn to_json(action) {
  match action {
    AppMcpElicitationAccept => "accept".to_json()
    AppMcpElicitationDecline => "decline".to_json()
    AppMcpElicitationCancel => "cancel".to_json()
  }
}

///|
pub(all) struct AppMcpElicitationSchema {
  schema_uri : String?
  object_type : AppMcpElicitationObjectType
  properties : Map[String, AppMcpElicitationPrimitiveSchema]
  required : ArrayView[String]?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationSchema with fn from_json(value, path) {
  guard value
    is {
      "$schema"? : schema_uri,
      "type": object_type,
      "properties": properties,
      "required"? : required,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP elicitation schema"))
  }
  {
    schema_uri: app_optional_string(schema_uri, path.add_key("$schema")),
    object_type: @json.from_json(object_type, path=path.add_key("type")),
    properties: @json.from_json(properties, path=path.add_key("properties")),
    required: match required {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("required")))
    },
  }
}

///|
pub(all) enum AppMcpElicitationObjectType {
  AppMcpElicitationObject
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationObjectType with fn from_json(value, path) {
  match value {
    String("object") => AppMcpElicitationObject
    _ => raise JsonDecodeError((path, "expected MCP elicitation object type"))
  }
}

///|
pub(all) enum AppMcpElicitationPrimitiveSchema {
  AppMcpElicitationString(AppMcpElicitationStringSchema)
  AppMcpElicitationNumber(AppMcpElicitationNumberSchema)
  AppMcpElicitationBoolean(AppMcpElicitationBooleanSchema)
  AppMcpElicitationStringEnum(AppMcpElicitationStringEnumSchema)
  AppMcpElicitationTitledStringEnum(AppMcpElicitationTitledStringEnumSchema)
  AppMcpElicitationUntitledMultiSelect(
    AppMcpElicitationUntitledMultiSelectSchema
  )
  AppMcpElicitationTitledMultiSelect(AppMcpElicitationTitledMultiSelectSchema)
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationPrimitiveSchema with fn from_json(
  value,
  path,
) {
  guard value is { "type": String(schema_type), .. } else {
    raise JsonDecodeError((path, "expected MCP elicitation primitive schema"))
  }
  match schema_type {
    "boolean" => AppMcpElicitationBoolean(@json.from_json(value, path~))
    "number" | "integer" =>
      AppMcpElicitationNumber(@json.from_json(value, path~))
    "string" =>
      match value {
        { "oneOf": _, .. } =>
          AppMcpElicitationTitledStringEnum(@json.from_json(value, path~))
        { "enum": _, .. } =>
          AppMcpElicitationStringEnum(@json.from_json(value, path~))
        _ => AppMcpElicitationString(@json.from_json(value, path~))
      }
    "array" =>
      match value {
        { "items": { "enum": _, .. }, .. } =>
          AppMcpElicitationUntitledMultiSelect(@json.from_json(value, path~))
        { "items": { "anyOf": _, .. }, .. } =>
          AppMcpElicitationTitledMultiSelect(@json.from_json(value, path~))
        { "items": { "oneOf": _, .. }, .. } =>
          AppMcpElicitationTitledMultiSelect(@json.from_json(value, path~))
        _ =>
          raise JsonDecodeError(
            (path.add_key("items"), "expected MCP enum items"),
          )
      }
    _ =>
      raise JsonDecodeError((path.add_key("type"), "expected MCP schema type"))
  }
}

///|
pub(all) struct AppMcpElicitationStringSchema {
  title : String?
  description : String?
  min_length : UInt?
  max_length : UInt?
  format : AppMcpElicitationStringFormat?
  default : String?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationStringSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("string"),
      "title"? : title,
      "description"? : description,
      "minLength"? : min_length,
      "maxLength"? : max_length,
      "format"? : format,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP string schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    min_length: app_optional_uint(min_length, path.add_key("minLength")),
    max_length: app_optional_uint(max_length, path.add_key("maxLength")),
    format: match format {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("format")))
    },
    default: app_optional_string(default, path.add_key("default")),
  }
}

///|
pub(all) enum AppMcpElicitationStringFormat {
  AppMcpElicitationEmailFormat
  AppMcpElicitationUriFormat
  AppMcpElicitationDateFormat
  AppMcpElicitationDateTimeFormat
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationStringFormat with fn from_json(
  value,
  path,
) {
  match value {
    String("email") => AppMcpElicitationEmailFormat
    String("uri") => AppMcpElicitationUriFormat
    String("date") => AppMcpElicitationDateFormat
    String("date-time") => AppMcpElicitationDateTimeFormat
    _ => raise JsonDecodeError((path, "expected MCP string format"))
  }
}

///|
pub(all) struct AppMcpElicitationNumberSchema {
  number_type : AppMcpElicitationNumberType
  title : String?
  description : String?
  minimum : Double?
  maximum : Double?
  default : Double?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationNumberSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": number_type,
      "title"? : title,
      "description"? : description,
      "minimum"? : minimum,
      "maximum"? : maximum,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP number schema"))
  }
  {
    number_type: @json.from_json(number_type, path=path.add_key("type")),
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    minimum: app_optional_double(minimum, path.add_key("minimum")),
    maximum: app_optional_double(maximum, path.add_key("maximum")),
    default: app_optional_double(default, path.add_key("default")),
  }
}

///|
pub(all) enum AppMcpElicitationNumberType {
  AppMcpElicitationNumberTypeNumber
  AppMcpElicitationNumberTypeInteger
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationNumberType with fn from_json(value, path) {
  match value {
    String("number") => AppMcpElicitationNumberTypeNumber
    String("integer") => AppMcpElicitationNumberTypeInteger
    _ => raise JsonDecodeError((path, "expected MCP number type"))
  }
}

///|
pub(all) struct AppMcpElicitationBooleanSchema {
  title : String?
  description : String?
  default : Bool?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationBooleanSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("boolean"),
      "title"? : title,
      "description"? : description,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP boolean schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    default: app_optional_bool(default, path.add_key("default")),
  }
}

///|
pub(all) struct AppMcpElicitationStringEnumSchema {
  title : String?
  description : String?
  enum_values : ArrayView[String]
  enum_names : ArrayView[String]?
  default : String?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationStringEnumSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("string"),
      "title"? : title,
      "description"? : description,
      "enum": enum_values,
      "enumNames"? : enum_names,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP string enum schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    enum_values: @json.from_json(enum_values, path=path.add_key("enum")),
    enum_names: match enum_names {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("enumNames")))
    },
    default: app_optional_string(default, path.add_key("default")),
  }
}

///|
pub(all) struct AppMcpElicitationTitledStringEnumSchema {
  title : String?
  description : String?
  one_of : ArrayView[AppMcpElicitationConstOption]
  default : String?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationTitledStringEnumSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("string"),
      "title"? : title,
      "description"? : description,
      "oneOf": one_of,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP titled string enum schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    one_of: @json.from_json(one_of, path=path.add_key("oneOf")),
    default: app_optional_string(default, path.add_key("default")),
  }
}

///|
pub(all) struct AppMcpElicitationUntitledMultiSelectSchema {
  title : String?
  description : String?
  min_items : UInt64?
  max_items : UInt64?
  items : AppMcpElicitationUntitledEnumItems
  default : ArrayView[String]?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationUntitledMultiSelectSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("array"),
      "title"? : title,
      "description"? : description,
      "minItems"? : min_items,
      "maxItems"? : max_items,
      "items": items,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP untitled multi-select schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    min_items: app_optional_uint64(min_items, path.add_key("minItems")),
    max_items: app_optional_uint64(max_items, path.add_key("maxItems")),
    items: @json.from_json(items, path=path.add_key("items")),
    default: match default {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("default")))
    },
  }
}

///|
pub(all) struct AppMcpElicitationTitledMultiSelectSchema {
  title : String?
  description : String?
  min_items : UInt64?
  max_items : UInt64?
  items : AppMcpElicitationTitledEnumItems
  default : ArrayView[String]?
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationTitledMultiSelectSchema with fn from_json(
  value,
  path,
) {
  guard value
    is {
      "type": String("array"),
      "title"? : title,
      "description"? : description,
      "minItems"? : min_items,
      "maxItems"? : max_items,
      "items": items,
      "default"? : default,
      ..
    } else {
    raise JsonDecodeError((path, "expected MCP titled multi-select schema"))
  }
  {
    title: app_optional_string(title, path.add_key("title")),
    description: app_optional_string(description, path.add_key("description")),
    min_items: app_optional_uint64(min_items, path.add_key("minItems")),
    max_items: app_optional_uint64(max_items, path.add_key("maxItems")),
    items: @json.from_json(items, path=path.add_key("items")),
    default: match default {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("default")))
    },
  }
}

///|
pub(all) struct AppMcpElicitationUntitledEnumItems {
  enum_values : ArrayView[String]
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationUntitledEnumItems with fn from_json(
  value,
  path,
) {
  guard value is { "type": String("string"), "enum": enum_values, .. } else {
    raise JsonDecodeError((path, "expected MCP untitled enum items"))
  }
  { enum_values: @json.from_json(enum_values, path=path.add_key("enum")) }
}

///|
pub(all) struct AppMcpElicitationTitledEnumItems {
  any_of : ArrayView[AppMcpElicitationConstOption]
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationTitledEnumItems with fn from_json(
  value,
  path,
) {
  guard value is { "anyOf"? : any_of, "oneOf"? : one_of, .. } else {
    raise JsonDecodeError((path, "expected MCP titled enum items"))
  }
  let options = match any_of {
    Some(Null) | None =>
      match one_of {
        Some(Null) | None =>
          raise JsonDecodeError((path, "expected MCP titled enum options"))
        Some(value) => @json.from_json(value, path=path.add_key("oneOf"))
      }
    Some(value) => @json.from_json(value, path=path.add_key("anyOf"))
  }
  { any_of: options }
}

///|
pub(all) struct AppMcpElicitationConstOption {
  const_value : String
  title : String
} derive(Debug)

///|
pub impl FromJson for AppMcpElicitationConstOption with fn from_json(
  value,
  path,
) {
  guard value is { "const": String(const_value), "title": String(title), .. } else {
    raise JsonDecodeError((path, "expected MCP enum option"))
  }
  { const_value, title }
}
