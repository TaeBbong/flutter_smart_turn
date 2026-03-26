# flutter_smart_turn 완전 가이드

> 음성 대화 앱에서 "지금 내가 말해도 되나?"를 판단하는 Flutter 패키지,
> `flutter_smart_turn`의 탄생 배경부터 내부 구조까지 코드를 따라가며 살펴봅니다.

---

## 목차

1. [어떤 문제에서 시작했나](#1-어떤-문제에서-시작했나)
2. [이 패키지가 하는 일, 딱 한 문장으로](#2-이-패키지가-하는-일-딱-한-문장으로)
3. [전체 구조 한눈에 보기](#3-전체-구조-한눈에-보기)
4. [핵심 개념 잡기 — 타입과 열거형](#4-핵심-개념-잡기--타입과-열거형)
5. [Engine — 점수를 매기는 사람](#5-engine--점수를-매기는-사람)
6. [Router — 점수를 행동으로 바꾸는 사람](#6-router--점수를-행동으로-바꾸는-사람)
7. [Policy — 마지막 안전장치](#7-policy--마지막-안전장치)
8. [State Machine — 대화 상태를 기억하는 기계](#8-state-machine--대화-상태를-기억하는-기계)
9. [TurnController — 모든 것을 하나로 묶는 지휘자](#9-turncontroller--모든-것을-하나로-묶는-지휘자)
10. [실제 데이터 흐름 따라가기](#10-실제-데이터-흐름-따라가기)
11. [끼어들기 이후 — 앱이 해야 할 일](#11-끼어들기-이후--앱이-해야-할-일)
12. [예제 앱으로 체험하기](#12-예제-앱으로-체험하기)
13. [마무리 — 확장 포인트와 로드맵](#13-마무리--확장-포인트와-로드맵)

---

## 1. 어떤 문제에서 시작했나

음성 AI 앱을 만들어 본 적이 있다면, 이런 경험이 있을 겁니다.

- 사용자가 말을 **잠깐 멈춘 건지, 진짜 끝난 건지** 알 수 없다.
- AI가 대답하는 도중에 사용자가 **끼어들면**(barge-in) 어떻게 해야 하지?
- "음…", "그러니까…" 같은 **머뭇거림**은 턴 종료가 아닌데 시스템이 자꾸 끊는다.
- ASR(음성 인식), LLM(언어 모델), TTS(음성 합성) 스택마다 턴 관리 로직을 **매번 새로 짜야** 한다.

이 문제들의 공통 원인은 하나입니다. **"지금 누가 말할 차례인가?"를 판단하는 로직이 따로 없다는 것.**

OpenAI Realtime API나 Gemini Live처럼 서버 안에 턴 관리가 내장된 서비스도 있지만, 그 로직을 직접 제어하거나 커스터마이징하기는 어렵습니다. 특히 Flutter로 크로스플랫폼 앱을 만들 때는 클라이언트 쪽에서 유연하게 턴을 관리할 수 있는 도구가 필요합니다.

**flutter_smart_turn**은 바로 이 문제를 풀기 위해 만들어졌습니다.

---

## 2. 이 패키지가 하는 일, 딱 한 문장으로

> **마이크 오디오와 대화 상태를 받아서, "지금 무엇을 해야 하는가"(계속 듣기 / 응답하기 / 끼어들기 중단 / …)를 스트림으로 알려주는 턴 관리 라우터.**

이 패키지는 **음성 인식(ASR)이나 LLM, TTS를 포함하지 않습니다.** 오직 "턴"만 관리합니다. 따라서 어떤 음성 스택과도 함께 사용할 수 있습니다.

---

## 3. 전체 구조 한눈에 보기

패키지의 아키텍처는 네 개의 레이어로 구성됩니다.

```
┌─────────────────────────────────────────────────┐
│                 TurnController                   │  ← 사용자가 접하는 유일한 클래스
│         (오케스트라의 지휘자 역할)                  │
├─────────────────────────────────────────────────┤
│                                                  │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│   │  Engine   │→│  Router   │→│  Policy   │     │
│   │ (점수)    │  │ (결정)    │  │ (검증)    │     │
│   └──────────┘  └──────────┘  └──────────┘     │
│                                                  │
├─────────────────────────────────────────────────┤
│              State Machine                       │  ← 대화 상태 전이 관리
└─────────────────────────────────────────────────┘
```

데이터는 항상 **Engine → Router → Policy** 순서로 한 방향으로 흐릅니다.

- **Engine**: 오디오를 분석해서 점수(0.0 ~ 1.0)를 매김
- **Router**: 점수를 임계값과 비교해서 행동을 결정
- **Policy**: 도메인 규칙으로 최종 검증 (너무 짧은 발화 차단, 디바운싱 등)

이 세 가지는 모두 **인터페이스**로 정의되어 있어서, 기본 구현을 쓰든 직접 만들든 자유롭게 교체할 수 있습니다. 이게 이 패키지의 가장 큰 장점입니다.

---

## 4. 핵심 개념 잡기 — 타입과 열거형

코드를 읽기 전에, 이 패키지가 사용하는 핵심 단어들을 먼저 정리하겠습니다. 모두 `lib/src/core/types.dart`에 정의되어 있습니다.

### TurnAction — "무엇을 할 것인가"

```dart
// lib/src/core/types.dart

enum TurnAction {
  continueListening,   // 아직 아무 일도 없으니 계속 듣기
  commitAndRespond,    // 사용자가 말을 끝냈으니 AI가 응답할 차례
  interruptAgent,      // 사용자가 끼어들었으니 AI 발화를 멈춰라
  continueTalking,     // AI가 계속 말해도 됨
  backchannel,         // "네", "음" 같은 짧은 맞장구
  hold,                // 사용자가 잠깐 멈춘 것 같은데 아직 끝은 아님
}
```

이 여섯 가지가 이 패키지의 **최종 출력**입니다. 앱에서는 이 값을 받아서 "TTS를 멈추기", "LLM에 요청 보내기" 같은 실제 동작을 수행하면 됩니다.

### ConversationState — "지금 대화가 어떤 상태인가"

```dart
// lib/src/core/types.dart

enum ConversationState {
  idle,                // 아무 활동 없음
  listening,           // 마이크 켜짐, 아직 음성 없음
  userSpeaking,        // 사용자가 말하는 중
  holdCandidate,       // 사용자가 잠깐 멈춤 — 아직 판단 중
  commitCandidate,     // 턴 종료로 판단됨 — 응답 준비
  agentThinking,       // LLM이 응답을 생성하는 중
  agentSpeaking,       // TTS가 재생하는 중
  interrupted,         // 사용자가 끼어들어서 AI가 멈춤
  backchannelPending,  // 맞장구를 넣을 타이밍
}
```

### ConversationEvent — "무슨 일이 일어났는가"

```dart
// lib/src/core/types.dart

enum ConversationEvent {
  speechStarted,       // 음성 감지됨
  silenceDetected,     // 침묵 감지됨
  turnEnded,           // 턴 종료 판정
  responseStarted,     // AI 응답 시작
  playbackStarted,     // TTS 재생 시작
  playbackEnded,       // TTS 재생 끝
  bargeIn,             // 사용자 끼어들기
  backchannelTriggered,// 맞장구 트리거
  reset,               // 초기 상태로 리셋
}
```

### AudioFrame — 오디오 한 조각

```dart
// lib/src/core/types.dart

class AudioFrame extends Equatable {
  final Float32List samples;    // PCM float32 샘플 배열
  final int sampleRate;         // 보통 16000 (16kHz)
  final int channels;           // 보통 1 (모노)
  final DateTime timestamp;     // 프레임 생성 시각

  // 이 프레임의 길이(시간)를 계산
  Duration get duration =>
      Duration(microseconds: (samples.length * 1000000 ~/ sampleRate));
}
```

마이크에서 들어오는 오디오를 이 클래스에 담아서 컨트롤러에 전달합니다.

### TurnContext — 판단에 필요한 맥락 정보

```dart
// lib/src/core/types.dart

class TurnContext extends Equatable {
  final ConversationState currentState;
  final bool isAgentSpeaking;
  final bool isUserSpeaking;
  final String? partialTranscript;
  final String? finalTranscript;
  final Duration silenceDuration;
  final Duration speechDuration;
}
```

Engine, Router, Policy가 결정을 내릴 때 참고하는 "현재 상황 요약서"입니다. "AI가 지금 말하고 있는가?", "사용자가 얼마나 오래 침묵했는가?" 같은 정보가 들어 있습니다.

---

## 5. Engine — 점수를 매기는 사람

Engine은 오디오를 분석해서 **"사용자가 말을 끝냈을 확률은 몇 %인가?"** 같은 점수를 산출합니다. 인터페이스는 아주 간단합니다.

```dart
// lib/src/core/turn_engine.dart

abstract interface class TurnEngine {
  Future<void> initialize();
  Future<TurnInference> analyze(TurnInput input);
  Future<void> dispose();
}
```

`analyze()`가 반환하는 `TurnInference`는 이렇게 생겼습니다.

```dart
// lib/src/core/turn_decision.dart

class TurnInference extends Equatable {
  final double endOfTurnScore;     // 턴 종료 확률 (0.0 ~ 1.0)
  final double holdScore;          // 일시 정지 확률
  final double interruptScore;     // 끼어들기 확률
  final double backchannelScore;   // 맞장구 확률
  final Map<String, double> extras;// 엔진별 추가 점수
}
```

이 패키지에는 **두 가지 Engine 구현체**가 포함되어 있습니다.

### 5-1. SmartTurnEngine — ONNX 모델 기반 추론

`lib/src/engines/smart_turn/smart_turn_engine.dart`

Pipecat AI의 Smart Turn v3 모델(Whisper Tiny 인코더 기반, 8MB)을 사용하는 엔진입니다. 사람이 말하는 패턴을 학습한 모델이 "이 오디오 다음에 턴이 끝날 확률"을 계산합니다.

이 엔진의 핵심은 **링 버퍼(Ring Buffer)** 입니다.

```dart
// lib/src/engines/smart_turn/smart_turn_engine.dart

class SmartTurnEngine implements TurnEngine {
  final SmartTurnBackend _backend;

  // 링 버퍼: 최근 8초(128,000 샘플)의 오디오를 순환 저장
  late final Float32List _ringBuffer;
  int _writeHead = 0;
  int _totalWritten = 0;

  static const int kWindowSamples = 128000; // 16kHz × 8초
}
```

왜 링 버퍼일까요? 모델은 항상 **최근 8초** 분량의 오디오를 입력받아야 합니다. 매번 8초치를 새로 복사하면 비효율적이니, 원형 큐처럼 오래된 샘플을 자연스럽게 덮어쓰는 구조를 사용합니다.

```dart
// 오디오 프레임이 들어오면 링 버퍼에 쓰기
void _writeToRing(Float32List samples) {
  for (var i = 0; i < samples.length; i++) {
    _ringBuffer[_writeHead] = samples[i];
    _writeHead = (_writeHead + 1) % kWindowSamples;
  }
  _totalWritten += samples.length;
}
```

분석할 때는 링 버퍼에서 **시간순으로** 데이터를 꺼냅니다.

```dart
Float32List _extractChronological() {
  final buf = Float32List(kWindowSamples);
  final filled = _totalWritten.clamp(0, kWindowSamples);

  if (filled < kWindowSamples) {
    // 아직 8초가 안 됐으면, 앞부분을 0으로 채우고 뒤에 실제 데이터
    final start = kWindowSamples - filled;
    for (var i = 0; i < filled; i++) {
      buf[start + i] = _ringBuffer[i];
    }
  } else {
    // 8초 이상이면, writeHead 위치부터 시간순으로 추출
    for (var i = 0; i < kWindowSamples; i++) {
      buf[i] = _ringBuffer[(_writeHead + i) % kWindowSamples];
    }
  }
  return buf;
}
```

SmartTurnEngine은 **백엔드를 선택할 수 있습니다**.

- **LocalBackend** (`local_backend.dart`): 디바이스에서 직접 ONNX Runtime으로 추론. 모델 파일은 HuggingFace에서 자동 다운로드 후 캐시.
- **ServerBackend** (`server_backend.dart`): HTTP POST로 서버에 오디오를 보내고 점수를 받음. 서버를 직접 운영할 때 사용.

#### LocalBackend — 모델 다운로드와 추론

```dart
// lib/src/engines/smart_turn/local_backend.dart

Future<void> connect() async {
  final modelPath = await ModelManager.ensureModel(config: _config);
  _session = await OrtSession.fromFile(File(modelPath));
}

Future<double> infer(Float32List samples) async {
  // [1, 128000] 형태로 텐서 생성
  final input = OrtValueTensor.fromList(
    samples, [1, samples.length],
  );
  final results = await _session!.run({'audio': input});
  // 결과에서 스코어 추출 (0.0 ~ 1.0)
  final score = (results['score']!.value as List<double>).first;
  return score.clamp(0.0, 1.0);
}
```

#### ModelManager — 자동 다운로드와 캐싱

```dart
// lib/src/engines/smart_turn/model_manager.dart

static Future<String> ensureModel({ModelConfig? config}) async {
  final dir = await getApplicationSupportDirectory();
  final modelDir = Directory(p.join(dir.path, 'smart_turn_models'));
  final file = File(p.join(modelDir.path, cfg.fileName));

  if (await file.exists()) {
    return file.path;  // 이미 다운로드되어 있으면 캐시 사용
  }

  // 없으면 HuggingFace에서 다운로드
  final response = await http.Client().send(
    http.Request('GET', Uri.parse(cfg.downloadUrl)),
  );
  // ... 파일 저장 로직
  return file.path;
}
```

### 5-2. HeuristicEngine — 모델 없이 규칙 기반으로

`lib/src/engines/heuristic_engine.dart`

ONNX 모델 없이, **침묵 시간**만으로 턴 종료를 판단하는 가벼운 엔진입니다. 시그모이드 함수를 사용해서 침묵이 길어질수록 "턴 종료 확률"이 올라가는 부드러운 곡선을 만듭니다.

```dart
// lib/src/engines/heuristic_engine.dart

class HeuristicConfig {
  final int silenceMidpointMs;      // 시그모이드 중간점 (기본 800ms)
  final double silenceSteepness;    // 곡선 기울기 (기본 0.006)
  final int minSpeechDurationMs;    // 최소 발화 시간 (기본 300ms)
  final int silenceHardTimeoutMs;   // 강제 종료 시간 (기본 2000ms)
}
```

점수 계산 로직을 보겠습니다.

```dart
@override
Future<TurnInference> analyze(TurnInput input) async {
  final silenceMs = input.context.silenceDuration.inMilliseconds;
  final speechMs = input.context.speechDuration.inMilliseconds;

  double endOfTurn = 0.0;
  double hold = 0.0;

  if (silenceMs > 0) {
    // 시그모이드: 침묵이 800ms 근처에서 확률 0.5, 이후 급상승
    endOfTurn = 1.0 / (1.0 + exp(-_config.silenceSteepness *
                                    (silenceMs - _config.silenceMidpointMs)));

    // 발화가 너무 짧으면(300ms 미만) 점수를 0으로 억제
    if (speechMs < _config.minSpeechDurationMs) {
      endOfTurn = 0.0;
    }

    // 2초 이상 침묵이면 무조건 턴 종료
    if (silenceMs >= _config.silenceHardTimeoutMs) {
      endOfTurn = 1.0;
    }

    // hold 점수는 endOfTurn의 반대: 아직 확신이 없을 때 높음
    if (endOfTurn < 0.7 && silenceMs > 0) {
      hold = 1.0 - endOfTurn;
    }
  }

  return TurnInference(
    endOfTurnScore: endOfTurn,
    holdScore: hold,
    interruptScore: scoreUtils.interruptScore(input.context),
    backchannelScore: 0.0,  // 휴리스틱으로는 맞장구 판단 불가
  );
}
```

그래프로 표현하면 이런 느낌입니다:

```
턴 종료 확률
1.0 ─────────────────────────────────── ████████████████
                                    ████
                                 ███
                               ██
0.5 ─────────────────────── ██
                          ██
                        ██
                     ███
0.0 ████████████████
    0ms     400ms    800ms   1200ms   1600ms   2000ms
                    침묵 시간 →
```

800ms 부근에서 확률이 50%가 되고, 2초에 도달하면 100%로 강제 종료됩니다.

---

## 6. Router — 점수를 행동으로 바꾸는 사람

Engine이 점수를 산출하면, Router가 그 점수를 보고 **구체적인 행동(TurnAction)을 결정**합니다.

인터페이스는 단 하나의 메서드뿐입니다.

```dart
// lib/src/core/turn_router.dart

abstract interface class TurnRouter {
  TurnDecision decide(TurnInference inference, TurnContext context);
}
```

### DefaultRouter — 우선순위 기반 임계값 라우터

`lib/src/router/default_router.dart`

기본 Router는 **우선순위 순서**로 점수를 확인합니다. 높은 우선순위부터 매칭되면 바로 결정을 내립니다.

```dart
// lib/src/router/default_router.dart

class RouterConfig {
  final double commitThreshold;      // 턴 종료 임계값 (기본 0.7)
  final double holdLowerBound;       // 홀드 하한 (기본 0.3)
  final double interruptThreshold;   // 끼어들기 임계값 (기본 0.8)
  final double backchannelThreshold; // 맞장구 임계값 (기본 0.6)
}
```

결정 로직을 순서대로 따라가 봅시다:

```dart
@override
TurnDecision decide(TurnInference inf, TurnContext ctx) {
  final scores = {
    'endOfTurn': inf.endOfTurnScore,
    'hold': inf.holdScore,
    'interrupt': inf.interruptScore,
    'backchannel': inf.backchannelScore,
  };

  // 1순위: 끼어들기 (가장 긴급)
  if (inf.interruptScore >= _config.interruptThreshold &&
      ctx.isAgentSpeaking) {
    return TurnDecision(
      action: TurnAction.interruptAgent,
      confidence: inf.interruptScore,
      reason: 'Interrupt score ${inf.interruptScore} ≥ ${_config.interruptThreshold}',
      scores: scores,
    );
  }

  // 2순위: 맞장구
  if (inf.backchannelScore >= _config.backchannelThreshold &&
      ctx.isAgentSpeaking) {
    return TurnDecision(
      action: TurnAction.backchannel,
      confidence: inf.backchannelScore,
      reason: 'Backchannel score ...',
      scores: scores,
    );
  }

  // 3순위: 턴 종료 → 응답 시작
  if (inf.endOfTurnScore >= _config.commitThreshold) {
    return TurnDecision(
      action: TurnAction.commitAndRespond,
      confidence: inf.endOfTurnScore,
      reason: 'End-of-turn score ...',
      scores: scores,
    );
  }

  // 4순위: 홀드 (점수가 0.3~0.7 사이)
  if (inf.endOfTurnScore >= _config.holdLowerBound) {
    return TurnDecision(
      action: TurnAction.hold,
      confidence: inf.holdScore,
      reason: 'End-of-turn in hold zone ...',
      scores: scores,
    );
  }

  // 5순위: AI가 말하는 중이면 계속 말하기
  if (ctx.isAgentSpeaking && !ctx.isUserSpeaking) {
    return TurnDecision(
      action: TurnAction.continueTalking,
      confidence: 1.0 - inf.interruptScore,
      reason: 'Agent speaking, no user interruption',
      scores: scores,
    );
  }

  // 기본값: 계속 듣기
  return TurnDecision(
    action: TurnAction.continueListening,
    confidence: 1.0 - inf.endOfTurnScore,
    reason: 'No threshold met',
    scores: scores,
  );
}
```

이 우선순위가 중요합니다:

| 순위 | 조건 | 행동 |
|------|------|------|
| 1 | 끼어들기 점수 ≥ 0.8 + AI 발화 중 | `interruptAgent` |
| 2 | 맞장구 점수 ≥ 0.6 + AI 발화 중 | `backchannel` |
| 3 | 턴 종료 점수 ≥ 0.7 | `commitAndRespond` |
| 4 | 턴 종료 점수 0.3 ~ 0.7 | `hold` |
| 5 | AI 발화 중, 사용자 조용 | `continueTalking` |
| 6 | 그 외 | `continueListening` |

---

## 7. Policy — 마지막 안전장치

Router가 결정을 내려도, 그 결정이 **현실적으로 적절한지** 한 번 더 검증하는 단계가 Policy입니다.

```dart
// lib/src/core/turn_policy.dart

abstract interface class TurnPolicy {
  TurnDecision apply(TurnDecision rawDecision, TurnContext context);
  void reset() {}
}
```

### DefaultPolicy — 실전에서 필요한 안전장치들

`lib/src/policy/default_policy.dart`

```dart
class PolicyConfig {
  final int minSpeechBeforeCommitMs;  // 최소 발화 시간 (기본 300ms)
  final int commitDebounceMs;          // 커밋 간 최소 간격 (기본 500ms)
}
```

기본 Policy는 두 가지 가드를 적용합니다:

**1. Commit Guard — 성급한 응답 방지**

```dart
if (raw.action == TurnAction.commitAndRespond) {
  // 가드 1: AI가 말하는 중이면 응답 시작하지 않음
  if (ctx.isAgentSpeaking) {
    return raw.copyWith(
      action: TurnAction.continueTalking,
      reason: 'Policy: agent is speaking, suppressing commit',
    );
  }

  // 가드 2: 사용자가 300ms도 안 말했으면 무시
  if (ctx.speechDuration.inMilliseconds < _config.minSpeechBeforeCommitMs) {
    return raw.copyWith(
      action: TurnAction.continueListening,
      reason: 'Policy: speech too short ...',
    );
  }

  // 가드 3: 마지막 커밋 후 500ms가 안 지났으면 디바운스
  if (_lastCommitTime != null) {
    final elapsed = DateTime.now().difference(_lastCommitTime!).inMilliseconds;
    if (elapsed < _config.commitDebounceMs) {
      return raw.copyWith(
        action: TurnAction.hold,
        reason: 'Policy: commit debounce ...',
      );
    }
  }

  _lastCommitTime = DateTime.now();
}
```

**2. Interrupt Guard — 불필요한 끼어들기 방지**

```dart
if (raw.action == TurnAction.interruptAgent) {
  // AI가 말하고 있지 않으면 끼어들기 자체가 불필요
  if (!ctx.isAgentSpeaking) {
    return raw.copyWith(
      action: TurnAction.continueListening,
      reason: 'Policy: agent not speaking, suppressing interrupt',
    );
  }
}
```

Policy의 역할을 실생활에 비유하면 이렇습니다:

- Engine이 "턴 종료 확률 80%"라고 말하고
- Router가 "그럼 응답을 시작하자!"라고 결정했는데
- Policy가 **"잠깐, 사용자가 0.1초밖에 안 말했어. 기침 같은 잡음일 수 있어."** 라며 차단하는 겁니다.

---

## 8. State Machine — 대화 상태를 기억하는 기계

`lib/src/core/state_machine.dart`

대화에는 **"지금 어떤 상태인가"**를 추적하는 것이 중요합니다. 상태 전이가 아무렇게나 일어나면 혼란이 생기니, 이 패키지는 명시적인 **전이 테이블**로 "어디서 어디로만 갈 수 있는지"를 정의합니다.

```dart
static final Map<ConversationState, Set<ConversationState>> _validTransitions = {
  idle:               {listening, userSpeaking, agentThinking, agentSpeaking},
  listening:          {userSpeaking, idle},
  userSpeaking:       {holdCandidate, commitCandidate, idle},
  holdCandidate:      {userSpeaking, commitCandidate, idle},
  commitCandidate:    {agentThinking, agentSpeaking, userSpeaking, idle},
  agentThinking:      {agentSpeaking, idle, interrupted},
  agentSpeaking:      {interrupted, idle, commitCandidate, backchannelPending},
  interrupted:        {userSpeaking, listening, idle},
  backchannelPending: {agentSpeaking, idle},
};
```

일반적인 대화 흐름을 따라가 보면 이렇습니다:

```
idle → userSpeaking → holdCandidate → commitCandidate → agentThinking → agentSpeaking → idle
                ↑                                                              │
                └──── interrupted ←────────────────────────────────────────────┘
                      (사용자가 끼어든 경우)
```

상태 전이를 시도하면 유효성을 검사합니다:

```dart
bool tryTransition(ConversationState next) {
  if (next == _current) return false;  // 같은 상태로는 전이 불가

  final allowed = _validTransitions[_current] ?? {};
  if (!allowed.contains(next)) {
    _onInvalidTransition?.call(_current, next);  // 콜백으로 로깅
    return false;
  }

  _current = next;
  _controller.add(next);  // 스트림으로 브로드캐스트
  return true;
}
```

`reset`은 특별히 어떤 상태에서든 `idle`로 돌아갈 수 있습니다.

---

## 9. TurnController — 모든 것을 하나로 묶는 지휘자

`lib/src/controller/turn_controller.dart`

지금까지 본 Engine, Router, Policy, State Machine을 **하나로 조합**해서 사용하기 쉬운 API를 제공하는 것이 TurnController입니다. 앱 개발자가 직접 상호작용하는 유일한 클래스입니다.

### 생성 — 네 가지 팩토리 메서드

```dart
// 1. Smart Turn 모델로 로컬 추론 (가장 정확)
final controller = TurnController.withSmartTurn();

// 2. Smart Turn 서버 추론
final controller = TurnController.withSmartTurnServer(
  serverUrl: 'https://my-inference-server.com',
);

// 3. 휴리스틱 (모델 불필요, 가벼움)
final controller = TurnController.withHeuristic();

// 4. 커스텀 조합
final controller = TurnController(
  engine: MyCustomEngine(),
  router: MyCustomRouter(),
  policy: MyCustomPolicy(),
);
```

### 입력 — 이벤트를 컨트롤러에 알려주기

```dart
// 마이크에서 오디오 프레임이 들어올 때마다
controller.onAudioFrame(audioFrame);

// VAD(Voice Activity Detection) 결과
controller.onVadResult(true);   // 음성 감지됨
controller.onVadResult(false);  // 침묵 감지됨

// 음성 인식 결과
controller.onPartialTranscript('안녕하');       // 중간 결과
controller.onFinalTranscript('안녕하세요');      // 최종 결과

// AI 상태 변경
controller.onAgentStateChanged(AgentState.thinking);
controller.onAgentStateChanged(AgentState.speaking);
controller.onAgentStateChanged(AgentState.idle);
```

### 출력 — 스트림으로 결정 받기

```dart
// 턴 결정 스트림
controller.decisions.listen((decision) {
  switch (decision.action) {
    case TurnAction.commitAndRespond:
      // LLM에 요청 보내기
      break;
    case TurnAction.interruptAgent:
      // TTS 재생 중지
      break;
    // ...
  }
});

// 상태 변경 스트림
controller.stateChanges.listen((state) {
  // UI 업데이트
});
```

### 내부 분석 흐름

`onAudioFrame()`이 호출될 때 내부에서 일어나는 일을 따라가 봅시다:

```dart
Future<void> onAudioFrame(AudioFrame frame) async {
  if (_analyzing) return;  // 이전 분석이 끝나지 않았으면 스킵
  _analyzing = true;

  try {
    // 1. 현재 맥락 정보 조립
    final context = TurnContext(
      currentState: _stateMachine.current,
      isAgentSpeaking: _agentIsSpeaking,
      isUserSpeaking: _userIsSpeaking,
      partialTranscript: _partialTranscript,
      finalTranscript: _finalTranscript,
      silenceDuration: /* 침묵 시간 계산 */,
      speechDuration: /* 발화 시간 계산 */,
    );

    final input = TurnInput(frame: frame, context: context);

    // 2. Engine → 점수 산출
    final inference = await _engine.analyze(input);

    // 3. Router → 행동 결정
    var decision = _router.decide(inference, context);

    // 4. Policy → 최종 검증
    decision = _policy.apply(decision, context);

    // 5. 상태 머신 전이
    _applyStateTransition(decision.action);

    // 6. 스트림으로 결정 발행
    _decisionController.add(decision);
  } finally {
    _analyzing = false;
  }
}
```

`_analyzing` 플래그로 동시에 두 번 분석이 실행되는 것을 방지합니다. 오디오 프레임은 매우 빠른 주기로 들어오기 때문에, 이전 분석이 끝나야 다음 분석을 시작합니다.

---

## 10. 실제 데이터 흐름 따라가기

사용자가 "안녕하세요"라고 말하고, AI가 응답하는 시나리오를 처음부터 끝까지 따라가 봅시다.

```
시간 →

[0.0s] 마이크 ON
  └→ 상태: idle → listening

[0.3s] 사용자: "안녕하세요" 발화 시작
  └→ onVadResult(true)
  └→ 상태: listening → userSpeaking
  └→ Engine 분석: endOfTurn=0.1 (말하는 중이니 낮음)
  └→ Router 결정: continueListening
  └→ Policy: 통과

[1.5s] 사용자: 발화 종료, 침묵 시작
  └→ onVadResult(false)
  └→ silenceStartTime 기록

[1.8s] 침묵 300ms 경과
  └→ Engine 분석: endOfTurn=0.35 (아직 낮음)
  └→ Router 결정: hold (0.3~0.7 구간)
  └→ 상태: userSpeaking → holdCandidate
  └→ Policy: 통과

[2.3s] 침묵 800ms 경과
  └→ Engine 분석: endOfTurn=0.75 (임계값 초과!)
  └→ Router 결정: commitAndRespond
  └→ 상태: holdCandidate → commitCandidate
  └→ Policy: speechDuration=1.2s ≥ 300ms ✓, 디바운스 ✓ → 통과!
  └→ 🎯 decisions 스트림으로 commitAndRespond 발행

[2.4s] 앱: LLM에 요청 전송
  └→ onAgentStateChanged(AgentState.thinking)
  └→ 상태: commitCandidate → agentThinking

[3.0s] LLM 응답 완료, TTS 재생 시작
  └→ onAgentStateChanged(AgentState.speaking)
  └→ 상태: agentThinking → agentSpeaking

[5.0s] TTS 재생 완료
  └→ onAgentStateChanged(AgentState.idle)
  └→ 상태: agentSpeaking → idle
```

만약 [4.0s]에 사용자가 끼어들었다면?

```
[4.0s] 사용자: AI 발화 중 끼어들기
  └→ onVadResult(true) (사용자 음성 감지)
  └→ Engine 분석: interruptScore=0.9
  └→ Router 결정: interruptAgent (0.9 ≥ 0.8 + AI 발화 중)
  └→ Policy: isAgentSpeaking=true ✓ → 통과!
  └→ 🎯 interruptAgent 발행
  └→ 상태: agentSpeaking → interrupted → userSpeaking
  └→ 앱: TTS 중지, 사용자 발화 대기
```

---

## 11. 끼어들기 이후 — 앱이 해야 할 일

10장에서 사용자가 AI 발화 중에 끼어드는 시나리오를 잠깐 봤습니다. 이 패키지는 `interruptAgent` 시그널을 발행하는 것까지만 담당합니다. **그 이후에 무슨 일이 벌어져야 하는지**는 앱이 직접 처리해야 합니다.

이것이 왜 복잡한 문제인지, 그리고 voice_chat 예제가 어떻게 해결하는지 코드를 따라가며 살펴봅시다.

### 끼어들기가 발생하면 무슨 일이 생기나

AI가 "오늘 날씨는 맑고 기온은 25도이며 미세먼지는…"이라고 말하는 도중에 사용자가 "아 그건 됐고 일정 알려줘"라고 끼어든 상황을 생각해 봅시다.

```
시간 →

[3.0s] AI: "오늘 날씨는 맑고 기온은 25도이며..."  (TTS 재생 중)
[4.0s] 사용자: "아 그건 됐고"  (끼어들기!)
         │
         ├─ TTS가 재생 중이었음 → 즉시 멈춰야 함
         ├─ LLM이 아직 생성 중이었을 수도 → 취소해야 함
         ├─ AI가 어디까지 말했는지 기록해야 함 → "오늘 날씨는 맑고 기온은 25도이며"
         └─ 사용자가 새로 말한 내용으로 다시 응답해야 함
```

이 네 가지를 제대로 처리하지 않으면, AI가 끊긴 문장을 다시 말하거나, 사용자의 새 요청을 무시하는 등의 문제가 발생합니다.

### 해법: 세 가지 서비스의 협력

voice_chat 예제에서는 `LlmService`와 `TtsService`에 끼어들기 지원 기능을 추가했습니다.

#### 1단계: TTS — 멈추면서 "어디까지 말했는지" 알려주기

기존의 `stop()`은 단순히 재생만 멈췄습니다. 새로 추가한 `stopAndGetProgress()`는 **재생 진행률을 추정**해서 반환합니다.

```dart
// example/voice_chat/lib/services/tts_service.dart

Future<TtsProgress> stopAndGetProgress() async {
  final text = _currentText ?? '';
  final startTime = _playbackStartTime;
  final estimatedTotal = _estimatedDuration;

  // 재생 중이던 타이머 즉시 종료
  if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
    _speakCompleter!.complete();
  }
  await _player.stop();

  // 경과 시간으로 진행률 추정
  final elapsed = DateTime.now().difference(startTime!);
  final progress =
      (elapsed.inMilliseconds / estimatedTotal!.inMilliseconds).clamp(0.0, 1.0);

  // 단어 단위로 끊어서 "말한 부분"과 "못 말한 부분" 분리
  final words = text.split(' ');
  final spokenWordCount = (words.length * progress).round();
  final spokenText = words.take(spokenWordCount).join(' ');
  final remainingText = words.skip(spokenWordCount).join(' ');

  return TtsProgress(
    fullText: text,
    spokenText: spokenText,      // "오늘 날씨는 맑고 기온은 25도이며"
    remainingText: remainingText, // "미세먼지는..."
  );
}
```

> **참고**: 이 예제에서는 경과 시간으로 진행률을 추정합니다. 프로덕션에서는 TTS 제공자의 워드 타이밍 콜백을 사용하면 훨씬 정확합니다.

#### 2단계: LLM — 진행 중인 요청 취소하기

AI가 아직 "생각하는 중"(thinking)이었다면, 그 요청을 취소해서 리소스를 절약해야 합니다.

```dart
// example/voice_chat/lib/services/llm_service.dart

/// 현재 진행 중인 HTTP 클라이언트
http.Client? _activeClient;
bool _cancelled = false;

void cancel() {
  _cancelled = true;
  _activeClient?.close();   // HTTP 연결 강제 종료
  _activeClient = null;
}

Future<String> generate(
  String userMessage, {
  List<ConversationTurn>? conversationContext,  // 대화 이력 전달
}) async {
  _cancelled = false;

  // ... API 호출 ...

  if (_cancelled) throw GenerationCancelledException();
  return response;
}
```

`conversationContext`가 새로 추가된 파라미터입니다. 끼어들기 이후에는 **이전 대화 이력(중단된 부분 포함)**을 함께 전달해서, LLM이 맥락을 이해하고 자연스러운 후속 응답을 생성할 수 있게 합니다.

#### 3단계: 메인 앱 — 전체 흐름 오케스트레이션

이제 세 서비스를 조합하는 핵심 코드입니다.

```dart
// example/voice_chat/lib/main.dart

/// 대화 이력 — 끼어들기 맥락도 포함
final List<ConversationTurn> _conversationHistory = [];

Future<void> _handleInterrupt() async {
  // 1. 진행 중인 LLM 요청 취소
  _llm.cancel();

  // 2. TTS 중지 + 진행률 확인
  final progress = await _tts.stopAndGetProgress();
  _turnController.onAgentStateChanged(AgentState.idle);

  // 3. 대화 이력 업데이트 — 전체 응답을 "실제로 말한 부분"으로 교체
  if (progress.fullText.isNotEmpty) {
    // 마지막 에이전트 메시지 제거 (전체 텍스트였던 것)
    if (_conversationHistory.isNotEmpty &&
        !_conversationHistory.last.isUser) {
      _conversationHistory.removeLast();
    }

    // 실제로 전달된 부분만 이력에 추가, 중단 표시 포함
    if (progress.spokenText.isNotEmpty) {
      _conversationHistory.add(ConversationTurn(
        text: progress.spokenText,
        isUser: false,
        wasInterrupted: true,  // ← LLM에게 "이건 중단된 응답이야"라고 알려줌
      ));
    }
  }

  // 4. 이제 컨트롤러가 계속 마이크를 듣고 있음.
  //    사용자가 새 발화를 마치면 commitAndRespond가 다시 발행되고,
  //    _handleCommit → _generateAndSpeak이 호출될 때
  //    _conversationHistory에 중단 맥락이 포함된 채로 LLM에 전달됨.
}
```

### 전체 시나리오를 처음부터 끝까지

```
[1.0s] 사용자: "오늘 날씨 어때?"
  └→ commitAndRespond 발행
  └→ _handleCommit() → _conversationHistory에 추가
  └→ LLM 생성: "오늘 날씨는 맑고 기온은 25도이며 미세먼지는 좋음입니다."
  └→ _conversationHistory에 전체 응답 추가
  └→ TTS 재생 시작

[3.5s] AI: "오늘 날씨는 맑고 기온은 25도이며..."  ← 여기까지 말함
[4.0s] 사용자: "아 그건 됐고"  ← 끼어들기!
  └→ interruptAgent 발행
  └→ _handleInterrupt():
      ├ _llm.cancel()         → (이미 생성 완료라 no-op)
      ├ _tts.stopAndGetProgress()
      │   → spokenText: "오늘 날씨는 맑고 기온은 25도이며"
      │   → remainingText: "미세먼지는 좋음입니다."
      └ _conversationHistory 업데이트:
          기존: [..., {agent: "오늘 날씨는 맑고 기온은 25도이며 미세먼지는 좋음입니다."}]
          변경: [..., {agent: "오늘 날씨는 맑고 기온은 25도이며", interrupted: true}]

[5.5s] 사용자: "일정 알려줘"
  └→ commitAndRespond 발행
  └→ _handleCommit():
      └ _conversationHistory =
          [{user: "오늘 날씨 어때?"},
           {agent: "오늘 날씨는 맑고 기온은 25도이며", interrupted: true},  ← 중단 맥락
           {user: "일정 알려줘"}]                                         ← 새 요청
      └ LLM이 이 맥락을 보고 자연스럽게 응답:
        "네! 오늘 일정은 오후 2시에 회의가 있고..."
```

### UI에서의 표현

끼어들린 메시지는 시각적으로 구분됩니다.

```dart
// 끼어들린 메시지의 UI 처리
if (message.wasInterrupted && message.spokenPortion != null) ...[
  Text(message.spokenPortion!),           // 전달된 부분: 정상 표시
  Text(
    /* 나머지 부분 */,
    style: TextStyle(
      decoration: TextDecoration.lineThrough,  // 취소선
      color: Colors.grey,
    ),
  ),
  Text('⚡ interrupted', style: TextStyle(color: Colors.red)),
]
```

채팅 버블에서 "전달된 부분"은 정상적으로, "전달되지 못한 부분"은 취소선으로 표시되어 사용자가 AI가 어디까지 말했는지 한눈에 알 수 있습니다.

### 이 패키지의 경계선

정리하면, **flutter_smart_turn이 하는 일**과 **앱이 해야 하는 일**의 경계는 이렇습니다:

| 영역 | flutter_smart_turn | 앱 (개발자 구현) |
|------|--------------------|-----------------|
| 끼어들기 감지 | `interruptAgent` 발행 | — |
| TTS 중지 | — | `tts.stopAndGetProgress()` |
| LLM 취소 | — | `llm.cancel()` |
| 대화 이력 관리 | — | `_conversationHistory` 업데이트 |
| 다음 응답 생성 | `commitAndRespond` 발행 | 중단 맥락 포함하여 LLM 호출 |

이 설계는 의도적입니다. 턴 판정 로직과 비즈니스 로직을 분리함으로써, 어떤 LLM/TTS 조합을 쓰든 턴 관리 부분은 동일하게 작동합니다.

---

## 12. 예제 앱으로 체험하기

이 패키지에는 두 개의 예제 앱이 포함되어 있습니다.

### Basic Demo — 턴 감지 시각화

`example/basic_demo/lib/main.dart`

마이크 입력을 받아서 턴 판정 결과를 시각적으로 보여주는 앱입니다.

```dart
// 엔진 선택 토글
TurnController _buildController() {
  return _useSmartTurn
      ? TurnController.withSmartTurn()
      : TurnController.withHeuristic();
}

// 마이크 오디오 → 컨트롤러로 전달
void _onAudioData(Uint8List pcm16Bytes) {
  final samples = AudioUtils.pcm16BytesToFloat32(pcm16Bytes);
  final frame = AudioFrame(
    samples: samples,
    sampleRate: 16000,
    channels: 1,
    timestamp: DateTime.now(),
  );
  _controller.onAudioFrame(frame);
}
```

이 앱에서 확인할 수 있는 것들:
- 실시간 대화 상태 표시 (아이콘 + 색상)
- 각 점수의 실시간 바 차트
- 이벤트 로그 (타임스탬프, 액션, 이유)
- Smart Turn ↔ Heuristic 엔진 전환

### Voice Chat — 실제 음성 대화 + 끼어들기 처리

`example/voice_chat/lib/main.dart`

턴 컨트롤러를 사용해 음성 대화를 구현한 앱입니다. **11장에서 설명한 끼어들기 처리 패턴**이 실제로 구현되어 있습니다.

```dart
// 턴 결정에 따라 동작
_controller.decisions.listen((decision) {
  switch (decision.action) {
    case TurnAction.commitAndRespond:
      _handleCommit();          // 대화 이력 포함 LLM 호출 → TTS 재생
      break;
    case TurnAction.interruptAgent:
      _handleInterrupt();       // LLM 취소 → TTS 중지 + 진행률 → 이력 업데이트
      break;
    default:
      break;
  }
});
```

이 앱에서 확인할 수 있는 것들:
- LLM 요청 취소 (`LlmService.cancel()`)
- TTS 진행률 추적 (`TtsService.stopAndGetProgress()`)
- 대화 이력 기반 맥락 유지 (`_conversationHistory`)
- 끼어들린 메시지의 시각적 구분 (취소선 + 인터럽트 표시)

---

## 13. 마무리 — 확장 포인트와 로드맵

> **참고**: 12장의 voice_chat 예제는 11장에서 설명한 끼어들기 처리를 실제로 구현하고 있습니다. LLM 취소, TTS 진행률 추적, 대화 이력 관리, 끼어들린 메시지의 UI 표현까지 모두 포함되어 있으니 코드를 직접 실행해 보세요.

### 직접 확장하기

이 패키지의 모든 핵심 컴포넌트는 인터페이스로 정의되어 있어서, 필요에 따라 교체할 수 있습니다.

**커스텀 Engine 예시 — WebSocket 실시간 추론:**

```dart
class WebSocketEngine implements TurnEngine {
  @override
  Future<TurnInference> analyze(TurnInput input) async {
    // WebSocket으로 오디오 전송, 서버에서 점수 수신
  }
}
```

**커스텀 Policy 예시 — 교육용 대기 정책:**

```dart
class PedagogicalPolicy implements TurnPolicy {
  @override
  TurnDecision apply(TurnDecision raw, TurnContext ctx) {
    // 학습자가 생각하는 시간을 더 주기 위해
    // commitAndRespond 대신 hold를 더 오래 유지
    if (raw.action == TurnAction.commitAndRespond &&
        ctx.silenceDuration < Duration(seconds: 3)) {
      return raw.copyWith(action: TurnAction.hold);
    }
    return raw;
  }
}
```

### 로드맵

| 버전 | 목표 |
|------|------|
| v0.1 ✅ | Smart Turn 로컬 + 휴리스틱 + 기본 Router/Policy |
| v0.2 | 교육용 Policy, 디버그 타임라인 UI 위젯 |
| v0.3 | 듀얼 채널 라우팅, 맞장구 정책 |
| v0.4 | VAP 어댑터, 서버 사이드 추론 강화 |
| v1.0 | 안정화된 API, 프로덕션 문서 |

### 파일 구조 요약

```
lib/
├── flutter_smart_turn.dart              # 배럴 export (공개 API)
└── src/
    ├── core/
    │   ├── types.dart                   # 열거형과 데이터 클래스
    │   ├── turn_decision.dart           # TurnInference, TurnDecision
    │   ├── turn_engine.dart             # Engine 인터페이스
    │   ├── turn_router.dart             # Router 인터페이스
    │   ├── turn_policy.dart             # Policy 인터페이스
    │   └── state_machine.dart           # 상태 전이 머신
    ├── controller/
    │   └── turn_controller.dart         # 메인 오케스트레이터
    ├── engines/
    │   ├── score_utils.dart             # 공유 점수 유틸
    │   ├── heuristic_engine.dart        # 규칙 기반 엔진
    │   └── smart_turn/
    │       ├── smart_turn_engine.dart   # ONNX 모델 엔진 + 링 버퍼
    │       ├── smart_turn_backend.dart  # 백엔드 인터페이스
    │       ├── local_backend.dart       # 로컬 ONNX 추론
    │       ├── server_backend.dart      # HTTP 서버 추론
    │       └── model_manager.dart       # 모델 다운로드/캐시
    ├── router/
    │   └── default_router.dart          # 임계값 기반 라우터
    ├── policy/
    │   └── default_policy.dart          # 안전장치 정책
    └── utils/
        └── audio_utils.dart             # PCM 변환 유틸
```

---

> **flutter_smart_turn**은 "누가 말할 차례인가?"라는 단순하지만 어려운 문제에 대해, 교체 가능한 모듈 구조로 깔끔한 해법을 제공합니다. Engine을 바꾸면 더 똑똑해지고, Policy를 바꾸면 더 적절해지고, Router를 바꾸면 더 유연해집니다. 코드를 직접 읽어보면서, 자신의 음성 앱에 맞는 조합을 찾아보세요.
