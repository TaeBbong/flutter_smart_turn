import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  group('AudioFrame', () {
    test('calculates duration correctly', () {
      final frame = AudioFrame(
        samples: Float32List(16000), // 1 second at 16kHz
        sampleRate: 16000,
        timestamp: DateTime.now(),
      );
      expect(frame.duration, const Duration(seconds: 1));
    });

    test('calculates duration for partial frame', () {
      final frame = AudioFrame(
        samples: Float32List(1600), // 100ms at 16kHz
        sampleRate: 16000,
        timestamp: DateTime.now(),
      );
      expect(frame.duration, const Duration(milliseconds: 100));
    });

    test('stores fields correctly', () {
      final now = DateTime(2026, 1, 1);
      final samples = Float32List.fromList([0.1, 0.2, 0.3]);
      final frame = AudioFrame(samples: samples, timestamp: now);
      expect(frame.samples, samples);
      expect(frame.sampleRate, 16000);
      expect(frame.channels, 1);
      expect(frame.timestamp, now);
    });
  });

  group('TurnContext', () {
    test('default values', () {
      const context = TurnContext(state: ConversationState.idle);
      expect(context.agentIsSpeaking, false);
      expect(context.userIsSpeaking, false);
      expect(context.partialTranscript, null);
      expect(context.silenceDuration, Duration.zero);
    });

    test('equality works', () {
      const a = TurnContext(
        state: ConversationState.userSpeaking,
        userIsSpeaking: true,
        speechDuration: Duration(seconds: 2),
      );
      const b = TurnContext(
        state: ConversationState.userSpeaking,
        userIsSpeaking: true,
        speechDuration: Duration(seconds: 2),
      );
      expect(a, equals(b));
    });
  });

  group('TurnInput', () {
    test('stores fields correctly', () {
      final now = DateTime(2026, 1, 1);
      final frame = AudioFrame(
        samples: Float32List(100),
        timestamp: now,
      );
      const context = TurnContext(state: ConversationState.idle);

      final input = TurnInput(audioFrame: frame, context: context);
      expect(input.audioFrame, same(frame));
      expect(input.context, equals(context));
    });
  });

  group('Enums', () {
    test('TurnAction has all expected values', () {
      expect(TurnAction.values, containsAll([
        TurnAction.continueListening,
        TurnAction.commitAndRespond,
        TurnAction.interruptAgent,
        TurnAction.continueTalking,
        TurnAction.backchannel,
        TurnAction.hold,
      ]));
    });

    test('ConversationState has all expected values', () {
      expect(ConversationState.values.length, 9);
    });

    test('ConversationEvent has all expected values', () {
      expect(ConversationEvent.values, contains(ConversationEvent.reset));
    });
  });
}
