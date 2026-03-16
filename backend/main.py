"""FastAPI application entry point for the Language Agent backend."""

import logging
import os

import dotenv
from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

from server.websocket_handler import websocket_endpoint

dotenv.load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)

app = FastAPI(
    title="Language Agent Backend",
    description="Live streaming language learning agent powered by Google ADK",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.websocket("/ws/{user_id}/{session_id}")
async def ws_route(websocket: WebSocket, user_id: str, session_id: str):
    await websocket_endpoint(websocket, user_id, session_id)


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
