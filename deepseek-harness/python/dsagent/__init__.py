"""dsagent — a small DeepSeek-driven coding agent."""

from .agent import Agent, AgentConfig
from .client import DeepSeekClient, DeepSeekError
from .permissions import Mode, PermissionGate
from .tools import Workspace, build_tools

__all__ = [
    "Agent",
    "AgentConfig",
    "DeepSeekClient",
    "DeepSeekError",
    "Mode",
    "PermissionGate",
    "Workspace",
    "build_tools",
]
__version__ = "0.1.0"
