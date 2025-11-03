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
/// Example: Process multiple packages with Codex
///
/// This shows how to iterate over packages and run Codex tasks,
/// using the working utilities.
async fn main {
  let project_path = "."
  match @moon.MoonProject::discover(project_path) {
    Some(project) => {
      println("Processing project: \{project.name}")

      // Process each package
      @tasks.for_each_package(project.root, async fn(pkg) {
        println("\nProcessing package: \{pkg.path}")

        // Run a simple Codex task on this package
        try {
          let turn = @tasks.run_simple_task(
            pkg.project.root,
            "Analyze the code in package \{pkg.path} and suggest improvements",
          )
          println("Codex response:")
          println(turn.final_response)
        } catch {
          e => println("Error processing \{pkg.path}: \{e}")
        }
      })
      println("\nAll packages processed")
    }
    None => println("No MoonBit project found at \{project_path}")
  }
}
