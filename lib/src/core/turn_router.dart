import 'turn_decision.dart';
import 'types.dart';

/// Interface for turn-taking routers.
///
/// A router maps raw [TurnInference] scores to a [TurnDecision] action,
/// taking the current [TurnContext] into account.
///
/// Built-in implementation: [DefaultRouter].
abstract interface class TurnRouter {
  /// Decide what action to take based on inference scores and context.
  TurnDecision decide(TurnInference inference, TurnContext context);
}
