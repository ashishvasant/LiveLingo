# talking_learning

## Current App Features Before Simplification

- Google sign-in gate with Firebase auth bootstrap.
- Realtime websocket live session with backend auth token exchange.
- Continuous microphone streaming for live speech input.
- Optional camera context capture and preview.
- Scenario and location context inference display.
- Phrase suggestion list with transliteration and pronunciation hints.
- Intent-assist card for phrases the user may want to say.
- On-demand phrase audio playback.
- Autonomous speaking mode with goal tracking and task status.
- Live transcript event stream.
- Language switching from UI and spoken language-selection commands.
- Local SQLite storage for settings, phrase history, diagnostics, and session summaries.
- Diagnostics and backend URL controls in settings.
- Android foreground service scaffolding for active live sessions.

## Simplified UI Goal

- WhatsApp-style chat interface.
- Top task field for the current task.
- Settings button on the top right.
- Bottom-left autonomous mode toggle.
- Bottom-middle camera toggle that reveals the camera background.
- Bottom-right mute or speaker toggle.
- Transcript-first conversation view where foreign speech is translated into chat bubbles.

The backend and data model may still support more than the simplified UI currently exposes.
