import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  late ConversationStateMachine sm;

  setUp(() {
    sm = ConversationStateMachine();
  });

  tearDown(() {
    sm.dispose();
  });

  group('initial state', () {
    test('starts in idle', () {
      expect(sm.state, ConversationState.idle);
    });
  });

  group('basic transitions', () {
    test('idle → userSpeaking on speechStarted', () {
      final result = sm.transition(ConversationEvent.speechStarted);
      expect(result, ConversationState.userSpeaking);
      expect(sm.state, ConversationState.userSpeaking);
    });

    test('userSpeaking → holdCandidate on silenceDetected', () {
      sm.transition(ConversationEvent.speechStarted);
      final result = sm.transition(ConversationEvent.silenceDetected);
      expect(result, ConversationState.holdCandidate);
    });

    test('holdCandidate → userSpeaking on speechResumed', () {
      sm.transition(ConversationEvent.speechStarted);
      sm.transition(ConversationEvent.silenceDetected);
      final result = sm.transition(ConversationEvent.speechResumed);
      expect(result, ConversationState.userSpeaking);
    });

    test('holdCandidate → commitCandidate on turnEnded', () {
      sm.transition(ConversationEvent.speechStarted);
      sm.transition(ConversationEvent.silenceDetected);
      final result = sm.transition(ConversationEvent.turnEnded);
      expect(result, ConversationState.commitCandidate);
    });

    test('holdCandidate → userSpeaking on turnContinuing', () {
      sm.transition(ConversationEvent.speechStarted);
      sm.transition(ConversationEvent.silenceDetected);
      final result = sm.transition(ConversationEvent.turnContinuing);
      expect(result, ConversationState.userSpeaking);
    });
  });

  group('agent flow', () {
    test('commitCandidate → agentThinking → agentSpeaking → idle', () {
      sm.transition(ConversationEvent.speechStarted);
      sm.transition(ConversationEvent.silenceDetected);
      sm.transition(ConversationEvent.turnEnded);

      sm.transition(ConversationEvent.responseStarted);
      expect(sm.state, ConversationState.agentThinking);

      sm.transition(ConversationEvent.playbackStarted);
      expect(sm.state, ConversationState.agentSpeaking);

      sm.transition(ConversationEvent.playbackFinished);
      expect(sm.state, ConversationState.idle);
    });
  });

  group('interruption', () {
    test('agentSpeaking → interrupted on bargeIn', () {
      sm.forceState(ConversationState.agentSpeaking);
      final result = sm.transition(ConversationEvent.bargeIn);
      expect(result, ConversationState.interrupted);
    });

    test('agentSpeaking → interrupted on speechStarted', () {
      sm.forceState(ConversationState.agentSpeaking);
      final result = sm.transition(ConversationEvent.speechStarted);
      expect(result, ConversationState.interrupted);
    });

    test('interrupted → userSpeaking on speechStarted', () {
      sm.forceState(ConversationState.interrupted);
      final result = sm.transition(ConversationEvent.speechStarted);
      expect(result, ConversationState.userSpeaking);
    });
  });

  group('backchannel', () {
    test('agentSpeaking → backchannelPending → agentSpeaking', () {
      sm.forceState(ConversationState.agentSpeaking);
      sm.transition(ConversationEvent.backchannelRequested);
      expect(sm.state, ConversationState.backchannelPending);

      sm.transition(ConversationEvent.backchannelFinished);
      expect(sm.state, ConversationState.agentSpeaking);
    });
  });

  group('reset', () {
    test('reset from any state returns to idle', () {
      for (final state in ConversationState.values) {
        sm.forceState(state);
        sm.transition(ConversationEvent.reset);
        expect(sm.state, ConversationState.idle,
            reason: 'Reset from $state should return to idle');
      }
    });
  });

  group('invalid transitions', () {
    test('invalid transition is ignored and returns current state', () {
      // idle + silenceDetected is not valid.
      final result = sm.transition(ConversationEvent.silenceDetected);
      expect(result, ConversationState.idle);
    });

    test('invalid transition logs via callback', () {
      String? loggedMessage;
      final sm2 = ConversationStateMachine(
        onInvalidTransition: (msg) => loggedMessage = msg,
      );

      sm2.transition(ConversationEvent.playbackFinished);
      expect(loggedMessage, contains('Invalid transition'));
      sm2.dispose();
    });
  });

  group('stateStream', () {
    test('emits state changes', () async {
      final states = <ConversationState>[];
      sm.stateStream.listen(states.add);

      sm.transition(ConversationEvent.speechStarted);
      sm.transition(ConversationEvent.silenceDetected);
      sm.transition(ConversationEvent.turnEnded);

      // Allow microtask to complete.
      await Future.delayed(Duration.zero);

      expect(states, [
        ConversationState.userSpeaking,
        ConversationState.holdCandidate,
        ConversationState.commitCandidate,
      ]);
    });

    test('does not emit when state unchanged', () async {
      final states = <ConversationState>[];
      sm.stateStream.listen(states.add);

      // Invalid transition — state stays idle, no emission.
      sm.transition(ConversationEvent.silenceDetected);

      await Future.delayed(Duration.zero);
      expect(states, isEmpty);
    });
  });

  group('forceState', () {
    test('sets state directly', () {
      sm.forceState(ConversationState.agentSpeaking);
      expect(sm.state, ConversationState.agentSpeaking);
    });
  });
}
