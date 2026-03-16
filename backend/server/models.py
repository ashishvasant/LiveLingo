"""Pydantic models for WebSocket message protocol."""

from enum import Enum
from typing import Optional

from pydantic import BaseModel


# --- Client -> Server messages ---

class ClientMessageType(str, Enum):
    AUDIO = "audio"
    VIDEO_FRAME = "video_frame"
    TEXT = "text"
    SET_SCENARIO = "set_scenario"
    END = "end"


class ClientMessage(BaseModel):
    type: ClientMessageType
    data: Optional[str] = None      # base64 audio/video data
    text: Optional[str] = None      # text content
    scenario: Optional[str] = None  # scenario prompt


# --- Server -> Client messages ---

class ServerMessageType(str, Enum):
    USER_TRANSCRIPT = "user_transcript"
    AGENT_TRANSCRIPT = "agent_transcript"
    AGENT_AUDIO = "agent_audio"
    TURN_COMPLETE = "turn_complete"
    STATUS = "status"
    ERROR = "error"
    SCENARIOS = "scenarios"


class ServerMessage(BaseModel):
    type: ServerMessageType
    text: Optional[str] = None
    data: Optional[str] = None
    message_id: Optional[str] = None
    status: Optional[str] = None
    message: Optional[str] = None
    scenarios: Optional[dict] = None
