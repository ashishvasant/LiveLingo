# Architecture

This file explains how the app is currently structured across the Flutter frontend and the FastAPI backend.

## Project split

- Frontend app: `D:\AppsMade2\LiveLearn\talking_learning`
- Backend service: `D:\gcloudBackends\locateAssist\backend_2`

The frontend is the mobile app the user sees. The backend owns the live websocket session, Gemini Live connection, translation logic, reply generation, and audio generation.

## Frontend

### Main responsibilities

The Flutter app does five main jobs:

1. Authenticates the user with Firebase / Google Sign-In.
2. Opens and maintains a websocket to the backend.
3. Streams microphone audio to the backend.
4. Renders live conversation messages in the UI.
5. Stores settings, diagnostics, and session summaries locally.

### Key frontend files

- `lib/main.dart`
  - Builds the visible UI.
  - Right now the primary experience is the autonomous conversation screen.
  - Contains the settings page, autonomous page, chat cards, and prompt cards.

- `lib/app_controller.dart`
  - Main state and orchestration layer.
  - Connects auth, websocket, mic streaming, playback, local storage, and UI state.
  - Interprets backend websocket events and converts them into `ConversationMessage` items for the UI.

- `lib/models.dart`
  - Defines app state models.
  - Important models include `AppSettings`, `LiveLanguageState`, `ConversationMessage`, `AutonomousStatus`, and `AutonomousPrompt`.

- `lib/services/live_session_service.dart`
  - Manages the websocket connection to the backend.
  - Sends JSON control messages and raw audio chunks.
  - Receives backend events and passes them to `AppController`.

- `lib/services/android_live_audio_service.dart`
  - Wrapper around the native Android audio stream channel.
  - Used for stable `16 kHz / PCM16 / mono` microphone capture on Android.

- `lib/services/audio_playback_service.dart`
  - Plays backend-generated audio replies.

- `lib/services/local_database.dart`
  - SQLite-backed local persistence for settings, diagnostics, history, and session summaries.

- `android/app/src/main/kotlin/.../LiveAudioStreamHandler.kt`
  - Native Android audio recorder bridge.
  - Captures microphone audio using `AudioRecord` and streams PCM frames into Flutter.

### Frontend runtime flow

1. App starts and loads `AppSettings` from SQLite.
2. User signs in with Google.
3. `AppController` opens a websocket through `LiveSessionService`.
4. Android mic audio is captured natively and streamed to the backend as raw PCM.
5. Backend websocket events are mapped into:
   - `Other person`
   - `AI speaking for you`
   - `You`
   - `AI needs your input`
6. The autonomous UI in `main.dart` renders these as chat bubbles.
7. Audio returned from the backend is played through `AudioPlaybackService`.

### Current frontend state model

The frontend currently treats autonomous mode as the main live mode. Important live state includes:

- current goal
- language of the place / target language
- connection status
- paused state
- whether mic streaming is active
- autonomous prompt requesting user clarification
- conversation timeline shown in the chat

The app also keeps diagnostics locally so settings can show logs from the last sessions.

## Backend

### Main responsibilities

The backend does six main jobs:

1. Accepts the authenticated websocket session from the app.
2. Streams audio into Gemini Live.
3. Receives live transcription and model events back from Gemini Live.
4. Decides what should be shown as chat messages.
5. Generates autonomous replies on behalf of the user.
6. Generates audio for replies when needed.

### Key backend files

- `app/main.py`
  - FastAPI application entry point.
  - Registers the `live`, `language`, `location`, and `session` routers.

- `app/routes/live.py`
  - Core live websocket route.
  - This is the most important backend file.
  - Owns session config, pause state, transcript buffering, autonomous flow, restart logic, and outbound websocket events.

- `app/ai/adk_live_agent.py`
  - Wrapper around the direct Gemini Live async session.
  - Sends audio and text to Gemini Live.
  - Emits normalized events such as:
    - `user_transcript`
    - `assistant_transcript`
    - `assistant_text`
    - `turn_complete`
    - `adk_error`

- `app/services/heard_message_service.py`
  - Converts nearby foreign-language speech into a structured `heard_message`.
  - Produces:
    - translated meaning in the user language
    - detected or assumed source language
    - two short reply suggestions
    - transliterations

- `app/services/autonomous_reply_tool.py`
  - Generates the AI's next spoken reply when autonomous mode is active.
  - Uses:
    - current goal
    - latest heard speech
    - target language
    - user language
    - context summary

- `app/services/speech_output_tool.py`
  - Builds playback audio for assistant replies.
  - Delegates to Gemini-based live audio output.

- `app/services/prompt_builder.py`
  - Defines the system instruction sent into Gemini Live.

- `app/services/translation_assist_service.py`
  - General translation helper used by multiple services.

- `app/services/language_selection_tool.py`
  - Normalizes or detects requested languages from text commands.

- `app/services/goal_tracker_tool.py`
  - Tracks autonomous goal progress.

- `app/services/session_registry.py`
  - Records internal session and debug events.

### Backend live websocket flow

The live route in `app/routes/live.py` currently works like this:

1. Authenticate websocket connection.
2. Accept the socket.
3. Create in-memory session state, including:
   - user language
   - target language
   - voice name
   - interaction mode
   - current task
   - autonomous goal
   - paused state
   - recent transcripts
4. Start a Gemini Live session through `AdkLiveAgentSession`.
5. Receive raw audio bytes from the phone and forward them to Gemini Live.
6. Receive live events back from Gemini Live.
7. Convert finished or stabilized transcripts into one of:
   - `heard_message`
   - `assistant_reply`
   - `autonomous_prompt`
   - `autonomous_status`
   - status / warning / diagnostic events
8. Send those structured events back to the Flutter app over the websocket.

### What Gemini Live is used for

Gemini Live is currently used for:

- streaming audio input
- live input transcription
- live output transcription
- live assistant text/audio turns

The backend does not simply mirror raw Gemini events straight into the UI. It translates them into app-specific events first.

## End-to-end autonomous flow

This is the current intended autonomous-mode flow:

1. User opens autonomous mode.
2. User provides:
   - what they want done
   - the language of the place / the language the AI should speak
3. Frontend sends session config and goal/language updates to the backend.
4. Mic stays on unless paused.
5. Nearby speech is streamed to Gemini Live.
6. Backend interprets the heard speech.
7. If the speech is from the other person, backend sends a translated `Other person` message in the user's language.
8. Backend decides whether the AI should answer immediately or wait.
9. If the AI should answer, backend generates:
   - translated meaning for the user
   - target-language text to speak
   - transliteration
   - audio payload
10. Frontend shows both the `Other person` and `AI speaking for you` messages in chat and plays the audio.
11. If the AI needs clarification, backend sends `autonomous_prompt` and waits silently for typed user feedback.

## Current design intent

The current code is trying to behave like a live negotiation assistant, not just a translator. That means the backend is doing more than transcription:

- it listens
- it translates
- it keeps track of the user's task
- it decides whether to speak
- it can pause and wait for user clarification

## Current pain points

These are the main areas still being debugged:

- websocket stability over longer live sessions
- continuous ambient speech pickup
- avoiding repeated assistant responses
- keeping the app responsive while audio streaming is active

## Short summary

Frontend:
- Flutter UI + local persistence + native Android mic capture + websocket client

Backend:
- FastAPI websocket server + Gemini Live session + translation/reply orchestration

Core interaction:
- phone streams audio -> backend forwards to Gemini Live -> backend turns model output into structured chat and reply audio -> frontend renders and plays it
