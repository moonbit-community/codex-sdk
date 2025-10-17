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
async fn[T, E : Error] async_suspend(
  cb : ((T) -> Unit, (E) -> Unit) -> Unit,
) -> T raise E = "%async.suspend"

///|
fn run_async(f : async () -> Unit noraise) = "%async.run"

///|
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
pub suberror Return

///|
pub suberror Running

///|
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
