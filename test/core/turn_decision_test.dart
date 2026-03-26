import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  group('TurnInference', () {
    test('equality works', () {
      const a = TurnInference(endOfTurnScore: 0.8, holdScore: 0.2);
      const b = TurnInference(endOfTurnScore: 0.8, holdScore: 0.2);
      expect(a, equals(b));
    });

    test('default values', () {
      const inference = TurnInference(endOfTurnScore: 0.5);
      expect(inference.holdScore, 0.0);
      expect(inference.interruptScore, 0.0);
      expect(inference.backchannelScore, 0.0);
      expect(inference.extras, isEmpty);
    });
  });

  group('TurnDecision', () {
    test('equality works', () {
      const a = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
        reason: 'test',
      );
      const b = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
        reason: 'test',
      );
      expect(a, equals(b));
    });

    test('copyWith overrides fields', () {
      const original = TurnDecision(
        action: TurnAction.commitAndRespond,
        confidence: 0.9,
        reason: 'original',
      );

      final modified = original.copyWith(
        action: TurnAction.hold,
        reason: 'modified',
      );

      expect(modified.action, TurnAction.hold);
      expect(modified.confidence, 0.9); // unchanged
      expect(modified.reason, 'modified');
    });

    test('copyWith with no args returns equal object', () {
      const original = TurnDecision(
        action: TurnAction.continueListening,
        confidence: 0.5,
      );
      final copy = original.copyWith();
      expect(copy, equals(original));
    });
  });
}
