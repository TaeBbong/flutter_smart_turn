import 'dart:async';

import 'types.dart';

/// A state machine that manages conversation state transitions.
///
/// Emits state changes via [stateStream]. Invalid transitions are
/// silently ignored (logged if a logger is provided).
class ConversationStateMachine {
  ConversationState _state = ConversationState.idle;

  final _stateController = StreamController<ConversationState>.broadcast();

  /// Optional callback for logging invalid transitions.
  final void Function(String message)? onInvalidTransition;

  ConversationStateMachine({this.onInvalidTransition});

  /// Current conversation state.
  ConversationState get state => _state;

  /// Stream of state changes.
  Stream<ConversationState> get stateStream => _stateController.stream;

  /// Valid transitions table.
  static final Map<ConversationState, Map<ConversationEvent, ConversationState>>
      _transitions = {
    ConversationState.idle: {
      ConversationEvent.speechStarted: ConversationState.userSpeaking,
      ConversationEvent.playbackStarted: ConversationState.agentSpeaking,
      ConversationEvent.responseStarted: ConversationState.agentThinking,
    },
    ConversationState.listening: {
      ConversationEvent.speechStarted: ConversationState.userSpeaking,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.userSpeaking: {
      ConversationEvent.silenceDetected: ConversationState.holdCandidate,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.holdCandidate: {
      ConversationEvent.speechResumed: ConversationState.userSpeaking,
      ConversationEvent.turnEnded: ConversationState.commitCandidate,
      ConversationEvent.turnContinuing: ConversationState.userSpeaking,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.commitCandidate: {
      ConversationEvent.responseStarted: ConversationState.agentThinking,
      ConversationEvent.speechResumed: ConversationState.userSpeaking,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.agentThinking: {
      ConversationEvent.playbackStarted: ConversationState.agentSpeaking,
      ConversationEvent.speechStarted: ConversationState.interrupted,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.agentSpeaking: {
      ConversationEvent.bargeIn: ConversationState.interrupted,
      ConversationEvent.speechStarted: ConversationState.interrupted,
      ConversationEvent.playbackFinished: ConversationState.idle,
      ConversationEvent.backchannelRequested: ConversationState.backchannelPending,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.interrupted: {
      ConversationEvent.speechStarted: ConversationState.userSpeaking,
      ConversationEvent.speechResumed: ConversationState.userSpeaking,
      ConversationEvent.reset: ConversationState.idle,
    },
    ConversationState.backchannelPending: {
      ConversationEvent.backchannelFinished: ConversationState.agentSpeaking,
      ConversationEvent.bargeIn: ConversationState.interrupted,
      ConversationEvent.reset: ConversationState.idle,
    },
  };

  /// Attempt a state transition with the given event.
  ///
  /// Returns the new state, or the current state if the transition is invalid.
  ConversationState transition(ConversationEvent event) {
    // Reset is always valid from any state.
    if (event == ConversationEvent.reset) {
      _setState(ConversationState.idle);
      return _state;
    }

    final transitions = _transitions[_state];
    final nextState = transitions?[event];

    if (nextState == null) {
      onInvalidTransition?.call(
        'Invalid transition: $_state + $event',
      );
      return _state;
    }

    _setState(nextState);
    return _state;
  }

  /// Force-set the state (for testing or external control).
  void forceState(ConversationState newState) {
    _setState(newState);
  }

  void _setState(ConversationState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Release resources.
  void dispose() {
    _stateController.close();
  }
}
