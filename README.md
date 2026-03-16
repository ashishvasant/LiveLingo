# LiveLingo

**A real-time AI language assistant that negotiates at street markets in any language — so you don't have to.**

Built for the **#GeminiLiveAgentChallenge** hackathon using Google's Gemini Live API, Google Cloud Translate, Cloud Firestore, the Google Gen AI SDK, and Google ADK.

---

## The Problem

Translation apps are too slow for real conversation. You speak into your phone, wait, show the screen, the other person replies, you fumble to record again — by then, the natural rhythm of the conversation is gone. Negotiations need timing, tone, and real-time back-and-forth.

LiveLingo keeps up with the actual pace of a street conversation.

## Two Modes

### Mode 1: Autonomous — The AI Speaks For You

Tell the app what you need — *"Buy 2 kg of tomatoes, negotiate the price down"* — and pick the target language. The AI takes over: it speaks the local language through your phone speaker, listens to replies, negotiates, and handles the conversation in real time.

On your screen, every exchange is translated into your language. If the shopkeeper asks something only you can answer, the AI pauses, shows you the question with options, and continues after you tap.

You can speak aloud in your own language mid-conversation — *"tell them I want the red ones"* — and the AI weaves it in seamlessly.

### Mode 2: Transliteration Guide — You Speak, the AI Coaches

The AI listens and translates everything so you understand, but instead of speaking for you, it shows you **what to say** in three layers:

1. **Original script** — text in the local language
2. **Translation** — meaning in your language
3. **Transliteration** — pronunciation in *your* familiar script (not just romanized — a Hindi speaker learning Tamil sees Devanagari, not Latin letters)

Tap play on any message to hear correct pronunciation first. Over time, this becomes a language learning tool.

## How It Works

The Gemini Live API produces two separate transcription streams — the AI's own speech (output) and everything the mic picks up (input). The backend runs three-way classification on input:

- **Echo detection** — fuzzy string similarity discards the AI's own voice bouncing back from the speaker
- **User language detection** — script ratio analysis and cue words identify your instructions, which get forwarded to the AI
- **Other person speech** — everything else gets translated and displayed in chat

## Architecture

```
Phone mic → PCM16 → WebSocket → FastAPI backend
  → Gemini Live API (speak + transcribe in target language)
      → AI speech → phone speaker (real-time)
      → AI transcript → translation queue (parallel)
      → Mic pickup → 3-way classification
          → Echo → dropped
          → User language → forwarded as instruction
          → Other person → translation queue
      → Tool call → user prompt → tap → AI continues
  → Translation (Cloud Translate / Gen AI SDK) → chat bubbles
  → Transliteration (Gen AI SDK) → pronunciation guide
```

**Key design decision:** The Live API does exactly one job — speak and transcribe in the target language. Translation, transliteration, audio playback, and echo detection all run in parallel services/threads. This separation is why it feels low-latency.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| AI Core | Gemini Live API (realtime Flash, native audio) |
| Agent Framework | Google ADK (Agent Development Kit) |
| Translation | Google Cloud Translate API + Gen AI SDK fallback |
| Auth | Firebase Authentication |
| State | Cloud Firestore |
| Backend | FastAPI on Google Cloud Run |
| Frontend | Flutter (Android / iOS / Web) |

## Getting Started

### Prerequisites

- Flutter SDK (3.x+)
- A Firebase project with Authentication enabled
- A Google Cloud project with Translate API enabled
- The LiveLingo backend deployed (see backend repo)

### Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/yourusername/livelingo.git
   cd livelingo
   ```

2. **Firebase config**
   - Copy `android/app/google-services.json.example` to `android/app/google-services.json` and fill in your Firebase project values
   - Add your `ios/Runner/GoogleService-Info.plist` from the Firebase console
   - Configure Firebase for web in your environment

3. **Set the backend URL**
   ```bash
   flutter run --dart-define=BACKEND_URL=https://your-backend.run.app
   ```

4. **Run**
   ```bash
   flutter run
   ```

### Security Notes

- Never commit `google-services.json` or `GoogleService-Info.plist` — they are gitignored
- Run `scripts/validate_repo_hygiene.ps1` before pushing to check for accidentally committed secrets
- All Firebase web config should use `String.fromEnvironment()` compile-time variables

## License

This project was created for the #GeminiLiveAgentChallenge hackathon.

---

*When sharing on social media, use the hashtag **#GeminiLiveAgentChallenge***
