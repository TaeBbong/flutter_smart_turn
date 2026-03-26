import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'model_manager.dart';
import 'smart_turn_backend.dart';

/// Local ONNX Runtime backend for Smart Turn inference.
///
/// Downloads and caches the Smart Turn v3 model, then runs inference
/// on-device using [flutter_onnxruntime].
///
/// Expects callers to provide audio already padded to [expectedInputLength].
class LocalSmartTurnBackend implements SmartTurnBackend {
  final ModelManager _modelManager;
  final OnnxRuntime _runtime = OnnxRuntime();

  OrtSession? _session;

  /// The expected input length: 8 seconds at 16kHz = 128000 samples.
  static const int expectedInputLength = 128000;

  LocalSmartTurnBackend({ModelConfig? config})
      : _modelManager = ModelManager(config: config ?? const ModelConfig());

  @override
  Future<void> connect() async {
    final modelPath = await _modelManager.ensureModel();
    _session = await _runtime.createSession(modelPath);
  }

  @override
  Future<double> infer(Float32List audioSamples) async {
    final session = _session;
    if (session == null) {
      throw StateError(
        'LocalSmartTurnBackend not connected. Call connect() first.',
      );
    }

    final inputName =
        session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    final inputTensor =
        await OrtValue.fromList(audioSamples, [audioSamples.length]);

    final outputs = await session.run({inputName: inputTensor});

    double score = 0.0;
    if (outputs.isNotEmpty) {
      final outputValue = outputs.values.first;
      final data = await outputValue.asFlattenedList();
      if (data.isNotEmpty) {
        score = (data.first as num).toDouble();
      }
      for (final value in outputs.values) {
        await value.dispose();
      }
    }

    await inputTensor.dispose();

    return score.clamp(0.0, 1.0);
  }

  @override
  Future<void> disconnect() async {
    await _session?.close();
    _session = null;
    _modelManager.dispose();
  }
}
