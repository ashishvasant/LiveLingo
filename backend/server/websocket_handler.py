"""WebSocket handler for bidirectional audio/video streaming with ADK."""

import asyncio
import base64
import json
import logging
import uuid

from fastapi import WebSocket, WebSocketDisconnect
from google.adk.agents.live_request_queue import LiveRequestQueue
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types

from live_agent import DEFAULT_SCENARIOS, agent
from .models import ServerMessage, ServerMessageType

logger = logging.getLogger(__name__)

APP_NAME = "language-agent"

session_service = InMemorySessionService()
runner = Runner(
    app_name=APP_NAME,
    agent=agent,
    session_service=session_service,
)


async def _send(ws: WebSocket, msg: ServerMessage) -> bool:
    """Send a ServerMessage as JSON over the WebSocket. Returns False if send failed."""
    try:
        await ws.send_text(msg.model_dump_json(exclude_none=True))
        return True
    except Exception:
        return False


async def _upstream(
    ws: WebSocket,
    queue: LiveRequestQueue,
    user_id: str,
    session_id: str,
) -> None:
    """Read client messages and feed them into the LiveRequestQueue."""
    try:
        while True:
            raw = await ws.receive_text()
            data = json.loads(raw)
            msg_type = data.get("type")

            if msg_type == "audio":
                audio_bytes = base64.b64decode(data["data"])
                queue.send_realtime(
                    types.Blob(
                        data=audio_bytes,
                        mime_type="audio/pcm;rate=16000",
                    )
                )

            elif msg_type == "video_frame":
                frame_bytes = base64.b64decode(data["data"])
                queue.send_realtime(
                    types.Blob(data=frame_bytes, mime_type="image/jpeg")
                )

            elif msg_type == "text":
                content = types.Content(
                    parts=[types.Part(text=data.get("text", ""))]
                )
                queue.send_content(content)

            elif msg_type == "set_scenario":
                scenario_key = data.get("scenario", "")
                scenario_prompt = ""
                if scenario_key in DEFAULT_SCENARIOS:
                    scenario_prompt = DEFAULT_SCENARIOS[scenario_key]["prompt"]
                else:
                    scenario_prompt = scenario_key

                session = await session_service.get_session(
                    app_name=APP_NAME,
                    user_id=user_id,
                    session_id=session_id,
                )
                if session:
                    session.state["scenario"] = scenario_prompt

                await _send(
                    ws,
                    ServerMessage(
                        type=ServerMessageType.STATUS,
                        status="scenario_set",
                        message="Scenario updated",
                    ),
                )

            elif msg_type == "end":
                break

    except WebSocketDisconnect:
        logger.info("Client disconnected (upstream)")
    except Exception:
        logger.exception("Error in upstream task")


async def _downstream(
    ws: WebSocket,
    queue: LiveRequestQueue,
    user_id: str,
    session_id: str,
) -> None:
    """Read events from the ADK runner and forward to the client.

    Wraps run_live() in a reconnection loop so the session survives
    across multiple conversation turns.
    """
    run_config = RunConfig(
        streaming_mode=StreamingMode.BIDI,
        response_modalities=[types.Modality.AUDIO],
        input_audio_transcription=types.AudioTranscriptionConfig(),
        output_audio_transcription=types.AudioTranscriptionConfig(),
    )

    current_agent_msg_id: str | None = None

    while True:
        try:
            logger.info("Starting run_live loop for session %s", session_id)
            await _send(ws, ServerMessage(
                type=ServerMessageType.STATUS,
                status="live_active",
                message="Live session active",
            ))
            async for event in runner.run_live(
                user_id=user_id,
                session_id=session_id,
                live_request_queue=queue,
                run_config=run_config,
            ):
                # --- Input transcription (user speech) ---
                input_tx = getattr(event, "input_transcription", None)
                if input_tx and getattr(input_tx, "text", None):
                    msg_id = str(uuid.uuid4())
                    logger.info("User said: %s", input_tx.text[:80])
                    await _send(
                        ws,
                        ServerMessage(
                            type=ServerMessageType.USER_TRANSCRIPT,
                            text=input_tx.text,
                            message_id=msg_id,
                        ),
                    )

                # --- Output transcription (agent speech) ---
                output_tx = getattr(event, "output_transcription", None)
                if output_tx and getattr(output_tx, "text", None):
                    if not current_agent_msg_id:
                        current_agent_msg_id = str(uuid.uuid4())
                    logger.info("Agent said: %s", output_tx.text[:80])
                    await _send(
                        ws,
                        ServerMessage(
                            type=ServerMessageType.AGENT_TRANSCRIPT,
                            text=output_tx.text,
                            message_id=current_agent_msg_id,
                        ),
                    )

                # --- Audio content from agent ---
                content = getattr(event, "content", None)
                if content and hasattr(content, "parts") and content.parts:
                    for part in content.parts:
                        inline = getattr(part, "inline_data", None)
                        if inline and inline.mime_type and "audio" in inline.mime_type:
                            if not current_agent_msg_id:
                                current_agent_msg_id = str(uuid.uuid4())
                            audio_b64 = base64.b64encode(inline.data).decode("ascii")
                            await _send(
                                ws,
                                ServerMessage(
                                    type=ServerMessageType.AGENT_AUDIO,
                                    data=audio_b64,
                                    message_id=current_agent_msg_id,
                                ),
                            )

                # --- Turn complete ---
                if getattr(event, "turn_complete", False):
                    logger.info("Turn complete (msg_id=%s)", current_agent_msg_id)
                    if current_agent_msg_id:
                        await _send(
                            ws,
                            ServerMessage(
                                type=ServerMessageType.TURN_COMPLETE,
                                message_id=current_agent_msg_id,
                            ),
                        )
                        current_agent_msg_id = None

                # --- Interrupted ---
                if getattr(event, "interrupted", False):
                    logger.info("Agent was interrupted")
                    current_agent_msg_id = None

            # run_live() generator exhausted — restart for next turn
            logger.info("run_live() ended, restarting for session %s", session_id)
            ok = await _send(ws, ServerMessage(
                type=ServerMessageType.STATUS,
                status="live_reconnecting",
                message="Reconnecting live session...",
            ))
            if not ok:
                logger.info("WebSocket dead, stopping downstream")
                return

        except WebSocketDisconnect:
            logger.info("Client disconnected (downstream)")
            return
        except asyncio.CancelledError:
            logger.info("Downstream task cancelled")
            return
        except Exception:
            logger.exception("Error in downstream, will retry in 2s")
            ok = await _send(ws, ServerMessage(
                type=ServerMessageType.STATUS,
                status="live_disconnected",
                message="Live session lost, reconnecting...",
            ))
            if not ok:
                logger.info("WebSocket dead, stopping downstream")
                return
            await asyncio.sleep(2)


async def websocket_endpoint(ws: WebSocket, user_id: str, session_id: str) -> None:
    """Main WebSocket endpoint handler."""
    await ws.accept()
    logger.info("Client connected: user=%s session=%s", user_id, session_id)

    # Ensure session exists
    session = await session_service.get_session(
        app_name=APP_NAME, user_id=user_id, session_id=session_id
    )
    if not session:
        await session_service.create_session(
            app_name=APP_NAME,
            user_id=user_id,
            session_id=session_id,
            state={"scenario": ""},
        )

    # Send available scenarios
    scenarios_payload = {
        k: {"title": v["title"], "description": v["description"]}
        for k, v in DEFAULT_SCENARIOS.items()
    }
    await _send(
        ws,
        ServerMessage(
            type=ServerMessageType.SCENARIOS,
            scenarios=scenarios_payload,
        ),
    )

    await _send(
        ws,
        ServerMessage(
            type=ServerMessageType.STATUS,
            status="connected",
            message="Connected to language agent",
        ),
    )

    queue = LiveRequestQueue()

    try:
        await asyncio.gather(
            _upstream(ws, queue, user_id, session_id),
            _downstream(ws, queue, user_id, session_id),
        )
    finally:
        queue.close()
        logger.info("Session ended: user=%s session=%s", user_id, session_id)
