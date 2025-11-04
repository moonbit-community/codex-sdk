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
      @stdio.stdout.write("Found project: \{project.name} at \{project.root}")

      // Get all packages
      let packages = project.packages()
      @stdio.stdout.write("Found \{packages.length()} packages:")
      for pkg in packages {
        @stdio.stdout.write("  - \{pkg.path}")
      }

      // Run validation
      @stdio.stdout.write("\nRunning validation...")
      let check_result = project.check()
      if check_result.passed {
        @stdio.stdout.write("✓ moon check passed")
      } else {
        @stdio.stdout.write("✗ moon check failed:")
        @stdio.stdout.write(check_result.stderr)
      }

      // Check git status
      match @git.GitRepo::discover(project.root) {
        Some(repo) => {
          @stdio.stdout.write("\nGit repository found")
          let branches = repo.existing_branches()
          @stdio.stdout.write("Branches: \{branches.length()}")
          let is_clean = repo.is_clean()
          if is_clean {
            @stdio.stdout.write("✓ Working tree is clean")
          } else {
            @stdio.stdout.write("⚠ Working tree has uncommitted changes")
          }
        }
        None => @stdio.stdout.write("No git repository found")
      }
    }
    None => @stdio.stdout.write("No MoonBit project found in current directory")
  }
}
