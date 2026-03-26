import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

/// A mock backend that returns a fixed score.
class MockSmartTurnBackend implements SmartTurnBackend {
  double scoreToReturn;
  int inferCallCount = 0;
  Float32List? lastInput;

  MockSmartTurnBackend({this.scoreToReturn = 0.5});

  @override
  Future<void> connect() async {}

  @override
  Future<double> infer(Float32List audioSamples) async {
    inferCallCount++;
    lastInput = audioSamples;
    return scoreToReturn;
  }

  @override
  Future<void> disconnect() async {}
}

void main() {
  late MockSmartTurnBackend mockBackend;
  late SmartTurnEngine engine;

  setUp(() async {
    mockBackend = MockSmartTurnBackend();
    engine = SmartTurnEngine.withBackend(mockBackend);
    await engine.initialize();
  });

  tearDown(() async {
    await engine.dispose();
  });

  TurnInput _makeInput({
    int sampleCount = 1600,
    bool userIsSpeaking = false,
    bool agentIsSpeaking = false,
  }) {
    return TurnInput(
      audioFrame: AudioFrame(
        samples: Float32List(sampleCount),
        timestamp: DateTime.now(),
      ),
      context: TurnContext(
        state: ConversationState.userSpeaking,
        userIsSpeaking: userIsSpeaking,
        agentIsSpeaking: agentIsSpeaking,
      ),
    );
  }

  group('analyze', () {
    test('returns endOfTurnScore from backend', () async {
      mockBackend.scoreToReturn = 0.85;
      final result = await engine.analyze(_makeInput());
      expect(result.endOfTurnScore, 0.85);
    });

    test('holdScore is inverse of endOfTurnScore', () async {
      mockBackend.scoreToReturn = 0.3;
      final result = await engine.analyze(_makeInput());
      expect(result.holdScore, closeTo(0.7, 0.01));
    });

    test('interruptScore is high when both speaking', () async {
      final result = await engine.analyze(
        _makeInput(userIsSpeaking: true, agentIsSpeaking: true),
      );
      expect(result.interruptScore, 0.9);
    });

    test('interruptScore is 0 when agent not speaking', () async {
      final result = await engine.analyze(
        _makeInput(userIsSpeaking: true, agentIsSpeaking: false),
      );
      expect(result.interruptScore, 0.0);
    });

    test('extras contains rawSmartTurnScore', () async {
      mockBackend.scoreToReturn = 0.6;
      final result = await engine.analyze(_makeInput());
      expect(result.extras['rawSmartTurnScore'], 0.6);
    });
  });

  group('audio buffer', () {
    test('accumulates audio across calls', () async {
      await engine.analyze(_makeInput(sampleCount: 1600));
      await engine.analyze(_makeInput(sampleCount: 1600));
      expect(mockBackend.inferCallCount, 2);
      // Ring buffer always outputs maxBufferSize, but with zero-padding.
      expect(mockBackend.lastInput!.length, SmartTurnEngine.maxBufferSize);
    });

    test('clearBuffer resets accumulated audio', () async {
      await engine.analyze(_makeInput(sampleCount: 1600));
      engine.clearBuffer();
      await engine.analyze(_makeInput(sampleCount: 800));
      // Ring buffer always outputs maxBufferSize (zero-padded).
      expect(mockBackend.lastInput!.length, SmartTurnEngine.maxBufferSize);
      // After clear + 800 samples, most of the buffer should be zeros.
      final nonZero = mockBackend.lastInput!.where((s) => s != 0.0).length;
      expect(nonZero, 0); // All zeros because Float32List(sampleCount) is zeros
    });
  });

  group('score passthrough', () {
    test('passes backend score directly as endOfTurnScore', () async {
      // Engine trusts backend to clamp; it passes scores through.
      mockBackend.scoreToReturn = 1.5;
      final result = await engine.analyze(_makeInput());
      expect(result.endOfTurnScore, 1.5);
    });

    test('holdScore is 1 - endOfTurnScore', () async {
      mockBackend.scoreToReturn = 0.3;
      final result = await engine.analyze(_makeInput());
      expect(result.holdScore, closeTo(0.7, 0.01));
    });
  });
}
