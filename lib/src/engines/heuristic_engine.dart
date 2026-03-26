import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../core/turn_decision.dart';
import '../core/turn_engine.dart';
import '../core/types.dart';
import 'score_utils.dart';

/// Configuration for [HeuristicEngine].
class HeuristicConfig extends Equatable {
  /// Silence duration (ms) at which endOfTurnScore reaches ~0.5.
  final int silenceMidpointMs;

  /// Steepness of the sigmoid curve for silence → endOfTurn mapping.
  final double silenceSteepness;

  /// Minimum speech duration (ms) before a commit is even considered.
  final int minSpeechDurationMs;

  /// Silence duration (ms) that always triggers a commit (hard timeout).
  final int silenceHardTimeoutMs;

  const HeuristicConfig({
    this.silenceMidpointMs = 800,
    this.silenceSteepness = 0.006,
    this.minSpeechDurationMs = 300,
    this.silenceHardTimeoutMs = 2000,
  });

  @override
  List<Object?> get props => [
        silenceMidpointMs,
        silenceSteepness,
        minSpeechDurationMs,
        silenceHardTimeoutMs,
      ];
}

/// A fallback turn-taking engine that uses VAD + silence duration heuristics.
///
/// No ML model required. Useful as a baseline or when no model is available.
class HeuristicEngine implements TurnEngine {
  final HeuristicConfig config;

  HeuristicEngine({this.config = const HeuristicConfig()});

  @override
  Future<void> initialize() async {}

  @override
  Future<TurnInference> analyze(TurnInput input) async {
    final context = input.context;
    final silenceMs = context.silenceDuration.inMilliseconds;
    final speechMs = context.speechDuration.inMilliseconds;

    // End-of-turn score: sigmoid based on silence duration.
    double endOfTurnScore;
    if (silenceMs >= config.silenceHardTimeoutMs) {
      endOfTurnScore = 1.0;
    } else if (!context.userIsSpeaking && silenceMs > 0) {
      endOfTurnScore = _sigmoid(
        silenceMs.toDouble(),
        config.silenceMidpointMs.toDouble(),
        config.silenceSteepness,
      );
    } else {
      endOfTurnScore = 0.0;
    }

    // Suppress end-of-turn if speech was too short.
    if (speechMs < config.minSpeechDurationMs) {
      endOfTurnScore *= 0.3;
    }

    // Hold score is inverse of end-of-turn when there's some silence.
    final holdScore =
        (silenceMs > 0 && silenceMs < config.silenceMidpointMs)
            ? 1.0 - endOfTurnScore
            : 0.0;

    final interruptScore = ScoreUtils.interruptScore(context);

    return TurnInference(
      endOfTurnScore: endOfTurnScore,
      holdScore: holdScore,
      interruptScore: interruptScore,
      backchannelScore: 0.0,
      extras: {
        'silenceMs': silenceMs.toDouble(),
        'speechMs': speechMs.toDouble(),
      },
    );
  }

  @override
  Future<void> dispose() async {}

  /// Sigmoid function: output in [0.0, 1.0].
  static double _sigmoid(double x, double midpoint, double steepness) {
    return 1.0 / (1.0 + math.exp(-steepness * (x - midpoint)));
  }
}
