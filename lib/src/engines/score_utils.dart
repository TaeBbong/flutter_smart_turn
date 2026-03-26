import '../core/types.dart';

/// Shared score computation utilities used across engines.
abstract final class ScoreUtils {
  /// Default interrupt score when both user and agent are speaking.
  static const double defaultInterruptScore = 0.9;

  /// Compute interrupt score from conversation context.
  ///
  /// Returns [defaultInterruptScore] when both parties are speaking,
  /// 0.0 otherwise.
  static double interruptScore(TurnContext context) {
    return (context.userIsSpeaking && context.agentIsSpeaking)
        ? defaultInterruptScore
        : 0.0;
  }
}
