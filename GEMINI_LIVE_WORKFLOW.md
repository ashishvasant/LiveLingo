# Gemini Live Workflow

This file explains how the current system uses Gemini Live and the surrounding backend services.

It focuses on:

- which Gemini calls are made
- which prompts are sent
- what the model is being asked to do
- which backend "tools" are used around the model

## Important idea

The app is not using one single Gemini call for everything.

Instead, the backend uses Gemini in three different ways:

1. A live Gemini session for streaming audio in and getting live transcription / live events back.
2. Regular text-model calls for translation, heard-message formatting, and autonomous reply generation.
3. A separate Gemini Live audio-output call to synthesize spoken assistant audio.

So the overall behavior is a pipeline, not one model prompt.

## High-level flow

1. The phone sends microphone audio to the backend websocket.
2. The backend forwards that audio into a Gemini Live session.
3. Gemini Live returns streaming events such as:
   - user input transcription
   - assistant output transcription
   - assistant text parts
   - turn completion markers
4. The backend decides what that transcript means for the app.
5. The backend may then call other Gemini text prompts to:
   - translate what another person said
   - create reply suggestions
   - generate an autonomous answer on behalf of the user
6. If the AI should speak, the backend makes another Gemini Live call just for audio generation.
7. The backend sends structured app events back to Flutter.

## The live Gemini session

### Where it is created

Backend file:
- `D:\gcloudBackends\locateAssist\backend_2\app\ai\adk_live_agent.py`

### What is configured

The live session is started with a `LiveConnectConfig` that currently does this:

- `responseModalities=["AUDIO"]`
- sets a system instruction
- enables input audio transcription
- enables output audio transcription
- enables automatic activity detection

### Why `AUDIO` is used

The model being used is the native-audio live model, so the backend keeps the session in audio mode and relies on transcription fields coming back from the live stream for text understanding.

### What is sent into the live session

The live session receives:

- microphone PCM audio
- optional text input
- optional camera frames

In practice, the most important input right now is microphone audio.

### Live calls made by the backend

From `AdkLiveAgentSession`:

- `send_realtime_input(audio=...)`
  - used for live microphone audio chunks
- `send_realtime_input(text=...)`
  - used when the backend wants to send text directly
- `send_realtime_input(video=...)`
  - available for camera frames

### What comes back from Gemini Live

The backend listens to `session.receive()` and converts each server message into simpler internal events such as:

- `user_transcript`
- `assistant_transcript`
- `assistant_text`
- `turn_complete`
- `interrupted`
- `adk_error`

These are not app UI messages yet. They are only the raw live-model layer.

## The live system instruction

### Where it comes from

Backend file:
- `D:\gcloudBackends\locateAssist\backend_2\app\services\prompt_builder.py`

### Current live instruction

The live Gemini model is currently told to behave like a transcription-first listener. The instruction says, in effect:

- you are a live transcription assistant
- prioritize accurate transcription of nearby human speech
- focus on the other person speaking near the phone
- do not answer the speaker
- do not carry on a conversation
- do not describe scenarios, locations, tools, or hidden state
- keep visible text short

### Why this matters

This means the live session is mainly being used as a streaming speech listener, not as the full conversation brain.

That is intentional. The backend wants a cleaner division:

- Gemini Live listens and transcribes
- backend services interpret the transcript
- separate prompts decide what to show or say

## Backend "tools" around Gemini

These are called "tools" in the app architecture, but they are backend service classes, not direct Gemini function-calling tools.

The main ones are:

- `HeardMessageService`
- `AutonomousReplyTool`
- `SpeechOutputTool`
- `LanguageSelectionTool`
- `GoalTrackerTool`
- `translation_assist_service.translate_text`

## Tool 1: HeardMessageService

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\services\heard_message_service.py`

### When it is used

After the backend receives a finalized or stabilized nearby-speech transcript from Gemini Live.

### What it is asked to do

It turns one heard utterance into a structured app event.

It tries to produce:

- the meaning in the user's language
- the source language
- whether the message should even be shown
- a speaker label
- two short reply suggestions
- transliterations for those replies

### Gemini prompt used here

This service makes a regular text-model call asking for JSON only.

The prompt tells the model to:

- help the listener understand nearby speech
- hide same-language speech
- translate foreign speech naturally
- detect the source language
- produce exactly 2 short replies in the source language
- provide transliteration that is easy for the user to pronounce
- use the current task only if it helps

### Output shape

It returns a structured object that becomes a `heard_message` websocket event.

## Tool 2: translate_text

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\services\translation_assist_service.py`

### When it is used

This is the general translation helper used by multiple services.

### What it is asked to do

The model is asked to return JSON containing:

- `display_text`
- `target_text`
- `transliteration`
- `pronunciation_hint`
- `audio_available`
- `explanation`
- `source_language`

### Prompt intent

The translation prompt tells Gemini to:

- keep the result practical for a live conversation
- translate meaning, not merely transcribe
- write transliteration for someone who reads the user's language
- detect the source language when needed
- produce natural English when English is the target

This helper is used as the fallback or normalization layer when the backend needs reliable translated text.

## Tool 3: AutonomousReplyTool

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\services\autonomous_reply_tool.py`

### When it is used

In autonomous mode, after the backend hears speech from the other person or when it needs to produce the opening line.

### What it is asked to do

This is the part that decides what the AI should say on behalf of the user.

It takes:

- the current goal
- the latest heard text
- the target language
- the user's language
- a short context summary

### Gemini prompt used here

This service makes a regular text-model call with a JSON-only response requirement.

The model is asked to return:

- `target_text`
- `translated_text`
- `transliteration`
- `pronunciation_hint`
- `should_speak`
- `progress_status`
- `progress_summary`
- `completion_confidence`

The prompt tells Gemini:

- you are speaking for the user in a live conversation
- user language is X
- target language is Y
- assume the other person is also speaking Y
- write the spoken reply itself in Y
- use the goal, context, and latest heard text

### Why this is separate from the live session

The live session is kept mostly transcription-focused.

The autonomous reply tool is the deliberation layer that decides:

- whether to speak
- what to say
- whether the task is progressing
- whether the AI should wait for user clarification

## Tool 4: SpeechOutputTool

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\services\speech_output_tool.py`

### When it is used

After the backend already knows the assistant text it wants to speak.

### What it does

It asks another service to synthesize audio, unless:

- the session is muted
- the text is empty

It also applies the selected voice name from app settings.

## Tool 5: Gemini Live audio generation

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\services\live_audio_output_service.py`

### Important distinction

This is separate from the main live listening session.

The backend opens another Gemini Live call just to synthesize speech audio for one reply.

### What the backend sends

It opens a live connection with:

- `response_modalities=["AUDIO"]`
- optional `speech_config.voice_config.prebuilt_voice_config.voice_name`

Then it sends a text prompt that says, in effect:

- speak exactly the following text
- do not add extra words
- use natural pronunciation for the requested language

### Why it exists

This is how the backend turns already-decided assistant text into playable audio for Flutter.

## How the live route uses all of this

### File

- `D:\gcloudBackends\locateAssist\backend_2\app\routes\live.py`

### Core backend loop

The live route does the orchestration.

It:

1. starts the live Gemini session
2. receives microphone chunks from the phone
3. forwards those chunks to Gemini Live
4. listens to Gemini Live events
5. debounces transcript updates
6. decides what app event to emit next

### Transcript handling logic

When a `user_transcript` event arrives from Gemini Live, the backend does not always act immediately.

It stores the latest text and then:

- waits a short debounce window, or
- processes it immediately on `turn_complete`

That transcript is then passed through app logic that checks:

- is this empty
- is this a duplicate of something just processed
- is this probably the assistant's own voice being picked up again
- are we currently capturing a task, a language, or a quick reply

### Possible outcomes after one transcript

A single transcript may lead to one of these backend actions:

- capture the user's goal
- capture the target language
- treat the speech as user feedback in autonomous mode
- translate it into a `heard_message`
- generate an autonomous assistant reply
- ask the user for clarification through `autonomous_prompt`

## What the live model is asked to do vs what the backend is asked to do

### Gemini Live is mainly asked to do

- listen continuously
- transcribe nearby speech
- surface streaming audio-related events

### Backend services are asked to do

- decide whether a transcript matters
- decide whether it came from the assistant or another person
- translate speech into the user's language
- generate reply suggestions
- generate autonomous next-step replies
- decide whether to speak or wait
- build audio output

## Current architectural tradeoff

The current design intentionally does not rely on one giant prompt.

Instead it uses:

- a narrow live transcription prompt
- structured text prompts for interpretation and replies
- a separate audio-output prompt for speech synthesis

This makes the behavior easier to control, but it also means there are multiple Gemini calls involved in one real interaction.

## Short summary

The current Gemini workflow is:

1. Gemini Live listens.
2. Backend interprets the transcript.
3. Backend calls text-model prompts for translation or autonomous reasoning.
4. Backend optionally calls Gemini Live again for reply audio.
5. Flutter receives clean app events and renders them.
