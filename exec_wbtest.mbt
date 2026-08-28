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
test "serialize Codex config overrides as TOML" {
  debug_inspect(
    codex_config_toml_value(
      @json.parse(
        (
          #|["gpt-5", true, { "name": "fast", "weight": 2 }]
        ),
      ),
      "models",
    ),
    content=(
      #|"[\"gpt-5\", true, {\"name\" = \"fast\", \"weight\" = 2}]"
    ),
  )
  debug_inspect(
    serialize_config_overrides({
      "sandbox_workspace_write": { "network_access": true },
    }),
    content=(
      #|["sandbox_workspace_write.network_access=true"]
    ),
  )
}

///|
test "reject null Codex config overrides" {
  let failed = try {
    ignore(codex_config_toml_value(Json::null(), "model"))
    false
  } catch {
    _ => true
  }
  guard failed else { fail("expected null override to fail") }
}
