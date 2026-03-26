import 'package:equatable/equatable.dart';

import '../core/turn_decision.dart';
import '../core/turn_policy.dart';
import '../core/types.dart';

/// Configuration for [DefaultPolicy] safety rules.
class PolicyConfig extends Equatable {
  /// Minimum speech duration (ms) before a commit is allowed.
  final int minSpeechBeforeCommitMs;

  /// Minimum interval (ms) between consecutive commits (debounce).
  final int commitDebounceMs;

  const PolicyConfig({
    this.minSpeechBeforeCommitMs = 300,
    this.commitDebounceMs = 500,
  });

  @override
  List<Object?> get props => [minSpeechBeforeCommitMs, commitDebounceMs];
}

/// Default conversation policy with safety rules.
///
/// Applies guards to prevent nonsensical actions:
/// - No commit while agent is speaking
/// - No commit if speech was too short
/// - Debounce rapid consecutive commits
class DefaultPolicy implements TurnPolicy {
  final PolicyConfig config;

  DateTime? _lastCommitTime;

  DefaultPolicy({this.config = const PolicyConfig()});

  @override
  TurnDecision apply(TurnDecision rawDecision, TurnContext context) {
    if (rawDecision.action == TurnAction.commitAndRespond) {
      return _applyCommitGuards(rawDecision, context);
    }

    if (rawDecision.action == TurnAction.interruptAgent) {
      return _applyInterruptGuards(rawDecision, context);
    }

    return rawDecision;
  }

  TurnDecision _applyCommitGuards(
    TurnDecision decision,
    TurnContext context,
  ) {
    // Guard: Don't commit while agent is speaking.
    if (context.agentIsSpeaking) {
      return decision.copyWith(
        action: TurnAction.continueListening,
        reason: 'Policy: blocked commit during agent speech',
      );
    }

    // Guard: Don't commit if speech was too short.
    if (context.speechDuration.inMilliseconds <
        config.minSpeechBeforeCommitMs) {
      return decision.copyWith(
        action: TurnAction.hold,
        reason: 'Policy: speech too short for commit',
      );
    }

    // Guard: Debounce rapid commits.
    final now = DateTime.now();
    if (_lastCommitTime != null) {
      final elapsed = now.difference(_lastCommitTime!).inMilliseconds;
      if (elapsed < config.commitDebounceMs) {
        return decision.copyWith(
          action: TurnAction.hold,
          reason: 'Policy: commit debounce (${elapsed}ms < ${config.commitDebounceMs}ms)',
        );
      }
    }

    // All guards passed — record commit time.
    _lastCommitTime = now;
    return decision;
  }

  TurnDecision _applyInterruptGuards(
    TurnDecision decision,
    TurnContext context,
  ) {
    // Guard: Interrupt only makes sense if agent is speaking.
    if (!context.agentIsSpeaking) {
      return decision.copyWith(
        action: TurnAction.continueListening,
        reason: 'Policy: interrupt ignored — agent not speaking',
      );
    }

    return decision;
  }

  @override
  void reset() {
    _lastCommitTime = null;
  }
}
