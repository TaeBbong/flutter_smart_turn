import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  late HeuristicEngine engine;

  setUp(() async {
    engine = HeuristicEngine();
    await engine.initialize();
  });

  tearDown(() async {
    await engine.dispose();
  });

  TurnInput _makeInput({
    Duration silenceDuration = Duration.zero,
    Duration speechDuration = const Duration(seconds: 1),
    bool userIsSpeaking = false,
    bool agentIsSpeaking = false,
  }) {
    return TurnInput(
      audioFrame: AudioFrame(
        samples: Float32List(1600),
        timestamp: DateTime.now(),
      ),
      context: TurnContext(
        state: ConversationState.userSpeaking,
        userIsSpeaking: userIsSpeaking,
        agentIsSpeaking: agentIsSpeaking,
        silenceDuration: silenceDuration,
        speechDuration: speechDuration,
      ),
    );
  }

  group('endOfTurnScore', () {
    test('is 0 when user is speaking', () async {
      final result = await engine.analyze(_makeInput(userIsSpeaking: true));
      expect(result.endOfTurnScore, 0.0);
    });

    test('increases with silence duration', () async {
      final short = await engine.analyze(
        _makeInput(silenceDuration: const Duration(milliseconds: 200)),
      );
      final long = await engine.analyze(
        _makeInput(silenceDuration: const Duration(milliseconds: 1000)),
      );
      expect(long.endOfTurnScore, greaterThan(short.endOfTurnScore));
    });

    test('reaches 1.0 at hard timeout', () async {
      final result = await engine.analyze(
        _makeInput(silenceDuration: const Duration(milliseconds: 2000)),
      );
      expect(result.endOfTurnScore, 1.0);
    });

    test('is suppressed when speech too short', () async {
      final result = await engine.analyze(
        _makeInput(
          silenceDuration: const Duration(milliseconds: 1000),
          speechDuration: const Duration(milliseconds: 100),
        ),
      );
      // Score should be significantly reduced.
      expect(result.endOfTurnScore, lessThan(0.5));
    });
  });

  group('interruptScore', () {
    test('is high when user and agent both speaking', () async {
      final result = await engine.analyze(
        _makeInput(userIsSpeaking: true, agentIsSpeaking: true),
      );
      expect(result.interruptScore, 0.9);
    });

    test('is 0 when only user speaking', () async {
      final result = await engine.analyze(
        _makeInput(userIsSpeaking: true, agentIsSpeaking: false),
      );
      expect(result.interruptScore, 0.0);
    });
  });

  group('holdScore', () {
    test('is high during short silence', () async {
      final result = await engine.analyze(
        _makeInput(silenceDuration: const Duration(milliseconds: 300)),
      );
      expect(result.holdScore, greaterThan(0.3));
    });

    test('is 0 when no silence', () async {
      final result = await engine.analyze(
        _makeInput(silenceDuration: Duration.zero),
      );
      expect(result.holdScore, 0.0);
    });
  });

  group('custom config', () {
    test('respects custom hard timeout', () async {
      final customEngine = HeuristicEngine(
        config: const HeuristicConfig(silenceHardTimeoutMs: 500),
      );
      await customEngine.initialize();

      final result = await customEngine.analyze(
        _makeInput(silenceDuration: const Duration(milliseconds: 500)),
      );
      expect(result.endOfTurnScore, 1.0);

      await customEngine.dispose();
    });
  });
}
