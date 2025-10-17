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
priv struct OutputSchemaFile {
  schema_path : String
  cleanup : async () -> Unit
}

///|
extern "C" fn random() -> UInt = "arc4random"

///|
async fn create_output_schema_file(schema : Json) -> OutputSchemaFile {
  let dir = "/tmp/codex-output-schema-\{random()}"
  let path = "\{dir}/schema.json"
  @fs.mkdir(dir, permission=0o700)
  let cleanup = async fn() { @fs.rmdir(dir, recursive=true) }
  try {
    let file = @fs.create(path, permission=0o600)
    file.write(schema.stringify(indent=2))
    file.close()
    return { schema_path: path, cleanup }
  } catch {
    e => {
      cleanup()
      raise e
    }
  }
}
