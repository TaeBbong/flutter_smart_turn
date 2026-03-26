import 'turn_decision.dart';
import 'types.dart';

/// Interface for turn-taking inference engines.
///
/// Engines analyze audio and context to produce raw [TurnInference] scores.
/// They are score providers — the [TurnRouter] interprets scores into actions.
///
/// Built-in implementations:
/// - [SmartTurnEngine] — Smart Turn v3 ONNX model (local or server)
/// - [HeuristicEngine] — VAD + silence duration fallback
abstract interface class TurnEngine {
  /// Initialize the engine (load model, connect to server, etc.).
  Future<void> initialize();

  /// Analyze the current audio and context to produce inference scores.
  Future<TurnInference> analyze(TurnInput input);

  /// Release resources.
  Future<void> dispose();
}
