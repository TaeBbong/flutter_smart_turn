import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  late DefaultRouter router;

  setUp(() {
    router = DefaultRouter();
  });

  TurnContext _ctx({
    ConversationState state = ConversationState.userSpeaking,
    bool agentIsSpeaking = false,
    bool userIsSpeaking = true,
  }) {
    return TurnContext(
      state: state,
      agentIsSpeaking: agentIsSpeaking,
      userIsSpeaking: userIsSpeaking,
    );
  }

  group('commitAndRespond', () {
    test('triggers when endOfTurnScore above threshold', () {
      const inference = TurnInference(endOfTurnScore: 0.8);
      final decision = router.decide(inference, _ctx());
      expect(decision.action, TurnAction.commitAndRespond);
    });

    test('does not trigger below threshold', () {
      const inference = TurnInference(endOfTurnScore: 0.5);
      final decision = router.decide(inference, _ctx());
      expect(decision.action, isNot(TurnAction.commitAndRespond));
    });
  });

  group('hold', () {
    test('triggers in hold zone', () {
      const inference = TurnInference(endOfTurnScore: 0.5);
      final decision = router.decide(inference, _ctx());
      expect(decision.action, TurnAction.hold);
    });

    test('does not trigger below lower bound', () {
      const inference = TurnInference(endOfTurnScore: 0.1);
      final decision = router.decide(inference, _ctx());
      expect(decision.action, isNot(TurnAction.hold));
    });
  });

  group('interruptAgent', () {
    test('triggers when interrupt score high and agent speaking', () {
      const inference = TurnInference(
        endOfTurnScore: 0.0,
        interruptScore: 0.9,
      );
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: true),
      );
      expect(decision.action, TurnAction.interruptAgent);
    });

    test('does not trigger when agent not speaking', () {
      const inference = TurnInference(
        endOfTurnScore: 0.0,
        interruptScore: 0.9,
      );
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: false),
      );
      expect(decision.action, isNot(TurnAction.interruptAgent));
    });
  });

  group('backchannel', () {
    test('triggers when backchannel score high and agent speaking', () {
      const inference = TurnInference(
        endOfTurnScore: 0.0,
        backchannelScore: 0.7,
      );
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: true),
      );
      expect(decision.action, TurnAction.backchannel);
    });
  });

  group('continueTalking', () {
    test('triggers when agent speaking and no interruption', () {
      const inference = TurnInference(endOfTurnScore: 0.1);
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: true, userIsSpeaking: false),
      );
      expect(decision.action, TurnAction.continueTalking);
    });
  });

  group('continueListening', () {
    test('is the default when no threshold met', () {
      const inference = TurnInference(endOfTurnScore: 0.1);
      final decision = router.decide(inference, _ctx());
      expect(decision.action, TurnAction.continueListening);
    });
  });

  group('priority order', () {
    test('interrupt takes priority over commit', () {
      const inference = TurnInference(
        endOfTurnScore: 0.9,
        interruptScore: 0.9,
      );
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: true),
      );
      expect(decision.action, TurnAction.interruptAgent);
    });

    test('interrupt takes priority over backchannel', () {
      const inference = TurnInference(
        endOfTurnScore: 0.0,
        interruptScore: 0.9,
        backchannelScore: 0.8,
      );
      final decision = router.decide(
        inference,
        _ctx(agentIsSpeaking: true),
      );
      expect(decision.action, TurnAction.interruptAgent);
    });
  });

  group('custom config', () {
    test('respects custom thresholds', () {
      final customRouter = DefaultRouter(
        config: const RouterConfig(commitThreshold: 0.5),
      );
      const inference = TurnInference(endOfTurnScore: 0.55);
      final decision = customRouter.decide(inference, _ctx());
      expect(decision.action, TurnAction.commitAndRespond);
    });
  });

  group('decision metadata', () {
    test('includes scores in decision', () {
      const inference = TurnInference(
        endOfTurnScore: 0.8,
        holdScore: 0.2,
      );
      final decision = router.decide(inference, _ctx());
      expect(decision.scores['endOfTurn'], 0.8);
      expect(decision.scores['hold'], 0.2);
    });

    test('includes reason in decision', () {
      const inference = TurnInference(endOfTurnScore: 0.8);
      final decision = router.decide(inference, _ctx());
      expect(decision.reason, isNotNull);
    });
  });
}
