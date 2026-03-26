# flutter_smart_turn

A Flutter/Dart turn-taking router for real-time voice apps.
**Separates "what to say" from "when to say it."**

This package provides a turn-taking orchestration layer that decides *when* to speak, *when* to listen, and *when* to interrupt — independently of your ASR, LLM, and TTS stack.

## Architecture

```
 [Flutter App]
      │
      │ onAudioFrame(), onVadResult(), onPartialTranscript(), ...
      ▼
┌─────────────────────────────────────────────────────┐
│                  TurnController                      │
│                                                      │
│   AudioBuffer → TurnEngine → TurnInference           │
│                      ↓                               │
│   TurnContext → TurnRouter → TurnPolicy → TurnDecision│
│                      ↓                               │
│              ConversationStateMachine                 │
└──────────────────────┬──────────────────────────────┘
                       ▼
          Stream<TurnDecision> + Stream<ConversationState>
```

## Features

- **Multi-engine support** — Smart Turn v3 (ONNX, on-device) or heuristic fallback
- **Pluggable architecture** — swap engines, routers, and policies independently
- **State machine** — tracks conversation state (idle → userSpeaking → holdCandidate → commit → agentSpeaking → ...)
- **Safety policies** — prevents nonsensical actions (e.g., commit while agent speaking)
- **Barge-in detection** — interrupts agent playback when user starts speaking
- **Cross-platform** — Android, iOS, Windows, macOS, Linux

## Quick Start

### 1. Add dependency

```yaml
dependencies:
  flutter_smart_turn: ^0.1.0
```

### 2. Create a controller

```dart
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

// Option A: Smart Turn (on-device ONNX model, auto-downloads 8MB model)
final controller = TurnController.withSmartTurn();

// Option B: Heuristic fallback (no model, VAD + silence duration)
final controller = TurnController.withHeuristic();

await controller.initialize();
```

### 3. Feed events and listen for decisions

```dart
// Listen for turn-taking decisions.
controller.decisions.listen((decision) {
  switch (decision.action) {
    case TurnAction.commitAndRespond:
      // User finished speaking → trigger LLM response.
      break;
    case TurnAction.interruptAgent:
      // User barged in → stop TTS playback.
      break;
    case TurnAction.hold:
      // User paused but might continue → wait.
      break;
    case TurnAction.continueListening:
      // No action needed.
      break;
    // ...
  }
});

// Feed audio frames from microphone.
controller.onAudioFrame(frame);

// Report VAD results.
controller.onVadResult(isSpeaking);

// Report agent state changes.
controller.onAgentStateChanged(AgentState.speaking);
```

### 4. Clean up

```dart
await controller.dispose();
```

## Engines

### Smart Turn v3 (default)

On-device inference using the [Smart Turn v3](https://huggingface.co/pipecat-ai/smart-turn-v3) model:
- Whisper Tiny encoder, 8MB int8 ONNX
- 12–60ms CPU inference
- 23 languages supported
- Auto-downloads and caches the model

```dart
final controller = TurnController.withSmartTurn();
```

### Server-side Smart Turn

For server deployments:

```dart
final controller = TurnController.withSmartTurnServer(
  serverUrl: 'http://localhost:8080',
);
```

### Heuristic Fallback

No model needed — uses VAD + silence duration + configurable thresholds:

```dart
final controller = TurnController.withHeuristic(
  config: HeuristicConfig(
    silenceMidpointMs: 800,
    silenceHardTimeoutMs: 2000,
    minSpeechDurationMs: 300,
  ),
);
```

## Custom Router & Policy

```dart
final controller = TurnController(
  engine: SmartTurnEngine.local(),
  router: DefaultRouter(
    config: RouterConfig(
      commitThreshold: 0.6,    // lower = more eager to commit
      holdLowerBound: 0.2,
      interruptThreshold: 0.7,
    ),
  ),
  policy: DefaultPolicy(
    config: PolicyConfig(
      minSpeechBeforeCommitMs: 500,
      commitDebounceMs: 300,
    ),
  ),
);
```

## Example Apps

### Basic Demo

Mic input → turn detection → visual state/score display:

```bash
cd example/basic_demo
flutter run
```

### Voice Chat

End-to-end voice conversation with barge-in handling:

- LLM cancellation on interrupt (`LlmService.cancel()`)
- TTS progress tracking (`TtsService.stopAndGetProgress()`)
- Conversation history with interruption context
- Visual indication of interrupted messages

```bash
cd example/voice_chat
flutter run
```

## Handling Barge-In (Interruption)

This package emits `TurnAction.interruptAgent` when a user barges in — but **what happens after** is your app's responsibility. The `voice_chat` example demonstrates the full lifecycle:

### The problem

When a user interrupts the agent mid-sentence, you need to:

1. **Cancel the LLM request** if it's still generating
2. **Stop TTS playback** and track how much was actually spoken
3. **Preserve conversation context** so the next response is coherent
4. **Wait for the user's new utterance** then re-generate

### Example pattern (from `voice_chat`)

```dart
Future<void> _handleInterrupt() async {
  // 1. Cancel in-progress LLM request.
  _llm.cancel();

  // 2. Stop TTS and find out what was actually delivered.
  final progress = await _tts.stopAndGetProgress();

  _turnController.onAgentStateChanged(AgentState.idle);

  // 3. Update conversation history with partial delivery.
  //    Replace the full agent message with only the spoken portion,
  //    marked as interrupted.
  if (progress.spokenText.isNotEmpty) {
    _conversationHistory.add(ConversationTurn(
      text: progress.spokenText,
      isUser: false,
      wasInterrupted: true,
    ));
  }

  // 4. Done — the controller keeps listening.
  //    Next commitAndRespond will include the interruption context
  //    so the LLM can produce a coherent follow-up.
}
```

### Key services

| Service | Barge-in support | What it does |
|---------|-----------------|--------------|
| `LlmService` | `cancel()` | Closes HTTP client, throws `GenerationCancelledException` |
| `TtsService` | `stopAndGetProgress()` | Stops playback, returns `TtsProgress` with spoken/remaining text |

See the full implementation in [`example/voice_chat/`](example/voice_chat/).

## Conversation States

| State | Description |
|-------|-------------|
| `idle` | No activity |
| `listening` | Mic active, no speech yet |
| `userSpeaking` | User is talking |
| `holdCandidate` | User paused — deciding if turn ended |
| `commitCandidate` | Turn ended — ready to respond |
| `agentThinking` | LLM generating response |
| `agentSpeaking` | TTS playing back |
| `interrupted` | User barged in |
| `backchannelPending` | Backchannel insertion pending |

## Turn Actions

| Action | When |
|--------|------|
| `continueListening` | Keep listening, no action |
| `commitAndRespond` | User done → trigger response |
| `interruptAgent` | User barged in → stop playback |
| `continueTalking` | Agent should keep speaking |
| `backchannel` | Insert short "uh-huh" |
| `hold` | User paused but not done |

## Roadmap

- **v0.2**: Pedagogical policy, debug timeline UI, ASR partial integration
- **v0.3**: Dual-channel routing, backchannel policy
- **v0.4**: VAP adapter, enhanced analytics
- **v1.0**: Stable API, production docs, benchmarks

## License

See [LICENSE](LICENSE) for details.
