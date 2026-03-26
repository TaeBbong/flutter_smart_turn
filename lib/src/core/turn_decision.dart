import 'package:equatable/equatable.dart';

import 'types.dart';

/// Raw inference scores produced by a [TurnEngine].
///
/// Each score is in the range [0.0, 1.0] where higher means more confident.
class TurnInference extends Equatable {
  /// Probability that the user has finished their turn.
  final double endOfTurnScore;

  /// Probability that the user is holding (paused but not done).
  final double holdScore;

  /// Probability that the user is interrupting the agent.
  final double interruptScore;

  /// Probability that a backchannel is appropriate.
  final double backchannelScore;

  /// Engine-specific extra scores.
  final Map<String, double> extras;

  const TurnInference({
    required this.endOfTurnScore,
    this.holdScore = 0.0,
    this.interruptScore = 0.0,
    this.backchannelScore = 0.0,
    this.extras = const {},
  });

  @override
  List<Object?> get props => [
        endOfTurnScore,
        holdScore,
        interruptScore,
        backchannelScore,
        extras,
      ];
}

/// A turn-taking decision produced by the router and refined by a policy.
class TurnDecision extends Equatable {
  /// The recommended action.
  final TurnAction action;

  /// Confidence in this decision (0.0–1.0).
  final double confidence;

  /// Human-readable reason for the decision (useful for debugging).
  final String? reason;

  /// The raw scores that led to this decision.
  final Map<String, double> scores;

  const TurnDecision({
    required this.action,
    required this.confidence,
    this.reason,
    this.scores = const {},
  });

  /// Creates a copy with optionally overridden fields.
  TurnDecision copyWith({
    TurnAction? action,
    double? confidence,
    String? reason,
    Map<String, double>? scores,
  }) {
    return TurnDecision(
      action: action ?? this.action,
      confidence: confidence ?? this.confidence,
      reason: reason ?? this.reason,
      scores: scores ?? this.scores,
    );
  }

  @override
  List<Object?> get props => [action, confidence, reason, scores];
}
