import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

/// Placeholder TTS (Text-to-Speech) service.
///
/// In production, replace with a real TTS integration such as:
/// - Google Cloud TTS
/// - ElevenLabs
/// - Platform native TTS (flutter_tts)
class TtsService {
  final AudioPlayer _player = AudioPlayer();

  /// API key for TTS service (optional — falls back to stub).
  final String? apiKey;

  /// The full text currently being spoken.
  String? _currentText;

  /// When playback started for the current utterance.
  DateTime? _playbackStartTime;

  /// Estimated total duration for the current utterance.
  Duration? _estimatedDuration;

  /// Completer for the current speak operation (used for cancellation).
  Completer<void>? _speakCompleter;

  TtsService({this.apiKey});

  /// Speak the given text.
  ///
  /// This is a stub that simulates playback delay.
  /// Replace with actual TTS API call + audio playback.
  Future<void> speak(String text) async {
    _currentText = text;
    _playbackStartTime = DateTime.now();

    if (apiKey != null && apiKey!.isNotEmpty) {
      await _speakWithApi(text);
    } else {
      // Stub: simulate TTS playback duration based on text length.
      // ~150ms per word is a rough approximation.
      final wordCount = text.split(' ').length;
      final duration = Duration(milliseconds: wordCount * 150);
      _estimatedDuration = duration;

      _speakCompleter = Completer<void>();
      final timer = Timer(duration, () {
        if (!_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });

      try {
        await _speakCompleter!.future;
      } finally {
        timer.cancel();
      }
    }

    _currentText = null;
    _playbackStartTime = null;
    _estimatedDuration = null;
    _speakCompleter = null;
  }

  Future<void> _speakWithApi(String text) async {
    // Example: Google Cloud TTS.
    // Replace with your preferred TTS provider.
    final wordCount = text.split(' ').length;
    _estimatedDuration = Duration(milliseconds: wordCount * 150);

    final url =
        'https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': {'text': text},
        'voice': {
          'languageCode': 'en-US',
          'name': 'en-US-Neural2-F',
        },
        'audioConfig': {'audioEncoding': 'MP3'},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS API request failed: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final audioContent = data['audioContent'] as String?;
    if (audioContent != null) {
      final bytes = base64Decode(audioContent);
      await _player.play(BytesSource(bytes));
      await _player.onPlayerComplete.first;
    }
  }

  /// Stop current playback immediately and return what was spoken so far.
  ///
  /// Returns a [TtsProgress] indicating how much of the text was delivered
  /// before the interruption. This is essential for building accurate
  /// conversation context after a barge-in.
  ///
  /// The progress estimation uses elapsed time vs estimated total duration.
  /// In production, use your TTS provider's progress callback for accuracy.
  Future<TtsProgress> stopAndGetProgress() async {
    final text = _currentText ?? '';
    final startTime = _playbackStartTime;
    final estimatedTotal = _estimatedDuration;

    // Cancel the stub timer if active.
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    await _player.stop();

    if (text.isEmpty || startTime == null || estimatedTotal == null) {
      return TtsProgress(fullText: text, spokenText: '', remainingText: text);
    }

    // Estimate how much was spoken based on elapsed time.
    final elapsed = DateTime.now().difference(startTime);
    final progress =
        (elapsed.inMilliseconds / estimatedTotal.inMilliseconds).clamp(0.0, 1.0);

    final words = text.split(' ');
    final spokenWordCount = (words.length * progress).round();
    final spokenText = words.take(spokenWordCount).join(' ');
    final remainingText = words.skip(spokenWordCount).join(' ');

    _currentText = null;
    _playbackStartTime = null;
    _estimatedDuration = null;
    _speakCompleter = null;

    return TtsProgress(
      fullText: text,
      spokenText: spokenText,
      remainingText: remainingText,
    );
  }

  /// Stop current playback immediately (for simple barge-in without tracking).
  Future<void> stop() async {
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    await _player.stop();
    _currentText = null;
    _playbackStartTime = null;
    _estimatedDuration = null;
    _speakCompleter = null;
  }

  void dispose() {
    _player.dispose();
  }
}

/// Represents how much of an utterance was spoken before interruption.
class TtsProgress {
  /// The complete text that was being spoken.
  final String fullText;

  /// The portion that was likely already delivered to the user.
  final String spokenText;

  /// The portion that was not yet spoken.
  final String remainingText;

  const TtsProgress({
    required this.fullText,
    required this.spokenText,
    required this.remainingText,
  });
}
