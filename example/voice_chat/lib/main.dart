import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';
import 'package:record/record.dart';

import 'services/asr_service.dart';
import 'services/llm_service.dart';
import 'services/tts_service.dart';

// ---------------------------------------------------------------------------
// API key configuration.
//
// Set via:
//   flutter run --dart-define=GEMINI_API_KEY=xxx
//
// A single Gemini API key powers all three services:
//   - ASR: Gemini 2.0 Flash (audio input → transcription)
//   - LLM: Gemini 2.0 Flash (text generation)
//   - TTS: Gemini 2.5 Flash TTS (text → audio generation)
//
// Without a key, the app runs in demo mode:
//   - ASR: cycles through predefined sample phrases
//   - LLM: returns stub conversational responses
//   - TTS: uses platform-native text-to-speech (always works)
// ---------------------------------------------------------------------------
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

void main() {
  runApp(const VoiceChatApp());
}

class VoiceChatApp extends StatelessWidget {
  const VoiceChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Chat Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late TurnController _turnController;
  final AudioRecorder _recorder = AudioRecorder();
  late final AsrService _asr;
  late final LlmService _llm;
  late final TtsService _tts;

  bool _isRecording = false;
  bool _isInitializing = true;
  String? _engineLabel;
  ConversationState _currentState = ConversationState.idle;
  final List<ChatMessage> _messages = [];

  /// Conversation history for LLM context (survives interruptions).
  final List<ConversationTurn> _conversationHistory = [];

  /// Raw PCM16 audio buffer for ASR transcription.
  final List<Uint8List> _audioBuffer = [];

  /// Smoothed audio energy for VAD (exponential moving average).
  double _smoothedEnergy = 0.0;

  /// Whether the agent is currently in a generate → speak pipeline.
  /// Used to prevent overlapping pipelines.
  bool _agentResponding = false;

  StreamSubscription<TurnDecision>? _decisionSub;
  StreamSubscription<ConversationState>? _stateSub;
  StreamSubscription<Uint8List>? _audioStreamSub;

  @override
  void initState() {
    super.initState();
    _asr = AsrService(
      apiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
    );
    _llm = LlmService(
      apiKey: _geminiApiKey.isNotEmpty ? _geminiApiKey : null,
    );
    _tts = TtsService();
    _setup();
  }

  Future<void> _setup() async {
    await _tts.initialize();

    // Try SmartTurn (ONNX model) first, fall back to heuristic on failure.
    try {
      _turnController = TurnController.withSmartTurn();
      await _turnController.initialize();
      _engineLabel = 'SmartTurn';
    } catch (e) {
      debugPrint('SmartTurn init failed ($e), falling back to heuristic');
      _turnController = TurnController.withHeuristic();
      await _turnController.initialize();
      _engineLabel = 'Heuristic';
    }

    _decisionSub = _turnController.decisions.listen(_handleDecision);
    _stateSub = _turnController.stateChanges.listen((state) {
      if (!mounted) return;
      debugPrint('[State] ${state.name}');
      setState(() => _currentState = state);
    });

    if (mounted) setState(() => _isInitializing = false);
  }

  // ---------------------------------------------------------------------------
  // Decision handling
  // ---------------------------------------------------------------------------

  Future<void> _handleDecision(TurnDecision decision) async {
    // Log non-trivial decisions (skip continueListening to reduce noise).
    if (decision.action != TurnAction.continueListening) {
      debugPrint('[Decision] ${decision.action.name} '
          '(confidence: ${decision.confidence.toStringAsFixed(2)}, '
          'reason: ${decision.reason})');
    }

    switch (decision.action) {
      case TurnAction.commitAndRespond:
        await _handleCommit();
      case TurnAction.interruptAgent:
        await _handleInterrupt();
      case TurnAction.backchannel:
      case TurnAction.continueListening:
      case TurnAction.continueTalking:
      case TurnAction.hold:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Commit — user finished speaking, transcribe → generate → speak.
  // ---------------------------------------------------------------------------

  Future<void> _handleCommit() async {
    if (_agentResponding) return;

    // 1. Merge buffered audio and clear for next utterance.
    final audioBytes = AsrService.mergeBuffers(_audioBuffer);
    _audioBuffer.clear();

    // 2. Transcribe audio to text.
    String userText;
    try {
      userText = await _asr.transcribe(audioBytes);
    } catch (e) {
      debugPrint('ASR failed: $e');
      userText = '';
    }

    if (userText.trim().isEmpty) return;

    // 3. Add user message to UI and conversation history.
    setState(() {
      _messages.add(ChatMessage(text: userText, isUser: true));
    });
    _conversationHistory.add(
      ConversationTurn(text: userText, isUser: true),
    );

    // Feed transcript to controller for context.
    _turnController.onFinalTranscript(userText);

    // 4. Generate and speak response.
    await _generateAndSpeak(userText);
  }

  /// Core pipeline: LLM generation → TTS playback.
  ///
  /// Separated from [_handleCommit] so it can be re-invoked after an
  /// interruption with updated context.
  Future<void> _generateAndSpeak(String userText) async {
    if (_agentResponding) return;
    _agentResponding = true;

    try {
      // --- Phase 1: LLM generation ---
      _turnController.onAgentStateChanged(AgentState.thinking);

      final String response;
      try {
        response = await _llm.generate(
          userText,
          conversationContext: _conversationHistory,
        );
      } on GenerationCancelledException {
        // Generation was cancelled due to barge-in during thinking.
        // The interrupt handler will take care of the next steps.
        return;
      }

      // Add agent response to UI and conversation history.
      setState(() {
        _messages.add(ChatMessage(text: response, isUser: false));
      });
      _conversationHistory.add(
        ConversationTurn(text: response, isUser: false),
      );

      // --- Phase 2: TTS playback ---
      // Clear audio buffer before speaking to discard any echo/noise
      // accumulated during LLM generation.
      _audioBuffer.clear();
      _turnController.onAgentStateChanged(AgentState.speaking);
      await _tts.speak(response);
      // Clear again after speaking to discard TTS echo residue.
      _audioBuffer.clear();
      _smoothedEnergy = 0.0;
      _turnController.onAgentStateChanged(AgentState.idle);
    } finally {
      _agentResponding = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Interrupt — user barged in during agent response.
  // ---------------------------------------------------------------------------

  /// Handles the full barge-in lifecycle:
  ///
  /// 1. Cancel any in-progress LLM generation.
  /// 2. Stop TTS playback and record how much was spoken.
  /// 3. Update conversation history to reflect the partial delivery.
  /// 4. Wait for the user's new utterance (next commitAndRespond).
  ///
  /// The next [_handleCommit] will automatically include the interruption
  /// context in [_conversationHistory], so the LLM can produce a coherent
  /// follow-up response.
  Future<void> _handleInterrupt() async {
    // 1. Cancel in-progress LLM request (if still in thinking phase).
    _llm.cancel();

    // 2. Stop TTS and find out what was actually delivered.
    final progress = await _tts.stopAndGetProgress();

    _turnController.onAgentStateChanged(AgentState.idle);
    _agentResponding = false;

    // 3. Update conversation history with partial delivery info.
    if (progress.fullText.isNotEmpty) {
      // Replace the last agent message with what was actually spoken,
      // marking it as interrupted so the LLM knows.
      if (_conversationHistory.isNotEmpty &&
          !_conversationHistory.last.isUser) {
        _conversationHistory.removeLast();
      }

      if (progress.spokenText.isNotEmpty) {
        _conversationHistory.add(ConversationTurn(
          text: progress.spokenText,
          isUser: false,
          wasInterrupted: true,
        ));
      }

      // Update the UI to show that the message was interrupted.
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        setState(() {
          final original = _messages.removeLast();
          _messages.add(ChatMessage(
            text: original.text,
            isUser: false,
            wasInterrupted: true,
            spokenPortion: progress.spokenText,
          ));
        });
      }
    }

    // 4. Nothing more to do — the controller continues listening.
    //    When the user finishes their new utterance, commitAndRespond
    //    will fire again. _handleCommit will call _generateAndSpeak
    //    with the updated _conversationHistory that includes the
    //    interruption context, allowing the LLM to respond coherently.
  }

  // ---------------------------------------------------------------------------
  // Recording controls
  // ---------------------------------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;

    _audioBuffer.clear();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _audioStreamSub = stream.listen((bytes) {
      if (bytes.isEmpty) return;
      // Buffer raw PCM16 bytes for ASR transcription.
      _audioBuffer.add(Uint8List.fromList(bytes));
      // Convert to Float32 for turn controller analysis.
      final samples = AudioUtils.pcm16BytesToFloat32(bytes);

      // Energy-based VAD with smoothing — prevents rapid toggling
      // during micro-pauses between syllables.
      double energy = 0.0;
      for (int i = 0; i < samples.length; i++) {
        energy += samples[i] * samples[i];
      }
      energy /= samples.length;
      // Asymmetric EMA: fast attack (detect speech quickly),
      // slow decay (ride through micro-pauses).
      final alpha = energy > _smoothedEnergy ? 0.4 : 0.05;
      _smoothedEnergy = alpha * energy + (1.0 - alpha) * _smoothedEnergy;

      // Suppress VAD while agent is speaking — TTS echo through the mic
      // would otherwise trigger false barge-in.
      final agentActive =
          _currentState == ConversationState.agentSpeaking ||
          _currentState == ConversationState.agentThinking;
      _turnController.onVadResult(!agentActive && _smoothedEnergy > 0.002);

      // Feed audio to turn controller for engine analysis.
      _turnController
          .onAudioFrame(AudioFrame(
            samples: samples,
            timestamp: DateTime.now(),
          ))
          .catchError(
            (Object e) => debugPrint('[AudioFrame error] $e'),
          );
    });

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _recorder.stop();
    _turnController.reset();
    _audioBuffer.clear();
    setState(() {
      _isRecording = false;
      _currentState = ConversationState.idle;
    });
  }

  @override
  void dispose() {
    _decisionSub?.cancel();
    _stateSub?.cancel();
    _audioStreamSub?.cancel();
    _turnController.dispose();
    _recorder.dispose();
    _tts.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voice Chat')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing turn engine...'),
            ],
          ),
        ),
      );
    }

    final isDemoMode = _geminiApiKey.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Chat'),
        actions: [
          if (_engineLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  _engineLabel!,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                _currentState.name,
                style: const TextStyle(fontSize: 11),
              ),
              backgroundColor: _colorForState(_currentState).withAlpha(40),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isDemoMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.withAlpha(40),
              child: const Text(
                'Demo mode — ASR uses sample phrases, LLM uses stub responses.\n'
                'Set GEMINI_API_KEY via --dart-define for real APIs.',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Press the mic to start a conversation',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msgIndex = _messages.length - 1 - index;
                      return _MessageBubble(message: _messages[msgIndex]);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _colorForState(_currentState).withAlpha(20),
            child: Row(
              children: [
                Icon(
                  _isRecording ? Icons.mic : Icons.mic_off,
                  size: 16,
                  color: _isRecording ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isRecording ? 'Listening...' : 'Mic off',
                  style: const TextStyle(fontSize: 12),
                ),
                const Spacer(),
                if (_currentState == ConversationState.agentThinking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleRecording,
        backgroundColor: _isRecording ? Colors.red : Colors.teal,
        child: Icon(
          _isRecording ? Icons.stop : Icons.mic,
          color: Colors.white,
        ),
      ),
    );
  }

  static Color _colorForState(ConversationState state) => switch (state) {
        ConversationState.idle => Colors.grey,
        ConversationState.listening => Colors.blue,
        ConversationState.userSpeaking => Colors.green,
        ConversationState.holdCandidate => Colors.orange,
        ConversationState.commitCandidate => Colors.deepOrange,
        ConversationState.agentThinking => Colors.purple,
        ConversationState.agentSpeaking => Colors.indigo,
        ConversationState.interrupted => Colors.red,
        ConversationState.backchannelPending => Colors.teal,
      };
}

// -----------------------------------------------------------------------------
// UI components & models
// -----------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : message.wasInterrupted
                  ? Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withAlpha(120)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.wasInterrupted && message.spokenPortion != null) ...[
              Text(message.spokenPortion!),
              Text(
                message.text.substring(
                  message.spokenPortion!.length.clamp(0, message.text.length),
                ),
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(100),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '⚡ interrupted',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ] else
              Text(message.text),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  /// Whether this agent message was interrupted before completion.
  final bool wasInterrupted;

  /// The portion of text that was actually spoken before interruption.
  final String? spokenPortion;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.wasInterrupted = false,
    this.spokenPortion,
  });
}
