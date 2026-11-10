import 'package:speech_to_text/speech_to_text.dart';

/// Speech recognition seam (faked in tests).
abstract interface class SpeechInput {
  /// Asks for mic + speech permission on first use. False if unavailable.
  Future<bool> init();

  Future<void> listen({
    required String localeId,
    required void Function(String text, {required bool isFinal}) onResult,
    void Function(double level)? onLevel,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  });

  Future<void> stop();
  bool get isListening;
}

/// On-device recognition via the OS engine (speech_to_text).
class DeviceSpeechInput implements SpeechInput {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize();
    } on Object {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String text, {required bool isFinal}) onResult,
    void Function(double level)? onLevel,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!await init()) return;
    await _stt.listen(
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        localeId: localeId.replaceAll('-', '_'),
        listenFor: listenFor,
        pauseFor: pauseFor,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        // Biases recognition toward Aria's vocabulary.
        contextualPhrases: const [
          'remind me',
          'every day',
          'every month',
          'snooze',
          'kal',
          'parso',
          'subah',
          'shaam',
          'raat',
          'baje',
          'yaad dilana',
          'grocery list',
        ],
      ),
      onResult: (r) => onResult(r.recognizedWords, isFinal: r.finalResult),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  bool get isListening => _stt.isListening;
}
