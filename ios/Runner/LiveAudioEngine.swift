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
  // The source format the cached [micConverter] was built for. The mic
  // converter is created LAZILY from the first real tap buffer (see
  // `converter(for:)`) because the input node's format is not reliable until
  // audio is actually flowing — see the note in `start()`.
  private var micSourceFormat: AVAudioFormat?
  private var pcm16ToPlayerConverter: AVAudioConverter?

  private var micEventSink: FlutterEventSink?
  private var isRunning = false
  private var micPaused = false
  /// Counts mic chunks pushed to Dart; logged once so a silent session is easy
  /// to diagnose (0 = the model is receiving no audio at all).
  private var micBuffersSent = 0
  /// Counts pal-audio chunks handed to the player node.
  private var playerChunksScheduled = 0

  // Playback progress tracking (so Dart's turn/echo logic can tell when audio
  // is still playing). This is deliberately completion-driven rather than a
  // wall-clock estimate: network gaps or output-route reconfiguration can make
  // wall time advance while no PCM is rendered, falsely reporting that a reply
  // has drained and cutting off its final words.
  private let playbackStateLock = NSLock()
  private var scheduledPlaybackFrames: AVAudioFramePosition = 0
  private var playbackGeneration: UInt64 = 0

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
        // Return diagnostics so the Dart side can log them. NSLog does NOT
        // reach `flutter run` output, so surfacing state through the channel is
        // the only way to see native audio state while debugging.
        result(diagnostics())
      } catch {
        result(FlutterError(code: "start_failed",
                            message: error.localizedDescription, details: nil))
      }
    case "diagnostics":
      result(diagnostics())
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

  // MARK: - Voice processing (AEC)

  /// Turns on the acoustic echo canceller. This is the crux of the whole
  /// pipeline: it uses the engine's output (the pal's voice) as the reference
  /// and subtracts it from the captured mic signal.
  ///
  /// MUST be re-applied after any engine reset or configuration change —
  /// `engine.reset()` and I/O reconfiguration drop it. If it is lost, the mic
  /// hears the loudspeaker, the server's VAD treats the pal's own voice as the
  /// user barging in, and the reply is cut off mid-sentence.
  ///
  /// Enabled on the OUTPUT node too: voice processing is a paired I/O unit, and
  /// enabling only one side can leave the engine unable to start at all.
  private func enableVoiceProcessing() {
    guard #available(iOS 13.0, *) else { return }
    do {
      if !engine.inputNode.isVoiceProcessingEnabled {
        try engine.inputNode.setVoiceProcessingEnabled(true)
      }
      if !engine.outputNode.isVoiceProcessingEnabled {
        try engine.outputNode.setVoiceProcessingEnabled(true)
      }
    } catch {
      NSLog("[LiveAudioEngine] could not enable voice processing: \(error)")
    }
    NSLog("[LiveAudioEngine] voice processing — input="
      + "\(engine.inputNode.isVoiceProcessingEnabled), "
      + "output=\(engine.outputNode.isVoiceProcessingEnabled)")
  }

  // MARK: - Graph wiring

  /// Attaches (once) and connects the pal-playback node to the main mixer.
  ///
  /// MUST be re-run after an engine reset or configuration change. iOS tears
  /// down connections involving the I/O nodes when the configuration changes,
  /// and a player node that isn't connected silently swallows every scheduled
  /// buffer — the pal's reply arrives and its captions render, but nothing is
  /// audible.
  private func connectPlayerNode() {
    if playerNode.engine == nil {
      engine.attach(playerNode)
    }
    // Connect player → main mixer at the player's format; the engine handles
    // conversion to the hardware output format.
    engine.connect(playerNode, to: engine.mainMixerNode, format: playerFormat)
  }

  // MARK: - Engine start / tap

  /// Installs the mic tap (idempotent — removes any existing tap first).
  private func installMicTap() {
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: nil) {
      [weak self] buffer, _ in
      self?.onMicBuffer(buffer)
    }
  }

  /// Starts the engine and VERIFIES it is actually running.
  ///
  /// `AVAudioEngine.start()` can succeed while leaving `isRunning == false`
  /// when the I/O unit has just been reconfigured (enabling voice processing,
  /// overriding the output port, or a route change all do this). That was the
  /// real cause of "the pal connects but never hears anything": the engine was
  /// stopped, so the mic tap never fired and zero audio reached the model.
  private func startEngineVerified(session: AVAudioSession) throws {
    var lastError: Error?
    for attempt in 1...3 {
      do {
        if !session.isOtherAudioPlaying {
          try? session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        engine.prepare()
        try engine.start()
      } catch {
        lastError = error
        NSLog("[LiveAudioEngine] engine.start() threw on attempt \(attempt): \(error)")
      }
      if engine.isRunning {
        NSLog("[LiveAudioEngine] engine running (attempt \(attempt))")
        return
      }
      NSLog("[LiveAudioEngine] engine NOT running after attempt \(attempt) — "
        + "resetting and retrying")
      // Reset the graph and give the I/O unit a moment to settle before retry.
      engine.stop()
      engine.reset()
      Thread.sleep(forTimeInterval: 0.12)
      // reset() drops voice processing AND the player connection — re-arm both
      // or the next attempt runs with no echo cancellation and no audio out.
      enableVoiceProcessing()
      connectPlayerNode()
    }
    throw lastError ?? NSError(
      domain: "LiveAudioEngine", code: -1,
      userInfo: [NSLocalizedDescriptionKey:
        "AVAudioEngine would not start (isRunning stayed false)."])
  }

  /// Rebuilds the engine when iOS reports a configuration change (route change,
  /// voice-processing toggle, media services reset). The engine is stopped by
  /// such changes, so without this the mic silently dies mid-session.
  private func observeConfigurationChanges() {
    NotificationCenter.default.removeObserver(
      self, name: .AVAudioEngineConfigurationChange, object: engine)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleConfigurationChange(_:)),
      name: .AVAudioEngineConfigurationChange,
      object: engine)
  }

  @objc private func handleConfigurationChange(_ note: Notification) {
    guard isRunning else { return }
    NSLog("[LiveAudioEngine] configuration change — engineRunning="
      + "\(engine.isRunning); rebuilding graph")
    // Configuration changes discard AVAudioPlayerNode's queued buffers. Reset
    // our completion-based counter too, so Dart never mistakes lost buffers for
    // speech that is still safely draining.
    resetPlaybackTracking()
    // The converter's source format may have changed with the new route.
    micConverter = nil
    micSourceFormat = nil
    let session = AVAudioSession.sharedInstance()
    do {
      // Re-arm AEC FIRST: the configuration change that stopped the engine also
      // drops voice processing. Rebuilding without this leaves the first reply
      // running with no echo cancellation, so the pal interrupts itself.
      enableVoiceProcessing()
      // Re-wire playback BEFORE starting: the configuration change broke the
      // player → mixer connection, so without this the pal is inaudible even
      // though its captions still render.
      connectPlayerNode()
      try startEngineVerified(session: session)
      installMicTap()
      playerNode.play()
      NSLog("[LiveAudioEngine] graph rebuilt after configuration change "
        + "(playerPlaying=\(playerNode.isPlaying))")
    } catch {
      NSLog("[LiveAudioEngine] failed to rebuild after configuration change: \(error)")
    }
  }

  // MARK: - Diagnostics

  /// A snapshot of the native audio state, surfaced to Dart for logging.
  private func diagnostics() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let inFmt = engine.inputNode.outputFormat(forBus: 0)
    return [
      "isRunning": isRunning,
      "engineRunning": engine.isRunning,
      "micPaused": micPaused,
      "hasEventSink": micEventSink != nil,
      "micBuffersSent": micBuffersSent,
      // Playback health: if playerAttached/playerPlaying is false, or frames are
      // being scheduled with nothing audible, the player lost its connection to
      // the mixer (happens on a configuration change).
      "playerAttached": playerNode.engine != nil,
      "playerPlaying": playerNode.isPlaying,
      "playerChunksScheduled": playerChunksScheduled,
      "scheduledFrames": scheduledPlaybackFrames,
      "inputSampleRate": inFmt.sampleRate,
      "inputChannels": Int(inFmt.channelCount),
      "converterReady": micConverter != nil,
      // If either of these is false, echo cancellation is OFF and the pal will
      // hear itself (cutting its own reply short via the server's VAD).
      "aecInput": {
        if #available(iOS 13.0, *) { return engine.inputNode.isVoiceProcessingEnabled }
        return false
      }(),
      "aecOutput": {
        if #available(iOS 13.0, *) { return engine.outputNode.isVoiceProcessingEnabled }
        return false
      }(),
      // The category is the crux: if something else (e.g. audio_service) has
      // taken the session to .playback, recording is silently dead.
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "inputAvailable": session.isInputAvailable,
      "recordPermission": session.recordPermission.rawValue,
      "sessionSampleRate": session.sampleRate,
      "inputs": session.currentRoute.inputs.map { $0.portType.rawValue },
      "outputs": session.currentRoute.outputs.map { $0.portType.rawValue },
    ]
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

    enableVoiceProcessing()

    // Enabling voice processing (and the speaker override above) reconfigures
    // the I/O unit, which STOPS the engine. Watch for that and rebuild, or the
    // engine silently ends up not running and the mic tap never fires.
    observeConfigurationChanges()

    // Player runs at 24 kHz mono float (our pal-audio native rate); the engine
    // converts to the hardware format on the way to the speaker.
    playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: playbackSampleRate,
      channels: 1, interleaved: false)!

    // Mic target: 16 kHz mono float we then pack to PCM16 for upstream.
    micTargetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: micSampleRate,
      channels: 1, interleaved: false)!

    // IMPORTANT (first-session bug): do NOT build the mic converter from
    // `input.outputFormat(forBus: 0)` here. On the FIRST start of the app's
    // lifetime the input hardware has not been configured yet — especially
    // right after `setVoiceProcessingEnabled(true)`, which reconfigures the
    // node — so that call can return an invalid 0 Hz format. `AVAudioConverter`
    // then returns nil, every tap buffer is dropped for want of a converter,
    // and the model receives total silence and never replies. (Stopping and
    // restarting "fixed" it only because the engine was warm the second time.)
    //
    // Instead we install the tap with a nil format (the node supplies its own
    // real format at callback time) and build the converter lazily from the
    // first buffer that actually arrives — that format is always valid.
    micConverter = nil
    micSourceFormat = nil

    connectPlayerNode()

    // Start the engine BEFORE installing the tap. `engine.start()` can return
    // without throwing while the engine is not actually running (the I/O unit
    // was reconfigured by the voice-processing/route changes above), and a tap
    // installed on a stopped engine never fires. Verify and retry.
    try startEngineVerified(session: session)

    // Now that the engine is confirmed running, tap the mic. format: nil uses
    // the bus's current (valid) format.
    installMicTap()

    playerNode.play()
    isRunning = true
    micPaused = false
    resetPlaybackTracking()

    // One-shot log: which port is the pal's audio actually going to? If this
    // says `builtInReceiver`, the earpiece override didn't stick and the user
    // will hear nothing from the loudspeaker.
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)" }
      .joined(separator: ",")
    let inFmt = engine.inputNode.outputFormat(forBus: 0)
    NSLog("[LiveAudioEngine] started — output route: [\(outputs)], "
      + "input node format: \(inFmt.sampleRate)Hz ch\(inFmt.channelCount) "
      + "(0Hz here is OK — the mic converter is built from the first real buffer)")
    micBuffersSent = 0
    playerChunksScheduled = 0
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
    // Drop the cached converter so the next session rebuilds it from that
    // session's real input format (the route may differ).
    micConverter = nil
    micSourceFormat = nil
    resetPlaybackTracking()
    NotificationCenter.default.removeObserver(self,
      name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.removeObserver(self,
      name: .AVAudioEngineConfigurationChange, object: engine)
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

  /// Returns a converter from [sourceFormat] to the 16 kHz mono mic target,
  /// building (and caching) it on first use.
  ///
  /// Built lazily from real tap buffers because the input node's advertised
  /// format is unreliable before audio flows (see the note in `start()`).
  /// Rebuilds automatically if the hardware format changes mid-session (e.g. a
  /// route change to/from Bluetooth).
  private func converter(for sourceFormat: AVAudioFormat) -> AVAudioConverter? {
    if let cached = micConverter, let cachedSource = micSourceFormat,
       cachedSource == sourceFormat {
      return cached
    }
    guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
          let target = micTargetFormat else {
      NSLog("[LiveAudioEngine] mic buffer has invalid format "
        + "(\(sourceFormat.sampleRate)Hz ch\(sourceFormat.channelCount)) — skipping")
      return nil
    }
    guard let built = AVAudioConverter(from: sourceFormat, to: target) else {
      NSLog("[LiveAudioEngine] could not build mic converter from "
        + "\(sourceFormat.sampleRate)Hz ch\(sourceFormat.channelCount)")
      return nil
    }
    micSourceFormat = sourceFormat
    micConverter = built
    NSLog("[LiveAudioEngine] mic converter ready: "
      + "\(sourceFormat.sampleRate)Hz ch\(sourceFormat.channelCount) -> 16000Hz mono")
    return built
  }

  private func onMicBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !micPaused, let sink = micEventSink else { return }
    guard let converter = converter(for: buffer.format) else { return }

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
      self.micBuffersSent += 1
      if self.micBuffersSent == 1 {
        NSLog("[LiveAudioEngine] first mic chunk sent upstream — capture is live")
      }
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

    // Defensive: if a configuration change broke the player's connection, the
    // scheduled buffer would otherwise be discarded silently.
    if playerNode.engine == nil || engine.outputConnectionPoints(
        for: playerNode, outputBus: 0).isEmpty {
      NSLog("[LiveAudioEngine] player was disconnected — re-wiring for playback")
      connectPlayerNode()
      if engine.isRunning { playerNode.play() }
    }

    // Count audio as pending until AVAudioPlayerNode confirms it has played
    // back. This intentionally overestimates by at most one small PCM chunk,
    // which is safe: an overestimate delays mic reopening/end teardown slightly
    // while an underestimate truncates audible speech.
    let generation = currentPlaybackGenerationAfterScheduling(frameCount)
    playerNode.scheduleBuffer(
      buffer,
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      self?.completePlaybackBuffer(frameCount, generation: generation)
    }
    playerChunksScheduled += 1
    if playerChunksScheduled == 1 {
      NSLog("[LiveAudioEngine] first pal audio chunk scheduled "
        + "(playerPlaying=\(playerNode.isPlaying), engineRunning=\(engine.isRunning))")
    }
    if !playerNode.isPlaying { playerNode.play() }
  }

  private func currentPlaybackGenerationAfterScheduling(
    _ frameCount: AVAudioFrameCount
  ) -> UInt64 {
    playbackStateLock.lock()
    scheduledPlaybackFrames += AVAudioFramePosition(frameCount)
    let generation = playbackGeneration
    playbackStateLock.unlock()
    return generation
  }

  private func completePlaybackBuffer(
    _ frameCount: AVAudioFrameCount,
    generation: UInt64
  ) {
    playbackStateLock.lock()
    defer { playbackStateLock.unlock() }
    // Completions from a previous turn can arrive after stopPlayback(). They
    // must never decrement audio queued for a newer turn.
    guard generation == playbackGeneration else { return }
    scheduledPlaybackFrames = max(
      0, scheduledPlaybackFrames - AVAudioFramePosition(frameCount))
  }

  private func resetPlaybackTracking() {
    playbackStateLock.lock()
    playbackGeneration &+= 1
    scheduledPlaybackFrames = 0
    playbackStateLock.unlock()
  }

  private func stopPlayback() {
    guard isRunning else { return }
    // Drop any queued/buffered pal audio immediately (barge-in / turn end).
    playerNode.stop()
    playerNode.play() // re-arm for the next turn
    resetPlaybackTracking()
  }

  /// Conservative remaining ms based on PCM buffers that AVAudioPlayerNode has
  /// not yet reported as played. Unlike a wall-clock estimate, this stays
  /// correct through network gaps and prevents an early stop from clipping a
  /// reply's final syllable.
  private func playbackRemainingMs() -> Int {
    playbackStateLock.lock()
    let pendingFrames = scheduledPlaybackFrames
    playbackStateLock.unlock()
    guard pendingFrames > 0 else { return 0 }
    let queuedMs = Double(pendingFrames) / playbackSampleRate * 1000
    // Include the output route's render latency; without it teardown can stop
    // the final buffer after the player consumed it but before it is audible.
    let outputLatencyMs = AVAudioSession.sharedInstance().outputLatency * 1000
    return Int(ceil(queuedMs + outputLatencyMs))
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
