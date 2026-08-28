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
// The ack confirms that the generator consumed this control message, so callers
// do not issue the next command while the previous yield is still unwinding.
priv enum InMsg {
  Next(@async.Queue[Unit])
  Throw(Error, @async.Queue[Unit])
}

///|
async fn[T] AsyncGenerator::read_after_control(
  self : AsyncGenerator[T],
  ack : @async.Queue[Unit],
) -> T? {
  let value = self.out.get().0 catch {
      Return => return None
      e => raise e
    }
  ignore(ack.get())
  value
}

///|
pub async fn[T] AsyncGenerator::next(self : AsyncGenerator[T]) -> T? {
  let ack = @async.Queue::Queue(kind=Unbounded)
  try self.in_.try_put(Next(ack)) catch {
    Return => None
    e => raise e
  } noraise {
    false => raise Running
    true => self.read_after_control(ack)
  }
}

///|
/// Throws an error into the async generator, allowing it to handle exceptions.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::throws(
  self : AsyncGenerator[T],
  e : Error,
) -> T? {
  let ack = @async.Queue::Queue(kind=Unbounded)
  try self.in_.try_put(Throw(e, ack)) catch {
    Return => None
    e => raise e
  } noraise {
    false => raise Running
    true => self.read_after_control(ack)
  }
}

///|
/// Signals the async generator to return, indicating normal completion.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::returns(self : AsyncGenerator[T]) -> T? {
  let ack = @async.Queue::Queue(kind=Unbounded)
  try self.in_.try_put(Throw(Return, ack)) catch {
    Return => None
    e => raise e
  } noraise {
    false => raise Running
    true => self.read_after_control(ack)
  }
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
  let in_ = @async.Queue::Queue(kind=Blocking(1))
  let out = @async.Queue::Queue(kind=Unbounded)
  let generator = { in_, out, }
  taskgroup.spawn_bg(no_wait~, () => {
    try
      f(value => {
        out.put(OutMsg(Some(value)))
        match in_.get() {
          Next(ack) => ack.put(())
          Throw(e, ack) => {
            ack.put(())
            raise e
          }
        }
      })
    catch {
      Return => {
        in_.close(error=Return)
        out.close(error=Return)
      }
      e => {
        in_.close(error=Return)
        out.close(error=e)
      }
    } noraise {
      _ => {
        in_.close(error=Return)
        out.close(error=Return)
      }
    }
  })
  generator
}
