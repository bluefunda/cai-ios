import Foundation
import AVFoundation
import Speech

/// Records a voice memo and transcribes it on-device.
///
/// No backend speech-to-text path exists anywhere in the chat pipeline today
/// (cai-bff/cai-llm-router only process images/PDF/text file attachments), so
/// transcription is entirely on-device via SFSpeechRecognizer — no new
/// backend dependency, no bytes leave the device beyond the recording itself
/// if the user later attaches it.
@MainActor
final class VoiceInputManager: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    /// Which permission was denied, so the UI can deep-link to the right Settings pane.
    enum DeniedPermission {
        case microphone
        case speechRecognition
    }

    @Published private(set) var state: State = .idle
    @Published var error: String?
    /// Set alongside `error` when the failure is a denied permission — nil for other errors.
    @Published var deniedPermission: DeniedPermission?
    /// Elapsed recording time, for a simple UI timer.
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    var isRecording: Bool { state == .recording }

    // MARK: - Permissions

    /// Requests microphone + speech-recognition permission. Returns false if
    /// either is denied — caller should surface a clear "enable in Settings" message.
    func requestPermissions() async -> Bool {
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            error = "Microphone access is required to record a voice message."
            deniedPermission = .microphone
            return false
        }

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            error = "Speech recognition access is required to transcribe voice messages."
            deniedPermission = .speechRecognition
            return false
        }
        deniedPermission = nil
        return true
    }

    private func requestMicrophonePermission() async -> Bool {
        // #if os(iOS) is true for Mac Catalyst too (it compiles against the iOS
        // SDK), so Catalyst must be checked first: AVAudioApplication's
        // permission API doesn't correctly bridge to macOS's mic prompt under
        // Catalyst -- it silently reports "denied" without ever showing a
        // dialog. AVCaptureDevice.requestAccess is the macOS-native path that
        // actually triggers the system permission sheet there.
        #if targetEnvironment(macCatalyst)
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    // MARK: - Recording

    func startRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()

        self.recorder = recorder
        self.recordingURL = url
        self.state = .recording
        self.elapsed = 0
        self.error = nil

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsed += 0.1
            }
        }
    }

    /// Stops recording and discards the audio without transcribing.
    func cancelRecording() {
        recorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        cleanup()
    }

    /// Stops recording, transcribes the audio on-device, and returns both the
    /// transcript and the recorded file (bytes + suggested filename) so the
    /// caller can persist it via `LocalFileStore`.
    func stopRecordingAndTranscribe() async -> (transcript: String?, audioData: Data?, filename: String)? {
        guard state == .recording, let recorder, let url = recordingURL else { return nil }
        recorder.stop()
        state = .transcribing
        timer?.invalidate()
        timer = nil

        let audioData = try? Data(contentsOf: url)
        let filename = url.lastPathComponent
        let transcript = await transcribe(url: url)

        try? FileManager.default.removeItem(at: url)
        cleanup()

        return (transcript, audioData, filename)
    }

    private func transcribe(url: URL) async -> String? {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition isn't available right now."
            return nil
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return await withCheckedContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    didResume = true
                    continuation.resume(returning: nil)
                    Task { @MainActor in
                        self.error = "Couldn't transcribe: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func cleanup() {
        recorder = nil
        recordingURL = nil
        timer?.invalidate()
        timer = nil
        elapsed = 0
        state = .idle
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
