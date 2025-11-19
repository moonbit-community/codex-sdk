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
/// GitHub CLI (gh) wrapper for MoonBit
/// Provides high-level operations for working with GitHub pull requests

///|
/// Check if GitHub CLI (gh) is available
pub async fn is_available() -> Bool {
  let (status, _output) = @process.collect_output_merged("which", ["gh"]) catch {
    _ => return false
  }
  status == 0
}

///|
/// Ensure GitHub CLI is available, raise error if not
pub async fn ensure_available() -> Unit raise Error {
  if !is_available() {
    raise Failure("GitHub CLI (gh) is not available. Please install gh.")
  }
}

///|
/// PR state information from GitHub
pub struct PrInfo {
  number : Int
  url : String
  state : String // OPEN, CLOSED, MERGED
  mergeable : String // MERGEABLE, CONFLICTING, UNKNOWN
  review_decision : String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or empty
}

///|
/// Create a pull request
/// Returns the PR URL on success
pub async fn create_pr(
  repo_path : String,
  title : String,
  body : String,
  base : String,
  head : String,
) -> String raise Error {
  ensure_available() catch {
    e => raise e
  }
  let (pipe, process_read) = @process.read_from_process()
  let (err_pipe, process_err) = @process.read_from_process()
  let status = @process.run(
    "gh",
    [
      "pr", "create", "--title", title, "--body", body, "--base", base, "--head",
      head,
    ],
    stdout=process_read,
    stderr=process_err,
    cwd=repo_path,
  ) catch {
    e => raise Failure("Failed to run gh pr create: \{e}")
  }
  if status != 0 {
    let error_output = err_pipe.read_all().text().to_string()
    raise Failure("gh pr create failed: \{error_output}")
  }
  pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
}

///|
/// Extract PR number from GitHub PR URL
/// Example: https://github.com/owner/repo/pull/123 -> Some(123)
pub fn extract_pr_number(pr_url : String) -> Int? {
  let parts = pr_url.split("/").to_array()
  if parts.length() > 0 {
    let last = parts[parts.length() - 1].to_string().trim(char_set=" \t\n\r")
    let num = @strconv.parse_int(last) catch { _ => -1 }
    if num > 0 {
      Some(num)
    } else {
      None
    }
  } else {
    None
  }
}

///|
/// Get PR state information from GitHub
pub async fn get_pr_state(repo_path : String, pr_number : Int) -> PrInfo {
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    [
      "pr",
      "view",
      pr_number.to_string(),
      "--json",
      "number,url,state,mergeable,reviewDecision",
    ],
    cwd=repo_path,
  ) catch {
    e => @error.reraise(e)
  }
  if status != 0 {
    @error.fail(
      (
        $|Error: \{stdout.text()}\{stderr.text()}")
        $|PR Number: \{pr_number}
        $|
      ),
    )
  }
  let output = stdout.text().trim(char_set=" \t\n\r").to_string()
  let json = @json.parse(output) catch {
    e => @error.fail_with("Failed to parse JSON", e)
  }
  match json {
    Object(
      {
        "number": Number(number, ..),
        "url": String(url),
        "state": String(state),
        "mergeable": String(mergeable),
        "reviewDecision": String(review_decision),
        ..
      }
    ) =>
      PrInfo::{
        number: number.to_int(),
        url,
        state,
        mergeable,
        review_decision,
      }
    _ => @error.fail("Unexpected JSON format: \{json.stringify()}")
  }
}

///|
/// Get PR review comments
pub async fn get_pr_comments(
  repo_path : String,
  pr_number : Int,
) -> String raise Error {
  ensure_available() catch {
    e => raise e
  }
  let (status, stdout, stderr) = @process.collect_output(
    "gh",
    ["pr", "view", pr_number.to_string(), "--comments"],
    cwd=repo_path,
  ) catch {
    e => raise Failure("Failed to fetch PR comments: \{e}")
  }
  if status != 0 {
    raise Failure(
      "Failed to fetch PR comments: \{stdout.text()}\{stderr.text()}",
    )
  }
  stdout.text()
}

///|
/// List PRs for a specific branch
/// Returns array of PR info
pub async fn list_prs_for_branch(
  repo_path : String,
  branch : String,
) -> Array[PrInfo] {
  ensure_available() catch {
    _ => return []
  }
  let (pipe, process_read) = @process.read_from_process()
  let status = @process.run(
    "gh",
    [
      "pr", "list", "--head", branch, "--json", "number,url,state,mergeable,reviewDecision",
    ],
    stdout=process_read,
    cwd=repo_path,
  ) catch {
    _ => return []
  }
  if status != 0 {
    return []
  }
  let output = pipe.read_all().text().trim(char_set=" \t\n\r").to_string()
  let json = @json.parse(output) catch { _ => return [] }
  let result = []
  match json {
    Array(prs) =>
      for pr in prs {
        match pr {
          Object(obj) => {
            let number = match obj.get("number") {
              Some(Number(n, ..)) => n.to_int()
              _ => continue
            }
            let url = match obj.get("url") {
              Some(String(s)) => s
              _ => continue
            }
            let state = match obj.get("state") {
              Some(String(s)) => s
              _ => "UNKNOWN"
            }
            let mergeable = match obj.get("mergeable") {
              Some(String(s)) => s
              _ => "UNKNOWN"
            }
            let review_decision = match obj.get("reviewDecision") {
              Some(String(s)) => s
              _ => ""
            }
            result.push(PrInfo::{
              number,
              url,
              state,
              mergeable,
              review_decision,
            })
          }
          _ => continue
        }
      }
    _ => ()
  }
  result
}
