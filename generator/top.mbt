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
/// Asynchronous generator producing values of type T.
/// 
/// Similar to JavaScript's async generators, but with explicit
/// handling of return and throw.
/// 
/// The generator must be drained to completion to avoid resource leaks.
struct AsyncGenerator[T] {
  in_ : @async.Queue[InMsg]
  out : @async.Queue[OutMsg[T]]
}

///|
priv struct OutMsg[T](T?)

///|
priv enum InMsg {
  Next
  Throw(Error)
}

///|
pub async fn[T] AsyncGenerator::next(self : AsyncGenerator[T]) -> T? {
  try self.in_.try_put(Next) catch {
    Return => None
    e => raise e
  } noraise {
    false => raise Running
    true =>
      self.out.get().0 catch {
        Return => None
        e => raise e
      }
  }
}

///|
/// Throws an error into the async generator, allowing it to handle exceptions.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::throws(
  self : AsyncGenerator[T],
  e : Error,
) -> T? {
  try self.in_.try_put(Throw(e)) catch {
    Return => None
    e => raise e
  } noraise {
    false => raise Running
    true =>
      self.out.get().0 catch {
        Return => None
        e => raise e
      }
  }
}

///|
/// Signals the async generator to return, indicating normal completion.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::returns(self : AsyncGenerator[T]) -> T? {
  self.throws(Return)
}

///|
/// Error indicating that the async generator should return
pub suberror Return

///|
/// Error indicating that the async generator is already running and cannot accept new operations.
pub suberror Running

///|
/// Creates a new AsyncGenerator from an async function that takes a yield function.
/// The yield function is used to produce values asynchronously.
/// 
/// The generator runs in the provided TaskGroup.
/// If `no_wait` is true (default), the taskgroup will not wait for the generator to finish
/// when other tasks are done, implicitly cancel it.
/// If `no_wait` is false, the taskgroup will wait for the generator to finish, potentially blocking shutdown.
/// 
/// It is encouraged to set `no_wait` to true to avoid resource leaks, and spawn the generator
/// in a dedicated TaskGroup with the consumer.
pub fn[T, G] AsyncGenerator::new(
  f : async (async (T) -> Unit) -> Unit,
  taskgroup : @async.TaskGroup[G],
  no_wait? : Bool = true,
) -> AsyncGenerator[T] {
  let in_ = @async.Queue::new(kind=Blocking(1))
  let out = @async.Queue::new(kind=Unbounded)
  let generator = { in_, out }
  taskgroup.spawn_bg(no_wait~, () => {
    try
      f(value => {
        out.put(OutMsg(Some(value)))
        match in_.get() {
          Next => ()
          Throw(e) => raise e
        }
      })
    catch {
      e => out.close(error=e)
    } noraise {
      _ => out.close(error=Return)
    }
    in_.close(error=Return)
  })
  generator
}
