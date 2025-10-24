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
/// Codex is the main class for interacting with the Codex agent.
///
/// Use the `start_thread()` method to start a new thread or `resume_thread()` to resume a previously started thread.
struct Codex {
  exec : CodexExec
  options : CodexOptions
}

///|
/// Create a new Codex instance.
///
/// # Arguments
/// * `options` - Optional configuration for the Codex client
///
/// # Returns
/// A new Codex instance
pub fn Codex::new(
  options? : CodexOptions = CodexOptions::{
    codex_path_override: None,
    base_url: None,
    api_key: None,
  },
) -> Codex {
  let exec = CodexExec::new(executable_path?=options.codex_path_override)
  { exec, options }
}

///|
/// Starts a new conversation with an agent.
///
/// # Arguments
/// * `options` - Optional configuration for the thread
///
/// # Returns
/// A new thread instance
pub fn Codex::start_thread(
  self : Codex,
  options? : ThreadOptions = ThreadOptions::{
    model: None,
    sandbox_mode: None,
    working_directory: None,
    skip_git_repo_check: None,
  },
) -> Thread {
  Thread::new(self.exec, self.options, options)
}

///|
/// Resumes a conversation with an agent based on the thread id.
/// Threads are persisted in ~/.codex/sessions.
///
/// # Arguments
/// * `id` - The id of the thread to resume
/// * `options` - Optional configuration for the thread
///
/// # Returns
/// A new thread instance
pub fn Codex::resume_thread(
  self : Codex,
  id : String,
  options? : ThreadOptions = ThreadOptions::{
    model: None,
    sandbox_mode: None,
    working_directory: None,
    skip_git_repo_check: None,
  },
) -> Thread {
  Thread::new(self.exec, self.options, options, id~)
}
