import 'dart:typed_data';

/// Audio format conversion utilities.
abstract final class AudioUtils {
  /// Convert PCM16 little-endian bytes to Float32List normalized to [-1.0, 1.0].
  ///
  /// Each pair of bytes is interpreted as a signed 16-bit integer (little-endian)
  /// and divided by 32768 to produce a float in [-1.0, 1.0).
  ///
  /// Throws [ArgumentError] if [bytes] has odd length.
  static Float32List pcm16BytesToFloat32(Uint8List bytes) {
    if (bytes.length % 2 != 0) {
      throw ArgumentError('PCM16 byte length must be even, got ${bytes.length}');
    }
    final byteData = ByteData.sublistView(bytes);
    final sampleCount = bytes.length ~/ 2;
    final result = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      result[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return result;
  }
}
