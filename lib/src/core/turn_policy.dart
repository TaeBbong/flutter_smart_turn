import 'turn_decision.dart';
import 'types.dart';

/// Interface for turn-taking policies.
///
/// A policy refines a router's [TurnDecision] by applying domain-specific
/// rules (e.g. safety guards, educational context, conversation mode).
///
/// Built-in implementation: [DefaultPolicy].
abstract interface class TurnPolicy {
  /// Apply policy rules to a raw decision, potentially changing the action.
  TurnDecision apply(TurnDecision rawDecision, TurnContext context);

  /// Reset internal state (e.g. for a new conversation session).
  ///
  /// Default implementations may be no-ops.
  void reset() {}
}
