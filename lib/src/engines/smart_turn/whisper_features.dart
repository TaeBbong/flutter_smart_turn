import 'dart:math' as math;
import 'dart:typed_data';

/// Whisper-compatible log-mel spectrogram feature extractor.
///
/// Reproduces the preprocessing pipeline from HuggingFace
/// `WhisperFeatureExtractor(chunk_length=8)`:
///   raw audio → reflect pad → STFT → power spectrum → mel filter bank → log → normalize
///
/// Uses 512-point radix-2 FFT (zero-padded from 400-sample windows) for
/// efficient computation on mobile devices.
class WhisperFeatureExtractor {
  /// Whisper STFT window size.
  static const int nFft = 400;

  /// Hop length between STFT frames.
  static const int hopLength = 160;

  /// Number of mel frequency bins.
  static const int nMels = 80;

  /// Expected sample rate.
  static const int sampleRate = 16000;

  /// Audio chunk length in seconds.
  static const int chunkLength = 8;

  /// Number of expected input samples.
  static const int nSamples = chunkLength * sampleRate; // 128000

  /// Number of output time frames.
  static const int nFrames = nSamples ~/ hopLength; // 800

  // Internal FFT size (next power of 2 from nFft).
  static const int _fftSize = 512;
  static const int _nFreqBins = _fftSize ~/ 2 + 1; // 257

  /// Pre-computed Hann window (periodic, length nFft).
  late final Float64List _window;

  /// Pre-computed mel filter bank [nMels][_nFreqBins].
  late final List<Float64List> _melFilters;

  // Pre-allocated FFT work buffers (reused per frame).
  final Float64List _fftReal = Float64List(_fftSize);
  final Float64List _fftImag = Float64List(_fftSize);

  WhisperFeatureExtractor() {
    _window = _createHannWindow();
    _melFilters = _createMelFilterBank();
  }

  /// Extract log-mel spectrogram features from raw audio.
  ///
  /// [audio] must be a Float32List of length [nSamples] (128000).
  /// Returns a flat Float32List of shape [nMels, nFrames] = [80, 800]
  /// in row-major order. The caller adds the batch dimension.
  Float32List extract(Float32List audio) {
    // 1. Reflect-pad audio by nFft/2 on each side.
    final padLen = nFft ~/ 2; // 200
    final padded = _reflectPad(audio, padLen);

    // 2. Compute STFT → mel spectrogram → log, one frame at a time.
    final totalFrames = (padded.length - nFft) ~/ hopLength + 1; // 801
    final outFrames = totalFrames - 1; // 800 (Whisper drops last frame)

    final logMel = Float64List(nMels * outFrames);
    double globalMax = -1e30;

    for (int t = 0; t < outFrames; t++) {
      // Compute power spectrum for this frame.
      _computePowerSpectrum(padded, t * hopLength);

      // Apply mel filter bank and log10.
      for (int m = 0; m < nMels; m++) {
        final filter = _melFilters[m];
        double sum = 0.0;
        for (int f = 0; f < _nFreqBins; f++) {
          sum += filter[f] * _fftReal[f]; // _fftReal reused as power output
        }
        final logVal = math.log(math.max(sum, 1e-10)) / math.ln10;
        final idx = m * outFrames + t;
        logMel[idx] = logVal;
        if (logVal > globalMax) globalMax = logVal;
      }
    }

    // 3. Whisper normalization: clamp to [max-8, max], scale to ~[0, 1].
    final threshold = globalMax - 8.0;
    final result = Float32List(nMels * outFrames);
    for (int i = 0; i < logMel.length; i++) {
      final v = math.max(logMel[i], threshold);
      result[i] = (v + 4.0) / 4.0;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // STFT
  // ---------------------------------------------------------------------------

  /// Compute the power spectrum of one frame, storing result in [_fftReal].
  void _computePowerSpectrum(Float64List padded, int start) {
    // Apply Hann window to frame, zero-pad to _fftSize.
    for (int n = 0; n < nFft; n++) {
      _fftReal[n] = padded[start + n] * _window[n];
    }
    _fftReal.fillRange(nFft, _fftSize, 0.0);
    _fftImag.fillRange(0, _fftSize, 0.0);

    // In-place radix-2 FFT.
    _fft(_fftReal, _fftImag);

    // Power spectrum |X[k]|² stored back in _fftReal[0.._nFreqBins).
    for (int k = 0; k < _nFreqBins; k++) {
      _fftReal[k] = _fftReal[k] * _fftReal[k] + _fftImag[k] * _fftImag[k];
    }
  }

  // ---------------------------------------------------------------------------
  // FFT (radix-2, in-place)
  // ---------------------------------------------------------------------------

  static void _fft(Float64List real, Float64List imag) {
    final n = real.length;

    // Bit-reversal permutation.
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        double t = real[i];
        real[i] = real[j];
        real[j] = t;
        t = imag[i];
        imag[i] = imag[j];
        imag[j] = t;
      }
      int k = n >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    // Butterfly stages.
    int step = 1;
    while (step < n) {
      final halfStep = step;
      step <<= 1;
      final angle = -math.pi / halfStep;
      final wR = math.cos(angle);
      final wI = math.sin(angle);

      for (int group = 0; group < n; group += step) {
        double curR = 1.0, curI = 0.0;
        for (int pair = 0; pair < halfStep; pair++) {
          final a = group + pair;
          final b = a + halfStep;
          final tR = curR * real[b] - curI * imag[b];
          final tI = curR * imag[b] + curI * real[b];
          real[b] = real[a] - tR;
          imag[b] = imag[a] - tI;
          real[a] += tR;
          imag[a] += tI;
          final newR = curR * wR - curI * wI;
          curI = curR * wI + curI * wR;
          curR = newR;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Hann window
  // ---------------------------------------------------------------------------

  /// Periodic Hann window matching `np.hanning(nFft + 1)[:-1]`.
  static Float64List _createHannWindow() {
    final w = Float64List(nFft);
    for (int i = 0; i < nFft; i++) {
      w[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / nFft));
    }
    return w;
  }

  // ---------------------------------------------------------------------------
  // Mel filter bank
  // ---------------------------------------------------------------------------

  /// Build mel filter bank matching `librosa.filters.mel(sr=16000, n_fft=..., n_mels=80)`.
  ///
  /// Uses the Slaney (O'Shaughnessy) mel scale — the librosa default
  /// when `htk=False`.
  List<Float64List> _createMelFilterBank() {
    final fMax = sampleRate / 2.0;

    // n_mels + 2 center frequencies in Hz, evenly spaced in mel scale.
    final melMin = _hzToMel(0.0);
    final melMax = _hzToMel(fMax);
    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => melMin + (melMax - melMin) * i / (nMels + 1),
    );
    final hzPoints = melPoints.map(_melToHz).toList();

    // Differences between consecutive Hz center frequencies.
    final fdiff = List<double>.generate(
      hzPoints.length - 1,
      (i) => hzPoints[i + 1] - hzPoints[i],
    );

    // FFT bin center frequencies (for _fftSize-point FFT).
    final fftFreqs = List<double>.generate(
      _nFreqBins,
      (j) => j * sampleRate / _fftSize,
    );

    // Triangular filters (matching librosa, no normalization).
    final filters =
        List<Float64List>.generate(nMels, (_) => Float64List(_nFreqBins));

    for (int m = 0; m < nMels; m++) {
      for (int j = 0; j < _nFreqBins; j++) {
        final lower = (fftFreqs[j] - hzPoints[m]) / fdiff[m];
        final upper = (hzPoints[m + 2] - fftFreqs[j]) / fdiff[m + 1];
        filters[m][j] = math.max(0.0, math.min(lower, upper));
      }
    }

    return filters;
  }

  // ---------------------------------------------------------------------------
  // Slaney mel scale (librosa default when htk=False)
  // ---------------------------------------------------------------------------

  static const double _fSp = 200.0 / 3.0;
  static const double _minLogHz = 1000.0;
  static const double _minLogMel = _minLogHz / _fSp; // 15.0
  static const double _logStep = 0.06875177742094912; // ln(6.4) / 27

  static double _hzToMel(double hz) {
    if (hz >= _minLogHz) {
      return _minLogMel + math.log(hz / _minLogHz) / _logStep;
    }
    return hz / _fSp;
  }

  static double _melToHz(double mel) {
    if (mel >= _minLogMel) {
      return _minLogHz * math.exp(_logStep * (mel - _minLogMel));
    }
    return _fSp * mel;
  }

  // ---------------------------------------------------------------------------
  // Reflect padding
  // ---------------------------------------------------------------------------

  /// Reflect-pad matching `np.pad(x, padLen, mode='reflect')`.
  static Float64List _reflectPad(Float32List x, int padLen) {
    final len = x.length;
    final result = Float64List(len + 2 * padLen);

    // Left padding: mirror from index 1 outward.
    for (int i = 0; i < padLen; i++) {
      result[padLen - 1 - i] = x[i + 1];
    }
    // Original signal.
    for (int i = 0; i < len; i++) {
      result[padLen + i] = x[i];
    }
    // Right padding: mirror from index len-2 inward.
    for (int i = 0; i < padLen; i++) {
      result[padLen + len + i] = x[len - 2 - i];
    }

    return result;
  }
}
