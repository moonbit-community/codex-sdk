# App-Server Session Owns Routing

The SDK keeps `CodexAppConnection` as the raw JSON-RPC transport escape hatch,
but the app-facing app-server API is an app-server session that owns the single
notification pump, server-initiated request routing, and typed outbound RPC
methods. This avoids exposing the shared event stream to application code while
still allowing session-level RPCs such as plugin, marketplace, filesystem,
configuration, and model operations to be called from the ergonomic API.
