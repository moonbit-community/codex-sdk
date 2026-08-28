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
#skip
async test "app-server session e2e talks to real app-server" {
  @async.with_timeout(120_000, () => {
    let mut server_request_seen : String? = None
    let mut stream_closed_before_terminal = false
    let mut saw_turn_started = false
    let mut saw_agent_message = false
    Codex::new(
      options=CodexOptions::new(
        codex_path_override?=@sys.get_env_var("CODEX_SDK_E2E_CODEX_PATH"),
      ),
    ).with_app_server_session(
      request_handler=fn(request) raise {
        server_request_seen = Some(
          match request.details {
            AppCommandExecutionApprovalRequest(_) => "command approval"
            AppFileChangeApprovalRequest(_) => "file-change approval"
            AppToolRequestUserInputRequest(_) => "user input"
            AppDynamicToolCallRequest(_) => "dynamic tool"
            AppPermissionsRequestApprovalRequest(_) => "permissions approval"
            AppChatgptAuthTokensRefreshRequest(_) =>
              "ChatGPT auth token refresh"
            AppAttestationGenerateRequest(_) => "attestation generation"
            AppMcpServerElicitationRequest(_) => "MCP elicitation"
            AppRawServerRequest(rpc_method~, ..) => rpc_method
          },
        )
        fail("e2e does not handle server request")
      },
      async fn(session) {
        let _plugins = session.plugin_list({
          cwds: None,
          marketplace_kinds: None,
        })
        let skills = session.skills_list()
        if skills.data.length() > 0 {
          if skills.data[0].skills.length() > 0 {
            let skill = skills.data[0].skills[0]
            assert_true(skill.name.length() > 0)
            match skill.scope {
              AppSkillScopeUser
              | AppSkillScopeRepo
              | AppSkillScopeSystem
              | AppSkillScopeAdmin => ()
            }
          }
        }
        let _threads = session.thread_list()
        let thread = session.start_thread(
          params=AppThreadStartParams::new(
            ephemeral=true,
            model?=@sys.get_env_var("CODEX_SDK_E2E_MODEL"),
          ),
        )
        assert_true(thread.id().length() > 0)
        let turn = thread.run_streamed(
          [AppInputText(text="hello")],
          options=AppTurnStartOptions::new(
            model?=@sys.get_env_var("CODEX_SDK_E2E_MODEL"),
          ),
        )
        let mut saw_terminal = false
        while !saw_terminal {
          match turn.next() {
            None => {
              stream_closed_before_terminal = true
              break
            }
            Some(event) =>
              match event {
                AppTurnStarted(..) => saw_turn_started = true
                AppTurnCompleted(..) => saw_terminal = true
                AppTurnError(error~, ..) => fail(error.message)
                _ =>
                  match event.thread_event() {
                    Some(ItemCompleted(AgentMessageItem(text~, ..))) =>
                      if text.length() > 0 {
                        saw_agent_message = true
                      }
                    _ => ()
                  }
              }
          }
        }
      },
    )
    if stream_closed_before_terminal {
      let server_request = match server_request_seen {
        Some(value) => value
        None => "None"
      }
      fail(
        "turn stream closed before terminal event; saw_turn_started=\{saw_turn_started}, saw_agent_message=\{saw_agent_message}, server_request_seen=\{server_request}",
      )
    }
    assert_true(saw_turn_started)
    assert_true(saw_agent_message)
  })
}
