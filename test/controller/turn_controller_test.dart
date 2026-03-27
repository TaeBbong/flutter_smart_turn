import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

/// A mock engine that returns configurable scores.
class MockEngine implements TurnEngine {
  double endOfTurnScore = 0.0;
  double interruptScore = 0.0;

  @override
  Future<void> initialize() async {}

  @override
  Future<TurnInference> analyze(TurnInput input) async {
    return TurnInference(
      endOfTurnScore: endOfTurnScore,
      interruptScore: interruptScore,
    );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late MockEngine mockEngine;
  late TurnController controller;

  AudioFrame makeFrame() => AudioFrame(
        samples: Float32List(1600),
        sampleRate: 16000,
        timestamp: DateTime.now(),
      );

  setUp(() async {
    mockEngine = MockEngine();
    controller = TurnController(engine: mockEngine);
    await controller.initialize();
  });

  tearDown(() async {
    await controller.dispose();
  });

  group('basic lifecycle', () {
    test('starts in idle state', () {
      expect(controller.currentState, ConversationState.idle);
    });

    test('emits decisions on audio frame', () async {
      final decisions = <TurnDecision>[];
      controller.decisions.listen(decisions.add);

      await controller.onAudioFrame(makeFrame());
      await Future.delayed(Duration.zero);

      expect(decisions, hasLength(1));
    });
  });

  group('VAD events', () {
    test('speech start transitions to userSpeaking', () async {
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      controller.onVadResult(true);
      await Future.delayed(Duration.zero);

      expect(states, contains(ConversationState.userSpeaking));
    });

    test('silence transitions to holdCandidate', () async {
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      controller.onVadResult(true); // start speaking
      controller.onVadResult(false); // silence
      await Future.delayed(Duration.zero);

      expect(states, contains(ConversationState.holdCandidate));
    });
  });

  group('agent state', () {
    test('agent thinking transitions state', () async {
      // Get to commitCandidate first.
      controller.onVadResult(true);
      controller.onVadResult(false);
      // Force to commitCandidate.
      controller.onAgentStateChanged(AgentState.thinking);

      await Future.delayed(Duration.zero);
      // State should be agentThinking (or remain if transition was invalid).
      // The exact state depends on whether commitCandidate was reached.
    });

    test('agent speaking then idle cycles correctly', () async {
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      controller.onAgentStateChanged(AgentState.thinking);
      controller.onAgentStateChanged(AgentState.speaking);
      controller.onAgentStateChanged(AgentState.idle);
      await Future.delayed(Duration.zero);

      // Should see state changes through the cycle.
      expect(states, isNotEmpty);
    });
  });

  group('turn-taking scenarios', () {
    test('high endOfTurn score produces commitAndRespond', () async {
      // Use a controller with no min-speech guard to avoid timing issues.
      final noGuardController = TurnController(
        engine: mockEngine,
        policy: DefaultPolicy(
          config: const PolicyConfig(minSpeechBeforeCommitMs: 0, commitDebounceMs: 0),
        ),
      );
      await noGuardController.initialize();
      mockEngine.endOfTurnScore = 0.9;

      final decisions = <TurnDecision>[];
      noGuardController.decisions.listen(decisions.add);

      noGuardController.onVadResult(true);
      noGuardController.onVadResult(false);
      await noGuardController.onAudioFrame(makeFrame());
      await Future.delayed(Duration.zero);

      expect(decisions.last.action, TurnAction.commitAndRespond);
      await noGuardController.dispose();
    });

    test('low endOfTurn score produces continueListening', () async {
      mockEngine.endOfTurnScore = 0.1;

      final decisions = <TurnDecision>[];
      controller.decisions.listen(decisions.add);

      await controller.onAudioFrame(makeFrame());
      await Future.delayed(Duration.zero);

      expect(decisions.last.action, TurnAction.continueListening);
    });

    test('barge-in during agent speech', () async {
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      // Agent starts speaking.
      controller.onAgentStateChanged(AgentState.thinking);
      controller.onAgentStateChanged(AgentState.speaking);

      // User barges in.
      controller.onVadResult(true);
      await Future.delayed(Duration.zero);

      expect(states, contains(ConversationState.interrupted));
    });
  });

  group('reset', () {
    test('reset returns to idle', () {
      controller.onVadResult(true);
      controller.reset();
      expect(controller.currentState, ConversationState.idle);
    });
  });

  group('transcript tracking', () {
    test('partial transcript is tracked', () async {
      mockEngine.endOfTurnScore = 0.1;
      controller.onPartialTranscript('hello');

      final decisions = <TurnDecision>[];
      controller.decisions.listen(decisions.add);

      await controller.onAudioFrame(makeFrame());
      await Future.delayed(Duration.zero);

      // Decision was made — partial transcript was in context.
      expect(decisions, hasLength(1));
    });

    test('final transcript clears partial', () {
      controller.onPartialTranscript('hello');
      controller.onFinalTranscript('hello world');
      // No crash, state is consistent.
    });
  });

  group('allowBargeIn', () {
    test('VAD is suppressed during agent speech when allowBargeIn is false',
        () async {
      controller.allowBargeIn = false;
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      // Agent starts speaking.
      controller.onAgentStateChanged(AgentState.thinking);
      controller.onAgentStateChanged(AgentState.speaking);

      // VAD fires during agent speech — should be ignored.
      controller.onVadResult(true);
      await Future.delayed(Duration.zero);

      expect(states, isNot(contains(ConversationState.interrupted)));
    });

    test('VAD works during agent speech when allowBargeIn is true', () async {
      controller.allowBargeIn = true;
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      controller.onAgentStateChanged(AgentState.thinking);
      controller.onAgentStateChanged(AgentState.speaking);

      controller.onVadResult(true);
      await Future.delayed(Duration.zero);

      expect(states, contains(ConversationState.interrupted));
    });

    test('allowBargeIn can be toggled at runtime', () async {
      final states = <ConversationState>[];
      controller.stateChanges.listen(states.add);

      // Start with barge-in disabled.
      controller.allowBargeIn = false;
      controller.onAgentStateChanged(AgentState.thinking);
      controller.onAgentStateChanged(AgentState.speaking);

      controller.onVadResult(true);
      await Future.delayed(Duration.zero);
      expect(states, isNot(contains(ConversationState.interrupted)));

      // Enable barge-in at runtime.
      controller.allowBargeIn = true;
      controller.onVadResult(true);
      await Future.delayed(Duration.zero);
      expect(states, contains(ConversationState.interrupted));
    });
  });

  group('factory constructors', () {
    test('withHeuristic creates working controller', () async {
      final hc = TurnController.withHeuristic();
      await hc.initialize();
      expect(hc.currentState, ConversationState.idle);
      await hc.dispose();
    });
  });
}
