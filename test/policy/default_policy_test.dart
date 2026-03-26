import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  late DefaultPolicy policy;

  setUp(() {
    policy = DefaultPolicy();
  });

  TurnContext makeCtx({
    bool agentIsSpeaking = false,
    Duration speechDuration = const Duration(seconds: 1),
  }) {
    return TurnContext(
      state: ConversationState.userSpeaking,
      agentIsSpeaking: agentIsSpeaking,
      speechDuration: speechDuration,
    );
  }

  group('commit guards', () {
    test('blocks commit when agent is speaking', () {
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final result = policy.apply(decision, makeCtx(agentIsSpeaking: true));
      expect(result.action, TurnAction.continueListening);
      expect(result.reason, contains('agent speech'));
    });

    test('blocks commit when speech too short', () {
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final result = policy.apply(
        decision,
        makeCtx(speechDuration: const Duration(milliseconds: 100)),
      );
      expect(result.action, TurnAction.hold);
      expect(result.reason, contains('too short'));
    });

    test('allows commit when all guards pass', () {
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final result = policy.apply(decision, makeCtx());
      expect(result.action, TurnAction.commitAndRespond);
    });

    test('debounces rapid commits', () {
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final ctx = makeCtx();

      // First commit should pass.
      final first = policy.apply(decision, ctx);
      expect(first.action, TurnAction.commitAndRespond);

      // Immediate second commit should be debounced.
      final second = policy.apply(decision, ctx);
      expect(second.action, TurnAction.hold);
      expect(second.reason, contains('debounce'));
    });
  });

  group('interrupt guards', () {
    test('allows interrupt when agent is speaking', () {
      const decision = TurnDecision(
        action: TurnAction.interruptAgent,
        confidence: 0.9,
      );
      final result = policy.apply(decision, makeCtx(agentIsSpeaking: true));
      expect(result.action, TurnAction.interruptAgent);
    });

    test('blocks interrupt when agent not speaking', () {
      const decision = TurnDecision(
        action: TurnAction.interruptAgent,
        confidence: 0.9,
      );
      final result = policy.apply(decision, makeCtx(agentIsSpeaking: false));
      expect(result.action, TurnAction.continueListening);
    });
  });

  group('passthrough', () {
    test('passes through non-commit non-interrupt actions', () {
      const decision = TurnDecision(
        action: TurnAction.hold,
        confidence: 0.5,
      );
      final result = policy.apply(decision, makeCtx());
      expect(result.action, TurnAction.hold);
    });

    test('passes through continueListening', () {
      const decision = TurnDecision(
        action: TurnAction.continueListening,
        confidence: 0.5,
      );
      final result = policy.apply(decision, makeCtx());
      expect(result.action, TurnAction.continueListening);
    });
  });

  group('reset', () {
    test('reset clears debounce state', () {
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final ctx = makeCtx();

      policy.apply(decision, ctx); // first commit
      policy.reset();

      // After reset, commit should pass again immediately.
      final result = policy.apply(decision, ctx);
      expect(result.action, TurnAction.commitAndRespond);
    });
  });

  group('custom config', () {
    test('respects custom minSpeechBeforeCommitMs', () {
      final customPolicy = DefaultPolicy(
        config: const PolicyConfig(minSpeechBeforeCommitMs: 1000),
      );
      const decision = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
      );
      final result = customPolicy.apply(
        decision,
        makeCtx(speechDuration: const Duration(milliseconds: 500)),
      );
      expect(result.action, TurnAction.hold);
    });
  });
}
