import 'dart:typed_data';

/// Interface for Smart Turn inference backends.
///
/// Backends handle the actual model execution, whether local (ONNX) or
/// remote (HTTP/WebSocket server).
abstract interface class SmartTurnBackend {
  /// Connect to the backend (load model, establish connection, etc.).
  Future<void> connect();

  /// Run inference on the given audio samples.
  ///
  /// [audioSamples] should be 16kHz mono PCM float32, up to 128000 samples
  /// (8 seconds). Shorter audio should be zero-padded at the beginning.
  ///
  /// Returns a turn-end score in [0.0, 1.0].
  Future<double> infer(Float32List audioSamples);

  /// Disconnect and release resources.
  Future<void> disconnect();
}
