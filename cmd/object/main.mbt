// Copyright 2025 International Digital Economy Academy
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
/// NOTICE: Make sure you are using a model provider that uses the Responses API
/// 
/// If you have set up a model provider at `.codex/config.toml`, make sure
/// `wire_api = "responses"` is set for that provider.
/// 
/// Use a model that generates structured outputs.
async fn main {
  let codex = @codex.Codex::new(options=@codex.CodexOptions::new())
  let thread = codex.start_thread()
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
    "required": ["name"],
  }
  try {
    let turn = thread.run(
      "Give me a name. Did you notice that you need to return a json object?\n\{schema.stringify(indent=2)}",
      turn_options=@codex.TurnOptions::new(output_schema=schema),
    )
    println(turn.final_response)
    println(turn.items.to_json().stringify())
    println(turn.usage.to_json().stringify())
  } catch {
    e => println(e)
  }
}
