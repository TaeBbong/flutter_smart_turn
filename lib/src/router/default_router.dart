import 'package:equatable/equatable.dart';

import '../core/turn_decision.dart';
import '../core/turn_router.dart';
import '../core/types.dart';

/// Configuration for [DefaultRouter] thresholds.
class RouterConfig extends Equatable {
  /// Score above which endOfTurn triggers [TurnAction.commitAndRespond].
  final double commitThreshold;

  /// Score range [holdLowerBound, commitThreshold) maps to [TurnAction.hold].
  final double holdLowerBound;

  /// Score above which interrupt is triggered.
  final double interruptThreshold;

  /// Score above which backchannel is triggered.
  final double backchannelThreshold;

  const RouterConfig({
    this.commitThreshold = 0.7,
    this.holdLowerBound = 0.3,
    this.interruptThreshold = 0.8,
    this.backchannelThreshold = 0.6,
  });

  @override
  List<Object?> get props => [
        commitThreshold,
        holdLowerBound,
        interruptThreshold,
        backchannelThreshold,
      ];
}

/// Default threshold-based turn router.
///
/// Maps [TurnInference] scores to [TurnDecision] actions using configurable
/// thresholds, and filters impossible actions based on the current
/// [ConversationState].
class DefaultRouter implements TurnRouter {
  final RouterConfig config;

  DefaultRouter({this.config = const RouterConfig()});

  @override
  TurnDecision decide(TurnInference inference, TurnContext context) {
    // Priority 1: Interrupt detection (highest priority).
    if (inference.interruptScore >= config.interruptThreshold &&
        context.agentIsSpeaking) {
      return TurnDecision(
        action: TurnAction.interruptAgent,
        confidence: inference.interruptScore,
        reason: 'User barge-in detected during agent speech',
        scores: _scoresToMap(inference),
      );
    }

    // Priority 2: Backchannel (only during agent speech).
    if (inference.backchannelScore >= config.backchannelThreshold &&
        context.agentIsSpeaking) {
      return TurnDecision(
        action: TurnAction.backchannel,
        confidence: inference.backchannelScore,
        reason: 'Backchannel opportunity detected',
        scores: _scoresToMap(inference),
      );
    }

    // Priority 3: End-of-turn → commit.
    if (inference.endOfTurnScore >= config.commitThreshold) {
      return TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: inference.endOfTurnScore,
        reason: 'End-of-turn score above commit threshold',
        scores: _scoresToMap(inference),
      );
    }

    // Priority 4: Hold zone.
    if (inference.endOfTurnScore >= config.holdLowerBound) {
      return TurnDecision(
        action: TurnAction.hold,
        confidence: inference.holdScore,
        reason: 'End-of-turn score in hold zone',
        scores: _scoresToMap(inference),
      );
    }

    // Priority 5: Agent should keep talking if it is speaking.
    if (context.agentIsSpeaking && !context.userIsSpeaking) {
      return TurnDecision(
        action: TurnAction.continueTalking,
        confidence: 1.0 - inference.interruptScore,
        reason: 'Agent speaking, no user interruption',
        scores: _scoresToMap(inference),
      );
    }

    // Default: keep listening.
    return TurnDecision(
      action: TurnAction.continueListening,
      confidence: 1.0 - inference.endOfTurnScore,
      reason: 'No action threshold met',
      scores: _scoresToMap(inference),
    );
  }

  Map<String, double> _scoresToMap(TurnInference inference) => {
        'endOfTurn': inference.endOfTurnScore,
        'hold': inference.holdScore,
        'interrupt': inference.interruptScore,
        'backchannel': inference.backchannelScore,
        ...inference.extras,
      };
}
