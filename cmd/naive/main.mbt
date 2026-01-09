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
async fn main {
  let codex = @codex.Codex::new()
  let thread = codex.start_thread()
  try {
    let turn = thread.run("Hello? Please remember me : Bob")
    println(turn.final_response)
    println(turn.items.to_json().stringify())
    println(turn.usage.to_json().stringify())
  } catch {
    e => println(e)
  }
  if thread.id() is Some(id) {
    try {
      let thread = codex.resume_thread(id)
      let turn = thread.run("Hello again? Do you remember who am I?")
      println(turn.final_response)
      println(turn.items.to_json().stringify())
      println(turn.usage.to_json().stringify())
    } catch {
      e => println(e)
    }
  }
}
