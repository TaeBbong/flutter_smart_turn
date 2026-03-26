## 0.1.0

* Initial release of flutter_smart_turn.
* Core abstractions: TurnEngine, TurnRouter, TurnPolicy, ConversationStateMachine.
* Smart Turn v3 engine with local ONNX inference (auto-download 8MB model).
* Server-side Smart Turn backend (HTTP/WebSocket).
* Heuristic fallback engine (VAD + silence duration).
* DefaultRouter with configurable thresholds.
* DefaultPolicy with safety guards (min speech, debounce, agent-speaking block).
* TurnController as single entry point orchestrator.
* Basic demo example app (mic → turn detection → visual display).
* Voice chat example app (end-to-end ASR + LLM + TTS pipeline).
* 87 unit and integration tests.
