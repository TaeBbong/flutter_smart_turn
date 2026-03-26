// This file intentionally left minimal.
// Tests are organized in subdirectories under test/.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  test('package exports core types', () {
    // Verify that the barrel export works.
    expect(TurnAction.values, isNotEmpty);
    expect(ConversationState.values, isNotEmpty);
  });
}
