import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// TTS (Text-to-Speech) service using platform-native engine.
///
/// Uses [FlutterTts] which starts speaking immediately (streaming synthesis)
/// and coexists cleanly with the audio recording session.
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  final String language;

  /// The full text currently being spoken.
  String? _currentText;

  /// Character offset tracking from flutter_tts progress handler.
  int _lastSpokenOffset = 0;

  /// Completer for the current speak operation.
  Completer<void>? _speakCompleter;

  TtsService({this.language = 'en-US'});

  /// Initialize the TTS engine. Must be called before [speak].
  Future<void> initialize() async {
    await _flutterTts.setLanguage(language);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Keep audio session alive so recording isn't interrupted.
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker],
    );

    _flutterTts.setCompletionHandler(() {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });

    _flutterTts.setCancelHandler(() {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    });

    _flutterTts.setErrorHandler((msg) {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.completeError(Exception('TTS error: $msg'));
      }
    });

    // Track word-level progress for accurate interruption handling.
    _flutterTts.setProgressHandler(
      (String text, int start, int end, String word) {
        _lastSpokenOffset = end;
      },
    );
  }

  /// Speak the given text. Starts playing immediately (streaming synthesis).
  Future<void> speak(String text) async {
    _currentText = text;
    _lastSpokenOffset = 0;
    _speakCompleter = Completer<void>();
    await _flutterTts.speak(text);
    await _speakCompleter!.future;
    _reset();
  }

  /// Stop current playback and return what was spoken so far.
  ///
  /// Uses flutter_tts word-level progress for accurate tracking.
  Future<TtsProgress> stopAndGetProgress() async {
    final text = _currentText ?? '';

    await _flutterTts.stop();

    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }

    String spokenText;
    String remainingText;

    if (_lastSpokenOffset > 0 && _lastSpokenOffset <= text.length) {
      spokenText = text.substring(0, _lastSpokenOffset);
      remainingText = text.substring(_lastSpokenOffset);
    } else {
      spokenText = '';
      remainingText = text;
    }

    _reset();

    return TtsProgress(
      fullText: text,
      spokenText: spokenText,
      remainingText: remainingText,
    );
  }

  /// Stop current playback immediately (for simple barge-in without tracking).
  Future<void> stop() async {
    await _flutterTts.stop();
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    _reset();
  }

  void _reset() {
    _currentText = null;
    _lastSpokenOffset = 0;
    _speakCompleter = null;
  }

  void dispose() {
    _flutterTts.stop();
  }
}

/// Represents how much of an utterance was spoken before interruption.
class TtsProgress {
  final String fullText;
  final String spokenText;
  final String remainingText;

  const TtsProgress({
    required this.fullText,
    required this.spokenText,
    required this.remainingText,
  });
}
