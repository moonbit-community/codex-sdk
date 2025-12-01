import os
import uuid
import argparse
import sys
import traceback

from pathlib import Path

from openhands.sdk import LLM, Agent, Conversation, Tool
import openhands.sdk.event as ose
from openhands.sdk.llm import content_to_str
from openhands.sdk.conversation.visualizer import ConversationVisualizerBase
from openhands.sdk.llm.exceptions import LLMError
from openhands.tools.file_editor import FileEditorTool
from openhands.tools.task_tracker import TaskTrackerTool
from openhands.tools.terminal import TerminalTool
from openhands.tools.glob import GlobTool

import codex


class JsonVisualizer(ConversationVisualizerBase):
    def on_event(self, event: ose.Event) -> None:
        super().on_event(event)
        if isinstance(event, ose.SystemPromptEvent):
            print(codex.TurnStarted().model_dump_json())
        elif isinstance(event, ose.MessageEvent):
            message = event.to_llm_message()
            if message is not None and message.role == "assistant":
                print(codex.ItemCompleted(
                    item=codex.AgentMessageItem(
                        text='\n'.join(content_to_str(message.content)), id=event.id)
                ).model_dump_json())


def execute(message: str, id: uuid.UUID | None = None, workspace: Path | None = None, model: str = "anthropic/claude-haiku-4.5"):
    llm = LLM(
        model=model,
        api_key=os.getenv("CODEX_API_KEY") or os.getenv("OPENAI_API_KEY"),
        max_output_tokens=64000,
    )

    agent = Agent(
        llm=llm,
        tools=[
            Tool(name=TerminalTool.name),
            Tool(name=FileEditorTool.name),
            Tool(name=TaskTrackerTool.name),
            Tool(name=GlobTool.name),
        ],
    )
    conversation = Conversation(
        agent=agent,
        workspace=workspace or os.getcwd(),
        persistence_dir=Path.home() / ".openhands" / "conversations",
        visualizer=JsonVisualizer(),
        conversation_id=id,
    )
    if id is None:
        print(codex.ThreadStarted(thread_id=conversation.id).model_dump_json())
    try:
        conversation.send_message(message)
        conversation.run()
        token_usage = llm.metrics.accumulated_token_usage
        if token_usage is not None:
            print(codex.TurnCompleted(usage=codex.Usage(
                input_tokens=token_usage.prompt_tokens,
                cached_input_tokens=token_usage.cache_read_tokens,
                output_tokens=token_usage.completion_tokens,
            )).model_dump_json())
        else:
            print(codex.TurnCompleted(usage=codex.Usage(
                input_tokens=0, cached_input_tokens=0, output_tokens=0,
            )).model_dump_json())
    except LLMError as e:
        print(codex.TurnFailed(error=codex.ThreadError(
            message=e.message
        )).model_dump_json())

    except Exception as e:
        print(codex.ThreadErrorEvent(
            message=traceback.format_exc()
        ).model_dump_json())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run the conversation script.")
    subparsers = parser.add_subparsers(dest='command')
    exec_parser = subparsers.add_parser(
        "exec",
        help="Run Codex non-interactively"
    )
    exec_parser.add_argument(
        "--model",
        default="anthropic/claude-haiku-4.5",
    )
    exec_parser.add_argument(
        "--experimental-json",
        action="store_true",
    )
    exec_parser.add_argument(
        "--sandbox",
    )
    exec_parser.add_argument(
        "--cd",
    )
    exec_parser.add_argument(
        "--skip-git-repo-check",
        action="store_true",
    )
    exec_subparsers = exec_parser.add_subparsers(dest='subcommand')
    resume_parser = exec_subparsers.add_parser(
        "resume", help="Resume a session")
    resume_parser.add_argument("SESSION_ID", help="The session ID to resume")

    args = parser.parse_args(sys.argv[1:])
    if args.command == 'exec':
        if args.subcommand == 'resume':
            id = uuid.UUID(args.SESSION_ID)
        else:
            # No subcommand: always read from stdin
            id = None
        message = sys.stdin.read().strip()
        workspace = args.cd
        model = args.model

        assert message != "", "PROMPT cannot be empty"
        execute(message=message, id=id,
                workspace=workspace, model=model)
    else:
        parser.error("Invalid command")
