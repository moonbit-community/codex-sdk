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
/// Suspends the current async computation and invokes the callback with resolve and reject functions.
/// The callback must call resolve with a value of type T or reject with an error of type E.
/// This function resumes the computation when the callback completes.
async fn[T, E : Error] async_suspend(
  cb : ((T) -> Unit, (E) -> Unit) -> Unit,
) -> T raise E = "%async.suspend"

///|
/// Runs an async function that returns Unit and does not raise errors.
/// This is the entry point for executing async computations.
fn run_async(f : async () -> Unit noraise) = "%async.run"

///|
/// Asynchronous generator producing values of type T.
/// 
/// Similar to JavaScript's async generators, but with explicit
/// handling of return and throw.
/// 
/// The generator must be drained to completion to avoid resource leaks.
struct AsyncGenerator[T] {
  mut consumer : ((Result[T?, Error]) -> Unit)?
  mut ok_cont : (Unit) -> Unit
  mut err_cont : (Error) -> Unit
}

///|
pub async fn[T] AsyncGenerator::next(self : AsyncGenerator[T]) -> T? {
  guard self.consumer is None else { raise Running }
  async_suspend((resolve, reject) => {
    self.consumer = Some(value => match value {
      Ok(v) => resolve(v)
      Err(e) => reject(e)
    })
    (self.ok_cont)(())
  })
}

///|
/// Throws an error into the async generator, allowing it to handle exceptions.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::throws(
  self : AsyncGenerator[T],
  e : Error,
) -> T? {
  guard self.consumer is None else { raise Running }
  async_suspend((resolve, reject) => {
    self.consumer = Some(value => match value {
      Ok(v) => resolve(v)
      Err(e) => reject(e)
    })
    (self.err_cont)(e)
  })
}

///|
/// Signals the async generator to return, indicating normal completion.
/// Returns the next value or None if the generator completes.
pub async fn[T] AsyncGenerator::returns(self : AsyncGenerator[T]) -> T? {
  guard self.consumer is None else { raise Running }
  async_suspend((resolve, reject) => {
    self.consumer = Some(value => match value {
      Ok(v) => resolve(v)
      Err(e) => reject(e)
    })
    (self.err_cont)(Return)
  })
}

///|
/// Error indicating that the async generator has returned normally.
pub suberror Return

///|
/// Error indicating that the async generator is already running and cannot accept new operations.
pub suberror Running

///|
/// Creates a new AsyncGenerator from an async function that takes a yield function.
/// The yield function is used to produce values asynchronously.
/// The generator must be fully consumed to avoid resource leaks.
pub fn[T] AsyncGenerator::new(
  f : async (async (T) -> Unit) -> Unit,
) -> AsyncGenerator[T] {
  let iterator = { consumer: None, ok_cont: _ => (), err_cont: _ => () }
  async fn yield_(value) {
    async_suspend((resolve, reject) => {
      iterator.ok_cont = resolve
      iterator.err_cont = reject
      guard iterator.consumer is Some(consumer)
      iterator.consumer = None
      consumer(Ok(Some(value)))
    })
  }

  iterator.ok_cont = _ => run_async(fn() {
    let ok_fin = _ => {
      guard iterator.consumer is Some(consumer)
      iterator.consumer = None
      consumer(Ok(None))
    }
    let err_fin = _ => {
      guard iterator.consumer is Some(consumer)
      iterator.consumer = None
      consumer(Ok(None))
    }
    try f(yield_) catch {
      Return => {
        iterator.ok_cont = ok_fin
        iterator.err_cont = err_fin
        guard iterator.consumer is Some(consumer)
        iterator.consumer = None
        consumer(Ok(None))
      }
      e => {
        iterator.ok_cont = ok_fin
        iterator.err_cont = err_fin
        guard iterator.consumer is Some(consumer)
        iterator.consumer = None
        consumer(Err(e))
      }
    } noraise {
      _ => {
        iterator.ok_cont = ok_fin
        iterator.err_cont = err_fin
        guard iterator.consumer is Some(consumer)
        iterator.consumer = None
        consumer(Ok(None))
      }
    }
  })
  iterator
}
