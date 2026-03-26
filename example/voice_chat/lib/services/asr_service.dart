import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ASR (Automatic Speech Recognition) service using Gemini API.
///
/// Sends audio to Gemini 2.0 Flash as inline data for transcription.
/// Falls back to cycling demo transcripts when no API key is provided.
class AsrService {
  final String? apiKey;
  final String languageCode;
  final String baseUrl;

  int _demoIndex = 0;

  static const _demoTranscripts = [
    'Hello, how are you doing today?',
    'Tell me something interesting.',
    'What can you help me with?',
    'That sounds great, tell me more about it.',
    'Can you explain that in simpler terms?',
    'Thank you, that was very helpful!',
  ];

  AsrService({
    this.apiKey,
    this.languageCode = 'en-US',
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  });

  /// Transcribe PCM16 audio bytes to text.
  ///
  /// [pcm16Bytes] should be 16-bit signed little-endian PCM at 16kHz mono.
  Future<String> transcribe(Uint8List pcm16Bytes) async {
    if (apiKey != null && apiKey!.isNotEmpty && pcm16Bytes.isNotEmpty) {
      try {
        return await _callGeminiAsr(pcm16Bytes);
      } catch (e) {
        // Fall back to demo phrases on API failure (e.g. rate limit).
        debugPrint('ASR API failed ($e), using demo transcript');
      }
    }

    // Demo mode: cycle through predefined phrases.
    await Future.delayed(const Duration(milliseconds: 100));
    final text = _demoTranscripts[_demoIndex % _demoTranscripts.length];
    _demoIndex++;
    return text;
  }

  Future<String> _callGeminiAsr(Uint8List pcm16Bytes) async {
    final wavBytes = pcmToWav(pcm16Bytes);
    final audioBase64 = base64Encode(wavBytes);

    final url =
        '$baseUrl/models/gemini-2.5-flash:generateContent?key=$apiKey';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/wav',
                  'data': audioBase64,
                },
              },
              {
                'text':
                    'Transcribe this audio exactly as spoken in $languageCode. '
                    'Return only the transcription text, nothing else. '
                    'If the audio is silent or unintelligible, return an empty string.',
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini ASR failed: HTTP ${response.statusCode}\n${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return '';

    return (parts.first['text'] as String? ?? '').trim();
  }

  /// Merge multiple audio buffers into a single [Uint8List].
  static Uint8List mergeBuffers(List<Uint8List> buffers) {
    if (buffers.isEmpty) return Uint8List(0);
    final totalLength = buffers.fold<int>(0, (sum, b) => sum + b.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final buffer in buffers) {
      result.setRange(offset, offset + buffer.length, buffer);
      offset += buffer.length;
    }
    return result;
  }

  /// Convert raw PCM16 bytes to WAV format.
  static Uint8List pcmToWav(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final dataSize = pcmBytes.length;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(44);
    // RIFF chunk descriptor
    header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    // fmt sub-chunk
    header.setUint32(12, 0x666D7420, Endian.big); // "fmt "
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data sub-chunk
    header.setUint32(36, 0x64617461, Endian.big); // "data"
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmBytes);
    return wav;
  }
}
