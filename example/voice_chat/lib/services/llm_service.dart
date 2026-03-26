import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Placeholder LLM service for generating conversational responses.
///
/// In production, replace with a real LLM integration such as:
/// - Gemini API (recommended — already used in the main project)
/// - OpenAI Chat Completions API
/// - Local LLM via llamadart
class LlmService {
  /// API key for the LLM service. Set via environment or config.
  final String? apiKey;

  /// Base URL for the LLM API.
  final String baseUrl;

  /// Active HTTP client for the current request (used for cancellation).
  http.Client? _activeClient;

  /// Whether the current generation has been cancelled.
  bool _cancelled = false;

  LlmService({
    this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  });

  /// Generate a response to the user's message.
  ///
  /// Optionally accepts [conversationContext] to provide prior conversation
  /// history, which is especially useful after a barge-in interruption.
  ///
  /// This is a stub that returns a canned response.
  /// Replace with actual LLM API call.
  Future<String> generate(
    String userMessage, {
    List<ConversationTurn>? conversationContext,
  }) async {
    _cancelled = false;

    if (apiKey != null && apiKey!.isNotEmpty) {
      return _callGeminiApi(userMessage, context: conversationContext);
    }

    // Stub response for demo without API key.
    await Future.delayed(const Duration(milliseconds: 500));
    if (_cancelled) throw GenerationCancelledException();
    return _stubResponse(userMessage, context: conversationContext);
  }

  /// Cancel the currently running generation.
  ///
  /// Call this when the user barges in during agent thinking/speaking
  /// to avoid wasting resources on a response that will be discarded.
  void cancel() {
    _cancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  Future<String> _callGeminiApi(
    String userMessage, {
    List<ConversationTurn>? context,
  }) async {
    _activeClient = http.Client();

    try {
      final url =
          '$baseUrl/models/gemini-2.5-flash:generateContent?key=$apiKey';

      // Build contents array with conversation history.
      final contents = <Map<String, dynamic>>[];
      if (context != null) {
        for (final turn in context) {
          final text = turn.wasInterrupted
              ? '${turn.text} [interrupted — did not finish speaking]'
              : turn.text;
          contents.add({
            'role': turn.isUser ? 'user' : 'model',
            'parts': [
              {'text': text}
            ],
          });
        }
      }
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      });

      final response = await _activeClient!.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {
            'parts': [
              {
                'text':
                    'You are a friendly voice assistant in a real-time conversation. '
                    'Keep responses concise (1-3 sentences) and natural for spoken dialogue. '
                    'Do not use markdown, bullet points, or special formatting — '
                    'your text will be read aloud by a TTS engine. '
                    'If the conversation shows you were interrupted, '
                    'briefly acknowledge it and address the user\'s latest message.',
              }
            ],
          },
          'contents': contents,
        }),
      );

      if (_cancelled) throw GenerationCancelledException();
      if (response.statusCode != 200) {
        throw Exception('LLM API request failed: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return 'No response.';

      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return 'No response.';

      return parts.first['text'] as String? ?? 'No response.';
    } on http.ClientException {
      // Client was closed due to cancellation.
      throw GenerationCancelledException();
    } finally {
      _activeClient = null;
    }
  }

  String _stubResponse(
    String userMessage, {
    List<ConversationTurn>? context,
  }) {
    final lower = userMessage.toLowerCase();

    // If this is a post-interruption re-generation, acknowledge it.
    if (context != null && context.any((t) => t.wasInterrupted)) {
      return "Sorry about that! Let me address your question instead. "
          "You asked: '$userMessage'. That's a great question!";
    }

    if (lower.contains('hello') || lower.contains('hi') ||
        lower.contains('how are you')) {
      return "Hello! I'm doing great, thanks for asking! "
          "How can I help you today?";
    }
    if (lower.contains('joke')) {
      return 'Why do programmers prefer dark mode? '
          'Because light attracts bugs!';
    }
    if (lower.contains('interesting') || lower.contains('tell me')) {
      return 'Did you know that honey never spoils? Archaeologists have found '
          '3000-year-old honey in Egyptian tombs that was still edible!';
    }
    if (lower.contains('help')) {
      return "I can chat about anything! Try asking me a question, "
          "requesting a joke, or just having a conversation.";
    }
    if (lower.contains('explain') || lower.contains('simpler')) {
      return "Of course! In simpler terms, I'm a voice assistant that uses "
          "smart turn-taking to have natural conversations with you.";
    }
    if (lower.contains('thank')) {
      return "You're welcome! Is there anything else you'd like to chat about?";
    }
    return "That's a great point! I'd love to hear more about "
        "your thoughts on that.";
  }
}

/// A single turn in the conversation, used for building LLM context.
class ConversationTurn {
  final String text;
  final bool isUser;

  /// Whether this agent turn was interrupted before completion.
  final bool wasInterrupted;

  const ConversationTurn({
    required this.text,
    required this.isUser,
    this.wasInterrupted = false,
  });
}

/// Thrown when [LlmService.cancel] is called during generation.
class GenerationCancelledException implements Exception {
  @override
  String toString() => 'GenerationCancelledException';
}
