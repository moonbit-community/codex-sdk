// Explicit `Debug::to_repr` promotions for this package.
//
// `derive(Debug)` used to promote `to_repr` implicitly as a regular method of
// the type. That implicit promotion is deprecated, so each one is declared here
// explicitly, exactly as the compiler asks for.

///|
pub extend Usage with @debug.Debug::{to_repr}

///|
pub extend AppInfo with @debug.Debug::{to_repr}

///|
pub extend AppTurn with @debug.Debug::{to_repr}

///|
pub extend AppModel with @debug.Debug::{to_repr}

///|
pub extend TodoItem with @debug.Debug::{to_repr}

///|
pub extend AppThread with @debug.Debug::{to_repr}

///|
pub extend AppAccount with @debug.Debug::{to_repr}

///|
pub extend AppMcpTool with @debug.Debug::{to_repr}

///|
pub extend AppSummary with @debug.Debug::{to_repr}

///|
pub extend CollabTool with @debug.Debug::{to_repr}

///|
pub extend ThreadItem with @debug.Debug::{to_repr}

///|
pub extend AppAuthMode with @debug.Debug::{to_repr}

///|
pub extend AppPlanType with @debug.Debug::{to_repr}

///|
pub extend SandboxMode with @debug.Debug::{to_repr}

///|
pub extend AppByteRange with @debug.Debug::{to_repr}

///|
pub extend AppHookScope with @debug.Debug::{to_repr}

///|
pub extend AppProfileV2 with @debug.Debug::{to_repr}

///|
pub extend AppRequestId with @debug.Debug::{to_repr}

///|
pub extend AppTextRange with @debug.Debug::{to_repr}

///|
pub extend AppTurnError with @debug.Debug::{to_repr}

///|
pub extend AppUserInput with @debug.Debug::{to_repr}

///|
pub extend AppAppsConfig with @debug.Debug::{to_repr}

///|
pub extend AppClientInfo with @debug.Debug::{to_repr}

///|
pub extend AppConfigEdit with @debug.Debug::{to_repr}

///|
pub extend AppHookSource with @debug.Debug::{to_repr}

///|
pub extend AppListParams with @debug.Debug::{to_repr}

///|
pub extend AppSkillScope with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoal with @debug.Debug::{to_repr}

///|
pub extend AppThreadItem with @debug.Debug::{to_repr}

///|
pub extend AppToolConfig with @debug.Debug::{to_repr}

///|
pub extend AppTurnStatus with @debug.Debug::{to_repr}

///|
pub extend AppConfigLayer with @debug.Debug::{to_repr}

///|
pub extend AppImageDetail with @debug.Debug::{to_repr}

///|
pub extend AppMcpResource with @debug.Debug::{to_repr}

///|
pub extend AppPersonality with @debug.Debug::{to_repr}

///|
pub extend AppServerEvent with @debug.Debug::{to_repr}

///|
pub extend AppTextElement with @debug.Debug::{to_repr}

///|
pub extend AppToolsConfig with @debug.Debug::{to_repr}

///|
pub extend AppFsCopyParams with @debug.Debug::{to_repr}

///|
pub extend AppFsPathParams with @debug.Debug::{to_repr}

///|
pub extend AppHookMetadata with @debug.Debug::{to_repr}

///|
pub extend AppListResponse with @debug.Debug::{to_repr}

///|
pub extend AppMessagePhase with @debug.Debug::{to_repr}

///|
pub extend AppOutputStream with @debug.Debug::{to_repr}

///|
pub extend AppPluginDetail with @debug.Debug::{to_repr}

///|
pub extend AppPluginSource with @debug.Debug::{to_repr}

///|
pub extend AppResponseItem with @debug.Debug::{to_repr}

///|
pub extend AppReviewTarget with @debug.Debug::{to_repr}

///|
pub extend AppSkillSummary with @debug.Debug::{to_repr}

///|
pub extend AppTextPosition with @debug.Debug::{to_repr}

///|
pub extend AppThreadStatus with @debug.Debug::{to_repr}

///|
pub extend AppToolApproval with @debug.Debug::{to_repr}

///|
pub extend AppTurnPlanStep with @debug.Debug::{to_repr}

///|
pub extend PatchChangeKind with @debug.Debug::{to_repr}

///|
pub extend AppCommandAction with @debug.Debug::{to_repr}

///|
pub extend AppConfigToolsV2 with @debug.Debug::{to_repr}

///|
pub extend AppFsWatchParams with @debug.Debug::{to_repr}

///|
pub extend AppHookErrorInfo with @debug.Debug::{to_repr}

///|
pub extend AppHookEventName with @debug.Debug::{to_repr}

///|
pub extend AppHookRunStatus with @debug.Debug::{to_repr}

///|
pub extend AppInputModality with @debug.Debug::{to_repr}

///|
pub extend AppMcpAuthStatus with @debug.Debug::{to_repr}

///|
pub extend AppMergeStrategy with @debug.Debug::{to_repr}

///|
pub extend AppNetworkAccess with @debug.Debug::{to_repr}

///|
pub extend AppNullableInt64 with @debug.Debug::{to_repr}

///|
pub extend AppPluginSummary with @debug.Debug::{to_repr}

///|
pub extend AppRealtimeVoice with @debug.Debug::{to_repr}

///|
pub extend AppSandboxPolicy with @debug.Debug::{to_repr}

///|
pub extend AppServerRequest with @debug.Debug::{to_repr}

///|
pub extend AppSessionSource with @debug.Debug::{to_repr}

///|
pub extend AppSkillMetadata with @debug.Debug::{to_repr}

///|
pub extend AppSortDirection with @debug.Debug::{to_repr}

///|
pub extend AppThreadListCwd with @debug.Debug::{to_repr}

///|
pub extend AppThreadSection with @debug.Debug::{to_repr}

///|
pub extend AppThreadSortKey with @debug.Debug::{to_repr}

///|
pub extend AppWebSearchMode with @debug.Debug::{to_repr}

///|
pub extend CollabAgentState with @debug.Debug::{to_repr}

///|
pub extend FileUpdateChange with @debug.Debug::{to_repr}

///|
pub extend PatchApplyStatus with @debug.Debug::{to_repr}

///|
pub extend AppApprovalPolicy with @debug.Debug::{to_repr}

///|
pub extend AppCodexErrorInfo with @debug.Debug::{to_repr}

///|
pub extend AppConfigSnapshot with @debug.Debug::{to_repr}

///|
pub extend AppFileSystemPath with @debug.Debug::{to_repr}

///|
pub extend AppFsRemoveParams with @debug.Debug::{to_repr}

///|
pub extend AppHookRunSummary with @debug.Debug::{to_repr}

///|
pub extend AppHooksListEntry with @debug.Debug::{to_repr}

///|
pub extend AppMemoryCitation with @debug.Debug::{to_repr}

///|
pub extend AppModelVerbosity with @debug.Debug::{to_repr}

///|
pub extend AppNamedMigration with @debug.Debug::{to_repr}

///|
pub extend AppNullableString with @debug.Debug::{to_repr}

///|
pub extend AppReviewDelivery with @debug.Debug::{to_repr}

///|
pub extend AppServerResponse with @debug.Debug::{to_repr}

///|
pub extend AppSkillErrorInfo with @debug.Debug::{to_repr}

///|
pub extend AppSkillInterface with @debug.Debug::{to_repr}

///|
pub extend AppSubAgentSource with @debug.Debug::{to_repr}

///|
pub extend AppThreadIdParams with @debug.Debug::{to_repr}

///|
pub extend CollabAgentStatus with @debug.Debug::{to_repr}

///|
pub extend McpToolCallResult with @debug.Debug::{to_repr}

///|
pub extend McpToolCallStatus with @debug.Debug::{to_repr}

///|
pub extend AppAnalyticsConfig with @debug.Debug::{to_repr}

///|
pub extend AppConnectorConfig with @debug.Debug::{to_repr}

///|
pub extend AppCreditsSnapshot with @debug.Debug::{to_repr}

///|
pub extend AppFsUnwatchParams with @debug.Debug::{to_repr}

///|
pub extend AppFsWatchResponse with @debug.Debug::{to_repr}

///|
pub extend AppHookHandlerType with @debug.Debug::{to_repr}

///|
pub extend AppHookOutputEntry with @debug.Debug::{to_repr}

///|
pub extend AppHookTrustStatus with @debug.Debug::{to_repr}

///|
pub extend AppHooksListParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerStatus with @debug.Debug::{to_repr}

///|
pub extend AppModelListParams with @debug.Debug::{to_repr}

///|
pub extend AppPluginInterface with @debug.Debug::{to_repr}

///|
pub extend AppRateLimitWindow with @debug.Debug::{to_repr}

///|
pub extend AppReasoningEffort with @debug.Debug::{to_repr}

///|
pub extend AppSkillsListEntry with @debug.Debug::{to_repr}

///|
pub extend AppThreadItemEvent with @debug.Debug::{to_repr}

///|
pub extend AppThreadUserInput with @debug.Debug::{to_repr}

///|
pub extend AppTurnStartParams with @debug.Debug::{to_repr}

///|
pub extend AppTurnSteerParams with @debug.Debug::{to_repr}

///|
pub extend AppWebSearchAction with @debug.Debug::{to_repr}

///|
pub extend AppConfigReadParams with @debug.Debug::{to_repr}

///|
pub extend AppInitializeParams with @debug.Debug::{to_repr}

///|
pub extend AppMigrationDetails with @debug.Debug::{to_repr}

///|
pub extend AppModelServiceTier with @debug.Debug::{to_repr}

///|
pub extend AppModelUpgradeInfo with @debug.Debug::{to_repr}

///|
pub extend AppPluginAuthPolicy with @debug.Debug::{to_repr}

///|
pub extend AppPluginListParams with @debug.Debug::{to_repr}

///|
pub extend AppPluginReadParams with @debug.Debug::{to_repr}

///|
pub extend AppPluginsMigration with @debug.Debug::{to_repr}

///|
pub extend AppReasoningSummary with @debug.Debug::{to_repr}

///|
pub extend AppSessionMigration with @debug.Debug::{to_repr}

///|
pub extend AppSkillsListParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadActiveFlag with @debug.Debug::{to_repr}

///|
pub extend AppThreadForkParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoalStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadListParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadMemoryMode with @debug.Debug::{to_repr}

///|
pub extend AppThreadReadParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSourceKind with @debug.Debug::{to_repr}

///|
pub extend AppThreadTokenUsage with @debug.Debug::{to_repr}

///|
pub extend AppTurnStartOptions with @debug.Debug::{to_repr}

///|
pub extend AppAccountReadParams with @debug.Debug::{to_repr}

///|
pub extend AppApprovalsReviewer with @debug.Debug::{to_repr}

///|
pub extend AppAppsDefaultConfig with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecParams with @debug.Debug::{to_repr}

///|
pub extend AppConfigLayerSource with @debug.Debug::{to_repr}

///|
pub extend AppConfigWriteStatus with @debug.Debug::{to_repr}

///|
pub extend AppCursorLimitParams with @debug.Debug::{to_repr}

///|
pub extend AppForcedLoginMethod with @debug.Debug::{to_repr}

///|
pub extend AppFsWriteFileParams with @debug.Debug::{to_repr}

///|
pub extend AppGuardianRiskLevel with @debug.Debug::{to_repr}

///|
pub extend AppHookExecutionMode with @debug.Debug::{to_repr}

///|
pub extend AppHooksListResponse with @debug.Debug::{to_repr}

///|
pub extend AppModelListResponse with @debug.Debug::{to_repr}

///|
pub extend AppModelVerification with @debug.Debug::{to_repr}

///|
pub extend AppMultiAgentVersion with @debug.Debug::{to_repr}

///|
pub extend AppRateLimitSnapshot with @debug.Debug::{to_repr}

///|
pub extend AppReviewStartParams with @debug.Debug::{to_repr}

///|
pub extend AppSkillDependencies with @debug.Debug::{to_repr}

///|
pub extend AppThreadStartParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadStartSource with @debug.Debug::{to_repr}

///|
pub extend AppTurnStartResponse with @debug.Debug::{to_repr}

///|
pub extend AppTurnSteerResponse with @debug.Debug::{to_repr}

///|
pub extend AppWebSearchLocation with @debug.Debug::{to_repr}

///|
pub extend CollabToolCallStatus with @debug.Debug::{to_repr}

///|
pub extend AppConfigReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppConfigRequirements with @debug.Debug::{to_repr}

///|
pub extend AppFsReadFileResponse with @debug.Debug::{to_repr}

///|
pub extend AppHookPromptFragment with @debug.Debug::{to_repr}

///|
pub extend AppInitializeResponse with @debug.Debug::{to_repr}

///|
pub extend AppLoginAccountParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpResourceContent with @debug.Debug::{to_repr}

///|
pub extend AppModelRerouteReason with @debug.Debug::{to_repr}

///|
pub extend AppPluginListResponse with @debug.Debug::{to_repr}

///|
pub extend AppPluginReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppRealtimeVoicesList with @debug.Debug::{to_repr}

///|
pub extend AppSkillsListResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadForkResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadListResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadResumeParams with @debug.Debug::{to_repr}

///|
pub extend AppTurnPlanStepStatus with @debug.Debug::{to_repr}

///|
pub extend AppAccountReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppAddCreditsNudgeKind with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecResponse with @debug.Debug::{to_repr}

///|
pub extend AppConfigLayerMetadata with @debug.Debug::{to_repr}

///|
pub extend AppConversationGitInfo with @debug.Debug::{to_repr}

///|
pub extend AppExperimentalFeature with @debug.Debug::{to_repr}

///|
pub extend AppHookOutputEntryKind with @debug.Debug::{to_repr}

///|
pub extend AppMcpResourceTemplate with @debug.Debug::{to_repr}

///|
pub extend AppMemoryCitationEntry with @debug.Debug::{to_repr}

///|
pub extend AppPluginInstallParams with @debug.Debug::{to_repr}

///|
pub extend AppPluginInstallPolicy with @debug.Debug::{to_repr}

///|
pub extend AppResponseContentItem with @debug.Debug::{to_repr}

///|
pub extend AppResponseImageDetail with @debug.Debug::{to_repr}

///|
pub extend AppReviewStartResponse with @debug.Debug::{to_repr}

///|
pub extend AppSkillToolDependency with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoalSetParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSetNameParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadStartResponse with @debug.Debug::{to_repr}

///|
pub extend AppTokenUsageBreakdown with @debug.Debug::{to_repr}

///|
pub extend AppTurnInterruptParams with @debug.Debug::{to_repr}

///|
pub extend AppWebSearchToolConfig with @debug.Debug::{to_repr}

///|
pub extend CommandExecutionStatus with @debug.Debug::{to_repr}

///|
pub extend AppFeedbackUploadParams with @debug.Debug::{to_repr}

///|
pub extend AppFileSystemAccessMode with @debug.Debug::{to_repr}

///|
pub extend AppFsReadDirectoryEntry with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceAddParams with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceInterface with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationSchema with @debug.Debug::{to_repr}

///|
pub extend AppModelAvailabilityNux with @debug.Debug::{to_repr}

///|
pub extend AppNonSteerableTurnKind with @debug.Debug::{to_repr}

///|
pub extend AppPermissionGrantScope with @debug.Debug::{to_repr}

///|
pub extend AppRateLimitReachedType with @debug.Debug::{to_repr}

///|
pub extend AppResidencyRequirement with @debug.Debug::{to_repr}

///|
pub extend AppResponseMessagePhase with @debug.Debug::{to_repr}

///|
pub extend AppServerRequestDetails with @debug.Debug::{to_repr}

///|
pub extend AppThreadResumeResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadRollbackParams with @debug.Debug::{to_repr}

///|
pub extend AppWebSearchContextSize with @debug.Debug::{to_repr}

///|
pub extend AppCollaborationModeKind with @debug.Debug::{to_repr}

///|
pub extend AppCollaborationModeMask with @debug.Debug::{to_repr}

///|
pub extend AppFileSystemSpecialPath with @debug.Debug::{to_repr}

///|
pub extend AppFsGetMetadataResponse with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchParams with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchResult with @debug.Debug::{to_repr}

///|
pub extend AppGuardianCommandSource with @debug.Debug::{to_repr}

///|
pub extend AppMcpResourceReadParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerStartupState with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerStatusDetail with @debug.Debug::{to_repr}

///|
pub extend AppPluginInstallResponse with @debug.Debug::{to_repr}

///|
pub extend AppPluginUninstallParams with @debug.Debug::{to_repr}

///|
pub extend AppReasoningEffortOption with @debug.Debug::{to_repr}

///|
pub extend AppSandboxWorkspaceWrite with @debug.Debug::{to_repr}

///|
pub extend AppThreadCollabAgentTool with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoalGetResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoalSetResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadPatchChangeKind with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadTurnsListParams with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecWriteParams with @debug.Debug::{to_repr}

///|
pub extend AppConfigBatchWriteParams with @debug.Debug::{to_repr}

///|
pub extend AppConfigValueWriteParams with @debug.Debug::{to_repr}

///|
pub extend AppDynamicToolCallRequest with @debug.Debug::{to_repr}

///|
pub extend AppFeedbackUploadResponse with @debug.Debug::{to_repr}

///|
pub extend AppFileSystemSandboxEntry with @debug.Debug::{to_repr}

///|
pub extend AppGuardianApprovalReview with @debug.Debug::{to_repr}

///|
pub extend AppInitializeCapabilities with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceAddResponse with @debug.Debug::{to_repr}

///|
pub extend AppNetworkApprovalContext with @debug.Debug::{to_repr}

///|
pub extend AppNetworkPolicyAmendment with @debug.Debug::{to_repr}

///|
pub extend AppPluginMarketplaceEntry with @debug.Debug::{to_repr}

///|
pub extend AppRealtimeOutputModality with @debug.Debug::{to_repr}

///|
pub extend AppThreadCollabAgentState with @debug.Debug::{to_repr}

///|
pub extend AppThreadFileUpdateChange with @debug.Debug::{to_repr}

///|
pub extend AppThreadLoadedListParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadMcpToolCallError with @debug.Debug::{to_repr}

///|
pub extend AppThreadPatchApplyStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadRollbackResponse with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecResizeParams with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecTerminalSize with @debug.Debug::{to_repr}

///|
pub extend AppFsCreateDirectoryParams with @debug.Debug::{to_repr}

///|
pub extend AppFsReadDirectoryResponse with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchResponse with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceRemoveParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerToolCallParams with @debug.Debug::{to_repr}

///|
pub extend AppNetworkApprovalProtocol with @debug.Debug::{to_repr}

///|
pub extend AppNetworkPolicyRuleAction with @debug.Debug::{to_repr}

///|
pub extend AppResponseWebSearchAction with @debug.Debug::{to_repr}

///|
pub extend AppSkillsConfigWriteParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadCollabAgentStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadGoalClearResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadInjectItemsParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadMcpToolCallResult with @debug.Debug::{to_repr}

///|
pub extend AppThreadMcpToolCallStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionAppearance with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionListParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionMoveParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadTurnsListResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadUnsubscribeStatus with @debug.Debug::{to_repr}

///|
pub extend AppWindowsSandboxSetupMode with @debug.Debug::{to_repr}

///|
pub extend AppAutoReviewDecisionSource with @debug.Debug::{to_repr}

///|
pub extend AppCancelLoginAccountParams with @debug.Debug::{to_repr}

///|
pub extend AppCancelLoginAccountStatus with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecProcessParams with @debug.Debug::{to_repr}

///|
pub extend AppConfigBatchWriteResponse with @debug.Debug::{to_repr}

///|
pub extend AppConfigOverriddenMetadata with @debug.Debug::{to_repr}

///|
pub extend AppConfigValueWriteResponse with @debug.Debug::{to_repr}

///|
pub extend AppExperimentalFeatureStage with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchMatchType with @debug.Debug::{to_repr}

///|
pub extend AppGrantedPermissionProfile with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceLoadErrorInfo with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceUpgradeParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationNumberType with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationObjectType with @debug.Debug::{to_repr}

///|
pub extend AppRequestPermissionProfile with @debug.Debug::{to_repr}

///|
pub extend AppResponseLocalShellAction with @debug.Debug::{to_repr}

///|
pub extend AppResponseLocalShellStatus with @debug.Debug::{to_repr}

///|
pub extend AppResponseReasoningContent with @debug.Debug::{to_repr}

///|
pub extend AppResponseReasoningSummary with @debug.Debug::{to_repr}

///|
pub extend AppThreadLoadedListResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeAudioChunk with @debug.Debug::{to_repr}

///|
pub extend AppThreadShellCommandParams with @debug.Debug::{to_repr}

///|
pub extend AppAccountLoginStartResponse with @debug.Debug::{to_repr}

///|
pub extend AppFileChangeApprovalRequest with @debug.Debug::{to_repr}

///|
pub extend AppGuardianUserAuthorization with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceRemoveResponse with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationConstOption with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerOauthLoginParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerStatusListParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerToolCallResponse with @debug.Debug::{to_repr}

///|
pub extend AppPluginListMarketplaceKind with @debug.Debug::{to_repr}

///|
pub extend AppSkillsConfigWriteResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadMemoryModeSetParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeStartParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionCreateParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionDeleteParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionListResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionUpdateParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadUnsubscribeResponse with @debug.Debug::{to_repr}

///|
pub extend AppAccountLoginCancelResponse with @debug.Debug::{to_repr}

///|
pub extend AppAddCreditsNudgeEmailStatus with @debug.Debug::{to_repr}

///|
pub extend AppAttestationGenerateRequest with @debug.Debug::{to_repr}

///|
pub extend AppFileChangeApprovalDecision with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceUpgradeResponse with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationNumberSchema with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationStringFormat with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationStringSchema with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerElicitationAction with @debug.Debug::{to_repr}

///|
pub extend AppThreadMetadataUpdateParams with @debug.Debug::{to_repr}

///|
pub extend AppToolRequestUserInputAnswer with @debug.Debug::{to_repr}

///|
pub extend AppToolRequestUserInputOption with @debug.Debug::{to_repr}

///|
pub extend AppMarketplaceUpgradeErrorInfo with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationBooleanSchema with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerElicitationContent with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerElicitationRequest with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerOauthLoginResponse with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerStatusListResponse with @debug.Debug::{to_repr}

///|
pub extend AppRealtimeConversationVersion with @debug.Debug::{to_repr}

///|
pub extend AppThreadDynamicToolCallStatus with @debug.Debug::{to_repr}

///|
pub extend AppToolRequestUserInputRequest with @debug.Debug::{to_repr}

///|
pub extend AppAdditionalNetworkPermissions with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecutionApprovalKind with @debug.Debug::{to_repr}

///|
pub extend AppGuardianApprovalReviewAction with @debug.Debug::{to_repr}

///|
pub extend AppGuardianApprovalReviewStatus with @debug.Debug::{to_repr}

///|
pub extend AppMockExperimentalMethodParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadCommandExecutionSource with @debug.Debug::{to_repr}

///|
pub extend AppThreadCommandExecutionStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadMetadataUpdateResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeStartTransport with @debug.Debug::{to_repr}

///|
pub extend AppToolRequestUserInputQuestion with @debug.Debug::{to_repr}

///|
pub extend AppAccountRateLimitsReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppCollaborationModeListResponse with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationPrimitiveSchema with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationTitledEnumItems with @debug.Debug::{to_repr}

///|
pub extend AppMcpServerResourceReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppRemoteControlConnectionStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadSectionAppearanceUpdate with @debug.Debug::{to_repr}

///|
pub extend AppChatgptAuthTokensRefreshReason with @debug.Debug::{to_repr}

///|
pub extend AppConfigRequirementsReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationStringEnumSchema with @debug.Debug::{to_repr}

///|
pub extend AppMockExperimentalMethodResponse with @debug.Debug::{to_repr}

///|
pub extend AppResponseFunctionCallOutputBody with @debug.Debug::{to_repr}

///|
pub extend AppSendAddCreditsNudgeEmailParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadElicitationCounterParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeAppendTextParams with @debug.Debug::{to_repr}

///|
pub extend AppWindowsSandboxSetupStartParams with @debug.Debug::{to_repr}

///|
pub extend AppAdditionalFileSystemPermissions with @debug.Debug::{to_repr}

///|
pub extend AppChatgptAuthTokensRefreshRequest with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecutionApprovalRequest with @debug.Debug::{to_repr}

///|
pub extend AppExperimentalFeatureListResponse with @debug.Debug::{to_repr}

///|
pub extend AppExternalAgentConfigDetectParams with @debug.Debug::{to_repr}

///|
pub extend AppExternalAgentConfigImportParams with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationUntitledEnumItems with @debug.Debug::{to_repr}

///|
pub extend AppThreadCollabAgentToolCallStatus with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeAppendAudioParams with @debug.Debug::{to_repr}

///|
pub extend AppCommandExecutionApprovalDecision with @debug.Debug::{to_repr}

///|
pub extend AppDynamicToolCallOutputContentItem with @debug.Debug::{to_repr}

///|
pub extend AppExternalAgentConfigMigrationItem with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchSessionStopParams with @debug.Debug::{to_repr}

///|
pub extend AppThreadElicitationCounterResponse with @debug.Debug::{to_repr}

///|
pub extend AppThreadRealtimeListVoicesResponse with @debug.Debug::{to_repr}

///|
pub extend AppWindowsSandboxSetupStartResponse with @debug.Debug::{to_repr}

///|
pub extend AppExternalAgentConfigDetectResponse with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchSessionStartParams with @debug.Debug::{to_repr}

///|
pub extend AppPermissionsRequestApprovalRequest with @debug.Debug::{to_repr}

///|
pub extend AppThreadMetadataGitInfoUpdateParams with @debug.Debug::{to_repr}

///|
pub extend AppFuzzyFileSearchSessionUpdateParams with @debug.Debug::{to_repr}

///|
pub extend AppExternalAgentConfigMigrationItemType with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationTitledStringEnumSchema with @debug.Debug::{to_repr}

///|
pub extend AppMcpElicitationTitledMultiSelectSchema with @debug.Debug::{to_repr}

///|
pub extend AppModelProviderCapabilitiesReadResponse with @debug.Debug::{to_repr}

///|
pub extend AppResponseFunctionCallOutputContentItem with @debug.Debug::{to_repr}

///|
pub extend AppExperimentalFeatureEnablementSetParams with @debug.Debug::{
  to_repr,
}

///|
pub extend AppAccountSendAddCreditsNudgeEmailResponse with @debug.Debug::{
  to_repr,
}

///|
pub extend AppMcpElicitationUntitledMultiSelectSchema with @debug.Debug::{
  to_repr,
}

///|
pub extend AppThreadApproveGuardianDeniedActionParams with @debug.Debug::{
  to_repr,
}

///|
pub extend AppExperimentalFeatureEnablementSetResponse with @debug.Debug::{
  to_repr,
}
