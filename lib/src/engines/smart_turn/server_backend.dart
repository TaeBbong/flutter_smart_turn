import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'smart_turn_backend.dart';

/// Server-side Smart Turn inference backend.
///
/// Sends audio to a remote inference server via HTTP POST and receives
/// turn-end scores in response.
class ServerSmartTurnBackend implements SmartTurnBackend {
  /// Base URL of the inference server (e.g. "http://localhost:8080").
  final String serverUrl;

  /// HTTP endpoint path for inference requests.
  final String inferPath;

  final http.Client _httpClient;
  bool _connected = false;

  ServerSmartTurnBackend({
    required this.serverUrl,
    this.inferPath = '/infer',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<void> connect() async {
    // Verify server is reachable.
    try {
      final response = await _httpClient
          .get(Uri.parse('$serverUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _connected = true;
        return;
      }
    } catch (_) {
      // Fall through to error.
    }
    throw ServerBackendException(
      'Cannot connect to Smart Turn server at $serverUrl',
    );
  }

  @override
  Future<double> infer(Float32List audioSamples) async {
    if (!_connected) {
      throw StateError(
        'ServerSmartTurnBackend not connected. Call connect() first.',
      );
    }

    final body = jsonEncode({
      'audio': audioSamples,
      'sample_rate': 16000,
    });

    final response = await _httpClient.post(
      Uri.parse('$serverUrl$inferPath'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw ServerBackendException(
        'Inference request failed: HTTP ${response.statusCode}',
      );
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final score = (result['score'] as num?)?.toDouble() ?? 0.0;
    return score.clamp(0.0, 1.0);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _httpClient.close();
  }
}

/// Exception thrown when server backend operations fail.
class ServerBackendException implements Exception {
  final String message;
  const ServerBackendException(this.message);

  @override
  String toString() => 'ServerBackendException: $message';
}
