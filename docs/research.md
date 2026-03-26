# AI 실시간 음성 대화 기술 조사 결과

## 1. 핵심 API / 서비스

| 서비스 | 방식 | 턴 감지 | 지연시간 | 비용 |
|--------|------|---------|----------|------|
| [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime) | 음성→음성 직접 처리 ([WebRTC](https://platform.openai.com/docs/guides/realtime-webrtc)/WebSocket) | [시맨틱 VAD](https://developers.openai.com/api/docs/guides/realtime-vad) (의미 기반 발화 종료 감지) | 낮음 | ~$0.04/분 |
| [Gemini Live API](https://ai.google.dev/gemini-api/docs/live-api) | WebSocket 양방향 스트리밍 | Barge-in 지원, 감정 대화 | 낮음 | $0.10/1M 토큰 (무료 티어 있음) |
| [ElevenLabs Conversational AI](https://elevenlabs.io/conversational-ai) | WebSocket | [자연스러운 턴테이킹 전용 모델](https://elevenlabs.io/blog/conversational-ai-2-0) | ~75ms | 유료 |
| [LiveKit](https://livekit.com/) | 오픈소스 WebRTC 인프라 | 트랜스포머 기반 시맨틱 턴 감지 | <100ms | 셀프호스트 가능 |
| [Vapi](https://vapi.ai/) / [Retell AI](https://www.retellai.com) | 음성 오케스트레이션 플랫폼 | 내장 | ~300-600ms | 유료 |

## 2. Flutter 관련 오픈소스

- [openai_webrtc](https://pub.dev/packages/openai_webrtc) (pub.dev) — OpenAI Realtime API를 WebRTC로 연결하는 Flutter 패키지. 마이크 캡처/원격 오디오 재생 내장
- [LiveKit Agent Starter for Flutter](https://github.com/livekit-examples/agent-starter-flutter) — 음성 AI 에이전트 공식 스타터 템플릿 (iOS/Android/Web/macOS)
- [Stream + OpenAI Flutter Tutorial](https://getstream.io/video/sdk/flutter/tutorial/ai-voice-assistant/) ([GitHub](https://github.com/GetStream/openai-tutorial-flutter)) — Flutter + OpenAI Realtime + Stream 비디오 엣지 네트워크 완성 튜토리얼
- [Gemini Talk](https://alfredobs97.medium.com/gemini-talk-project-ai-live-multimodality-in-flutter-ac37f1787709) (Flutter) — Gemini Live API 기반 언어학습 오픈소스 프로젝트
- [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) — WebRTC 기반 음성 AI의 기초가 되는 코어 플러그인
- [Firebase AI Logic - Live API Flutter 통합](https://firebase.google.com/docs/ai-logic/live-api) — Gemini Live API의 공식 Flutter 통합 경로

## 3. 프레임워크 무관 핵심 오픈소스

- [Pipecat](https://github.com/pipecat-ai/pipecat) — 음성/멀티모달 대화 에이전트 프레임워크 (STT→LLM→TTS 파이프라인, 컴포넌트 교체 가능)
- [LiveKit Agents](https://github.com/livekit/agents) — WebRTC 기반 실시간 음성 AI 에이전트 프레임워크 (시맨틱 턴 감지, 인터럽션 처리 내장)
- [Silero VAD](https://github.com/snakers4/silero-vad) — ML 기반 음성 활동 감지기 (MIT 라이선스, <1ms/프레임, 6000+ 언어)

## 4. 핵심 기술 개념

**턴테이킹(Turn-taking)이 진짜 핵심 난제입니다:**

- **VAD만으로는 부족** — "사용자가 말하고 있는가?"는 알 수 있지만 "말을 마쳤는가?"는 알 수 없음 ([VAD 완전 가이드](https://picovoice.ai/blog/complete-guide-voice-activity-detection-vad/) / [VAD vs Turn-taking 비교](https://www.retellai.com/blog/vad-vs-turn-taking-end-point-in-conversational-ai))
- **시맨틱 턴 감지** — 운율(피치 하강), 문법적 완결성, 의미적 의도, 휴지 시간(>800ms) 등을 종합 분석 ([트랜스포머 기반 구현](https://medium.com/@manoranjan.rajguru/end-of-turn-detection-with-transformers-a-python-implementation-23bd74f621f3))
- **인터럽션(Barge-in)** — TTS 재생 중에도 사용자 음성을 모니터링하여 즉시 중단하는 풀 듀플렉스 처리 ([NVIDIA PersonaPlex](https://research.nvidia.com/labs/adlr/personaplex/))
- **WebRTC vs WebSocket** — 모바일 클라이언트는 WebRTC (UDP, 에코 캔슬링 내장), 서버 간은 WebSocket 권장 ([비교 분석](https://getstream.io/blog/webrtc-websockets/))
- **실전 구현 경험기** — [Implementing VAD and Turn-Taking for Natural Voice AI Flow](https://dev.to/callstacktech/implementing-vad-and-turn-taking-for-natural-voice-ai-flow-my-experience-1bdf)

## 5. 언어학습 앱 사례

- [Praktika](https://openai.com/index/praktika/) — OpenAI 파트너십, 멀티 에이전트 아키텍처, 비원어민 발화에 특화된 STT
- [ELSA Speak](https://elsaspeak.com/en/) — 200M+ 시간의 억양 데이터로 훈련, 음소 레벨 발음 분석 ([ELSA Voice AI Tutor](https://blog.elsaspeak.com/en/elsa-voice-ai-tutor-generative-ai/))
- **오픈소스 쪽은 아직 빈약** — 상용 앱 위주로 발전, 오픈소스 언어학습 음성대화 앱은 거의 없음

## 6. 관련 연구 및 참고자료

- [CHI 2025 - LLM 기반 음성 에이전트의 인터럽션/백채널 설계](https://dl.acm.org/doi/full/10.1145/3706598.3714228)
- [arXiv 2025 - 범용 턴테이킹 모델의 대화형 로봇 적용](https://arxiv.org/html/2501.08946v1)
- [MagicHub 듀플렉스 대화 데이터셋](https://magichub.com/unlocking-the-future-of-voice-aiintroducing-the-duplex-conversation-datasets-on-magichub-com/) — 자연스러운 인터럽션/백채널 포함 학습 데이터
- [Voice AI Agent 프레임워크 비교 (2026.03)](https://webrtc.ventures/2026/03/choosing-a-voice-ai-agent-production-framework/) — Bedrock, Vertex, LiveKit, Pipecat 비교
- [Voice AI의 빠진 퍼즐: 말하면서 듣는 능력](https://www.fastcompany.com/91448246/voice-ais-missing-piece-the-ability-to-listen-while-it-talks) — Fast Company 풀 듀플렉스 분석

## 추천 아키텍처 경로

현재 프로젝트에 Gemini를 이미 사용하고 있는 점을 고려하면:

1. **가장 빠른 경로**: [openai_webrtc](https://pub.dev/packages/openai_webrtc) → OpenAI가 VAD/턴테이킹/TTS 모두 처리 (비용 높음)
2. **비용 효율적 경로**: [Gemini Live API](https://ai.google.dev/gemini-api/docs/live-api) + [Firebase AI Logic](https://firebase.google.com/docs/ai-logic/live-api) Flutter 통합 (기존 코드베이스와 호환)
3. **가장 유연한 경로**: [LiveKit Agents](https://github.com/livekit/agents) (서버) + [Flutter 클라이언트](https://github.com/livekit-examples/agent-starter-flutter) → STT/LLM/TTS 교체 가능, 셀프호스트
4. **패키지화에 최적**: 공통 인터페이스 뒤에 여러 백엔드(Gemini/OpenAI/LiveKit)를 추상화

**오픈소스 기여 관점에서 가장 가치 있는 방향**은 3번 또는 4번입니다. Flutter에서 실시간 음성 대화를 위한 통합 패키지는 현재 시장에 거의 없어서, 높은 임팩트를 낼 수 있습니다.
