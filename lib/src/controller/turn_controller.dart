import 'dart:async';

import '../core/state_machine.dart';
import '../core/turn_decision.dart';
import '../core/turn_engine.dart';
import '../core/turn_policy.dart';
import '../core/turn_router.dart';
import '../core/types.dart';
import '../engines/heuristic_engine.dart';
import '../engines/smart_turn/model_manager.dart';
import '../engines/smart_turn/smart_turn_engine.dart';
import '../policy/default_policy.dart';
import '../router/default_router.dart';

/// Top-level orchestrator for turn-taking decisions.
///
/// Combines a [TurnEngine], [TurnRouter], [TurnPolicy], and
/// [ConversationStateMachine] into a single entry point.
///
/// Usage:
/// ```dart
/// final controller = TurnController.withSmartTurn();
/// await controller.initialize();
///
/// controller.decisions.listen((decision) {
///   switch (decision.action) {
///     case TurnAction.commitAndRespond:
///       // Trigger LLM response generation.
///       break;
///     case TurnAction.interruptAgent:
///       // Stop TTS playback.
///       break;
///     // ...
///   }
/// });
///
/// // Feed audio frames from microphone.
/// controller.onAudioFrame(frame);
/// ```
class TurnController {
  final TurnEngine _engine;
  final TurnRouter _router;
  final TurnPolicy _policy;
  final ConversationStateMachine _stateMachine;

  final _decisionController = StreamController<TurnDecision>.broadcast();

  bool _userIsSpeaking = false;
  bool _agentIsSpeaking = false;
  String? _partialTranscript;
  String? _finalTranscript;
  DateTime? _silenceStartTime;
  DateTime? _speechStartTime;

  bool _initialized = false;
  bool _analyzing = false;

  /// Whether user barge-in is allowed during agent speech.
  ///
  /// When `false`, [onVadResult] suppresses speech detection while the agent
  /// is speaking, preventing TTS echo from triggering false interrupts.
  /// Can be toggled at runtime (e.g. switching between speaker and earphone).
  ///
  /// Defaults to `true`.
  bool allowBargeIn = true;

  /// Create a controller with explicit components.
  TurnController({
    required TurnEngine engine,
    TurnRouter? router,
    TurnPolicy? policy,
    ConversationStateMachine? stateMachine,
  })  : _engine = engine,
        _router = router ?? DefaultRouter(),
        _policy = policy ?? DefaultPolicy(),
        _stateMachine = stateMachine ?? ConversationStateMachine();

  /// Create a controller with local Smart Turn ONNX inference.
  factory TurnController.withSmartTurn({
    ModelConfig? config,
    TurnRouter? router,
    TurnPolicy? policy,
  }) {
    return TurnController(
      engine: SmartTurnEngine.local(config: config),
      router: router,
      policy: policy,
    );
  }

  /// Create a controller with server-side Smart Turn inference.
  factory TurnController.withSmartTurnServer({
    required String serverUrl,
    String inferPath = '/infer',
    TurnRouter? router,
    TurnPolicy? policy,
  }) {
    return TurnController(
      engine: SmartTurnEngine.server(
        serverUrl: serverUrl,
        inferPath: inferPath,
      ),
      router: router,
      policy: policy,
    );
  }

  /// Create a controller with the heuristic fallback engine.
  factory TurnController.withHeuristic({
    HeuristicConfig? config,
    TurnRouter? router,
    TurnPolicy? policy,
  }) {
    return TurnController(
      engine: HeuristicEngine(config: config ?? const HeuristicConfig()),
      router: router,
      policy: policy,
    );
  }

  /// Initialize the engine. Must be called before feeding events.
  Future<void> initialize() async {
    await _engine.initialize();
    _initialized = true;
  }

  /// Release all resources.
  Future<void> dispose() async {
    await _engine.dispose();
    _stateMachine.dispose();
    await _decisionController.close();
    _initialized = false;
  }

  /// Stream of turn-taking decisions.
  Stream<TurnDecision> get decisions => _decisionController.stream;

  /// Stream of conversation state changes.
  Stream<ConversationState> get stateChanges => _stateMachine.stateStream;

  /// Current conversation state.
  ConversationState get currentState => _stateMachine.state;

  /// Feed an audio frame from the microphone.
  ///
  /// Triggers engine analysis and emits a [TurnDecision].
  Future<void> onAudioFrame(AudioFrame frame) async {
    if (!_initialized || _analyzing) return;
    _analyzing = true;
    try {
      final context = _buildContext();
      final input = TurnInput(audioFrame: frame, context: context);

      final inference = await _engine.analyze(input);
      final routerDecision = _router.decide(inference, context);
      final finalDecision = _policy.apply(routerDecision, context);

      _applyDecisionToStateMachine(finalDecision);
      _decisionController.add(finalDecision);
    } finally {
      _analyzing = false;
    }
  }

  /// Report VAD (Voice Activity Detection) result.
  void onVadResult(bool isSpeaking) {
    // Suppress speech detection during agent playback when barge-in is
    // disabled, preventing TTS echo from triggering false interrupts.
    if (!allowBargeIn && _agentIsSpeaking) {
      return;
    }

    if (isSpeaking && !_userIsSpeaking) {
      _userIsSpeaking = true;
      _speechStartTime = DateTime.now();
      _silenceStartTime = null;

      if (_agentIsSpeaking) {
        _stateMachine.transition(ConversationEvent.bargeIn);
      } else {
        _stateMachine.transition(ConversationEvent.speechStarted);
      }
    } else if (!isSpeaking && _userIsSpeaking) {
      _userIsSpeaking = false;
      _silenceStartTime = DateTime.now();
      _stateMachine.transition(ConversationEvent.silenceDetected);
    }
  }

  /// Report a partial ASR transcript.
  void onPartialTranscript(String text) {
    _partialTranscript = text;
  }

  /// Report a final ASR transcript.
  void onFinalTranscript(String text) {
    _finalTranscript = text;
    _partialTranscript = null;
  }

  /// Report agent state changes from the host application.
  void onAgentStateChanged(AgentState state) {
    switch (state) {
      case AgentState.idle:
        if (_agentIsSpeaking) {
          _agentIsSpeaking = false;
          _stateMachine.transition(ConversationEvent.playbackFinished);
        }
      case AgentState.thinking:
        _agentIsSpeaking = false;
        _stateMachine.transition(ConversationEvent.responseStarted);
      case AgentState.speaking:
        _agentIsSpeaking = true;
        _stateMachine.transition(ConversationEvent.playbackStarted);
    }
  }

  /// Reset to idle state (e.g. for a new conversation session).
  void reset() {
    _userIsSpeaking = false;
    _agentIsSpeaking = false;
    _partialTranscript = null;
    _finalTranscript = null;
    _silenceStartTime = null;
    _speechStartTime = null;
    _stateMachine.transition(ConversationEvent.reset);
    _policy.reset();
  }

  TurnContext _buildContext() {
    final now = DateTime.now();
    return TurnContext(
      state: _stateMachine.state,
      agentIsSpeaking: _agentIsSpeaking,
      userIsSpeaking: _userIsSpeaking,
      partialTranscript: _partialTranscript,
      finalTranscript: _finalTranscript,
      silenceDuration: _silenceStartTime != null
          ? now.difference(_silenceStartTime!)
          : Duration.zero,
      speechDuration: _speechStartTime != null && _userIsSpeaking
          ? now.difference(_speechStartTime!)
          : Duration.zero,
    );
  }

  void _applyDecisionToStateMachine(TurnDecision decision) {
    switch (decision.action) {
      case TurnAction.commitAndRespond:
        _stateMachine.transition(ConversationEvent.turnEnded);
      case TurnAction.interruptAgent:
        _stateMachine.transition(ConversationEvent.bargeIn);
      case TurnAction.hold:
        break;
      case TurnAction.backchannel:
        _stateMachine.transition(ConversationEvent.backchannelRequested);
      case TurnAction.continueListening:
      case TurnAction.continueTalking:
        break;
    }
  }
}
