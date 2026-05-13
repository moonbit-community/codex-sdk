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
test "parse_diagnostics parses errors and warnings" {
  let output =
    #|Error: [3002]
    #|   ╭─[ /private/tmp/test_error.mbt:1:3 ]
    #|   │
    #| 1 │ fn test() { let x : Int = "string" }
    #|   │   ┬  
    #|   │   ╰── Parse error, unexpected token `test`, you may expect id (lowercase start), id (uppercase start) or package name.
    #|───╯
    #|Error: [4074]
    #|   ╭─[ /private/tmp/test_error.mbt:1:3 ]
    #|   │
    #| 1 │ fn test() { let x : Int = "string" }
    #|   │   ┬  
    #|   │   ╰── Missing type annotation for the return value.
    #|───╯
    #|Warning: [0019]
    #|   ╭─[ /private/tmp/test_error.mbt:1:4 ]
    #|   │
    #| 1 │ fn test() { let x : Int = "string" }
    #|   │    ────────────────┬────────────────  
    #|   │                    ╰────────────────── Warning: Toplevel declaration is not left aligned.
    #|───╯
    #|Warning: [0002]
    #|   ╭─[ /private/tmp/test_error.mbt:17:8 ]
    #|   │
    #|17 │ fn test() { let x : Int = "string" }
    #|   │                 ┬  
    #|   │                 ╰── Warning: Unused variable 'x'
    #|───╯
    #|Failed with 2 warnings, 2 errors.
  let diagnostics = parse_diagnostics(output)
  debug_inspect(diagnostics.length(), content="4")

  // Check first error
  let d0 = diagnostics[0]
  debug_inspect(
    d0.file,
    content=(
      #|"/private/tmp/test_error.mbt"
    ),
  )
  debug_inspect(d0.line, content="1")
  debug_inspect(d0.column, content="Some(3)")
  debug_inspect(
    d0.level,
    content=(
      #|"error"
    ),
  )
  debug_inspect(
    d0.message,
    content=(
      #|"Parse error, unexpected token `test`, you may expect id (lowercase start), id (uppercase start) or package name."
    ),
  )

  // Check second error
  let d1 = diagnostics[1]
  debug_inspect(
    d1.level,
    content=(
      #|"error"
    ),
  )
  debug_inspect(
    d1.message,
    content=(
      #|"Missing type annotation for the return value."
    ),
  )

  // Check first warning
  let d2 = diagnostics[2]
  debug_inspect(
    d2.level,
    content=(
      #|"warning"
    ),
  )
  debug_inspect(d2.line, content="1")
  debug_inspect(d2.column, content="Some(4)")

  // Check second warning with different line number
  let d3 = diagnostics[3]
  debug_inspect(
    d3.level,
    content=(
      #|"warning"
    ),
  )
  debug_inspect(d3.line, content="17")
  debug_inspect(d3.column, content="Some(8)")
  debug_inspect(
    d3.message,
    content=(
      #|"Warning: Unused variable 'x'"
    ),
  )
}

///|
test "get_errors filters only errors" {
  let output =
    #|Error: [3002]
    #|   ╭─[ /tmp/test.mbt:1:3 ]
    #|   │
    #|   │   ╰── Some error
    #|───╯
    #|Warning: [0019]
    #|   ╭─[ /tmp/test.mbt:2:4 ]
    #|   │
    #|   │   ╰── Some warning
    #|───╯
  let diagnostics = parse_diagnostics(output)
  let errors = get_errors(diagnostics)
  debug_inspect(errors.length(), content="1")
  debug_inspect(
    errors[0].level,
    content=(
      #|"error"
    ),
  )
}

///|
test "get_warnings filters only warnings" {
  let output =
    #|Error: [3002]
    #|   ╭─[ /tmp/test.mbt:1:3 ]
    #|   │
    #|   │   ╰── Some error
    #|───╯
    #|Warning: [0019]
    #|   ╭─[ /tmp/test.mbt:2:4 ]
    #|   │
    #|   │   ╰── Some warning
    #|───╯
  let diagnostics = parse_diagnostics(output)
  let warnings = get_warnings(diagnostics)
  debug_inspect(warnings.length(), content="1")
  debug_inspect(
    warnings[0].level,
    content=(
      #|"warning"
    ),
  )
}
