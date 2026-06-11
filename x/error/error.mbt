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
priv suberror Reraise {
  Reraise((String, Error?))
}

///|
#callsite(autofill(loc))
pub fn[A] reraise(e : Error, loc~ : SourceLoc) -> A raise {
  match e {
    Reraise((msg, cause)) =>
      raise Reraise(
        (
          (
            $|\{msg}
            $|  at \{loc}
          ),
          cause,
        ),
      )
    Failure::Failure(msg) => {
      guard msg =~ (re"FAILED", before=prefix, after=rest)
      raise Reraise(
        (
          (
            $|FAILED: \{rest}
            $|  at \{prefix}
            $|  at \{loc}
          ),
          None,
        ),
      )
    }
    e =>
      raise Reraise(
        (
          (
            $|FAILED: \{e}
            $|  at \{loc}
          ),
          None,
        ),
      )
  }
}

///|
#callsite(autofill(loc))
pub fn[A] fail_with(
  message : String,
  cause : Error,
  loc~ : SourceLoc,
) -> A raise {
  raise Reraise(
    (
      (
        $|FAILED: \{message}
        $|  at \{loc}
      ),
      Some(cause),
    ),
  )
}

///|
#callsite(autofill(loc))
pub fn[A] fail(message : String, loc~ : SourceLoc) -> A raise {
  raise Reraise(
    (
      (
        $|FAILED: \{message}
        $|  at \{loc}
      ),
      None,
    ),
  )
}

///|
impl Show for Reraise with fn output(error, logger) {
  guard error is Reraise((msg, cause))
  logger.write_string(msg + "\n")
  if cause is Some(error) {
    let message = error.to_string()
    if message.strip_prefix("FAILED: ") is Some(msg) {
      logger.write_string("Caused by: \{msg}\n")
    } else {
      logger.write_string("Caused by: \{message}\n")
    }
  }
}
