import 'dart:typed_data';

import '../../core/turn_decision.dart';
import '../../core/turn_engine.dart';
import '../../core/types.dart';
import '../score_utils.dart';
import 'local_backend.dart';
import 'model_manager.dart';
import 'server_backend.dart';
import 'smart_turn_backend.dart';

/// Smart Turn v3 turn-taking engine.
///
/// Uses the Smart Turn model (Whisper Tiny encoder, 8MB ONNX) to predict
/// whether the user has finished speaking. Supports both local (on-device)
/// and server-side inference.
///
/// The engine maintains a rolling 8-second audio buffer and feeds it to
/// the backend for inference on each [analyze] call.
class SmartTurnEngine implements TurnEngine {
  final SmartTurnBackend _backend;

  /// Maximum buffer size: 8 seconds at 16kHz.
  static const int maxBufferSize = 128000;

  /// Ring buffer for audio samples.
  final Float32List _ringBuffer = Float32List(maxBufferSize);
  int _writeHead = 0;
  int _samplesWritten = 0;

  /// Pre-allocated output buffer to avoid per-frame allocations.
  final Float32List _inferenceBuffer = Float32List(maxBufferSize);

  /// Create a Smart Turn engine with local ONNX inference.
  SmartTurnEngine.local({ModelConfig? config})
      : _backend = LocalSmartTurnBackend(config: config);

  /// Create a Smart Turn engine with server-side inference.
  SmartTurnEngine.server({
    required String serverUrl,
    String inferPath = '/infer',
  }) : _backend = ServerSmartTurnBackend(
          serverUrl: serverUrl,
          inferPath: inferPath,
        );

  /// Create a Smart Turn engine with a custom backend.
  SmartTurnEngine.withBackend(SmartTurnBackend backend) : _backend = backend;

  @override
  Future<void> initialize() async {
    await _backend.connect();
  }

  @override
  Future<TurnInference> analyze(TurnInput input) async {
    _appendAudio(input.audioFrame);
    final samples = _prepareInferenceBuffer();

    final score = await _backend.infer(samples);
    final context = input.context;

    return TurnInference(
      endOfTurnScore: score,
      holdScore: 1.0 - score,
      interruptScore: ScoreUtils.interruptScore(context),
      backchannelScore: 0.0,
      extras: {
        'rawSmartTurnScore': score,
        'bufferLengthMs': (_filledLength / 16.0).roundToDouble(),
      },
    );
  }

  @override
  Future<void> dispose() async {
    clearBuffer();
    await _backend.disconnect();
  }

  void _appendAudio(AudioFrame frame) {
    final samples = frame.samples;
    for (int i = 0; i < samples.length; i++) {
      _ringBuffer[_writeHead] = samples[i];
      _writeHead = (_writeHead + 1) % maxBufferSize;
    }
    _samplesWritten += samples.length;
  }

  /// Extract the ring buffer contents into [_inferenceBuffer] in chronological order.
  Float32List _prepareInferenceBuffer() {
    final filled = _filledLength;
    if (filled < maxBufferSize) {
      // Zero-pad at the beginning, audio at the end.
      _inferenceBuffer.fillRange(0, maxBufferSize - filled, 0.0);
      final start = (_writeHead - filled) % maxBufferSize;
      if (start + filled <= maxBufferSize) {
        _inferenceBuffer.setRange(maxBufferSize - filled, maxBufferSize,
            _ringBuffer, start);
      } else {
        final firstChunk = maxBufferSize - start;
        _inferenceBuffer.setRange(maxBufferSize - filled,
            maxBufferSize - filled + firstChunk, _ringBuffer, start);
        _inferenceBuffer.setRange(
            maxBufferSize - filled + firstChunk, maxBufferSize, _ringBuffer, 0);
      }
    } else {
      // Buffer is full — extract in order from writeHead.
      if (_writeHead == 0) {
        _inferenceBuffer.setAll(0, _ringBuffer);
      } else {
        final firstChunk = maxBufferSize - _writeHead;
        _inferenceBuffer.setRange(0, firstChunk, _ringBuffer, _writeHead);
        _inferenceBuffer.setRange(firstChunk, maxBufferSize, _ringBuffer, 0);
      }
    }
    return _inferenceBuffer;
  }

  int get _filledLength =>
      _samplesWritten < maxBufferSize ? _samplesWritten : maxBufferSize;

  /// Clear the audio buffer (e.g. when starting a new turn).
  void clearBuffer() {
    _ringBuffer.fillRange(0, maxBufferSize, 0.0);
    _writeHead = 0;
    _samplesWritten = 0;
  }
}
