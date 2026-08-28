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
/// Send an arbitrary app-server request and return its raw JSON result.
/// Prefer a typed session method when one is available.
pub async fn CodexAppSession::request(
  self : CodexAppSession,
  rpc_method : String,
  params? : Json,
) -> Json {
  self.connection.request(rpc_method, params?)
}

///|
/// Send an arbitrary app-server notification.
pub async fn CodexAppSession::notify(
  self : CodexAppSession,
  rpc_method : String,
  params? : Json,
) -> Unit {
  self.connection.notify(rpc_method, params?)
}

///|
pub async fn CodexAppSession::account_login_cancel(
  self : CodexAppSession,
  params : AppCancelLoginAccountParams,
) -> AppAccountLoginCancelResponse {
  self.connection.account_login_cancel(params)
}

///|
pub async fn CodexAppSession::account_login_start(
  self : CodexAppSession,
  params : AppLoginAccountParams,
) -> AppAccountLoginStartResponse {
  self.connection.account_login_start(params)
}

///|
pub async fn CodexAppSession::account_logout(self : CodexAppSession) -> Unit {
  self.connection.account_logout()
}

///|
pub async fn CodexAppSession::account_rate_limits_read(
  self : CodexAppSession,
) -> AppAccountRateLimitsReadResponse {
  self.connection.account_rate_limits_read()
}

///|
pub async fn CodexAppSession::account_read(
  self : CodexAppSession,
  params : AppAccountReadParams,
) -> AppAccountReadResponse {
  self.connection.account_read(params)
}

///|
pub async fn CodexAppSession::account_send_add_credits_nudge_email(
  self : CodexAppSession,
  params : AppSendAddCreditsNudgeEmailParams,
) -> AppAccountSendAddCreditsNudgeEmailResponse {
  self.connection.account_send_add_credits_nudge_email(params)
}

///|
pub async fn CodexAppSession::app_list(
  self : CodexAppSession,
  params? : AppListParams,
) -> AppListResponse {
  self.connection.app_list(params?)
}

///|
pub async fn CodexAppSession::collaboration_mode_list(
  self : CodexAppSession,
) -> AppCollaborationModeListResponse {
  self.connection.collaboration_mode_list()
}

///|
pub async fn CodexAppSession::command_exec(
  self : CodexAppSession,
  params : AppCommandExecParams,
) -> AppCommandExecResponse {
  self.connection.command_exec(params)
}

///|
pub async fn CodexAppSession::command_exec_resize(
  self : CodexAppSession,
  params : AppCommandExecResizeParams,
) -> Unit {
  self.connection.command_exec_resize(params)
}

///|
pub async fn CodexAppSession::command_exec_terminate(
  self : CodexAppSession,
  params : AppCommandExecProcessParams,
) -> Unit {
  self.connection.command_exec_terminate(params)
}

///|
pub async fn CodexAppSession::command_exec_write(
  self : CodexAppSession,
  params : AppCommandExecWriteParams,
) -> Unit {
  self.connection.command_exec_write(params)
}

///|
pub async fn CodexAppSession::config_batch_write(
  self : CodexAppSession,
  params : AppConfigBatchWriteParams,
) -> AppConfigBatchWriteResponse {
  self.connection.config_batch_write(params)
}

///|
pub async fn CodexAppSession::config_mcp_server_reload(
  self : CodexAppSession,
) -> Unit {
  self.connection.config_mcp_server_reload()
}

///|
pub async fn CodexAppSession::config_read(
  self : CodexAppSession,
  params : AppConfigReadParams,
) -> AppConfigReadResponse {
  self.connection.config_read(params)
}

///|
pub async fn CodexAppSession::config_requirements_read(
  self : CodexAppSession,
) -> AppConfigRequirementsReadResponse {
  self.connection.config_requirements_read()
}

///|
pub async fn CodexAppSession::config_value_write(
  self : CodexAppSession,
  params : AppConfigValueWriteParams,
) -> AppConfigValueWriteResponse {
  self.connection.config_value_write(params)
}

///|
pub async fn CodexAppSession::experimental_feature_enablement_set(
  self : CodexAppSession,
  params : AppExperimentalFeatureEnablementSetParams,
) -> AppExperimentalFeatureEnablementSetResponse {
  self.connection.experimental_feature_enablement_set(params)
}

///|
pub async fn CodexAppSession::experimental_feature_list(
  self : CodexAppSession,
  params : AppCursorLimitParams,
) -> AppExperimentalFeatureListResponse {
  self.connection.experimental_feature_list(params)
}

///|
pub async fn CodexAppSession::external_agent_config_detect(
  self : CodexAppSession,
  params : AppExternalAgentConfigDetectParams,
) -> AppExternalAgentConfigDetectResponse {
  self.connection.external_agent_config_detect(params)
}

///|
pub async fn CodexAppSession::external_agent_config_import(
  self : CodexAppSession,
  params : AppExternalAgentConfigImportParams,
) -> Unit {
  self.connection.external_agent_config_import(params)
}

///|
pub async fn CodexAppSession::feedback_upload(
  self : CodexAppSession,
  params : AppFeedbackUploadParams,
) -> AppFeedbackUploadResponse {
  self.connection.feedback_upload(params)
}

///|
pub async fn CodexAppSession::fs_copy(
  self : CodexAppSession,
  params : AppFsCopyParams,
) -> Unit {
  self.connection.fs_copy(params)
}

///|
pub async fn CodexAppSession::fs_create_directory(
  self : CodexAppSession,
  params : AppFsCreateDirectoryParams,
) -> Unit {
  self.connection.fs_create_directory(params)
}

///|
pub async fn CodexAppSession::fs_get_metadata(
  self : CodexAppSession,
  params : AppFsPathParams,
) -> AppFsGetMetadataResponse {
  self.connection.fs_get_metadata(params)
}

///|
pub async fn CodexAppSession::fs_read_directory(
  self : CodexAppSession,
  params : AppFsPathParams,
) -> AppFsReadDirectoryResponse {
  self.connection.fs_read_directory(params)
}

///|
pub async fn CodexAppSession::fs_read_file(
  self : CodexAppSession,
  params : AppFsPathParams,
) -> AppFsReadFileResponse {
  self.connection.fs_read_file(params)
}

///|
pub async fn CodexAppSession::fs_remove(
  self : CodexAppSession,
  params : AppFsRemoveParams,
) -> Unit {
  self.connection.fs_remove(params)
}

///|
pub async fn CodexAppSession::fs_unwatch(
  self : CodexAppSession,
  params : AppFsUnwatchParams,
) -> Unit {
  self.connection.fs_unwatch(params)
}

///|
pub async fn CodexAppSession::fs_watch(
  self : CodexAppSession,
  params : AppFsWatchParams,
) -> AppFsWatchResponse {
  self.connection.fs_watch(params)
}

///|
pub async fn CodexAppSession::fs_write_file(
  self : CodexAppSession,
  params : AppFsWriteFileParams,
) -> Unit {
  self.connection.fs_write_file(params)
}

///|
pub async fn CodexAppSession::fuzzy_file_search(
  self : CodexAppSession,
  params : AppFuzzyFileSearchParams,
) -> AppFuzzyFileSearchResponse {
  self.connection.fuzzy_file_search(params)
}

///|
pub async fn CodexAppSession::fuzzy_file_search_session_start(
  self : CodexAppSession,
  params : AppFuzzyFileSearchSessionStartParams,
) -> Unit {
  self.connection.fuzzy_file_search_session_start(params)
}

///|
pub async fn CodexAppSession::fuzzy_file_search_session_stop(
  self : CodexAppSession,
  params : AppFuzzyFileSearchSessionStopParams,
) -> Unit {
  self.connection.fuzzy_file_search_session_stop(params)
}

///|
pub async fn CodexAppSession::fuzzy_file_search_session_update(
  self : CodexAppSession,
  params : AppFuzzyFileSearchSessionUpdateParams,
) -> Unit {
  self.connection.fuzzy_file_search_session_update(params)
}

///|
pub async fn CodexAppSession::hooks_list(
  self : CodexAppSession,
  params : AppHooksListParams,
) -> AppHooksListResponse {
  self.connection.hooks_list(params)
}

///|
pub async fn CodexAppSession::marketplace_add(
  self : CodexAppSession,
  params : AppMarketplaceAddParams,
) -> AppMarketplaceAddResponse {
  self.connection.marketplace_add(params)
}

///|
pub async fn CodexAppSession::marketplace_remove(
  self : CodexAppSession,
  params : AppMarketplaceRemoveParams,
) -> AppMarketplaceRemoveResponse {
  self.connection.marketplace_remove(params)
}

///|
pub async fn CodexAppSession::marketplace_upgrade(
  self : CodexAppSession,
  params : AppMarketplaceUpgradeParams,
) -> AppMarketplaceUpgradeResponse {
  self.connection.marketplace_upgrade(params)
}

///|
pub async fn CodexAppSession::mcp_server_oauth_login(
  self : CodexAppSession,
  params : AppMcpServerOauthLoginParams,
) -> AppMcpServerOauthLoginResponse {
  self.connection.mcp_server_oauth_login(params)
}

///|
pub async fn CodexAppSession::mcp_server_resource_read(
  self : CodexAppSession,
  params : AppMcpResourceReadParams,
) -> AppMcpServerResourceReadResponse {
  self.connection.mcp_server_resource_read(params)
}

///|
pub async fn CodexAppSession::mcp_server_status_list(
  self : CodexAppSession,
  params : AppMcpServerStatusListParams,
) -> AppMcpServerStatusListResponse {
  self.connection.mcp_server_status_list(params)
}

///|
pub async fn CodexAppSession::mcp_server_tool_call(
  self : CodexAppSession,
  params : AppMcpServerToolCallParams,
) -> AppMcpServerToolCallResponse {
  self.connection.mcp_server_tool_call(params)
}

///|
pub async fn CodexAppSession::memory_reset(self : CodexAppSession) -> Unit {
  self.connection.memory_reset()
}

///|
pub async fn CodexAppSession::mock_experimental_method(
  self : CodexAppSession,
  params : AppMockExperimentalMethodParams,
) -> AppMockExperimentalMethodResponse {
  self.connection.mock_experimental_method(params)
}

///|
pub async fn CodexAppSession::model_provider_capabilities_read(
  self : CodexAppSession,
) -> AppModelProviderCapabilitiesReadResponse {
  self.connection.model_provider_capabilities_read()
}

///|
pub async fn CodexAppSession::plugin_install(
  self : CodexAppSession,
  params : AppPluginInstallParams,
) -> AppPluginInstallResponse {
  self.connection.plugin_install(params)
}

///|
pub async fn CodexAppSession::plugin_list(
  self : CodexAppSession,
  params : AppPluginListParams,
) -> AppPluginListResponse {
  self.connection.plugin_list(params)
}

///|
pub async fn CodexAppSession::plugin_read(
  self : CodexAppSession,
  params : AppPluginReadParams,
) -> AppPluginReadResponse {
  self.connection.plugin_read(params)
}

///|
pub async fn CodexAppSession::plugin_uninstall(
  self : CodexAppSession,
  params : AppPluginUninstallParams,
) -> Unit {
  self.connection.plugin_uninstall(params)
}

///|
pub async fn CodexAppSession::review_start(
  self : CodexAppSession,
  params : AppReviewStartParams,
) -> AppReviewStartResponse {
  self.connection.review_start(params)
}

///|
pub async fn CodexAppSession::skills_config_write(
  self : CodexAppSession,
  params : AppSkillsConfigWriteParams,
) -> AppSkillsConfigWriteResponse {
  self.connection.skills_config_write(params)
}

///|
pub async fn CodexAppSession::skills_list(
  self : CodexAppSession,
  params? : AppSkillsListParams,
) -> AppSkillsListResponse {
  self.connection.skills_list(params?)
}

///|
pub async fn CodexAppSession::thread_approve_guardian_denied_action(
  self : CodexAppSession,
  params : AppThreadApproveGuardianDeniedActionParams,
) -> Unit {
  self.connection.thread_approve_guardian_denied_action(params)
}

///|
pub async fn CodexAppSession::thread_archive(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> Unit {
  self.connection.thread_archive(params)
}

///|
pub async fn CodexAppSession::thread_background_terminals_clean(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> Unit {
  self.connection.thread_background_terminals_clean(params)
}

///|
pub async fn CodexAppSession::thread_compact_start(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> Unit {
  self.connection.thread_compact_start(params)
}

///|
pub async fn CodexAppSession::thread_decrement_elicitation(
  self : CodexAppSession,
  params : AppThreadElicitationCounterParams,
) -> AppThreadElicitationCounterResponse {
  self.connection.thread_decrement_elicitation(params)
}

///|
pub async fn CodexAppSession::thread_fork(
  self : CodexAppSession,
  params : AppThreadForkParams,
) -> AppThreadForkResponse {
  self.connection.thread_fork(params)
}

///|
pub async fn CodexAppSession::thread_goal_clear(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> AppThreadGoalClearResponse {
  self.connection.thread_goal_clear(params)
}

///|
pub async fn CodexAppSession::thread_goal_get(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> AppThreadGoalGetResponse {
  self.connection.thread_goal_get(params)
}

///|
pub async fn CodexAppSession::thread_goal_set(
  self : CodexAppSession,
  params : AppThreadGoalSetParams,
) -> AppThreadGoalSetResponse {
  self.connection.thread_goal_set(params)
}

///|
pub async fn CodexAppSession::thread_increment_elicitation(
  self : CodexAppSession,
  params : AppThreadElicitationCounterParams,
) -> AppThreadElicitationCounterResponse {
  self.connection.thread_increment_elicitation(params)
}

///|
pub async fn CodexAppSession::thread_inject_items(
  self : CodexAppSession,
  params : AppThreadInjectItemsParams,
) -> Unit {
  self.connection.thread_inject_items(params)
}

///|
pub async fn CodexAppSession::thread_loaded_list(
  self : CodexAppSession,
  params? : AppThreadLoadedListParams,
) -> AppThreadLoadedListResponse {
  self.connection.thread_loaded_list(params?)
}

///|
pub async fn CodexAppSession::thread_memory_mode_set(
  self : CodexAppSession,
  params : AppThreadMemoryModeSetParams,
) -> Unit {
  self.connection.thread_memory_mode_set(params)
}

///|
pub async fn CodexAppSession::thread_metadata_update(
  self : CodexAppSession,
  params : AppThreadMetadataUpdateParams,
) -> AppThreadMetadataUpdateResponse {
  self.connection.thread_metadata_update(params)
}

///|
pub async fn CodexAppSession::thread_realtime_append_audio(
  self : CodexAppSession,
  params : AppThreadRealtimeAppendAudioParams,
) -> Unit {
  self.connection.thread_realtime_append_audio(params)
}

///|
pub async fn CodexAppSession::thread_realtime_append_text(
  self : CodexAppSession,
  params : AppThreadRealtimeAppendTextParams,
) -> Unit {
  self.connection.thread_realtime_append_text(params)
}

///|
pub async fn CodexAppSession::thread_realtime_list_voices(
  self : CodexAppSession,
) -> AppThreadRealtimeListVoicesResponse {
  self.connection.thread_realtime_list_voices()
}

///|
pub async fn CodexAppSession::thread_realtime_start(
  self : CodexAppSession,
  params : AppThreadRealtimeStartParams,
) -> Unit {
  self.connection.thread_realtime_start(params)
}

///|
pub async fn CodexAppSession::thread_realtime_stop(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> Unit {
  self.connection.thread_realtime_stop(params)
}

///|
pub async fn CodexAppSession::thread_resume(
  self : CodexAppSession,
  params : AppThreadResumeParams,
) -> AppThreadResumeResponse {
  self.connection.thread_resume(params)
}

///|
pub async fn CodexAppSession::thread_rollback(
  self : CodexAppSession,
  params : AppThreadRollbackParams,
) -> AppThreadRollbackResponse {
  self.connection.thread_rollback(params)
}

///|
pub async fn CodexAppSession::thread_set_name(
  self : CodexAppSession,
  params : AppThreadSetNameParams,
) -> Unit {
  self.connection.thread_set_name(params)
}

///|
pub async fn CodexAppSession::thread_shell_command(
  self : CodexAppSession,
  params : AppThreadShellCommandParams,
) -> Unit {
  self.connection.thread_shell_command(params)
}

///|
pub async fn CodexAppSession::thread_turns_list(
  self : CodexAppSession,
  params : AppThreadTurnsListParams,
) -> AppThreadTurnsListResponse {
  self.connection.thread_turns_list(params)
}

///|
pub async fn CodexAppSession::thread_unarchive(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> AppThreadReadResponse {
  self.connection.thread_unarchive(params)
}

///|
pub async fn CodexAppSession::thread_unsubscribe(
  self : CodexAppSession,
  params : AppThreadIdParams,
) -> AppThreadUnsubscribeResponse {
  self.connection.thread_unsubscribe(params)
}

///|
pub async fn CodexAppSession::turn_steer(
  self : CodexAppSession,
  params : AppTurnSteerParams,
) -> AppTurnSteerResponse {
  self.connection.turn_steer(params)
}

///|
pub async fn CodexAppSession::windows_sandbox_setup_start(
  self : CodexAppSession,
  params : AppWindowsSandboxSetupStartParams,
) -> AppWindowsSandboxSetupStartResponse {
  self.connection.windows_sandbox_setup_start(params)
}
