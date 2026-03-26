import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';
import 'package:record/record.dart';

import 'services/llm_service.dart';
import 'services/tts_service.dart';

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
  late final TurnController _turnController;
  final AudioRecorder _recorder = AudioRecorder();
  late final LlmService _llm;
  late final TtsService _tts;

  bool _isRecording = false;
  ConversationState _currentState = ConversationState.idle;
  final List<ChatMessage> _messages = [];

  /// Conversation history for LLM context (survives interruptions).
  final List<ConversationTurn> _conversationHistory = [];

  /// Whether the agent is currently in a generate → speak pipeline.
  /// Used to prevent overlapping pipelines.
  bool _agentResponding = false;

  StreamSubscription<TurnDecision>? _decisionSub;
  StreamSubscription<ConversationState>? _stateSub;
  StreamSubscription<Uint8List>? _audioStreamSub;

  @override
  void initState() {
    super.initState();
    _llm = LlmService();
    _tts = TtsService();
    _turnController = TurnController.withHeuristic();
    _setup();
  }

  Future<void> _setup() async {
    await _turnController.initialize();

    _decisionSub = _turnController.decisions.listen(_handleDecision);
    _stateSub = _turnController.stateChanges.listen((state) {
      if (!mounted) return;
      setState(() => _currentState = state);
    });
  }

  // ---------------------------------------------------------------------------
  // Decision handling
  // ---------------------------------------------------------------------------

  Future<void> _handleDecision(TurnDecision decision) async {
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
  // Commit — user finished speaking, generate and speak response.
  // ---------------------------------------------------------------------------

  Future<void> _handleCommit() async {
    // TODO: Wire up ASR to populate real user text.
    const userText = '...';

    // Add user message to UI and conversation history.
    setState(() {
      _messages.add(const ChatMessage(text: userText, isUser: true));
    });
    _conversationHistory.add(
      const ConversationTurn(text: userText, isUser: true),
    );

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
      _turnController.onAgentStateChanged(AgentState.speaking);
      await _tts.speak(response);
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
      final samples = AudioUtils.pcm16BytesToFloat32(bytes);
      _turnController.onAudioFrame(AudioFrame(
        samples: samples,
        timestamp: DateTime.now(),
      ));
    });

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _recorder.stop();
    _turnController.reset();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Chat'),
        actions: [
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
