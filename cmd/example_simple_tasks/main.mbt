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
/// Example: Using the high-level moon and git utilities
/// 
/// This demonstrates the working utilities for project discovery,
/// validation, and git operations.
async fn main {
  // Discover the project
  match @moon.MoonProject::discover(".") {
    Some(project) => {
      println("Found project: \{project.name} at \{project.root}")

      // Get all packages
      let packages = project.packages()
      println("Found \{packages.length()} packages:")
      for pkg in packages {
        println("  - \{pkg.path}")
      }

      // Run validation
      println("\nRunning validation...")
      let check_result = project.check()
      if check_result.passed {
        println("✓ moon check passed")
      } else {
        println("✗ moon check failed:")
        println(check_result.stderr)
      }

      // Check git status
      match @git.GitRepo::discover(project.root) {
        Some(repo) => {
          println("\nGit repository found")
          let branches = repo.existing_branches()
          println("Branches: \{branches.length()}")
          let is_clean = repo.is_clean()
          if is_clean {
            println("✓ Working tree is clean")
          } else {
            println("⚠ Working tree has uncommitted changes")
          }
        }
        None => println("No git repository found")
      }
    }
    None => println("No MoonBit project found in current directory")
  }
}
