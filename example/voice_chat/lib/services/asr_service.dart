/// Placeholder ASR (Automatic Speech Recognition) service.
///
/// In production, replace with a real ASR integration such as:
/// - Google Speech-to-Text
/// - OpenAI Whisper API
/// - Local Whisper model
class AsrService {
  /// Transcribe audio bytes to text.
  ///
  /// This is a stub — replace with actual ASR API call.
  Future<String> transcribe(List<int> audioBytes) async {
    // TODO: Integrate real ASR service.
    await Future.delayed(const Duration(milliseconds: 200));
    return '';
  }

  /// Start streaming recognition (returns partial transcripts).
  Stream<String> streamTranscribe(Stream<List<int>> audioStream) async* {
    // TODO: Integrate real streaming ASR.
    yield '';
  }
}
