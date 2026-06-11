# Codex SDK

This context names the app-server concepts exposed by the SDK. It keeps the
protocol transport vocabulary distinct from application-level session,
thread, and turn concepts.

## Language

**App-Server Connection**:
The low-level JSON-RPC transport link to a Codex app server.
_Avoid_: runtime, session

**App-Server Session**:
The application-level scope that owns one app-server connection, request
routing, and notification routing.
_Avoid_: Raw connection, event stream

**App-Server Thread**:
A conversation scope inside an app-server session. It owns a thread id for
thread-scoped operations.
_Avoid_: Conversation handle

**Turn Stream**:
A turn-scoped notification stream keyed by one thread id and one turn id.
_Avoid_: Global event stream, shared stream

**Request Handler**:
Application code that answers server-initiated app-server requests.
_Avoid_: RPC method, notification handler
