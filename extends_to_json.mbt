// Explicit `ToJson::to_json` promotions for this package.
//
// `pub impl ToJson for T` used to promote `to_json` implicitly as a regular
// method of the type. That implicit promotion is deprecated, so each one is
// declared here explicitly, exactly as the compiler asks for.

///|
pub extend Event with ToJson::{to_json}

///|
pub extend Usage with ToJson::{to_json}

///|
pub extend TodoItem with ToJson::{to_json}

///|
pub extend CollabTool with ToJson::{to_json}

///|
pub extend ThreadItem with ToJson::{to_json}

///|
pub extend SandboxMode with ToJson::{to_json}

///|
pub extend ThreadError with ToJson::{to_json}

///|
pub extend AppByteRange with ToJson::{to_json}

///|
pub extend AppRequestId with ToJson::{to_json}

///|
pub extend AppUserInput with ToJson::{to_json}

///|
pub extend AppClientInfo with ToJson::{to_json}

///|
pub extend AppConfigEdit with ToJson::{to_json}

///|
pub extend AppListParams with ToJson::{to_json}

///|
pub extend AppImageDetail with ToJson::{to_json}

///|
pub extend AppPersonality with ToJson::{to_json}

///|
pub extend AppTextElement with ToJson::{to_json}

///|
pub extend AppFsCopyParams with ToJson::{to_json}

///|
pub extend AppFsPathParams with ToJson::{to_json}

///|
pub extend AppReviewTarget with ToJson::{to_json}

///|
pub extend PatchChangeKind with ToJson::{to_json}

///|
pub extend AppFsWatchParams with ToJson::{to_json}

///|
pub extend AppMergeStrategy with ToJson::{to_json}

///|
pub extend AppNetworkAccess with ToJson::{to_json}

///|
pub extend AppNullableInt64 with ToJson::{to_json}

///|
pub extend AppRealtimeVoice with ToJson::{to_json}

///|
pub extend AppSandboxPolicy with ToJson::{to_json}

///|
pub extend AppSortDirection with ToJson::{to_json}

///|
pub extend AppThreadListCwd with ToJson::{to_json}

///|
pub extend AppThreadSortKey with ToJson::{to_json}

///|
pub extend CollabAgentState with ToJson::{to_json}

///|
pub extend FileUpdateChange with ToJson::{to_json}

///|
pub extend PatchApplyStatus with ToJson::{to_json}

///|
pub extend AppApprovalPolicy with ToJson::{to_json}

///|
pub extend AppConfigSnapshot with ToJson::{to_json}

///|
pub extend AppFileSystemPath with ToJson::{to_json}

///|
pub extend AppFsRemoveParams with ToJson::{to_json}

///|
pub extend AppNamedMigration with ToJson::{to_json}

///|
pub extend AppNullableString with ToJson::{to_json}

///|
pub extend AppReviewDelivery with ToJson::{to_json}

///|
pub extend AppServerResponse with ToJson::{to_json}

///|
pub extend AppThreadIdParams with ToJson::{to_json}

///|
pub extend CollabAgentStatus with ToJson::{to_json}

///|
pub extend McpToolCallResult with ToJson::{to_json}

///|
pub extend McpToolCallStatus with ToJson::{to_json}

///|
pub extend AppFsUnwatchParams with ToJson::{to_json}

///|
pub extend AppHooksListParams with ToJson::{to_json}

///|
pub extend AppModelListParams with ToJson::{to_json}

///|
pub extend AppReasoningEffort with ToJson::{to_json}

///|
pub extend AppTurnStartParams with ToJson::{to_json}

///|
pub extend AppTurnSteerParams with ToJson::{to_json}

///|
pub extend AppConfigReadParams with ToJson::{to_json}

///|
pub extend AppInitializeParams with ToJson::{to_json}

///|
pub extend AppMigrationDetails with ToJson::{to_json}

///|
pub extend AppPluginListParams with ToJson::{to_json}

///|
pub extend AppPluginReadParams with ToJson::{to_json}

///|
pub extend AppPluginsMigration with ToJson::{to_json}

///|
pub extend AppReasoningSummary with ToJson::{to_json}

///|
pub extend AppSessionMigration with ToJson::{to_json}

///|
pub extend AppSkillsListParams with ToJson::{to_json}

///|
pub extend AppThreadForkParams with ToJson::{to_json}

///|
pub extend AppThreadGoalStatus with ToJson::{to_json}

///|
pub extend AppThreadListParams with ToJson::{to_json}

///|
pub extend AppThreadMemoryMode with ToJson::{to_json}

///|
pub extend AppThreadReadParams with ToJson::{to_json}

///|
pub extend AppThreadSourceKind with ToJson::{to_json}

///|
pub extend AppAccountReadParams with ToJson::{to_json}

///|
pub extend AppApprovalsReviewer with ToJson::{to_json}

///|
pub extend AppCommandExecParams with ToJson::{to_json}

///|
pub extend AppCursorLimitParams with ToJson::{to_json}

///|
pub extend AppFsWriteFileParams with ToJson::{to_json}

///|
pub extend AppReviewStartParams with ToJson::{to_json}

///|
pub extend AppThreadStartParams with ToJson::{to_json}

///|
pub extend AppThreadStartSource with ToJson::{to_json}

///|
pub extend CollabToolCallStatus with ToJson::{to_json}

///|
pub extend AppLoginAccountParams with ToJson::{to_json}

///|
pub extend AppThreadResumeParams with ToJson::{to_json}

///|
pub extend AppAddCreditsNudgeKind with ToJson::{to_json}

///|
pub extend AppPluginInstallParams with ToJson::{to_json}

///|
pub extend AppThreadGoalSetParams with ToJson::{to_json}

///|
pub extend AppThreadSetNameParams with ToJson::{to_json}

///|
pub extend AppTurnInterruptParams with ToJson::{to_json}

///|
pub extend CommandExecutionStatus with ToJson::{to_json}

///|
pub extend AppFeedbackUploadParams with ToJson::{to_json}

///|
pub extend AppFileSystemAccessMode with ToJson::{to_json}

///|
pub extend AppMarketplaceAddParams with ToJson::{to_json}

///|
pub extend AppPermissionGrantScope with ToJson::{to_json}

///|
pub extend AppThreadRollbackParams with ToJson::{to_json}

///|
pub extend AppFileSystemSpecialPath with ToJson::{to_json}

///|
pub extend AppFuzzyFileSearchParams with ToJson::{to_json}

///|
pub extend AppMcpResourceReadParams with ToJson::{to_json}

///|
pub extend AppMcpServerStatusDetail with ToJson::{to_json}

///|
pub extend AppPluginUninstallParams with ToJson::{to_json}

///|
pub extend AppThreadTurnsListParams with ToJson::{to_json}

///|
pub extend AppCommandExecWriteParams with ToJson::{to_json}

///|
pub extend AppConfigBatchWriteParams with ToJson::{to_json}

///|
pub extend AppConfigValueWriteParams with ToJson::{to_json}

///|
pub extend AppFileSystemSandboxEntry with ToJson::{to_json}

///|
pub extend AppInitializeCapabilities with ToJson::{to_json}

///|
pub extend AppNetworkPolicyAmendment with ToJson::{to_json}

///|
pub extend AppRealtimeOutputModality with ToJson::{to_json}

///|
pub extend AppThreadLoadedListParams with ToJson::{to_json}

///|
pub extend AppCommandExecResizeParams with ToJson::{to_json}

///|
pub extend AppCommandExecTerminalSize with ToJson::{to_json}

///|
pub extend AppFsCreateDirectoryParams with ToJson::{to_json}

///|
pub extend AppMarketplaceRemoveParams with ToJson::{to_json}

///|
pub extend AppMcpServerToolCallParams with ToJson::{to_json}

///|
pub extend AppNetworkPolicyRuleAction with ToJson::{to_json}

///|
pub extend AppSkillsConfigWriteParams with ToJson::{to_json}

///|
pub extend AppThreadInjectItemsParams with ToJson::{to_json}

///|
pub extend AppThreadSectionAppearance with ToJson::{to_json}

///|
pub extend AppThreadSectionListParams with ToJson::{to_json}

///|
pub extend AppThreadSectionMoveParams with ToJson::{to_json}

///|
pub extend AppWindowsSandboxSetupMode with ToJson::{to_json}

///|
pub extend AppCancelLoginAccountParams with ToJson::{to_json}

///|
pub extend AppCommandExecProcessParams with ToJson::{to_json}

///|
pub extend AppGrantedPermissionProfile with ToJson::{to_json}

///|
pub extend AppMarketplaceUpgradeParams with ToJson::{to_json}

///|
pub extend AppThreadRealtimeAudioChunk with ToJson::{to_json}

///|
pub extend AppThreadShellCommandParams with ToJson::{to_json}

///|
pub extend AppMcpServerOauthLoginParams with ToJson::{to_json}

///|
pub extend AppMcpServerStatusListParams with ToJson::{to_json}

///|
pub extend AppPluginListMarketplaceKind with ToJson::{to_json}

///|
pub extend AppThreadMemoryModeSetParams with ToJson::{to_json}

///|
pub extend AppThreadRealtimeStartParams with ToJson::{to_json}

///|
pub extend AppThreadSectionCreateParams with ToJson::{to_json}

///|
pub extend AppThreadSectionDeleteParams with ToJson::{to_json}

///|
pub extend AppThreadSectionUpdateParams with ToJson::{to_json}

///|
pub extend AppFileChangeApprovalDecision with ToJson::{to_json}

///|
pub extend AppMcpServerElicitationAction with ToJson::{to_json}

///|
pub extend AppThreadMetadataUpdateParams with ToJson::{to_json}

///|
pub extend AppToolRequestUserInputAnswer with ToJson::{to_json}

///|
pub extend AppAdditionalNetworkPermissions with ToJson::{to_json}

///|
pub extend AppMockExperimentalMethodParams with ToJson::{to_json}

///|
pub extend AppThreadRealtimeStartTransport with ToJson::{to_json}

///|
pub extend AppThreadSectionAppearanceUpdate with ToJson::{to_json}

///|
pub extend AppSendAddCreditsNudgeEmailParams with ToJson::{to_json}

///|
pub extend AppThreadElicitationCounterParams with ToJson::{to_json}

///|
pub extend AppThreadRealtimeAppendTextParams with ToJson::{to_json}

///|
pub extend AppWindowsSandboxSetupStartParams with ToJson::{to_json}

///|
pub extend AppAdditionalFileSystemPermissions with ToJson::{to_json}

///|
pub extend AppExternalAgentConfigDetectParams with ToJson::{to_json}

///|
pub extend AppExternalAgentConfigImportParams with ToJson::{to_json}

///|
pub extend AppThreadRealtimeAppendAudioParams with ToJson::{to_json}

///|
pub extend AppCommandExecutionApprovalDecision with ToJson::{to_json}

///|
pub extend AppDynamicToolCallOutputContentItem with ToJson::{to_json}

///|
pub extend AppExternalAgentConfigMigrationItem with ToJson::{to_json}

///|
pub extend AppFuzzyFileSearchSessionStopParams with ToJson::{to_json}

///|
pub extend AppFuzzyFileSearchSessionStartParams with ToJson::{to_json}

///|
pub extend AppThreadMetadataGitInfoUpdateParams with ToJson::{to_json}

///|
pub extend AppFuzzyFileSearchSessionUpdateParams with ToJson::{to_json}

///|
pub extend AppExternalAgentConfigMigrationItemType with ToJson::{to_json}

///|
pub extend AppExperimentalFeatureEnablementSetParams with ToJson::{to_json}

///|
pub extend AppThreadApproveGuardianDeniedActionParams with ToJson::{to_json}
