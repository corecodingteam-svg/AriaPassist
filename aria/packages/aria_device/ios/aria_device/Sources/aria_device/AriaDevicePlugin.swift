import AVFoundation
import Flutter
import UIKit

/// iOS side of Aria's device bridge:
/// - speak: AVSpeechSynthesizer (foreground previews, replies, briefings)
/// - synthesizeToFile: renders speech to a 16-bit PCM .caf, used as a
///   notification sound so voice reminders play even when the app is closed.
/// - ringerMode: no public API on iOS → "unknown" (notification sounds obey
///   the silent switch anyway).
public class AriaDevicePlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  private let synth = AVSpeechSynthesizer()
  private let fileSynth = AVSpeechSynthesizer()
  private var pendingSpeak: FlutterResult?
  private lazy var places = AriaPlaces()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.aria/device", binaryMessenger: registrar.messenger())
    let instance = AriaDevicePlugin()
    instance.synth.delegate = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "ringerMode":
      result("unknown")
    case "speak":
      speak(args, result: result)
    case "stop":
      synth.stopSpeaking(at: .immediate)
      result(true)
    case "synthesizeToFile":
      synthesizeToFile(args, result: result)
    case "manufacturer":
      result("apple")
    case "isIgnoringBatteryOptimizations":
      result(true) // not applicable on iOS
    case "openAppSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
        result(true)
      } else {
        result(false)
      }
    case "locationPermission": places.locationPermission(result)
    case "requestLocationPermission": places.requestLocationPermission(result)
    case "currentLocation": places.currentLocation(result)
    case "setGeofences": places.setGeofences(args, result: result)
    case "calendarPermission": places.calendarPermission(result)
    case "requestCalendarPermission": places.requestCalendarPermission(result)
    case "calendarEvents": places.calendarEvents(args, result: result)
    case "requestIgnoreBatteryOptimizations", "openAutoStartSettings":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func utterance(_ args: [String: Any]) -> AVSpeechUtterance {
    let u = AVSpeechUtterance(string: args["text"] as? String ?? "")
    let locale = args["locale"] as? String ?? "en-IN"
    let gender = args["gender"] as? String
    u.voice = Self.voice(locale: locale, gender: gender)
    let rate = Float(args["rate"] as? Double ?? 1.0)
    u.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate,
                     AVSpeechUtteranceMinimumSpeechRate),
                 AVSpeechUtteranceMaximumSpeechRate)
    u.pitchMultiplier = Float(min(max(args["pitch"] as? Double ?? 1.0, 0.5), 2.0))
    return u
  }

  /// Best installed voice for the locale, preferring the requested gender
  /// and higher quality.
  private static func voice(locale: String, gender: String?) -> AVSpeechSynthesisVoice? {
    let lang = locale.lowercased()
    let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.lowercased() == lang
    }
    let wanted: AVSpeechSynthesisVoiceGender? = gender == "male" ? .male : (gender == "female" ? .female : nil)
    let pool = candidates.filter { wanted == nil || $0.gender == wanted }
    let best = (pool.isEmpty ? candidates : pool).max { $0.quality.rawValue < $1.quality.rawValue }
    return best ?? AVSpeechSynthesisVoice(language: locale)
  }

  private func speak(_ args: [String: Any], result: @escaping FlutterResult) {
    let alarm = args["alarmStream"] as? Bool ?? false
    try? AVAudioSession.sharedInstance().setCategory(
      alarm ? .playback : .ambient, mode: .spokenAudio, options: [.duckOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    pendingSpeak?(false)
    pendingSpeak = result
    synth.stopSpeaking(at: .immediate)
    synth.speak(utterance(args))
  }

  public func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
    pendingSpeak?(true)
    pendingSpeak = nil
  }

  public func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
    pendingSpeak?(false)
    pendingSpeak = nil
  }

  private func synthesizeToFile(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["path"] as? String else { return result(false) }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    var file: AVAudioFile?
    var finished = false
    func finish(_ ok: Bool) {
      if finished { return }
      finished = true
      file = nil // closes the file
      DispatchQueue.main.async { result(ok && FileManager.default.fileExists(atPath: path)) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finish(file != nil) }

    fileSynth.write(utterance(args)) { buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer else { return }
      if pcm.frameLength == 0 { return finish(file != nil) }
      do {
        if file == nil {
          // 16-bit linear PCM in CAF: a format UNNotificationSound plays.
          let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: pcm.format.sampleRate,
            AVNumberOfChannelsKey: pcm.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
          ]
          file = try AVAudioFile(
            forWriting: url, settings: settings,
            commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
        }
        try file?.write(from: pcm)
      } catch {
        finish(false)
      }
    }
  }
}
