// Explicit `FromJson::from_json` promotions for this package.
//
// `pub impl FromJson for T` used to promote `from_json` implicitly as a regular
// method of the type. That implicit promotion is deprecated, so each one is
// declared here explicitly, exactly as the compiler asks for.

///|
pub extend Event with @json.FromJson::{from_json}

///|
pub extend Usage with @json.FromJson::{from_json}

///|
pub extend AppInfo with @json.FromJson::{from_json}

///|
pub extend AppTurn with @json.FromJson::{from_json}

///|
pub extend AppModel with @json.FromJson::{from_json}

///|
pub extend TodoItem with @json.FromJson::{from_json}

///|
pub extend AppThread with @json.FromJson::{from_json}

///|
pub extend AppAccount with @json.FromJson::{from_json}

///|
pub extend AppMcpTool with @json.FromJson::{from_json}

///|
pub extend AppSummary with @json.FromJson::{from_json}

///|
pub extend CollabTool with @json.FromJson::{from_json}

///|
pub extend ThreadItem with @json.FromJson::{from_json}

///|
pub extend AppAuthMode with @json.FromJson::{from_json}

///|
pub extend AppPlanType with @json.FromJson::{from_json}

///|
pub extend SandboxMode with @json.FromJson::{from_json}

///|
pub extend ThreadError with @json.FromJson::{from_json}

///|
pub extend AppByteRange with @json.FromJson::{from_json}

///|
pub extend AppHookScope with @json.FromJson::{from_json}

///|
pub extend AppProfileV2 with @json.FromJson::{from_json}

///|
pub extend AppRequestId with @json.FromJson::{from_json}

///|
pub extend AppTextRange with @json.FromJson::{from_json}

///|
pub extend AppTurnError with @json.FromJson::{from_json}

///|
pub extend AppAppsConfig with @json.FromJson::{from_json}

///|
pub extend AppHookSource with @json.FromJson::{from_json}

///|
pub extend AppSkillScope with @json.FromJson::{from_json}

///|
pub extend AppThreadGoal with @json.FromJson::{from_json}

///|
pub extend AppThreadItem with @json.FromJson::{from_json}

///|
pub extend AppToolConfig with @json.FromJson::{from_json}

///|
pub extend AppTurnStatus with @json.FromJson::{from_json}

///|
pub extend AppConfigLayer with @json.FromJson::{from_json}

///|
pub extend AppImageDetail with @json.FromJson::{from_json}

///|
pub extend AppMcpResource with @json.FromJson::{from_json}

///|
pub extend AppServerEvent with @json.FromJson::{from_json}

///|
pub extend AppTextElement with @json.FromJson::{from_json}

///|
pub extend AppToolsConfig with @json.FromJson::{from_json}

///|
pub extend AppHookMetadata with @json.FromJson::{from_json}

///|
pub extend AppListResponse with @json.FromJson::{from_json}

///|
pub extend AppMessagePhase with @json.FromJson::{from_json}

///|
pub extend AppOutputStream with @json.FromJson::{from_json}

///|
pub extend AppPluginDetail with @json.FromJson::{from_json}

///|
pub extend AppPluginSource with @json.FromJson::{from_json}

///|
pub extend AppResponseItem with @json.FromJson::{from_json}

///|
pub extend AppSkillSummary with @json.FromJson::{from_json}

///|
pub extend AppTextPosition with @json.FromJson::{from_json}

///|
pub extend AppThreadStatus with @json.FromJson::{from_json}

///|
pub extend AppToolApproval with @json.FromJson::{from_json}

///|
pub extend AppTurnPlanStep with @json.FromJson::{from_json}

///|
pub extend PatchChangeKind with @json.FromJson::{from_json}

///|
pub extend AppCommandAction with @json.FromJson::{from_json}

///|
pub extend AppConfigToolsV2 with @json.FromJson::{from_json}

///|
pub extend AppHookErrorInfo with @json.FromJson::{from_json}

///|
pub extend AppHookEventName with @json.FromJson::{from_json}

///|
pub extend AppHookRunStatus with @json.FromJson::{from_json}

///|
pub extend AppInputModality with @json.FromJson::{from_json}

///|
pub extend AppMcpAuthStatus with @json.FromJson::{from_json}

///|
pub extend AppNetworkAccess with @json.FromJson::{from_json}

///|
pub extend AppPluginSummary with @json.FromJson::{from_json}

///|
pub extend AppRealtimeVoice with @json.FromJson::{from_json}

///|
pub extend AppSandboxPolicy with @json.FromJson::{from_json}

///|
pub extend AppSessionSource with @json.FromJson::{from_json}

///|
pub extend AppSkillMetadata with @json.FromJson::{from_json}

///|
pub extend AppThreadSection with @json.FromJson::{from_json}

///|
pub extend AppWebSearchMode with @json.FromJson::{from_json}

///|
pub extend CollabAgentState with @json.FromJson::{from_json}

///|
pub extend FileUpdateChange with @json.FromJson::{from_json}

///|
pub extend PatchApplyStatus with @json.FromJson::{from_json}

///|
pub extend AppApprovalPolicy with @json.FromJson::{from_json}

///|
pub extend AppCodexErrorInfo with @json.FromJson::{from_json}

///|
pub extend AppConfigSnapshot with @json.FromJson::{from_json}

///|
pub extend AppFileSystemPath with @json.FromJson::{from_json}

///|
pub extend AppHookRunSummary with @json.FromJson::{from_json}

///|
pub extend AppHooksListEntry with @json.FromJson::{from_json}

///|
pub extend AppMemoryCitation with @json.FromJson::{from_json}

///|
pub extend AppModelVerbosity with @json.FromJson::{from_json}

///|
pub extend AppNamedMigration with @json.FromJson::{from_json}

///|
pub extend AppSkillErrorInfo with @json.FromJson::{from_json}

///|
pub extend AppSkillInterface with @json.FromJson::{from_json}

///|
pub extend AppSubAgentSource with @json.FromJson::{from_json}

///|
pub extend CollabAgentStatus with @json.FromJson::{from_json}

///|
pub extend McpToolCallResult with @json.FromJson::{from_json}

///|
pub extend McpToolCallStatus with @json.FromJson::{from_json}

///|
pub extend AppAnalyticsConfig with @json.FromJson::{from_json}

///|
pub extend AppConnectorConfig with @json.FromJson::{from_json}

///|
pub extend AppCreditsSnapshot with @json.FromJson::{from_json}

///|
pub extend AppFsWatchResponse with @json.FromJson::{from_json}

///|
pub extend AppHookHandlerType with @json.FromJson::{from_json}

///|
pub extend AppHookOutputEntry with @json.FromJson::{from_json}

///|
pub extend AppHookTrustStatus with @json.FromJson::{from_json}

///|
pub extend AppMcpServerStatus with @json.FromJson::{from_json}

///|
pub extend AppPluginInterface with @json.FromJson::{from_json}

///|
pub extend AppRateLimitWindow with @json.FromJson::{from_json}

///|
pub extend AppReasoningEffort with @json.FromJson::{from_json}

///|
pub extend AppSkillsListEntry with @json.FromJson::{from_json}

///|
pub extend AppThreadItemEvent with @json.FromJson::{from_json}

///|
pub extend AppThreadUserInput with @json.FromJson::{from_json}

///|
pub extend AppWebSearchAction with @json.FromJson::{from_json}

///|
pub extend AppMigrationDetails with @json.FromJson::{from_json}

///|
pub extend AppModelServiceTier with @json.FromJson::{from_json}

///|
pub extend AppModelUpgradeInfo with @json.FromJson::{from_json}

///|
pub extend AppPluginAuthPolicy with @json.FromJson::{from_json}

///|
pub extend AppPluginsMigration with @json.FromJson::{from_json}

///|
pub extend AppReasoningSummary with @json.FromJson::{from_json}

///|
pub extend AppSessionMigration with @json.FromJson::{from_json}

///|
pub extend AppThreadActiveFlag with @json.FromJson::{from_json}

///|
pub extend AppThreadGoalStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadTokenUsage with @json.FromJson::{from_json}

///|
pub extend AppApprovalsReviewer with @json.FromJson::{from_json}

///|
pub extend AppAppsDefaultConfig with @json.FromJson::{from_json}

///|
pub extend AppConfigLayerSource with @json.FromJson::{from_json}

///|
pub extend AppConfigWriteStatus with @json.FromJson::{from_json}

///|
pub extend AppForcedLoginMethod with @json.FromJson::{from_json}

///|
pub extend AppGuardianRiskLevel with @json.FromJson::{from_json}

///|
pub extend AppHookExecutionMode with @json.FromJson::{from_json}

///|
pub extend AppHooksListResponse with @json.FromJson::{from_json}

///|
pub extend AppModelListResponse with @json.FromJson::{from_json}

///|
pub extend AppModelVerification with @json.FromJson::{from_json}

///|
pub extend AppMultiAgentVersion with @json.FromJson::{from_json}

///|
pub extend AppRateLimitSnapshot with @json.FromJson::{from_json}

///|
pub extend AppSkillDependencies with @json.FromJson::{from_json}

///|
pub extend AppTurnStartResponse with @json.FromJson::{from_json}

///|
pub extend AppTurnSteerResponse with @json.FromJson::{from_json}

///|
pub extend AppWebSearchLocation with @json.FromJson::{from_json}

///|
pub extend CollabToolCallStatus with @json.FromJson::{from_json}

///|
pub extend AppConfigReadResponse with @json.FromJson::{from_json}

///|
pub extend AppConfigRequirements with @json.FromJson::{from_json}

///|
pub extend AppFsReadFileResponse with @json.FromJson::{from_json}

///|
pub extend AppHookPromptFragment with @json.FromJson::{from_json}

///|
pub extend AppInitializeResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpResourceContent with @json.FromJson::{from_json}

///|
pub extend AppModelRerouteReason with @json.FromJson::{from_json}

///|
pub extend AppPluginListResponse with @json.FromJson::{from_json}

///|
pub extend AppPluginReadResponse with @json.FromJson::{from_json}

///|
pub extend AppRealtimeVoicesList with @json.FromJson::{from_json}

///|
pub extend AppSkillsListResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadForkResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadListResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadReadResponse with @json.FromJson::{from_json}

///|
pub extend AppTurnPlanStepStatus with @json.FromJson::{from_json}

///|
pub extend AppAccountReadResponse with @json.FromJson::{from_json}

///|
pub extend AppCommandExecResponse with @json.FromJson::{from_json}

///|
pub extend AppConfigLayerMetadata with @json.FromJson::{from_json}

///|
pub extend AppConversationGitInfo with @json.FromJson::{from_json}

///|
pub extend AppExperimentalFeature with @json.FromJson::{from_json}

///|
pub extend AppHookOutputEntryKind with @json.FromJson::{from_json}

///|
pub extend AppMcpResourceTemplate with @json.FromJson::{from_json}

///|
pub extend AppMemoryCitationEntry with @json.FromJson::{from_json}

///|
pub extend AppPluginInstallPolicy with @json.FromJson::{from_json}

///|
pub extend AppResponseContentItem with @json.FromJson::{from_json}

///|
pub extend AppResponseImageDetail with @json.FromJson::{from_json}

///|
pub extend AppReviewStartResponse with @json.FromJson::{from_json}

///|
pub extend AppSkillToolDependency with @json.FromJson::{from_json}

///|
pub extend AppThreadStartResponse with @json.FromJson::{from_json}

///|
pub extend AppTokenUsageBreakdown with @json.FromJson::{from_json}

///|
pub extend AppWebSearchToolConfig with @json.FromJson::{from_json}

///|
pub extend CommandExecutionStatus with @json.FromJson::{from_json}

///|
pub extend AppFileSystemAccessMode with @json.FromJson::{from_json}

///|
pub extend AppFsReadDirectoryEntry with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceInterface with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationSchema with @json.FromJson::{from_json}

///|
pub extend AppModelAvailabilityNux with @json.FromJson::{from_json}

///|
pub extend AppNonSteerableTurnKind with @json.FromJson::{from_json}

///|
pub extend AppPermissionGrantScope with @json.FromJson::{from_json}

///|
pub extend AppRateLimitReachedType with @json.FromJson::{from_json}

///|
pub extend AppResidencyRequirement with @json.FromJson::{from_json}

///|
pub extend AppResponseMessagePhase with @json.FromJson::{from_json}

///|
pub extend AppThreadResumeResponse with @json.FromJson::{from_json}

///|
pub extend AppWebSearchContextSize with @json.FromJson::{from_json}

///|
pub extend AppCollaborationModeKind with @json.FromJson::{from_json}

///|
pub extend AppCollaborationModeMask with @json.FromJson::{from_json}

///|
pub extend AppFileSystemSpecialPath with @json.FromJson::{from_json}

///|
pub extend AppFsGetMetadataResponse with @json.FromJson::{from_json}

///|
pub extend AppFuzzyFileSearchResult with @json.FromJson::{from_json}

///|
pub extend AppGuardianCommandSource with @json.FromJson::{from_json}

///|
pub extend AppMcpServerStartupState with @json.FromJson::{from_json}

///|
pub extend AppPluginInstallResponse with @json.FromJson::{from_json}

///|
pub extend AppReasoningEffortOption with @json.FromJson::{from_json}

///|
pub extend AppSandboxWorkspaceWrite with @json.FromJson::{from_json}

///|
pub extend AppThreadCollabAgentTool with @json.FromJson::{from_json}

///|
pub extend AppThreadGoalGetResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadGoalSetResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadPatchChangeKind with @json.FromJson::{from_json}

///|
pub extend AppThreadSectionResponse with @json.FromJson::{from_json}

///|
pub extend AppDynamicToolCallRequest with @json.FromJson::{from_json}

///|
pub extend AppFeedbackUploadResponse with @json.FromJson::{from_json}

///|
pub extend AppFileSystemSandboxEntry with @json.FromJson::{from_json}

///|
pub extend AppGuardianApprovalReview with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceAddResponse with @json.FromJson::{from_json}

///|
pub extend AppNetworkApprovalContext with @json.FromJson::{from_json}

///|
pub extend AppNetworkPolicyAmendment with @json.FromJson::{from_json}

///|
pub extend AppPluginMarketplaceEntry with @json.FromJson::{from_json}

///|
pub extend AppThreadCollabAgentState with @json.FromJson::{from_json}

///|
pub extend AppThreadFileUpdateChange with @json.FromJson::{from_json}

///|
pub extend AppThreadMcpToolCallError with @json.FromJson::{from_json}

///|
pub extend AppThreadPatchApplyStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadRollbackResponse with @json.FromJson::{from_json}

///|
pub extend AppFsReadDirectoryResponse with @json.FromJson::{from_json}

///|
pub extend AppFuzzyFileSearchResponse with @json.FromJson::{from_json}

///|
pub extend AppNetworkApprovalProtocol with @json.FromJson::{from_json}

///|
pub extend AppNetworkPolicyRuleAction with @json.FromJson::{from_json}

///|
pub extend AppResponseWebSearchAction with @json.FromJson::{from_json}

///|
pub extend AppThreadCollabAgentStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadGoalClearResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadMcpToolCallResult with @json.FromJson::{from_json}

///|
pub extend AppThreadMcpToolCallStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadSectionAppearance with @json.FromJson::{from_json}

///|
pub extend AppThreadTurnsListResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadUnsubscribeStatus with @json.FromJson::{from_json}

///|
pub extend AppWindowsSandboxSetupMode with @json.FromJson::{from_json}

///|
pub extend AppAutoReviewDecisionSource with @json.FromJson::{from_json}

///|
pub extend AppCancelLoginAccountStatus with @json.FromJson::{from_json}

///|
pub extend AppConfigBatchWriteResponse with @json.FromJson::{from_json}

///|
pub extend AppConfigOverriddenMetadata with @json.FromJson::{from_json}

///|
pub extend AppConfigValueWriteResponse with @json.FromJson::{from_json}

///|
pub extend AppExperimentalFeatureStage with @json.FromJson::{from_json}

///|
pub extend AppFuzzyFileSearchMatchType with @json.FromJson::{from_json}

///|
pub extend AppGrantedPermissionProfile with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceLoadErrorInfo with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationNumberType with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationObjectType with @json.FromJson::{from_json}

///|
pub extend AppRequestPermissionProfile with @json.FromJson::{from_json}

///|
pub extend AppResponseLocalShellAction with @json.FromJson::{from_json}

///|
pub extend AppResponseLocalShellStatus with @json.FromJson::{from_json}

///|
pub extend AppResponseReasoningContent with @json.FromJson::{from_json}

///|
pub extend AppResponseReasoningSummary with @json.FromJson::{from_json}

///|
pub extend AppThreadLoadedListResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadRealtimeAudioChunk with @json.FromJson::{from_json}

///|
pub extend AppAccountLoginStartResponse with @json.FromJson::{from_json}

///|
pub extend AppFileChangeApprovalRequest with @json.FromJson::{from_json}

///|
pub extend AppGuardianUserAuthorization with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceRemoveResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationConstOption with @json.FromJson::{from_json}

///|
pub extend AppMcpServerToolCallResponse with @json.FromJson::{from_json}

///|
pub extend AppSkillsConfigWriteResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadSectionListResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadUnsubscribeResponse with @json.FromJson::{from_json}

///|
pub extend AppAccountLoginCancelResponse with @json.FromJson::{from_json}

///|
pub extend AppAddCreditsNudgeEmailStatus with @json.FromJson::{from_json}

///|
pub extend AppAttestationGenerateRequest with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceUpgradeResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationNumberSchema with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationStringFormat with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationStringSchema with @json.FromJson::{from_json}

///|
pub extend AppToolRequestUserInputOption with @json.FromJson::{from_json}

///|
pub extend AppMarketplaceUpgradeErrorInfo with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationBooleanSchema with @json.FromJson::{from_json}

///|
pub extend AppMcpServerElicitationContent with @json.FromJson::{from_json}

///|
pub extend AppMcpServerElicitationRequest with @json.FromJson::{from_json}

///|
pub extend AppMcpServerOauthLoginResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpServerStatusListResponse with @json.FromJson::{from_json}

///|
pub extend AppRealtimeConversationVersion with @json.FromJson::{from_json}

///|
pub extend AppThreadDynamicToolCallStatus with @json.FromJson::{from_json}

///|
pub extend AppToolRequestUserInputRequest with @json.FromJson::{from_json}

///|
pub extend AppAdditionalNetworkPermissions with @json.FromJson::{from_json}

///|
pub extend AppCommandExecutionApprovalKind with @json.FromJson::{from_json}

///|
pub extend AppGuardianApprovalReviewAction with @json.FromJson::{from_json}

///|
pub extend AppGuardianApprovalReviewStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadCommandExecutionSource with @json.FromJson::{from_json}

///|
pub extend AppThreadCommandExecutionStatus with @json.FromJson::{from_json}

///|
pub extend AppThreadMetadataUpdateResponse with @json.FromJson::{from_json}

///|
pub extend AppToolRequestUserInputQuestion with @json.FromJson::{from_json}

///|
pub extend AppAccountRateLimitsReadResponse with @json.FromJson::{from_json}

///|
pub extend AppCollaborationModeListResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationPrimitiveSchema with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationTitledEnumItems with @json.FromJson::{from_json}

///|
pub extend AppMcpServerResourceReadResponse with @json.FromJson::{from_json}

///|
pub extend AppRemoteControlConnectionStatus with @json.FromJson::{from_json}

///|
pub extend AppChatgptAuthTokensRefreshReason with @json.FromJson::{from_json}

///|
pub extend AppConfigRequirementsReadResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationStringEnumSchema with @json.FromJson::{from_json}

///|
pub extend AppMockExperimentalMethodResponse with @json.FromJson::{from_json}

///|
pub extend AppResponseFunctionCallOutputBody with @json.FromJson::{from_json}

///|
pub extend AppAdditionalFileSystemPermissions with @json.FromJson::{from_json}

///|
pub extend AppChatgptAuthTokensRefreshRequest with @json.FromJson::{from_json}

///|
pub extend AppCommandExecutionApprovalRequest with @json.FromJson::{from_json}

///|
pub extend AppExperimentalFeatureListResponse with @json.FromJson::{from_json}

///|
pub extend AppMcpElicitationUntitledEnumItems with @json.FromJson::{from_json}

///|
pub extend AppThreadCollabAgentToolCallStatus with @json.FromJson::{from_json}

///|
pub extend AppDynamicToolCallOutputContentItem with @json.FromJson::{from_json}

///|
pub extend AppExternalAgentConfigMigrationItem with @json.FromJson::{from_json}

///|
pub extend AppThreadElicitationCounterResponse with @json.FromJson::{from_json}

///|
pub extend AppThreadRealtimeListVoicesResponse with @json.FromJson::{from_json}

///|
pub extend AppWindowsSandboxSetupStartResponse with @json.FromJson::{from_json}

///|
pub extend AppExternalAgentConfigDetectResponse with @json.FromJson::{from_json}

///|
pub extend AppPermissionsRequestApprovalRequest with @json.FromJson::{from_json}

///|
pub extend AppExternalAgentConfigMigrationItemType with @json.FromJson::{
  from_json,
}

///|
pub extend AppMcpElicitationTitledStringEnumSchema with @json.FromJson::{
  from_json,
}

///|
pub extend AppMcpElicitationTitledMultiSelectSchema with @json.FromJson::{
  from_json,
}

///|
pub extend AppModelProviderCapabilitiesReadResponse with @json.FromJson::{
  from_json,
}

///|
pub extend AppResponseFunctionCallOutputContentItem with @json.FromJson::{
  from_json,
}

///|
pub extend AppAccountSendAddCreditsNudgeEmailResponse with @json.FromJson::{
  from_json,
}

///|
pub extend AppMcpElicitationUntitledMultiSelectSchema with @json.FromJson::{
  from_json,
}

///|
pub extend AppExperimentalFeatureEnablementSetResponse with @json.FromJson::{
  from_json,
}
