//
//  LiveAudioEngine.swift
//  Runner
//
//  Unified, echo-cancelled audio pipeline for the Gemini Live "pal"
//  conversation, replacing the two-separate-engines approach (record +
//  flutter_pcm_sound) that let the pal's own voice leak into the mic and be
//  transcribed as the user ("pal hears himself").
//
//  It uses ONE AVAudioEngine whose input node has Voice-Processing enabled
//  (`setVoiceProcessingEnabled(true)`), which turns on Apple's hardware/
//  software acoustic echo canceller (AEC). Because the SAME engine both
//  captures the mic AND plays the pal's audio (via an AVAudioPlayerNode), the
//  AEC has the playback as its reference signal and subtracts it from the mic
//  input in real time — so the pal's voice is removed BEFORE the mic PCM is
//  sent upstream. This is the same class of pipeline ChatGPT-style voice apps
//  use, and it gives clean, correctly-attributed transcripts + natural
//  barge-in.
//
//  Bridged to Dart via:
//    - MethodChannel  "aiwellnesspal/live_audio"        (control)
//    - EventChannel   "aiwellnesspal/live_audio/mic"     (mic PCM16 upstream)
//
//  Audio formats (fixed by the Live API spec):
//    - Mic upstream:   16 kHz mono PCM16 LE
//    - Pal playback:   24 kHz mono PCM16 LE
//  The engine's hardware format is whatever the device uses; we convert to/from
//  these with AVAudioConverter.

import AVFoundation
import Flutter

final class LiveAudioEngine: NSObject {
  static let shared = LiveAudioEngine()

  // Live API fixed formats.
  private let micSampleRate: Double = 16000
  private let playbackSampleRate: Double = 24000

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()

  // Format the player node runs at (24 kHz mono float — the engine converts to
  // hardware on the way out; we feed it converted-from-PCM16 buffers).
  private var playerFormat: AVAudioFormat!
  // Target format for mic upstream (16 kHz mono PCM16-compatible float).
  private var micTargetFormat: AVAudioFormat!

  private var micConverter: AVAudioConverter?
  private var pcm16ToPlayerConverter: AVAudioConverter?

  private var micEventSink: FlutterEventSink?
  private var isRunning = false
  private var micPaused = false

  // Playback progress tracking (so Dart's turn/echo logic can tell when audio
  // is still playing). We count frames scheduled vs. a start time.
  private var scheduledPlaybackFrames: AVAudioFramePosition = 0
  private var playbackStartHostTime: UInt64 = 0

  // MARK: - Channel registration

  func register(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(
      name: "aiwellnesspal/live_audio", binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    let event = FlutterEventChannel(
      name: "aiwellnesspal/live_audio/mic", binaryMessenger: messenger)
    event.setStreamHandler(self)
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result)
    case "start":
      do {
        try start()
        result(true)
      } catch {
        result(FlutterError(code: "start_failed",
                            message: error.localizedDescription, details: nil))
      }
    case "stop":
      stop()
      result(nil)
    case "pauseMic":
      micPaused = true
      result(nil)
    case "resumeMic":
      micPaused = false
      result(nil)
    case "playChunk":
      if let data = (call.arguments as? FlutterStandardTypedData)?.data {
        playChunk(data)
      }
      result(nil)
    case "stopPlayback":
      stopPlayback()
      result(nil)
    case "playbackRemainingMs":
      result(playbackRemainingMs())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func requestPermission(_ result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async { result(granted) }
    }
  }

  // MARK: - Engine lifecycle

  private func start() throws {
    if isRunning { return }

    // Configure the session for simultaneous play + record with echo
    // cancellation. `.voiceChat` mode enables the system's voice-processing
    // path; defaultToSpeaker routes the pal's voice to the loudspeaker.
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    // `.voiceChat` mode is optimized for a phone-call earpiece route: even
    // with `.defaultToSpeaker` set, iOS often routes playback to the tiny
    // earpiece receiver instead of the loudspeaker on physical devices ("can't
    // hear the pal"). Explicitly forcing the speaker port fixes this. We also
    // observe route changes and re-force it below.
    try? session.overrideOutputAudioPort(.speaker)
    observeRouteChanges()

    let input = engine.inputNode
    // Turn on the acoustic echo canceller on the mic input. This is the crux:
    // it uses the engine's output (the pal's voice) as the reference and
    // removes it from the captured mic signal.
    if #available(iOS 13.0, *) {
      try input.setVoiceProcessingEnabled(true)
    }

    let hwFormat = input.outputFormat(forBus: 0)

    // Player runs at 24 kHz mono float (our pal-audio native rate); the engine
    // converts to the hardware format on the way to the speaker.
    playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: playbackSampleRate,
      channels: 1, interleaved: false)!

    // Mic target: 16 kHz mono float we then pack to PCM16 for upstream.
    micTargetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: micSampleRate,
      channels: 1, interleaved: false)!

    micConverter = AVAudioConverter(from: hwFormat, to: micTargetFormat)

    engine.attach(playerNode)
    // Connect player → main mixer at the player's format; the engine handles
    // conversion to the hardware output format.
    engine.connect(playerNode, to: engine.mainMixerNode, format: playerFormat)

    // Tap the mic. Buffers arrive in the hardware format; we convert to 16 kHz
    // mono, pack to PCM16, and emit to Dart.
    input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) {
      [weak self] buffer, _ in
      self?.onMicBuffer(buffer)
    }

    engine.prepare()
    try engine.start()
    playerNode.play()
    isRunning = true
    micPaused = false
    scheduledPlaybackFrames = 0
    playbackStartHostTime = 0

    // One-shot log: which port is the pal's audio actually going to? If this
    // says `builtInReceiver`, the earpiece override didn't stick and the user
    // will hear nothing from the loudspeaker.
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)" }
      .joined(separator: ",")
    NSLog("[LiveAudioEngine] started — output route: [\(outputs)]")
  }

  private func stop() {
    guard isRunning else { return }
    engine.inputNode.removeTap(onBus: 0)
    playerNode.stop()
    engine.stop()
    if #available(iOS 13.0, *) {
      try? engine.inputNode.setVoiceProcessingEnabled(false)
    }
    isRunning = false
    micEventSink = nil
    scheduledPlaybackFrames = 0
    playbackStartHostTime = 0
    NotificationCenter.default.removeObserver(self,
      name: AVAudioSession.routeChangeNotification, object: nil)
    try? AVAudioSession.sharedInstance().setActive(
      false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Route override

  private func observeRouteChanges() {
    NotificationCenter.default.removeObserver(self,
      name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil)
  }

  @objc private func handleRouteChange(_ note: Notification) {
    guard isRunning else { return }
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs.map { $0.portType }
    // If we ended up on the tiny earpiece receiver (built-in receiver), force
    // the loudspeaker so the pal is audible. Leave Bluetooth/headphones alone.
    if outputs.contains(.builtInReceiver) {
      try? session.overrideOutputAudioPort(.speaker)
      NSLog("[LiveAudioEngine] Route on receiver → forcing .speaker")
    }
  }

  // MARK: - Mic capture → 16 kHz PCM16 → Dart

  private func onMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !micPaused, let sink = micEventSink, let converter = micConverter
    else { return }

    let ratio = micSampleRate / buffer.format.sampleRate
    let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
    guard let outBuffer = AVAudioPCMBuffer(
      pcmFormat: micTargetFormat, frameCapacity: outCapacity) else { return }

    var fed = false
    var convError: NSError?
    converter.convert(to: outBuffer, error: &convError) { _, statusPtr in
      if fed {
        statusPtr.pointee = .noDataNow
        return nil
      }
      fed = true
      statusPtr.pointee = .haveData
      return buffer
    }
    if convError != nil || outBuffer.frameLength == 0 { return }

    // Pack float32 mono → little-endian PCM16.
    guard let ch = outBuffer.floatChannelData?[0] else { return }
    let n = Int(outBuffer.frameLength)
    var pcm = Data(capacity: n * 2)
    for i in 0..<n {
      let clamped = max(-1.0, min(1.0, ch[i]))
      let s = Int16(clamped * 32767.0)
      var le = s.littleEndian
      withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
    }
    DispatchQueue.main.async {
      sink(FlutterStandardTypedData(bytes: pcm))
    }
  }

  // MARK: - Pal playback: 24 kHz PCM16 → player node

  private func playChunk(_ data: Data) {
    guard isRunning else { return }
    let frameCount = AVAudioFrameCount(data.count / 2)
    if frameCount == 0 { return }
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount

    // Unpack little-endian PCM16 → float32 mono.
    guard let ch = buffer.floatChannelData?[0] else { return }
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let src = raw.bindMemory(to: Int16.self)
      let count = Int(frameCount)
      for i in 0..<count {
        ch[i] = Float(Int16(littleEndian: src[i])) / 32767.0
      }
    }

    if playbackStartHostTime == 0 {
      playbackStartHostTime = mach_absolute_time()
      scheduledPlaybackFrames = 0
    }
    scheduledPlaybackFrames += AVAudioFramePosition(frameCount)
    playerNode.scheduleBuffer(buffer, completionHandler: nil)
    if !playerNode.isPlaying { playerNode.play() }
  }

  private func stopPlayback() {
    guard isRunning else { return }
    // Drop any queued/buffered pal audio immediately (barge-in / turn end).
    playerNode.stop()
    playerNode.play() // re-arm for the next turn
    scheduledPlaybackFrames = 0
    playbackStartHostTime = 0
  }

  /// Estimated ms of pal audio still to play (scheduled frames minus elapsed).
  private func playbackRemainingMs() -> Int {
    if playbackStartHostTime == 0 || scheduledPlaybackFrames == 0 { return 0 }
    let scheduledMs = Double(scheduledPlaybackFrames) / playbackSampleRate * 1000
    let elapsedMs = hostTimeToMs(mach_absolute_time() - playbackStartHostTime)
    let remaining = scheduledMs - elapsedMs
    return remaining > 0 ? Int(remaining) : 0
  }

  private func hostTimeToMs(_ hostTime: UInt64) -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = Double(hostTime) * Double(info.numer) / Double(info.denom)
    return nanos / 1_000_000.0
  }
}

// MARK: - EventChannel (mic stream)

extension LiveAudioEngine: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    micEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    micEventSink = nil
    return nil
  }
}
