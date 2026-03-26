좋아요.
지금까지의 대화를 종합하면, 당신이 만들려는 것은 **“DualTurn 같은 특정 모델의 Dart 포팅”** 이 아니라, **실시간 음성 대화에서 말차례를 제어하는 Flutter/Dart용 turn-taking orchestration 패키지**가 가장 맞습니다.

이 방향이 좋은 이유는 명확합니다. DualTurn 논문은 실시간 음성 대화에서 **두 채널을 계속 보며** turn-taking 신호를 예측하고, 그것을 `ST / CL / SL / CT / BC` 같은 에이전트 행동으로 매핑하는 구조를 제안합니다. 즉 핵심은 “답변 내용을 생성하는 모델”이 아니라 **언제 말할지, 언제 더 들을지, 언제 끊을지, 언제 backchannel만 넣을지**를 결정하는 별도 레이어라는 점입니다. 논문도 production ASR–LLM–TTS 파이프라인이 silence timeout에 의존해 부자연스러워지는 문제를 해결하려는 맥락에서 DualTurn을 제시합니다. ([paperreading.club][1])

동시에, Gemini Live 같은 실시간 음성 API는 분명 강력하지만, 공식 문서상으로도 **Native Audio**와 **Half-Cascade**라는 서로 다른 아키텍처를 구분하고 있습니다. Native Audio는 더 자연스러운 prosody, affective dialog, proactive audio 같은 장점이 있고, Half-Cascade는 텍스트 중간 단계를 두어 **production reliability**와 **tool execution robustness**가 더 낫다고 설명합니다. 또 Live API는 VAD 기반 interruption 처리와 수동 activity control도 제공합니다. 즉 현재 생태계도 이미 “한 모델이 다 알아서 한다”보다는, **음성 처리와 제어를 어떻게 분리할 것인가**가 중요한 문제라는 뜻입니다. ([Google GitHub][2])

그래서 최종 방향은 이렇게 정리할 수 있습니다.

---

## 1. 패키지의 정체성

이 패키지는 이렇게 정의하는 게 가장 좋습니다.

**“Flutter/Dart에서 사용할 수 있는 실시간 음성 대화용 turn-taking router”**

더 구체적으로는:

- 마이크 입력, ASR partial/final, 재생 중인 에이전트 오디오, VAD 결과를 받아서
- 지금은 더 들어야 하는지
- 지금 응답 생성 트리거를 걸어야 하는지
- 에이전트 재생을 중단해야 하는지
- 짧은 backchannel만 넣어야 하는지
- 단순 pause인지 실제 turn end인지

를 판단해주는 **상태머신 + 정책엔진 + 어댑터 계층**입니다.

즉 이 패키지는 음성 모델이 아닙니다.
**음성 앱의 “conversation floor controller”** 입니다.

이 포지셔닝이 좋은 이유는, DualTurn 공식 공개 여부와 무관하게 패키지 가치가 유지되기 때문입니다. 현재 확인 가능한 공개 대안으로는 **Smart Turn v3**와 **VAP**가 있습니다. Smart Turn v3는 BSD-2-Clause의 truly open model로 공개되어 있고, 23개 언어를 지원하며, Whisper Tiny encoder 기반 8M 파라미터, 8MB int8 ONNX 체크포인트를 제공합니다. 반면 VAP는 MIT 라이선스 저장소로 공개되어 있고, 대화의 다음 2초 voice activity를 예측하는 **predictive turn-taking model**이며, stereo 두 채널 입력을 사용하는 구조입니다. ([GitHub][3])

---

## 2. 왜 “모델 패키지”가 아니라 “오케스트레이션 패키지”여야 하는가

이건 꽤 중요합니다.

지금 바로 “DualTurn 같은 모델을 내가 학습해서 Dart 패키지에 넣겠다”는 방향은 과투자에 가깝습니다. DualTurn은 dual-channel generative speech pretraining을 통해 conversational dynamics를 학습하고, fine-tuning 단계에서 turn-taking signals를 agent actions로 매핑하는 구조입니다. 논문 요약 기준으로도 0.5B 모델이 VAP보다 agent action prediction에서 더 좋은 성능을 보였고, 더 이르게 turn boundary를 예측하면서 interruption을 줄였다고 합니다. 하지만 그만큼 재현 비용도 높습니다. ([paperreading.club][1])

반면 패키지 관점에서 진짜 중요한 건 “모델의 내부 구조”가 아니라 **앱이 사용할 수 있는 안정적인 추상화**입니다. 사용자는 결국 이런 걸 원합니다.

- `아직 더 들어라`
- `지금 발화를 commit하고 응답 생성 시작`
- `사용자가 끼어들었으니 즉시 말 멈춰라`
- `backchannel만 짧게 넣어라`
- `이 pause는 아직 hold로 봐라`

즉 패키지의 핵심 가치는 **모델을 바꾸어도 안 깨지는 이벤트 계약(contract)** 에 있습니다.

그래서 이 패키지는 다음 질문에 답해야 합니다.

- 입력이 어떤 형식으로 들어오는가
- 내부 상태는 어떻게 유지되는가
- 어떤 이벤트를 방출하는가
- 어떤 엔진을 붙일 수 있는가
- 엔진이 없을 때 fallback은 무엇인가

이걸 잘 만들면,
지금은 Smart Turn, 다음엔 VAP, 나중엔 DualTurn, 혹은 상용 API 기반 custom adapter도 붙일 수 있습니다.

---

## 3. 최종 제품 전략

가장 추천하는 방향은 **멀티 엔진 구조**입니다.

### 기본 엔진

**Smart Turn adapter**

이유:

- 공개 모델이다
- ONNX가 있다
- CPU inference가 빠르다
- multilingual 지원이 있다
- “single-speaker semantic end-of-turn detector”로 MVP 만들기 좋다 ([GitHub][3])

### 실험 엔진

**VAP adapter**

이유:

- DualTurn에 더 가까운 철학이다
- stereo 두 채널 기반이다
- predictive turn-taking 실험에 적합하다
- future activity를 본다는 점에서 floor control 연구용 가치가 높다 ([Erik Ekstedt][4])

### 미래 엔진

**DualTurn adapter**

- 공식 공개가 확인되면 추가
- 패키지 전체 구조는 바뀌지 않음

### 백업 엔진

**Heuristic fallback**

- VAD + silence + partial transcript heuristic
- 어떤 모델도 못 쓰는 환경에서 동작

이 전략의 장점은 명확합니다.
패키지의 성공 여부가 특정 논문 모델의 공개 여부에 묶이지 않습니다.

---

## 4. 패키지 목표와 비목표

### 목표

이 패키지는 다음을 잘해야 합니다.

- 실시간 음성 대화에서 turn-taking 의사결정을 내린다
- Flutter 앱에서 쓰기 쉬운 API를 제공한다
- 서로 다른 turn detector/model을 공통 인터페이스로 감싼다
- barge-in, pause, hold, backchannel 같은 실전 이슈를 다룬다
- LLM/TTS와 분리된 채로 동작한다

### 비목표

처음부터 이 패키지가 하지 말아야 할 것:

- 자체 ASR 엔진 제공
- 자체 TTS 엔진 제공
- 자체 LLM 제공
- 자체 end-to-end speech model 제공
- 자체 대규모 turn-taking 모델 학습 파이프라인 제공

즉 이 패키지는 **brain**도 아니고 **voice synthesizer**도 아닙니다.
**실시간 대화의 교통경찰**입니다.

---

## 5. 패키지 구조 제안

가장 좋은 형태는 **모노레포 안의 3~4개 패키지**입니다.

### `turn_taking_core`

핵심 추상화와 상태머신

포함:

- 이벤트 타입
- 상태 enum
- router 인터페이스
- policy 인터페이스
- 공통 config
- metrics hook
- simulation utilities

### `turn_taking_smart_turn`

Smart Turn ONNX 기반 어댑터

포함:

- Smart Turn analyzer adapter
- VAD 연동
- end-of-turn score → router action 매핑
- 플랫폼별 inference bridge

### `turn_taking_vap`

VAP 서버/파이썬 프로세스/원격 inference 어댑터

포함:

- stereo audio framing
- VAP score parsing
- projection output → router action 매핑
- optional websocket bridge

### `turn_taking_flutter`

Flutter 친화 레이어

포함:

- microphone stream integration helpers
- audio playback sync hooks
- Riverpod/Bloc friendly controller
- widget/debug overlay
- example app

### 선택 패키지: `turn_taking_fallback`

모델 없는 환경용 heuristic engine

---

## 6. 핵심 추상화 설계

여기서 제일 중요합니다.
패키지 성공 여부는 이 인터페이스에 달려 있습니다.

예를 들면 public API는 이런 형태가 좋습니다.

```dart
enum TurnAction {
  continueListening,
  commitAndRespond,
  interruptAgent,
  continueTalking,
  backchannel,
  hold,
}

enum ConversationState {
  idle,
  userSpeaking,
  agentThinking,
  agentSpeaking,
  overlapping,
  paused,
}

class AudioFrame {
  final List<int> pcm16;
  final int sampleRate;
  final int channels;
  final DateTime timestamp;
}

class TurnContext {
  final bool agentIsSpeaking;
  final bool userIsSpeaking;
  final String? partialTranscript;
  final String? finalTranscript;
  final Duration silenceDuration;
  final ConversationMode mode;
}
```

그리고 엔진 추상화는 이렇게 가는 게 좋습니다.

```dart
abstract interface class TurnEngine {
  Future<void> initialize();
  Future<TurnInference> analyze(TurnInput input);
  Future<void> dispose();
}
```

`TurnInference`는 raw score를 담고,
그 위에서 `TurnRouter`가 최종 action을 냅니다.

```dart
class TurnInference {
  final double endOfTurnScore;
  final double holdScore;
  final double interruptScore;
  final double backchannelScore;
  final Map<String, double> extras;
}
```

그리고 최종 decision은 엔진이 아니라 router가 합니다.

```dart
abstract interface class TurnRouter {
  TurnDecision decide(
    TurnInference inference,
    TurnContext context,
  );
}
```

이렇게 해야 하는 이유는,
Smart Turn처럼 end-of-turn 위주 모델도 있고,
VAP처럼 future activity 위주 모델도 있고,
DualTurn처럼 agent action 직접 예측하는 모델도 있기 때문입니다.

즉 **engine은 score provider**,
**router는 policy interpreter**
로 분리해야 합니다.

---

## 7. 상태머신 설계

이 패키지는 내부적으로 상태머신이 반드시 있어야 합니다.

핵심 상태는 이 정도면 충분합니다.

- `idle`
- `listening`
- `userSpeaking`
- `holdCandidate`
- `commitCandidate`
- `agentThinking`
- `agentSpeaking`
- `interrupted`
- `backchannelPending`

전환 예시는 이렇습니다.

### 사용자 발화 시작

- VAD 또는 client signal로 speech 시작 감지
- 상태: `idle -> userSpeaking`

### 사용자가 잠깐 멈춤

- 상태: `userSpeaking -> holdCandidate`

### pause가 실제 끝으로 판단됨

- 상태: `holdCandidate -> commitCandidate`
- action: `commitAndRespond`

### LLM 응답 생성 중

- 상태: `commitCandidate -> agentThinking`

### TTS 재생 시작

- 상태: `agentThinking -> agentSpeaking`

### 사용자 끼어듦

- 상태: `agentSpeaking -> interrupted -> userSpeaking`
- action: `interruptAgent`

### 긴 설명 중 짧은 추임새

- 상태 유지
- action: `backchannel`

이 상태머신이 있으면 앱 레벨에서 제어가 쉬워집니다.

---

## 8. 전화영어 앱에 맞는 정책 레이어

이건 일반 대화 앱과 다른 포인트입니다.

당신이 만들려는 건 그냥 voice chat이 아니라 **전화영어/교육형 대화**이기 때문에, turn-taking 위에 **pedagogical policy**를 한 겹 더 두는 게 좋습니다.

예를 들면:

### speaking practice 모드

- pause를 더 길게 허용
- backchannel은 허용
- assistant의 선점 응답은 줄임

### pronunciation drill 모드

- 발화 완료 전 절대 interrupt 금지
- end-of-turn confidence가 높아야만 commit

### roleplay 모드

- 응답 latency를 짧게
- interrupt sensitivity를 높게
- overlap 허용치를 조금 완화

### correction mode

- 학생이 self-repair 중이면 기다리기
- “I go… no, I went…” 같은 패턴은 hold로 유지

즉 패키지 설계상 `TurnPolicy`를 분리하세요.

```dart
abstract interface class TurnPolicy {
  TurnDecision apply(
    TurnDecision engineDecision,
    TurnContext context,
  );
}
```

기본 정책은 general conversation,
확장 정책은 education, customer support, interview coach 등으로 갈 수 있습니다.

이게 패키지 확장성의 핵심입니다.

---

## 9. 실제 런타임 이벤트 흐름

패키지는 대략 이런 흐름으로 돌아가야 합니다.

### 입력

- mic audio frame
- playback audio frame
- VAD result
- ASR partial/final
- app mode
- user interruption signal

### 처리

1. frame buffer 누적
2. current state 업데이트
3. engine inference 호출
4. policy 적용
5. router action 확정
6. action event 방출

### 출력

- `continueListening`
- `commitAndRespond`
- `interruptAgent`
- `backchannel`
- `hold`

Flutter 앱은 이 output만 받아서 행동합니다.

예를 들어:

- `commitAndRespond` → LLM 호출
- `interruptAgent` → TTS stop + queued audio flush
- `backchannel` → 짧은 canned clip 재생
- `continueListening` → 아무것도 안 함

이렇게 되면 패키지가 매우 실용적이 됩니다.

---

## 10. Flutter 구현 관점

Flutter/Dart에서 중요한 건 “ML inference를 어디서 돌릴 것인가”입니다.

### Smart Turn 경로

가장 현실적인 방법은:

- ONNX Runtime를 네이티브 쪽에서 돌리고
- Flutter에는 platform channel 또는 FFI bridge로 연결하는 방식입니다.

Smart Turn은 ONNX 기반 공개 모델이고, CPU inference를 염두에 둔 형태라서 mobile/desktop bridge 가능성이 높습니다. 공식 문서도 로컬 ONNX inference analyzer와 CPU 사용을 설명합니다. ([Pipecat API Reference][5])

### VAP 경로

VAP는 Dart 단독 탑재보다:

- Python sidecar
- local websocket server
- remote inference server
  중 하나가 더 현실적입니다.

그래서 `turn_taking_vap`는 “모바일 온디바이스 패키지”라기보다 **실험용/서버형 adapter**로 두는 게 좋습니다.

---

## 11. 가장 좋은 MVP 범위

첫 버전은 욕심내지 않는 게 중요합니다.

### v0.1

- Smart Turn adapter만 지원
- single-user microphone turn completion detection
- VAD + Smart Turn + fallback timeout
- Flutter example app 제공

### v0.2

- ASR partial input 반영
- pedagogical policy 추가
- interruption event 지원
- debug timeline UI 추가

### v0.3

- agent playback channel 반영
- pseudo dual-channel routing
- backchannel policy 추가

### v0.4

- VAP adapter 추가
- server-side inference mode 추가
- richer analytics and metrics

### v1.0

- stable public API
- production docs
- benchmark & tuning guide
- Gemini Live / OpenAI Realtime / custom ASR-LLM-TTS integration examples

이 순서가 좋은 이유는,
처음부터 “완전한 DualTurn 대체제”를 노리면 너무 커지기 때문입니다.
반면 Smart Turn만으로도 **“semantic endpointing + turn router”**라는 명확한 가치는 바로 줄 수 있습니다. Smart Turn 자체도 basic VAD보다 자연스러운 conversational cues를 반영하는 semantic turn detector로 설명됩니다. ([Pipecat][6])

---

## 12. 차별점 문장

패키지 소개 문구는 이런 식이 좋습니다.

> A Flutter/Dart turn-taking router for real-time voice apps.
> It separates “what to say” from “when to say it”.

혹은 한국어로:

> 실시간 음성 앱에서 “무슨 말을 할지”와 “언제 말할지”를 분리해주는 Flutter/Dart turn-taking 패키지

이 문장이 지금까지 논의를 가장 잘 압축합니다.

---

## 13. 왜 이 패키지가 시장성이 있는가

당신이 느꼈던 문제가 바로 시장 문제입니다.

많은 개발자가 Gemini Live나 다른 실시간 음성 API를 써보지만, 실제 제품에 들어가면 다음에서 막힙니다.

- silence timeout이 어색함
- 사용자 pause를 너무 빨리 끝으로 침
- 끼어들기 처리 품질이 아쉬움
- backchannel 제어가 없음
- 교육/상담/인터뷰 같은 도메인 정책을 넣기 어려움

공식 문서들도 Live API에서 VAD, interruption, manual activity signal, Native Audio vs Half-Cascade 트레이드오프를 자세히 다룹니다. 이건 곧 **“말차례 제어”가 제품의 독립 문제**라는 뜻입니다. ([Google GitHub][2])

즉 이 패키지는 단순 wrapper가 아니라,
**실시간 음성 앱 생태계에서 아직 빈 곳이 큰 레이어**를 노릴 수 있습니다.

---

## 14. 오픈소스 전략

이건 오픈소스로 시작하는 게 좋습니다.

추천 방식은:

- `turn_taking_core`: 완전 오픈
- `turn_taking_smart_turn`: 오픈
- `turn_taking_vap`: 오픈
- 예제 앱: 오픈
- 고급 대시보드/analytics/tuning presets는 나중에 확장 가능

이렇게 하면:

- pub.dev 유입
- GitHub 스타 확보
- voice AI / Flutter 커뮤니티 노출
- “Flutter용 실시간 음성 UX 인프라” 포지셔닝
  이 가능합니다.

특히 당신은 패키지화와 오픈소스 브랜딩에 강점이 있으니,
이건 “앱 하나”보다 “기반 기술”로 브랜딩하기 좋습니다.

---

## 15. 최종 권장 결론

최종적으로 나는 이렇게 권합니다.

### 하지 말 것

- 지금 DualTurn 같은 모델을 직접 만들지 말 것
- 처음부터 end-to-end speech model 패키지를 만들지 말 것
- LLM/TTS까지 한 패키지에 섞지 말 것

### 해야 할 것

- **Turn-taking router 패키지**로 정의할 것
- 엔진/정책/상태머신을 분리할 것
- 기본 엔진은 Smart Turn으로 갈 것
- 실험 엔진은 VAP로 둘 것
- 미래 DualTurn 공개 가능성을 염두에 둔 adapter 구조로 설계할 것
- 전화영어용 pedagogical policy를 차별점으로 둘 것

한 문장으로 요약하면:

**당신이 만들어야 하는 것은 “DualTurn 구현체”가 아니라, DualTurn·Smart Turn·VAP·휴리스틱을 모두 수용할 수 있는 Flutter/Dart용 실시간 음성 turn-taking 플랫폼 패키지입니다.**

원하면 다음 단계로 바로 이어서
**패키지 이름 후보, pub.dev README 초안, 폴더 구조, Dart 인터페이스 코드, example 앱 구조**까지 구체적으로 설계해드릴게요.

[1]: https://paperreading.club/page?id=383774&utm_source=chatgpt.com "DualTurn: Learning Turn-Taking from Dual-Channel Generative Speech Pretraining"
[2]: https://google.github.io/adk-docs/streaming/dev-guide/part5/?utm_source=chatgpt.com "Part 5. Audio, Images, and Video - Agent Development Kit"
[3]: https://github.com/pipecat-ai/smart-turn?utm_source=chatgpt.com "GitHub - pipecat-ai/smart-turn"
[4]: https://erikekstedt.github.io/VAP/?utm_source=chatgpt.com "VAP"
[5]: https://reference-server.pipecat.ai/en/stable/_modules/pipecat/audio/turn/smart_turn/local_smart_turn_v3.html?utm_source=chatgpt.com "pipecat.audio.turn.smart_turn.local_smart_turn_v3 — pipecat-ai documentation"
[6]: https://docs.pipecat.ai/deployment/pipecat-cloud/guides/smart-turn?utm_source=chatgpt.com "Smart Turn Detection - Pipecat"
