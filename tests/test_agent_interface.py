"""Contract tests for AgentInterface.

These guard the seam that lets host_agent_server accept any agent
implementation. If these break, swapping OpenAIAgentWithMCP for the
MSAF sibling (or any future agent) will fail at host startup.
"""

import pytest

from agent_interface import AgentInterface, check_agent_inheritance


class _FakeAgent(AgentInterface):
    """Minimal valid implementation used to prove the ABC accepts subclasses."""

    def __init__(self):
        self.initialized = False
        self.cleaned_up = False
        self.last_message: str | None = None

    async def initialize(self) -> None:
        self.initialized = True

    async def process_user_message(self, message, auth, auth_handler_name, context) -> str:
        self.last_message = message
        return f"echo:{message}"

    async def cleanup(self) -> None:
        self.cleaned_up = True


def test_abc_rejects_partial_implementation():
    class Partial(AgentInterface):
        async def initialize(self) -> None:
            pass

    with pytest.raises(TypeError):
        Partial()  # type: ignore[abstract]


def test_check_agent_inheritance_accepts_valid_subclass():
    assert check_agent_inheritance(_FakeAgent) is True


def test_check_agent_inheritance_rejects_unrelated_class():
    class NotAnAgent:
        pass

    assert check_agent_inheritance(NotAnAgent) is False  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_fake_agent_lifecycle_round_trip():
    agent = _FakeAgent()
    await agent.initialize()
    assert agent.initialized is True

    reply = await agent.process_user_message("hi", auth=None, auth_handler_name="", context=None)
    assert reply == "echo:hi"
    assert agent.last_message == "hi"

    await agent.cleanup()
    assert agent.cleaned_up is True
