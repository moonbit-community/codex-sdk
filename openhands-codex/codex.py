from typing import Literal
from pydantic import BaseModel, SerializeAsAny
from uuid import UUID

# Items


class CodexItem(BaseModel):
    id: str


class ErrorItem(CodexItem):
    type: Literal["error"] = "error"
    message: str


class AgentMessageItem(CodexItem):
    type: Literal["agent_message"] = "agent_message"
    text: str


# Events

class CodexEvent(BaseModel):
    pass


class ThreadStarted(CodexEvent):
    """Emitted when a new thread is started as the first event."""
    type: Literal["thread.started"] = "thread.started"
    thread_id: UUID


class ThreadErrorEvent(CodexEvent):
    """Represents an unrecoverable error emitted directly by the event stream."""
    type: Literal["error"] = "error"
    message: str


class TurnStarted(CodexEvent):
    """Emitted when a turn is started by sending a new prompt to the model.
    A turn encompasses all events that happen while the agent is processing the prompt."""
    type: Literal["turn.started"] = "turn.started"


class TurnCompleted(CodexEvent):
    type: Literal["turn.completed"] = "turn.completed"
    usage: Usage


class TurnFailed(CodexEvent):
    type: Literal["turn.failed"] = "turn.failed"
    error: ThreadError


class ItemCompleted(CodexEvent):
    type: Literal["item.completed"] = "item.completed"
    item: SerializeAsAny[CodexItem]

# Misc


class Usage(BaseModel):
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int


class ThreadError(BaseModel):
    message: str
