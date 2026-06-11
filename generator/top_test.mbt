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
async test {
  @async.with_task_group(tg => {
    // async iterator
    let iterator = AsyncGenerator::new(
      async fn(yield_) {
        for i = 0; ; i = i + 1 {
          yield_(i) catch {
            Failure::Failure(e) => {
              guard e == "error"
            }
            e => raise e
          }
        }
      },
      tg,
    )
    debug_inspect(iterator.next(), content="Some(0)")
    debug_inspect(iterator.throws(Failure::Failure("error")), content="Some(1)")
    debug_inspect(iterator.returns(), content="Some(2)")
    debug_inspect(iterator.next(), content="None")
  })
}

///|
async test "returns yields pending value before closing" {
  @async.with_task_group(tg => {
    let iterator = AsyncGenerator::new(
      async fn(yield_) {
        for i = 0; ; i = i + 1 {
          yield_(i)
        }
      },
      tg,
    )
    debug_inspect(iterator.returns(), content="Some(0)")
    debug_inspect(iterator.next(), content="None")
  })
}
