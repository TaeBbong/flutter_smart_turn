import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Configuration for the Smart Turn model.
class ModelConfig {
  /// URL to download the ONNX model from.
  final String modelUrl;

  /// Filename for the cached model.
  final String modelFilename;

  /// Expected model file size in bytes (for validation). Null to skip check.
  final int? expectedSizeBytes;

  const ModelConfig({
    this.modelUrl =
        'https://huggingface.co/pipecat-ai/smart-turn-v3/resolve/main/smart-turn-v3.2-cpu.onnx',
    this.modelFilename = 'smart-turn-v3.2-cpu.onnx',
    this.expectedSizeBytes,
  });
}

/// Manages downloading, caching, and loading the Smart Turn ONNX model.
class ModelManager {
  final ModelConfig config;
  final http.Client _httpClient;

  ModelManager({
    this.config = const ModelConfig(),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Get the path to the cached model, downloading if necessary.
  Future<String> ensureModel() async {
    final modelPath = await _getModelPath();
    final modelFile = File(modelPath);

    if (await modelFile.exists()) {
      if (config.expectedSizeBytes != null) {
        final size = await modelFile.length();
        if (size == config.expectedSizeBytes) {
          return modelPath;
        }
        await modelFile.delete();
      } else {
        return modelPath;
      }
    }

    await _downloadModel(modelPath);
    return modelPath;
  }

  /// Check if the model is already cached.
  Future<bool> isModelCached() async {
    return File(await _getModelPath()).exists();
  }

  /// Delete the cached model.
  Future<void> clearCache() async {
    final modelFile = File(await _getModelPath());
    if (await modelFile.exists()) {
      await modelFile.delete();
    }
  }

  Future<String> _getModelPath() async {
    final cacheDir = await _getCacheDirectory();
    return '${cacheDir.path}/${config.modelFilename}';
  }

  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}/smart_turn_models');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<void> _downloadModel(String targetPath) async {
    final response = await _httpClient.get(Uri.parse(config.modelUrl));
    if (response.statusCode != 200) {
      throw ModelDownloadException(
        'Failed to download model: HTTP ${response.statusCode}',
      );
    }
    await File(targetPath).writeAsBytes(response.bodyBytes);
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Exception thrown when model download fails.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);

  @override
  String toString() => 'ModelDownloadException: $message';
}
