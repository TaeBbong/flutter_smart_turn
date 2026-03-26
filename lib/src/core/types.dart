import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Actions that the turn-taking router can emit.
enum TurnAction {
  /// Keep listening — no action needed.
  continueListening,

  /// User finished speaking — trigger response generation.
  commitAndRespond,

  /// User is barging in — stop agent playback immediately.
  interruptAgent,

  /// Agent should keep talking — user noise is not an interruption.
  continueTalking,

  /// Insert a short backchannel (e.g. "uh-huh", "mm") without taking the floor.
  backchannel,

  /// User paused but likely hasn't finished — hold the floor.
  hold,
}

/// States of the conversation state machine.
enum ConversationState {
  /// No conversation activity.
  idle,

  /// Microphone is active but no speech detected yet.
  listening,

  /// User is actively speaking.
  userSpeaking,

  /// User paused — waiting to determine if turn ended.
  holdCandidate,

  /// Engine determined turn ended — ready to commit.
  commitCandidate,

  /// LLM is generating a response.
  agentThinking,

  /// Agent TTS is playing back audio.
  agentSpeaking,

  /// User interrupted the agent — playback should stop.
  interrupted,

  /// A backchannel is pending insertion.
  backchannelPending,
}

/// Events that drive state machine transitions.
enum ConversationEvent {
  /// VAD detected speech start.
  speechStarted,

  /// VAD detected silence.
  silenceDetected,

  /// Speech resumed after a pause.
  speechResumed,

  /// Engine determined the turn has ended.
  turnEnded,

  /// Engine determined the user is still speaking (hold).
  turnContinuing,

  /// LLM response generation started.
  responseStarted,

  /// TTS playback started.
  playbackStarted,

  /// TTS playback finished.
  playbackFinished,

  /// User barged in during agent speech.
  bargeIn,

  /// Backchannel insertion requested.
  backchannelRequested,

  /// Backchannel finished playing.
  backchannelFinished,

  /// Session reset to idle.
  reset,
}

/// Agent state reported by the host application.
enum AgentState {
  /// Agent is idle / not doing anything.
  idle,

  /// Agent is generating a response (LLM processing).
  thinking,

  /// Agent is speaking (TTS playback).
  speaking,
}

/// A single frame of audio data.
class AudioFrame {
  /// PCM samples as float32 values in [-1.0, 1.0].
  final Float32List samples;

  /// Sample rate in Hz (typically 16000).
  final int sampleRate;

  /// Number of channels (typically 1 for mono).
  final int channels;

  /// Timestamp when this frame was captured.
  final DateTime timestamp;

  const AudioFrame({
    required this.samples,
    this.sampleRate = 16000,
    this.channels = 1,
    required this.timestamp,
  });

  /// Duration of this audio frame.
  Duration get duration => Duration(
        microseconds: (samples.length / sampleRate * 1000000).round(),
      );
}

/// Contextual information about the current conversation state.
class TurnContext extends Equatable {
  /// Current state of the conversation state machine.
  final ConversationState state;

  /// Whether the agent is currently speaking.
  final bool agentIsSpeaking;

  /// Whether the user is currently speaking.
  final bool userIsSpeaking;

  /// Partial ASR transcript (still being recognized).
  final String? partialTranscript;

  /// Final ASR transcript (recognition complete).
  final String? finalTranscript;

  /// How long silence has lasted since last speech.
  final Duration silenceDuration;

  /// How long the user has been speaking continuously.
  final Duration speechDuration;

  const TurnContext({
    required this.state,
    this.agentIsSpeaking = false,
    this.userIsSpeaking = false,
    this.partialTranscript,
    this.finalTranscript,
    this.silenceDuration = Duration.zero,
    this.speechDuration = Duration.zero,
  });

  @override
  List<Object?> get props => [
        state,
        agentIsSpeaking,
        userIsSpeaking,
        partialTranscript,
        finalTranscript,
        silenceDuration,
        speechDuration,
      ];
}

/// Input bundle passed to [TurnEngine.analyze].
class TurnInput {
  /// The audio frame to analyze.
  final AudioFrame audioFrame;

  /// Current conversation context.
  final TurnContext context;

  const TurnInput({
    required this.audioFrame,
    required this.context,
  });
}
