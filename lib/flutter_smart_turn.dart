/// A Flutter/Dart turn-taking router for real-time voice apps.
///
/// This package separates "what to say" from "when to say it" by providing
/// a turn-taking orchestration layer that works independently of ASR/LLM/TTS.
library;

// Core types and abstractions
export 'src/core/types.dart';
export 'src/core/turn_decision.dart';
export 'src/core/turn_engine.dart';
export 'src/core/turn_router.dart';
export 'src/core/turn_policy.dart';
export 'src/core/state_machine.dart';

// Engine implementations
export 'src/engines/heuristic_engine.dart';
export 'src/engines/smart_turn/smart_turn_engine.dart';
export 'src/engines/smart_turn/smart_turn_backend.dart';
export 'src/engines/smart_turn/local_backend.dart';
export 'src/engines/smart_turn/server_backend.dart';
export 'src/engines/smart_turn/model_manager.dart';

// Router implementations
export 'src/router/default_router.dart';

// Policy implementations
export 'src/policy/default_policy.dart';

// Utilities
export 'src/utils/audio_utils.dart';

// Controller
export 'src/controller/turn_controller.dart';
