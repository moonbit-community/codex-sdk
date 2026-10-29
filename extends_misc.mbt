// Explicit trait-method promotions for this package.
//
// `derive(...)` and `impl` blocks used to promote their trait methods implicitly
// as regular methods of the type. That implicit promotion is deprecated, so each
// promoted method is declared here explicitly, exactly as the compiler asks for.

///|
pub extend TurnOptions with Default::{default}

///|
pub extend CodexOptions with Default::{default}

///|
pub extend ThreadOptions with Default::{default}

///|
pub extend TodoItem with Show::{to_string, output}

///|
pub extend AppRequestId with Eq::{not_equal, equal}

///|
pub extend AppServerOptions with Default::{default}

///|
pub extend AppTurnStatus with Eq::{not_equal, equal}

///|
pub extend CollabTool with Show::{to_string, output}

///|
pub extend SandboxMode with Show::{to_string, output}

///|
pub extend AppTurnStartOptions with Default::{default}

///|
pub extend ApprovalMode with Show::{to_string, output}

///|
pub extend WebSearchMode with Show::{to_string, output}

///|
pub extend PatchChangeKind with Show::{to_string, output}

///|
pub extend FileUpdateChange with Show::{to_string, output}

///|
pub extend PatchApplyStatus with Show::{to_string, output}

///|
pub extend CollabAgentStatus with Show::{to_string, output}

///|
pub extend McpToolCallStatus with Show::{to_string, output}

///|
pub extend AppThreadSectionListParams with Default::{default}

///|
pub extend CollabToolCallStatus with Show::{to_string, output}

///|
pub extend ModelReasoningEffort with Show::{to_string, output}

///|
pub extend CommandExecutionStatus with Show::{to_string, output}
