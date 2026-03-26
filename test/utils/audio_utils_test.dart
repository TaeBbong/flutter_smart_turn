import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_turn/flutter_smart_turn.dart';

void main() {
  group('AudioUtils.pcm16BytesToFloat32', () {
    test('converts silence (all zeros)', () {
      final bytes = Uint8List(8); // 4 samples of silence
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result.length, 4);
      for (final sample in result) {
        expect(sample, 0.0);
      }
    });

    test('converts max positive value', () {
      // Int16 max = 32767 = 0x7FFF, little-endian: [0xFF, 0x7F]
      final bytes = Uint8List.fromList([0xFF, 0x7F]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result.length, 1);
      expect(result[0], closeTo(32767.0 / 32768.0, 0.0001));
    });

    test('converts max negative value', () {
      // Int16 min = -32768 = 0x8000, little-endian: [0x00, 0x80]
      final bytes = Uint8List.fromList([0x00, 0x80]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result.length, 1);
      expect(result[0], closeTo(-1.0, 0.0001));
    });

    test('converts known value', () {
      // Int16 = 16384 = 0x4000, little-endian: [0x00, 0x40]
      final bytes = Uint8List.fromList([0x00, 0x40]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result[0], closeTo(0.5, 0.0001));
    });

    test('converts negative known value', () {
      // Int16 = -16384 = 0xC000, little-endian: [0x00, 0xC0]
      final bytes = Uint8List.fromList([0x00, 0xC0]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result[0], closeTo(-0.5, 0.0001));
    });

    test('converts multiple samples', () {
      // Two samples: 0 and 16384
      final bytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x40]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result.length, 2);
      expect(result[0], 0.0);
      expect(result[1], closeTo(0.5, 0.0001));
    });

    test('converts empty bytes', () {
      final bytes = Uint8List(0);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      expect(result.length, 0);
    });

    test('throws on odd byte length', () {
      final bytes = Uint8List(3);
      expect(
        () => AudioUtils.pcm16BytesToFloat32(bytes),
        throwsArgumentError,
      );
    });

    test('result values are in [-1.0, 1.0) range', () {
      // Generate all extreme values
      final bytes = Uint8List.fromList([
        0xFF, 0x7F, // max positive: 32767
        0x00, 0x80, // max negative: -32768
        0x00, 0x00, // zero
        0x01, 0x00, // small positive: 1
        0xFF, 0xFF, // small negative: -1
      ]);
      final result = AudioUtils.pcm16BytesToFloat32(bytes);
      for (final sample in result) {
        expect(sample, greaterThanOrEqualTo(-1.0));
        expect(sample, lessThan(1.0));
      }
    });
  });
}
