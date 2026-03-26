import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';
import 'package:record/record.dart';

void main() {
  runApp(const BasicDemoApp());
}

class BasicDemoApp extends StatelessWidget {
  const BasicDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Turn Basic Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  TurnController? _controller;
  final AudioRecorder _recorder = AudioRecorder();

  bool _useSmartTurn = false;
  bool _isRecording = false;
  ConversationState _currentState = ConversationState.idle;
  TurnDecision? _lastDecision;
  final List<_EventLogEntry> _eventLog = [];

  StreamSubscription<TurnDecision>? _decisionSub;
  StreamSubscription<ConversationState>? _stateSub;
  StreamSubscription<Uint8List>? _audioStreamSub;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    await _controller?.dispose();

    final controller = _useSmartTurn
        ? TurnController.withSmartTurn()
        : TurnController.withHeuristic();

    await controller.initialize();

    _decisionSub?.cancel();
    _stateSub?.cancel();

    _decisionSub = controller.decisions.listen((decision) {
      if (!mounted) return;
      setState(() {
        _lastDecision = decision;
        _eventLog.insert(0, _EventLogEntry(
          time: DateTime.now(),
          action: decision.action,
          confidence: decision.confidence,
          reason: decision.reason,
        ));
        if (_eventLog.length > 50) _eventLog.removeLast();
      });
    });

    _stateSub = controller.stateChanges.listen((state) {
      if (!mounted) return;
      setState(() => _currentState = state);
    });

    setState(() {
      _controller = controller;
      _currentState = controller.currentState;
    });
  }

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
      _controller?.onAudioFrame(AudioFrame(
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
    _controller?.reset();
    setState(() {
      _isRecording = false;
      _currentState = ConversationState.idle;
    });
  }

  Future<void> _switchEngine(bool useSmartTurn) async {
    if (_isRecording) await _stopRecording();
    setState(() => _useSmartTurn = useSmartTurn);
    await _initController();
  }

  @override
  void dispose() {
    _decisionSub?.cancel();
    _stateSub?.cancel();
    _audioStreamSub?.cancel();
    _controller?.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Turn Demo'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Heuristic', style: TextStyle(fontSize: 12)),
              Switch(
                value: _useSmartTurn,
                onChanged: _switchEngine,
              ),
              const Text('Smart Turn', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _StateIndicator(state: _currentState),
          if (_lastDecision != null)
            _ScoreGauge(decision: _lastDecision!),
          const Divider(),
          Expanded(
            child: _EventLog(entries: _eventLog),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _toggleRecording,
        backgroundColor: _isRecording ? Colors.red : Colors.indigo,
        child: Icon(
          _isRecording ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
}

class _StateIndicator extends StatelessWidget {
  final ConversationState state;
  const _StateIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = _colorForState(state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      color: color.withAlpha(30),
      child: Column(
        children: [
          Icon(_iconForState(state), size: 48, color: color),
          const SizedBox(height: 8),
          Text(
            state.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
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

  static IconData _iconForState(ConversationState state) => switch (state) {
        ConversationState.idle => Icons.pause_circle_outline,
        ConversationState.listening => Icons.hearing,
        ConversationState.userSpeaking => Icons.record_voice_over,
        ConversationState.holdCandidate => Icons.hourglass_top,
        ConversationState.commitCandidate => Icons.check_circle_outline,
        ConversationState.agentThinking => Icons.psychology,
        ConversationState.agentSpeaking => Icons.volume_up,
        ConversationState.interrupted => Icons.pan_tool,
        ConversationState.backchannelPending => Icons.thumb_up_alt_outlined,
      };
}

class _ScoreGauge extends StatelessWidget {
  final TurnDecision decision;
  const _ScoreGauge({required this.decision});

  @override
  Widget build(BuildContext context) {
    final scores = decision.scores;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreBar(label: 'End-of-Turn', value: scores['endOfTurn'] ?? 0),
          _ScoreBar(label: 'Hold', value: scores['hold'] ?? 0),
          _ScoreBar(label: 'Interrupt', value: scores['interrupt'] ?? 0),
          _ScoreBar(label: 'Backchannel', value: scores['backchannel'] ?? 0),
          const SizedBox(height: 4),
          Text(
            '→ ${decision.action.name} (${(decision.confidence * 100).toStringAsFixed(0)}%)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (decision.reason != null)
            Text(
              decision.reason!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  const _ScoreBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  final List<_EventLogEntry> entries;
  const _EventLog({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'Press the mic button to start',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          dense: true,
          leading: Icon(
            _iconForAction(entry.action),
            color: _colorForAction(entry.action),
            size: 20,
          ),
          title: Text(
            entry.action.name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _colorForAction(entry.action),
            ),
          ),
          subtitle: entry.reason != null ? Text(entry.reason!, style: const TextStyle(fontSize: 11)) : null,
          trailing: Text(
            '${entry.time.hour.toString().padLeft(2, '0')}:'
            '${entry.time.minute.toString().padLeft(2, '0')}:'
            '${entry.time.second.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        );
      },
    );
  }

  static IconData _iconForAction(TurnAction action) => switch (action) {
        TurnAction.continueListening => Icons.hearing,
        TurnAction.commitAndRespond => Icons.check_circle,
        TurnAction.interruptAgent => Icons.pan_tool,
        TurnAction.continueTalking => Icons.volume_up,
        TurnAction.backchannel => Icons.thumb_up,
        TurnAction.hold => Icons.hourglass_top,
      };

  static Color _colorForAction(TurnAction action) => switch (action) {
        TurnAction.continueListening => Colors.grey,
        TurnAction.commitAndRespond => Colors.green,
        TurnAction.interruptAgent => Colors.red,
        TurnAction.continueTalking => Colors.indigo,
        TurnAction.backchannel => Colors.teal,
        TurnAction.hold => Colors.orange,
      };
}

class _EventLogEntry {
  final DateTime time;
  final TurnAction action;
  final double confidence;
  final String? reason;

  const _EventLogEntry({
    required this.time,
    required this.action,
    required this.confidence,
    this.reason,
  });
}
